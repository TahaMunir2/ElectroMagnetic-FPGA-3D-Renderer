// ===================================================================
//  EE2 FDTD EM Wave Simulator — Panel 1 bring-up test (auto-calibrating)
//
//  Panel connector (4-wire, from resistivetouchpanel.jpg):
//      pin 1 = Y1 , pin 2 = X1 , pin 3 = Y2 , pin 4 = X2
//  Wiring to the ESP32 (X1/X2 = X layer, Y1/Y2 = Y layer):
//      pin 4  X2 -> GPIO32  (X+ : drives HIGH / senses)
//      pin 2  X1 -> GPIO23  (X- : digital LOW / Hi-Z)
//      pin 3  Y2 -> GPIO33  (Y+ : drives HIGH / senses)
//      pin 1  Y1 -> GPIO22  (Y- : digital LOW / Hi-Z)
//
//  NO MANUAL CALIBRATION. The sketch learns each axis's raw min/max live from
//  FIRM presses: sweep a stylus firmly around all four edges/corners once after
//  boot and the output stretches to full range. Physically proportional:
//      X -> 0..1023 over 16.4 cm   |   Y -> 0..612 over 9.8 cm
//  The outer EDGE_MARGIN of the learned span clamps to 0 / full, so the noisy
//  boundary reads a steady value instead of wandering. Send 'r' to relearn.
//
//  Coordinates are sampled with analogReadMilliVolts(), which applies the ESP32's
//  ADC calibration to LINEARISE the reading (raw analogRead() at 11 dB is very
//  nonlinear — a centre press would otherwise read ~78% instead of 50%).
//  Board: "ESP32 Dev Module". WiFi stays off.
// ===================================================================

#define ADC_MAX      1023      // 10-bit full scale
#define SETTLE_MS    8         // let the panel + RC filter settle before sampling
#define TOUCH_FRAC   0.70f     // touched if sense < this fraction of full scale
#define FIRM_FRAC    0.45f     // only LEARN the range from presses firmer than this
#define REPORT_MS    60        // serial print period

// ---- Panel 1 pins ----
#define PIN_XP   32   // X+  (panel pin 4, X2)
#define PIN_YP   33   // Y+  (panel pin 3, Y2)
#define PIN_XM   23   // X-  (panel pin 2, X1)
#define PIN_YM   22   // Y-  (panel pin 1, Y1)

// ---- output ranges (physically proportional) ----
#define X_OUT_MAX  1023   // 16.4 cm
#define Y_OUT_MAX  612    //  9.8 cm

// ---- filtering / auto-calibration tuning ----
#define OVERSAMPLE   12        // reads per coordinate (trimmed-mean of these)
#define TRIM          3        // drop this many lowest + highest before averaging
#define MIN_SPAN    300        // need this much learned span (mV) before mapping
#define EDGE_MARGIN  0.06f     // outer 6% of span clamps to 0 / full
#define EMA_ALPHA    0.40f     // output smoothing (higher = snappier, lower = smoother)

const int TOUCH_THRESH = (int)(TOUCH_FRAC * ADC_MAX);
const int FIRM_THRESH  = (int)(FIRM_FRAC  * ADC_MAX);

// learned extremes in mV (start inverted so the first firm presses define them)
int xRawMin = 9999, xRawMax = -1, yRawMin = 9999, yRawMax = -1;
float emaX = -1, emaY = -1;            // smoothed output

// quick median-of-3 raw counts (used for touch detect only — a threshold, not a coord)
int sampleADC(uint8_t pin) {
  int a = analogRead(pin), b = analogRead(pin), c = analogRead(pin);
  return a + b + c - max(a, max(b, c)) - min(a, min(b, c));
}

// trimmed-mean of OVERSAMPLE *linearised* reads (mV) — analogReadMilliVolts()
// corrects the ESP32 ADC nonlinearity so position maps ~linearly.
int sampleTrim(uint8_t pin) {
  int a[OVERSAMPLE];
  for (int i = 0; i < OVERSAMPLE; i++) a[i] = analogReadMilliVolts(pin);
  for (int i = 1; i < OVERSAMPLE; i++) {        // insertion sort
    int k = a[i], j = i - 1;
    while (j >= 0 && a[j] > k) { a[j + 1] = a[j]; j--; }
    a[j + 1] = k;
  }
  long s = 0;
  for (int i = TRIM; i < OVERSAMPLE - TRIM; i++) s += a[i];
  return (int)(s / (OVERSAMPLE - 2 * TRIM));
}

void idlePanel() {
  pinMode(PIN_XP, INPUT); pinMode(PIN_YP, INPUT);
  pinMode(PIN_XM, INPUT); pinMode(PIN_YM, INPUT);
}

// touch detect: drive Y- LOW, read X+ through its pull-up (low when touched)
int touchSense() {
  pinMode(PIN_XM, INPUT);
  pinMode(PIN_YP, INPUT);
  pinMode(PIN_YM, OUTPUT); digitalWrite(PIN_YM, LOW);
  pinMode(PIN_XP, INPUT_PULLUP);
  delay(SETTLE_MS);
  int v = sampleADC(PIN_XP);
  pinMode(PIN_XP, INPUT);
  return v;
}

int readX() {  // X+ = HIGH, X- = LOW, Y floats, sense Y+
  pinMode(PIN_XP, OUTPUT); digitalWrite(PIN_XP, HIGH);
  pinMode(PIN_XM, OUTPUT); digitalWrite(PIN_XM, LOW);
  pinMode(PIN_YP, INPUT); pinMode(PIN_YM, INPUT);
  delay(SETTLE_MS);
  return sampleTrim(PIN_YP);
}

int readY() {  // Y+ = HIGH, Y- = LOW, X floats, sense X+
  pinMode(PIN_YP, OUTPUT); digitalWrite(PIN_YP, HIGH);
  pinMode(PIN_YM, OUTPUT); digitalWrite(PIN_YM, LOW);
  pinMode(PIN_XP, INPUT); pinMode(PIN_XM, INPUT);
  delay(SETTLE_MS);
  return sampleTrim(PIN_XP);
}

// map a raw count to 0..outMax using the learned span, with margin + clamp.
// returns -1 until enough span has been learned.
int mapAxis(int raw, int rmin, int rmax, int outMax) {
  int span = rmax - rmin;
  if (span < MIN_SPAN) return -1;
  int m = (int)(EDGE_MARGIN * span);
  long v = (long)(raw - (rmin + m)) * outMax / (span - 2 * m);
  return constrain((int)v, 0, outMax);
}

void resetCal() {
  xRawMin = 9999; xRawMax = -1; yRawMin = 9999; yRawMax = -1;
  emaX = emaY = -1;
  Serial.println(">> calibration reset — sweep all four edges/corners firmly again.");
}

void setup() {
  Serial.begin(115200);
  analogReadResolution(10);
  analogSetAttenuation(ADC_11db);
  idlePanel();
  delay(200);
  Serial.println();
  Serial.println("Panel 1 auto-calibrating test (X+=32 Y+=33 X-=23 Y-=22).");
  Serial.println("Press FIRMLY around ALL edges/corners once. Send 'r' to relearn.");
}

void loop() {
  static uint32_t last = 0;
  if (Serial.available() && Serial.read() == 'r') resetCal();
  if (millis() - last < REPORT_MS) return;
  last = millis();

  int sense = touchSense();
  if (sense >= TOUCH_THRESH) {                       // released
    Serial.printf("(release)        learned X[%d..%d] Y[%d..%d]\n",
                  xRawMin, xRawMax, yRawMin, yRawMax);
    idlePanel();
    return;
  }

  int rx = readX(), ry = readY();
  idlePanel();

  // learn the range only from FIRM presses (rejects light/partial contacts)
  if (sense < FIRM_THRESH) {
    if (rx < xRawMin) xRawMin = rx;  if (rx > xRawMax) xRawMax = rx;
    if (ry < yRawMin) yRawMin = ry;  if (ry > yRawMax) yRawMax = ry;
  }

  int xc = mapAxis(rx, xRawMin, xRawMax, X_OUT_MAX);
  int yc = mapAxis(ry, yRawMin, yRawMax, Y_OUT_MAX);
  if (xc < 0 || yc < 0) {
    Serial.printf("calibrating... press the edges firmly   mV(%d,%d) X[%d..%d] Y[%d..%d]\n",
                  rx, ry, xRawMin, xRawMax, yRawMin, yRawMax);
    return;
  }

  // smooth the output
  emaX = (emaX < 0) ? xc : EMA_ALPHA * xc + (1 - EMA_ALPHA) * emaX;
  emaY = (emaY < 0) ? yc : EMA_ALPHA * yc + (1 - EMA_ALPHA) * emaY;

  Serial.printf("X=%4d  Y=%4d   (mV %4d,%4d)\n",
                (int)(emaX + 0.5f), (int)(emaY + 0.5f), rx, ry);
}
