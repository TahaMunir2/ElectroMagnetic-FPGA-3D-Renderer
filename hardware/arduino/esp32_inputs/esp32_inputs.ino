// ===================================================================
//  EE2 FDTD EM Wave Simulator — ESP32-WROOM-32 input firmware
//  2 independent touch panels (idle one tri-stated), 6 pots,
//  mode/2D-3D encoder, field-type pot, wall/source switch, clear button.
//  Sends 21-byte packet to PYNQ over UART2 @ ~50 Hz.
//  WiFi MUST stay off — ADC2 pins are in use.
//  Pot/probe values are raw ADC counts (0..ADC_MAX). Panel X/Y are CALIBRATED
//  to a physically-proportional grid: X 0..1023 (16.4 cm), Y 0..612 (9.8 cm),
//  same counts/cm on both axes. Only the probe is a real measured voltage.
//
//  Panel connector (4-wire, see resistivetouchpanel.jpg): pin1=Y1 pin2=X1
//  pin3=Y2 pin4=X2.  Panel 1 wiring: X2->32(X+) X1->23(X-) Y2->33(Y+) Y1->22(Y-).
// ===================================================================

#define ADC_MAX 1023           // 10-bit full scale; all thresholds are fractions of this

// Panel output ranges — physically proportional (same counts/cm on both axes).
// X is the 16.4 cm edge, Y the 9.8 cm edge. If your panel is rotated so these
// come out swapped, swap X_OUT_MAX/Y_OUT_MAX (or the panel's X/Y pin pairs).
#define X_OUT_MAX 1023         // 16.4 cm -> 0..1023
#define Y_OUT_MAX 612          //  9.8 cm -> 0..612

// ---------- Touch panels (independent; idle panel tri-stated) -------
struct Panel {
  uint8_t  xp;   // X+ : ADC GPIO — HIGH (X read) / sense Y-coord (Y read) / touch
  uint8_t  yp;   // Y+ : ADC GPIO — HIGH (Y read) / sense X-coord (X read)
  uint8_t  xm;   // X- : digital  — LOW (X read) / Hi-Z
  uint8_t  ym;   // Y- : digital  — LOW (Y read) / Hi-Z / touch
  uint16_t settleMs;
  // raw-ADC calibration extremes per axis (measure with panel1_test; map -> out range)
  int xRawMin, xRawMax, yRawMin, yRawMax;
};
//                xp  yp  xm  ym  settle   xRawMin xRawMax yRawMin yRawMax
Panel panel1 = {  32, 33, 23, 22,   5,        0,    1023,    0,    1023 };  // Mode 1 (10k/100nF -> 5 ms)
Panel panel2 = {  25, 26, 21, 19,   1,        0,    1023,    0,    1023 };  // Mode 2 (no filter -> 1 ms)

// ---------- Analog inputs ----------
#define PIN_PROBE      34   // Mode 1 only (real measured potential)
#define PIN_MODE_ENC   35   // mode + 2D/3D, 4-level R/2R encoder
#define PIN_FIELD_POT  36   // Mode 2 only, field type E/B/S
#define PIN_POT_YAW    39
#define PIN_POT_PITCH  27
#define PIN_POT_ZOOM   14
#define PIN_POT_ZSCALE 13
#define PIN_POT_AMP     4
#define PIN_POT_COND   15   // conductivity -> Mode 2 wave speed (c)

// ---------- Digital inputs ----------
#define PIN_SW_WALL     5   // Mode 2: LOW = wall, HIGH = source
#define PIN_BTN_CLEAR  18   // clear / erase button (active LOW)

// ---------- UART to PYNQ ----------
#define PIN_UART_TX    17   // -> PYNQ Arduino header D0 (RX)
#define PIN_UART_RX    16   // <- PYNQ Arduino header D1 (TX)
#define UART_BAUD  115200

// ---------- helpers ----------
int sampleADC(uint8_t pin) {              // median-of-3, rejects one spike
  int a = analogRead(pin), b = analogRead(pin), c = analogRead(pin);
  return a + b + c - max(a, max(b, c)) - min(a, min(b, c));
}

void idlePanel(const Panel& p) {          // tri-state all four terminals
  pinMode(p.xp, INPUT); pinMode(p.yp, INPUT);
  pinMode(p.xm, INPUT); pinMode(p.ym, INPUT);
}

bool panelTouched(const Panel& p) {       // drive Y- low, read X+ via pull-up
  pinMode(p.xm, INPUT);
  pinMode(p.yp, INPUT);
  pinMode(p.ym, OUTPUT); digitalWrite(p.ym, LOW);
  pinMode(p.xp, INPUT_PULLUP);
  delay(p.settleMs);
  bool down = sampleADC(p.xp) < (7 * ADC_MAX) / 10;   // ~full scale untouched
  pinMode(p.xp, INPUT);
  return down;
}

int panelReadX(const Panel& p) {          // X-coordinate (sense on Y+)
  pinMode(p.xp, OUTPUT); digitalWrite(p.xp, HIGH);   // X ladder +
  pinMode(p.xm, OUTPUT); digitalWrite(p.xm, LOW);    // X ladder -
  pinMode(p.yp, INPUT);                              // Y layer floats
  pinMode(p.ym, INPUT);
  delay(p.settleMs);
  return sampleADC(p.yp);
}

int panelReadY(const Panel& p) {          // Y-coordinate (sense on X+)
  pinMode(p.yp, OUTPUT); digitalWrite(p.yp, HIGH);   // Y ladder +
  pinMode(p.ym, OUTPUT); digitalWrite(p.ym, LOW);    // Y ladder -
  pinMode(p.xp, INPUT);                              // X layer floats
  pinMode(p.xm, INPUT);
  delay(p.settleMs);
  return sampleADC(p.xp);
}

// mode+2D/3D encoder: levels at 0, 1/3, 2/3, 1 of full scale
//   0=M1/2D  1=M1/3D  2=M2/2D  3=M2/3D
int readModeEncoder() {
  int v = sampleADC(PIN_MODE_ENC);
  if      (v < ADC_MAX / 6)        return 0;
  else if (v < ADC_MAX / 2)        return 1;
  else if (v < (5 * ADC_MAX) / 6)  return 2;
  else                             return 3;
}

// field-type pot: thirds of full scale -> 0=E 1=B 2=S
int readFieldType() {
  int v = sampleADC(PIN_FIELD_POT);
  if      (v < ADC_MAX / 3)        return 0;
  else if (v < (2 * ADC_MAX) / 3)  return 1;
  else                             return 2;
}

void putU16(uint8_t* b, int i, int v) {   // 10-bit value, high byte first
  b[i] = (v >> 8) & 0xFF;  b[i + 1] = v & 0xFF;
}

// ---------- setup ----------
void setup() {
  Serial.begin(115200);                                       // USB debug
  Serial2.begin(UART_BAUD, SERIAL_8N1, PIN_UART_RX, PIN_UART_TX);
  analogReadResolution(10);                                   // 0..ADC_MAX
  analogSetAttenuation(ADC_11db);                             // full 0..3.3 V span
  pinMode(PIN_SW_WALL,   INPUT_PULLUP);
  pinMode(PIN_BTN_CLEAR, INPUT_PULLUP);
  idlePanel(panel1);
  idlePanel(panel2);
  Serial.println("ESP32 input firmware ready.");
}

// ---------- main loop @ ~50 Hz ----------
void loop() {
  uint32_t t0 = millis();

  int enc = readModeEncoder();
  bool mode2  = enc & 0b10;
  bool threeD = enc & 0b01;

  Panel& P   = mode2 ? panel2 : panel1;
  Panel& off = mode2 ? panel1 : panel2;
  idlePanel(off);                          // idle panel is electrically invisible

  bool touched = panelTouched(P);
  int px = 0, py = 0;
  if (touched) {
    // raw read, then calibrate to the physically-proportional grid
    int rx = panelReadX(P), ry = panelReadY(P);
    px = constrain(map(rx, P.xRawMin, P.xRawMax, 0, X_OUT_MAX), 0, X_OUT_MAX);
    py = constrain(map(ry, P.yRawMin, P.yRawMax, 0, Y_OUT_MAX), 0, Y_OUT_MAX);
  }
  idlePanel(P);

  int amp    = sampleADC(PIN_POT_AMP);
  int cond   = sampleADC(PIN_POT_COND);
  int yaw    = sampleADC(PIN_POT_YAW);
  int pitch  = sampleADC(PIN_POT_PITCH);
  int zoom   = sampleADC(PIN_POT_ZOOM);
  int zscale = sampleADC(PIN_POT_ZSCALE);

  int  fieldType = mode2 ? readFieldType() : 0;       // Mode 2
  int  probe     = mode2 ? 0 : sampleADC(PIN_PROBE);  // Mode 1 measured potential
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
  putU16(buf,  2, px);
  putU16(buf,  4, py);
  putU16(buf,  6, amp);
  putU16(buf,  8, cond);
  putU16(buf, 10, probe);
  putU16(buf, 12, yaw);
  putU16(buf, 14, pitch);
  putU16(buf, 16, zoom);
  putU16(buf, 18, zscale);
  uint8_t cks = 0;
  for (int i = 1; i <= 19; i++) cks ^= buf[i];
  buf[20] = cks;

  Serial2.write(buf, sizeof(buf));

  // Debug (uncomment during bring-up):
  // Serial.printf("M%d %s touch=%d X=%4d Y=%4d ft=%d cond=%4d wall=%d clr=%d\n",
  //               mode2?2:1, threeD?"3D":"2D", touched, px, py, fieldType, cond, wall, clear);

  while (millis() - t0 < 20) { }           // pace to ~50 Hz (20 ms frame)
}
