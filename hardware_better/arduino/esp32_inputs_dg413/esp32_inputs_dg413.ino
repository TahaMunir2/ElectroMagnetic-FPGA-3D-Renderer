// ===================================================================
//  EE2 FDTD EM Wave Simulator — ESP32 input firmware (DG413 two-panel)
//
//  "hardware_better" variant:
//   * Each panel uses the 6-pin SPLIT drive/sense scheme (cleaner, linear) —
//     coordinates are read on dedicated input-only ADC pins, separate from the
//     push-pull drive pins.
//   * ONE shared 6-pin panel port serves BOTH panels; a DG413 analog switch
//     routes the two "+" lines (X+, Y+) to Panel 1 (Mode 1) or Panel 2 (Mode 2).
//     X-/Y- are tied common to both panels. MUX_SEL is driven from the mode bit.
//   * Coordinates are read with analogReadMilliVolts() (linearised) and
//     auto-calibrated per panel, output X 0..1023 (16.4 cm) / Y 0..612 (9.8 cm).
//   * Pots reduced to amplitude, conductivity, field-type (yaw/pitch/zoom/Zscale
//     removed to keep the pinout clean — see pin_connections.md).
//
//  WiFi MUST stay off (ADC2 in use). Board: "ESP32 Dev Module".
//  DG413 is powered from the 5 V rail (it is not a 3.3 V part); its logic inputs
//  are TTL-compatible so the 3.3 V MUX_SEL drives it fine.
// ===================================================================

#define ADC_MAX    1023        // 10-bit full scale (raw counts, for thresholds)
#define X_OUT_MAX  1023        // 16.4 cm -> 0..1023
#define Y_OUT_MAX  612         //  9.8 cm -> 0..612

// ---------- shared panel port (DG413 routes it to the active panel) ----------
#define XP_DRIVE 18    // X+ push-pull drive (HIGH on X-read)
#define XP_SENSE 32    // X+ ADC sense -> Y-coord; has pull-up -> touch detect
#define XM       23    // X- drive (LOW on X-read)  [common to both panels]
#define YP_DRIVE 25    // Y+ push-pull drive (HIGH on Y-read)
#define YP_SENSE 35    // Y+ ADC sense (input-only) -> X-coord
#define YM       22    // Y- drive (LOW on Y-read)  [common to both panels]
#define MUX_SEL  19    // DG413 select: LOW = Panel 1 (NC), HIGH = Panel 2 (NO)

// ---------- analog inputs ----------
#define PIN_PROBE     34   // Mode 1 probe (input-only)
#define PIN_MODE      21   // Mode 1/2 switch (digital, pull-up; LOW = Mode 2)
#define PIN_DISP      26   // 2D/3D switch  (digital, pull-up; LOW = 3D)
#define PIN_FIELD_POT  4   // field type E/B/S (Mode 2)
#define PIN_POT_AMP   39   // amplitude (Mode 2)
#define PIN_POT_COND  33   // conductivity / wave speed (Mode 2)

// ---------- digital ----------
#define PIN_SW_WALL   27   // wall/source: LOW = wall, HIGH = source
#define PIN_BTN_CLEAR 14   // clear (active LOW)

// ---------- UART2 to PYNQ ----------
#define PIN_UART_TX 17
#define PIN_UART_RX 16
#define UART_BAUD 115200

// ---------- timing / filtering / auto-cal ----------
#define SETTLE_MS     6
#define MUX_SETTLE_MS 2        // after switching the DG413
#define OVERSAMPLE    12       // reads per coordinate (trimmed mean)
#define TRIM          3
#define TOUCH_FRAC    0.70f    // touched if sense < this fraction of full scale
#define FIRM_FRAC     0.45f    // only LEARN the range from presses firmer than this
#define EDGE_MARGIN   0.06f    // outer 6% of learned span clamps to 0/full
#define MIN_SPAN      300      // mV of learned span before mapping is trusted

const int TOUCH_THRESH = (int)(TOUCH_FRAC * ADC_MAX);
const int FIRM_THRESH  = (int)(FIRM_FRAC  * ADC_MAX);

// per-panel learned extremes in mV: index 0 = Panel 1, 1 = Panel 2
int xMinP[2] = {9999, 9999}, xMaxP[2] = {-1, -1};
int yMinP[2] = {9999, 9999}, yMaxP[2] = {-1, -1};

// median-of-3 raw counts (touch detect only — a threshold, not a coordinate)
int sampleADC(uint8_t pin) {
  int a = analogRead(pin), b = analogRead(pin), c = analogRead(pin);
  return a + b + c - max(a, max(b, c)) - min(a, min(b, c));
}

// trimmed-mean of OVERSAMPLE *linearised* reads (mV) — fixes ESP32 ADC nonlinearity
int sampleTrim(uint8_t pin) {
  int v[OVERSAMPLE];
  for (int i = 0; i < OVERSAMPLE; i++) v[i] = analogReadMilliVolts(pin);
  for (int i = 1; i < OVERSAMPLE; i++) {
    int k = v[i], j = i - 1;
    while (j >= 0 && v[j] > k) { v[j + 1] = v[j]; j--; }
    v[j + 1] = k;
  }
  long s = 0;
  for (int i = TRIM; i < OVERSAMPLE - TRIM; i++) s += v[i];
  return (int)(s / (OVERSAMPLE - 2 * TRIM));
}

void idlePanel() {
  pinMode(XP_DRIVE, INPUT); pinMode(XP_SENSE, INPUT); pinMode(XM, INPUT);
  pinMode(YP_DRIVE, INPUT); pinMode(YP_SENSE, INPUT); pinMode(YM, INPUT);
}

// touch detect: drive Y- LOW, read X+ sense via its pull-up. Returns raw counts
// (low when touched). Use < TOUCH_THRESH for touch, < FIRM_THRESH for "firm".
int panelSense() {
  pinMode(XP_DRIVE, INPUT); pinMode(XM, INPUT);
  pinMode(YP_DRIVE, INPUT); pinMode(YP_SENSE, INPUT);
  pinMode(YM, OUTPUT); digitalWrite(YM, LOW);
  pinMode(XP_SENSE, INPUT_PULLUP);
  delay(SETTLE_MS);
  int v = sampleADC(XP_SENSE);
  pinMode(XP_SENSE, INPUT);
  return v;
}

// X-coordinate: drive the X layer, sense on the Y+ terminal (YP_SENSE)
int readXmv() {
  pinMode(XP_DRIVE, OUTPUT); digitalWrite(XP_DRIVE, HIGH);
  pinMode(XM, OUTPUT);       digitalWrite(XM, LOW);
  pinMode(XP_SENSE, INPUT);
  pinMode(YP_DRIVE, INPUT); pinMode(YM, INPUT); pinMode(YP_SENSE, INPUT);
  delay(SETTLE_MS);
  return sampleTrim(YP_SENSE);
}

// Y-coordinate: drive the Y layer, sense on the X+ terminal (XP_SENSE)
int readYmv() {
  pinMode(YP_DRIVE, OUTPUT); digitalWrite(YP_DRIVE, HIGH);
  pinMode(YM, OUTPUT);       digitalWrite(YM, LOW);
  pinMode(YP_SENSE, INPUT);
  pinMode(XP_DRIVE, INPUT); pinMode(XM, INPUT); pinMode(XP_SENSE, INPUT);
  delay(SETTLE_MS);
  return sampleTrim(XP_SENSE);
}

// map raw mV to 0..outMax using the learned span (margin + clamp); -1 if unlearned
int mapAxis(int raw, int rmin, int rmax, int outMax) {
  int span = rmax - rmin;
  if (span < MIN_SPAN) return -1;
  int m = (int)(EDGE_MARGIN * span);
  long v = (long)(raw - (rmin + m)) * outMax / (span - 2 * m);
  return constrain((int)v, 0, outMax);
}

// field-type pot: thirds -> 0=E 1=B 2=S
int readFieldType() {
  int v = sampleADC(PIN_FIELD_POT);
  if      (v < ADC_MAX / 3)       return 0;
  else if (v < (2 * ADC_MAX) / 3) return 1;
  else                            return 2;
}

void putU16(uint8_t* b, int i, int v) { b[i] = (v >> 8) & 0xFF; b[i + 1] = v & 0xFF; }

void setup() {
  Serial.begin(115200);
  Serial2.begin(UART_BAUD, SERIAL_8N1, PIN_UART_RX, PIN_UART_TX);
  analogReadResolution(10);
  analogSetAttenuation(ADC_11db);
  pinMode(MUX_SEL, OUTPUT); digitalWrite(MUX_SEL, LOW);   // default Panel 1
  pinMode(PIN_MODE, INPUT_PULLUP);
  pinMode(PIN_DISP, INPUT_PULLUP);
  pinMode(PIN_SW_WALL,   INPUT_PULLUP);
  pinMode(PIN_BTN_CLEAR, INPUT_PULLUP);
  idlePanel();
  Serial.println("ESP32 DG413 two-panel firmware ready. Sweep each panel's edges to auto-cal.");
}

void loop() {
  uint32_t t0 = millis();

  bool mode2  = (digitalRead(PIN_MODE) == LOW);   // switch closed = Mode 2
  bool threeD = (digitalRead(PIN_DISP) == LOW);   // switch closed = 3D
  int  p = mode2 ? 1 : 0;                 // active panel index

  // route the shared port to the active panel, then let it settle
  digitalWrite(MUX_SEL, mode2 ? HIGH : LOW);
  delay(MUX_SETTLE_MS);

  int  sense   = panelSense();
  bool touched = sense < TOUCH_THRESH;
  int  px = 0, py = 0;
  if (touched) {
    int rx = readXmv(), ry = readYmv();
    if (sense < FIRM_THRESH) {            // learn range from firm presses only
      if (rx < xMinP[p]) xMinP[p] = rx;  if (rx > xMaxP[p]) xMaxP[p] = rx;
      if (ry < yMinP[p]) yMinP[p] = ry;  if (ry > yMaxP[p]) yMaxP[p] = ry;
    }
    int xc = mapAxis(rx, xMinP[p], xMaxP[p], X_OUT_MAX);
    int yc = mapAxis(ry, yMinP[p], yMaxP[p], Y_OUT_MAX);
    if (xc < 0 || yc < 0) touched = false;   // not calibrated yet -> not a valid touch
    else { px = xc; py = yc; }
  }
  idlePanel();

  int  amp       = sampleADC(PIN_POT_AMP);
  int  cond      = sampleADC(PIN_POT_COND);
  int  fieldType = mode2 ? readFieldType() : 0;
  int  probe     = mode2 ? 0 : sampleADC(PIN_PROBE);
  bool wall  = (digitalRead(PIN_SW_WALL)   == LOW);
  bool clear = (digitalRead(PIN_BTN_CLEAR) == LOW);

  // 21-byte frame (same contract as the base design; yaw/pitch/zoom/Zscale = 0
  // because those pots are not fitted in this build)
  uint8_t buf[21];
  buf[0] = 0xAA;
  buf[1] = (mode2   ? 0x01 : 0)
         | (threeD  ? 0x02 : 0)
         | ((fieldType & 0x03) << 2)
         | (wall    ? 0x10 : 0)
         | (clear   ? 0x20 : 0)
         | (touched ? 0x40 : 0);
  putU16(buf,  2, px);
  putU16(buf,  4, py);
  putU16(buf,  6, amp);
  putU16(buf,  8, cond);
  putU16(buf, 10, probe);
  putU16(buf, 12, 0);   // yaw   (not fitted)
  putU16(buf, 14, 0);   // pitch (not fitted)
  putU16(buf, 16, 0);   // zoom  (not fitted)
  putU16(buf, 18, 0);   // Zscale(not fitted)
  uint8_t cks = 0;
  for (int i = 1; i <= 19; i++) cks ^= buf[i];
  buf[20] = cks;

  Serial2.write(buf, sizeof(buf));

  while (millis() - t0 < 20) { }          // ~50 Hz
}
