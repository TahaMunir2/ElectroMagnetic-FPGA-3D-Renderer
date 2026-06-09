// ===================================================================
//  EE2 FDTD EM Wave Simulator — ESP32 input firmware (ONE board, ONE panel)
//
//  Only one mode runs at a time, so a single touch panel serves BOTH:
//    Mode 1 — the conducting sheet lies on the panel; the probe presses through
//             and the panel reports the probe's XY, the probe ADC reports V(x,y).
//    Mode 2 — a stylus on the same panel sets the source/wall/erase position.
//  No DG413 mux, no second board — the panel is wired directly. One ESP32 reads
//  the panel + all controls and sends the 21-byte frame to the PYNQ @ ~50 Hz.
//
//  PANEL COORDINATE:
//    raw -> calibrated full-scale  X 0..1023 (16.4 cm) / Y 0..612 (9.8 cm)
//        -> fitted to a 64 x 38 GRID, nearest cell:  X 0..63 , Y 0..37.
//    The PS receives the GRID CELL (X 0..63, Y 0..37) in the Panel X/Y bytes.
//  TWO-CORNER calibration (press one corner, then the opposite) sets the raw
//  min/max; saved to flash (NVS) and reloaded on boot. Recalibrate: HOLD Clear
//  at power-up, or send 'c' on the Serial Monitor.
//  WiFi MUST stay off (ADC2 in use). Board: "ESP32 Dev Module".
//
//  TRANSPORT:  ESP32 --UART2 (115200 8N1)--> PYNQ PS.  The PS reads this frame
//  and forwards it as the UDP payload to the renderer. (The ESP32 can't do
//  WiFi/UDP itself — WiFi is off because ADC2 is in use — so UDP is on the PS.)
//
//  PACKET (21 bytes, fixed, big-endian 16-bit fields) — also the UDP payload:
//    [0]    0xAA  header
//    [1]    flags: b0 mode2, b1 3D, b2-3 field(0=E 1=B 2=S), b4 wall, b5 clear, b6 touch-valid
//    [2-3]  Panel X grid cell (0..63)   [4-5]  Panel Y grid cell (0..37)
//    [6-7]  amplitude (0..1023)         [8-9]  conductivity (0..1023)
//    [10-11] probe (Mode 1, 0..1023)
//    [12-13] yaw  [14-15] pitch  [16-17] zoom  [18-19] Zscale  (each 0..1023)
//    [20]   checksum = XOR of bytes 1..19
//  When touch-valid (b6) is 0, Panel X/Y are 0 — the PS should not place a point.
// ===================================================================

#include <Preferences.h>

#define ADC_MAX 1023
#define X_FULL  1023               // calibrated full-scale X (16.4 cm long edge)
#define Y_FULL  612                // calibrated full-scale Y (9.8 cm short edge)
#define GRID_X  64                 // grid columns -> X cell 0..GRID_X-1 (0..63)
#define GRID_Y  38                 // grid rows    -> Y cell 0..GRID_Y-1 (0..37)

// ---------- Panel (directly wired, 6-pin split drive/sense) ----------
#define XP_DRIVE 18    // X+ drive (HIGH on X-layer read)
#define XP_SENSE 32    // X+ sense (ADC); pull-up -> touch detect
#define XM       23    // X- drive (LOW on X-layer read)
#define YP_DRIVE 25    // Y+ drive (HIGH on Y-layer read)
#define YP_SENSE 35    // Y+ sense (ADC, input-only)
#define YM       22    // Y- drive (LOW on Y-layer read)

// ---------- analog inputs ----------
#define PIN_PROBE      34  // Mode-1 probe (input-only)
#define PIN_POT_AMP    13  // amplitude (Mode 2)  [ADC2; GPIO39/VN not on some boards]
#define PIN_POT_COND   33  // conductivity / wave speed (Mode 2)
#define PIN_FIELD_POT   4  // field type E/B/S (Mode 2)
#define PIN_POT_YAW    27  // 3D view (both modes)
#define PIN_POT_PITCH  14  // 3D view
#define PIN_POT_ZOOM   26  // 3D view
#define PIN_POT_ZSCALE 36  // 3D view  [GPIO36/VP, input-only]

// ---------- digital ----------
#define PIN_MODE      21   // Mode 1/2 switch  (LOW = Mode 2)
#define PIN_DISP      19   // 2D/3D switch     (LOW = 3D)
#define PIN_SW_WALL    5   // LOW = wall, HIGH = source (Mode 2)        [GPIO5 strapping]
#define PIN_BTN_CLEAR 15   // clear (active LOW); also HOLD at boot to recalibrate [GPIO15 strapping]

// ---------- UART to PYNQ ----------
#define PIN_UART_TX 17
#define PIN_UART_RX 16
#define UART_BAUD 115200

// ---------- debug ----------
#define DEBUG     1        // 1 = print live readings to the USB Serial Monitor
#define DEBUG_MS  200

// ---------- filtering / calibration ----------
#define SETTLE_MS   6
#define OVERSAMPLE  12
#define TRIM        3
#define TOUCH_FRAC  0.70f
#define FIRM_FRAC   0.45f          // calibration captures only firm presses
#define CAL_MIN_SPAN 200          // mV; a stored calibration must span >= this to be valid

const int TOUCH_THRESH = (int)(TOUCH_FRAC * ADC_MAX);
const int FIRM_THRESH  = (int)(FIRM_FRAC  * ADC_MAX);

Preferences prefs;
int xMin = -1, xMax = -1, yMin = -1, yMax = -1;   // calibration extremes (mV), from corner presses

int sampleADC(uint8_t pin) {                 // median-of-3 raw counts (touch detect)
  int a = analogRead(pin), b = analogRead(pin), c = analogRead(pin);
  return a + b + c - max(a, max(b, c)) - min(a, min(b, c));
}
int sampleTrim(uint8_t pin) {                // trimmed-mean of linearised mV (coordinates)
  int v[OVERSAMPLE];
  for (int i = 0; i < OVERSAMPLE; i++) v[i] = analogReadMilliVolts(pin);
  for (int i = 1; i < OVERSAMPLE; i++) { int k = v[i], j = i - 1; while (j >= 0 && v[j] > k) { v[j+1]=v[j]; j--; } v[j+1]=k; }
  long s = 0; for (int i = TRIM; i < OVERSAMPLE - TRIM; i++) s += v[i];
  return (int)(s / (OVERSAMPLE - 2 * TRIM));
}
void idlePanel() {
  pinMode(XP_DRIVE, INPUT); pinMode(XP_SENSE, INPUT); pinMode(XM, INPUT);
  pinMode(YP_DRIVE, INPUT); pinMode(YP_SENSE, INPUT); pinMode(YM, INPUT);
}
int panelSense() {                           // touch detect: Y- low, read X+ via pull-up
  pinMode(XP_DRIVE, INPUT); pinMode(XM, INPUT);
  pinMode(YP_DRIVE, INPUT); pinMode(YP_SENSE, INPUT);
  pinMode(YM, OUTPUT); digitalWrite(YM, LOW);
  pinMode(XP_SENSE, INPUT_PULLUP);
  delay(SETTLE_MS);
  int v = sampleADC(XP_SENSE);
  pinMode(XP_SENSE, INPUT);
  return v;
}
int readXmv() {                              // drive X-layer, sense Y+  (9.8 cm short axis)
  pinMode(XP_DRIVE, OUTPUT); digitalWrite(XP_DRIVE, HIGH);
  pinMode(XM, OUTPUT);       digitalWrite(XM, LOW);
  pinMode(XP_SENSE, INPUT); pinMode(YP_DRIVE, INPUT); pinMode(YM, INPUT); pinMode(YP_SENSE, INPUT);
  delay(SETTLE_MS);
  return sampleTrim(YP_SENSE);
}
int readYmv() {                              // drive Y-layer, sense X+  (16.4 cm long axis)
  pinMode(YP_DRIVE, OUTPUT); digitalWrite(YP_DRIVE, HIGH);
  pinMode(YM, OUTPUT);       digitalWrite(YM, LOW);
  pinMode(YP_SENSE, INPUT); pinMode(XP_DRIVE, INPUT); pinMode(XM, INPUT); pinMode(XP_SENSE, INPUT);
  delay(SETTLE_MS);
  return sampleTrim(XP_SENSE);
}
// raw mV -> calibrated full-scale value in [0 .. full]
int toScale(int raw, int rmin, int rmax, int full) {
  if (rmax - rmin < 1) return 0;
  float f = (float)(raw - rmin) / (float)(rmax - rmin);   // 0..1
  return constrain((int)lroundf(f * full), 0, full);
}
// full-scale [0..full] -> nearest cell of an N-line grid [0 .. N-1]
int toGrid(int fullVal, int full, int n) {
  return constrain((int)lroundf((float)fullVal * (n - 1) / full), 0, n - 1);
}
int readFieldType() {                        // thirds -> 0=E 1=B 2=S
  int v = sampleADC(PIN_FIELD_POT);
  if      (v < ADC_MAX / 3)       return 0;
  else if (v < (2 * ADC_MAX) / 3) return 1;
  else                            return 2;
}
void putU16(uint8_t* b, int i, int v) { b[i] = (v >> 8) & 0xFF; b[i + 1] = v & 0xFF; }

// ---------- calibration (2 opposite corners, saved to NVS) ----------
bool calValid() { return (xMax - xMin) >= CAL_MIN_SPAN && (yMax - yMin) >= CAL_MIN_SPAN; }
void loadCal() {
  prefs.begin("panelcal", true);
  xMin = prefs.getInt("xmin", -1); xMax = prefs.getInt("xmax", -1);
  yMin = prefs.getInt("ymin", -1); yMax = prefs.getInt("ymax", -1);
  prefs.end();
}
void saveCal() {
  prefs.begin("panelcal", false);
  prefs.putInt("xmin", xMin); prefs.putInt("xmax", xMax);
  prefs.putInt("ymin", yMin); prefs.putInt("ymax", yMax);
  prefs.end();
}
void waitRelease() {                          // block until the panel is released
  while (panelSense() < TOUCH_THRESH) delay(20);
  idlePanel(); delay(150);
}
void captureCorner(int &ox, int &oy) {        // wait for a firm press, then average it
  while (panelSense() >= FIRM_THRESH) { idlePanel(); delay(20); }
  delay(120);                                 // settle
  long sx = 0, sy = 0; const int N = 8;
  for (int i = 0; i < N; i++) { sx += readYmv(); sy += readXmv(); idlePanel(); delay(8); }
  ox = (int)(sx / N); oy = (int)(sy / N);
}
void calibrate() {
  Serial.println(">> CALIBRATION — press the two OPPOSITE corners of the panel.");
  Serial.println(">> 1) press & hold one corner (e.g. bottom-left)...");
  int ax, ay; captureCorner(ax, ay);
  Serial.printf("   corner A: rawX=%d rawY=%d mV  -- release\n", ax, ay);
  waitRelease();
  Serial.println(">> 2) press & hold the OPPOSITE corner (top-right)...");
  int bx, by; captureCorner(bx, by);
  Serial.printf("   corner B: rawX=%d rawY=%d mV  -- release\n", bx, by);
  waitRelease();
  xMin = min(ax, bx); xMax = max(ax, bx);     // per-axis extremes (works for either diagonal)
  yMin = min(ay, by); yMax = max(ay, by);
  saveCal();
  Serial.printf(">> calibrated & saved: X[%d..%d] Y[%d..%d] mV  ->  full %d/%d, grid %dx%d\n",
                xMin, xMax, yMin, yMax, X_FULL, Y_FULL, GRID_X, GRID_Y);
}

void setup() {
  Serial.begin(115200);
  Serial2.begin(UART_BAUD, SERIAL_8N1, PIN_UART_RX, PIN_UART_TX);
  analogReadResolution(10);
  analogSetAttenuation(ADC_11db);
  pinMode(PIN_MODE,      INPUT_PULLUP);
  pinMode(PIN_DISP,      INPUT_PULLUP);
  pinMode(PIN_SW_WALL,   INPUT_PULLUP);
  pinMode(PIN_BTN_CLEAR, INPUT_PULLUP);
  idlePanel();
  loadCal();
  delay(200);
  Serial.println("ESP32 one-panel firmware ready (Panel -> 64x38 grid cell, X 0..63 Y 0..37; UART2 -> PS).");
  if (!calValid() || digitalRead(PIN_BTN_CLEAR) == LOW) {       // no cal stored, or Clear held
    Serial.println("(no saved calibration, or Clear held at boot)");
    calibrate();
  } else {
    Serial.printf("loaded calibration X[%d..%d] Y[%d..%d]. Hold Clear at boot or send 'c' to recalibrate.\n",
                  xMin, xMax, yMin, yMax);
  }
}

void loop() {
  uint32_t t0 = millis();
  if (Serial.available() && Serial.read() == 'c') calibrate();   // recalibrate on demand

  bool mode2  = (digitalRead(PIN_MODE) == LOW);   // shared switch: LOW = Mode 2
  bool threeD = (digitalRead(PIN_DISP) == LOW);

  int  sense   = panelSense();
  bool touched = sense < TOUCH_THRESH;
  int  gx = 0, gy = 0, rx = -1, ry = -1, xf = -1, yf = -1;
  if (touched) {
    rx = readYmv();   // long edge  (16.4 cm) -> X
    ry = readXmv();   // short edge ( 9.8 cm) -> Y
    xf = toScale(rx, xMin, xMax, X_FULL);      // calibrated full-scale 0..1023
    yf = toScale(ry, yMin, yMax, Y_FULL);      // calibrated full-scale 0..612
    gx = toGrid(xf, X_FULL, GRID_X);           // fit to 64-col grid -> 0..63
    gy = toGrid(yf, Y_FULL, GRID_Y);           // fit to 38-row grid -> 0..37
  }
  idlePanel();

  int  amp       = sampleADC(PIN_POT_AMP);
  int  cond      = sampleADC(PIN_POT_COND);
  int  yaw       = sampleADC(PIN_POT_YAW);               // 3D view (both modes)
  int  pitch     = sampleADC(PIN_POT_PITCH);
  int  zoom      = sampleADC(PIN_POT_ZOOM);
  int  zscale    = sampleADC(PIN_POT_ZSCALE);
  int  fieldType = mode2 ? readFieldType() : 0;          // Mode 2
  int  probe     = mode2 ? 0 : sampleADC(PIN_PROBE);     // Mode 1 measured potential
  bool wall  = (digitalRead(PIN_SW_WALL)   == LOW);
  bool clear = (digitalRead(PIN_BTN_CLEAR) == LOW);

  uint8_t buf[21];
  buf[0] = 0xAA;
  buf[1] = (mode2   ? 0x01 : 0)
         | (threeD  ? 0x02 : 0)
         | ((fieldType & 0x03) << 2)
         | (wall    ? 0x10 : 0)
         | (clear   ? 0x20 : 0)
         | (touched ? 0x40 : 0);
  putU16(buf,  2, gx);       // Panel X grid cell (0..63)
  putU16(buf,  4, gy);       // Panel Y grid cell (0..37)
  putU16(buf,  6, amp);
  putU16(buf,  8, cond);
  putU16(buf, 10, probe);
  putU16(buf, 12, yaw);
  putU16(buf, 14, pitch);
  putU16(buf, 16, zoom);
  putU16(buf, 18, zscale);
  uint8_t cks = 0; for (int i = 1; i <= 19; i++) cks ^= buf[i]; buf[20] = cks;
  Serial2.write(buf, sizeof(buf));

#if DEBUG
  static uint32_t dbg = 0;
  if (millis() - dbg >= DEBUG_MS) {
    dbg = millis();
    Serial.printf("M%d %s touch=%d sense=%4d | rawX=%5d rawY=%5d mV  full(%4d,%4d) -> grid X=%2d Y=%2d | cal X[%d..%d] Y[%d..%d]\n",
                  mode2 ? 2 : 1, threeD ? "3D" : "2D", touched, sense, rx, ry, xf, yf, gx, gy, xMin, xMax, yMin, yMax);
    Serial.printf("    amp=%4d cond=%4d field=%d yaw=%4d pitch=%4d zoom=%4d zscale=%4d | wall=%d clr=%d probe=%4d\n",
                  amp, cond, fieldType, yaw, pitch, zoom, zscale, wall, clear, probe);
  }
#endif

  while (millis() - t0 < 20) { }                  // ~50 Hz
}
