// ===================================================================
//  EE2 — hardware_onepanel PORT / CONTROLS TEST
//  Reads the panel, probe, all 7 pots and the 4 switches and prints them
//  to the Serial Monitor @ 115200, ~3x/second. No FPGA / UART2 needed.
//
//  Use it to verify every wire:
//    * turn each pot fully both ways  -> raw should sweep ~0..1023 (mV ~0..3300)
//    * flip mode/2D-3D/wall, press clear -> the state should toggle
//    * press the panel / drag a stylus -> touch=1 and rawX/rawY change
//  If a pot reads stuck at 0 or 4095 / a switch never changes, that pin is
//  mis-wired (or, for zscale on GPIO36/VP, that pin may be absent on your board).
//  Board: "ESP32 Dev Module". WiFi stays off.
// ===================================================================

#define ADC_MAX 1023

// ---- Panel (6-pin split drive/sense) ----
#define XP_DRIVE 18
#define XP_SENSE 32      // pull-up -> touch detect
#define XM       23
#define YP_DRIVE 25
#define YP_SENSE 35
#define YM       22

// ---- analog controls ----
#define PIN_PROBE      34
#define PIN_POT_AMP    13
#define PIN_POT_COND   33
#define PIN_FIELD_POT   4
#define PIN_POT_YAW    27
#define PIN_POT_PITCH  14
#define PIN_POT_ZOOM   26
#define PIN_POT_ZSCALE 36   // GPIO36 / VP (input-only)

// ---- digital controls ----
#define PIN_MODE      21
#define PIN_DISP      19
#define PIN_SW_WALL    5
#define PIN_BTN_CLEAR 15

#define SETTLE_MS 6

int sampleADC(uint8_t pin) {                 // median-of-3 raw counts
  int a = analogRead(pin), b = analogRead(pin), c = analogRead(pin);
  return a + b + c - max(a, max(b, c)) - min(a, min(b, c));
}

void idlePanel() {
  pinMode(XP_DRIVE, INPUT); pinMode(XP_SENSE, INPUT); pinMode(XM, INPUT);
  pinMode(YP_DRIVE, INPUT); pinMode(YP_SENSE, INPUT); pinMode(YM, INPUT);
}
bool panelTouched() {                         // Y- low, read X+ via pull-up
  pinMode(XP_DRIVE, INPUT); pinMode(XM, INPUT);
  pinMode(YP_DRIVE, INPUT); pinMode(YP_SENSE, INPUT);
  pinMode(YM, OUTPUT); digitalWrite(YM, LOW);
  pinMode(XP_SENSE, INPUT_PULLUP);
  delay(SETTLE_MS);
  bool down = sampleADC(XP_SENSE) < (7 * ADC_MAX) / 10;
  pinMode(XP_SENSE, INPUT);
  return down;
}
int readXlong() {                             // drive Y-layer, sense X+  (16.4 cm -> X)
  pinMode(YP_DRIVE, OUTPUT); digitalWrite(YP_DRIVE, HIGH);
  pinMode(YM, OUTPUT);       digitalWrite(YM, LOW);
  pinMode(YP_SENSE, INPUT); pinMode(XP_DRIVE, INPUT); pinMode(XM, INPUT); pinMode(XP_SENSE, INPUT);
  delay(SETTLE_MS);
  return sampleADC(XP_SENSE);
}
int readYshort() {                            // drive X-layer, sense Y+  (9.8 cm -> Y)
  pinMode(XP_DRIVE, OUTPUT); digitalWrite(XP_DRIVE, HIGH);
  pinMode(XM, OUTPUT);       digitalWrite(XM, LOW);
  pinMode(XP_SENSE, INPUT); pinMode(YP_DRIVE, INPUT); pinMode(YM, INPUT); pinMode(YP_SENSE, INPUT);
  delay(SETTLE_MS);
  return sampleADC(YP_SENSE);
}

// print one pot as "name(pin): raw / mV"
void showPot(const char* name, uint8_t pin) {
  Serial.printf("  %-7s(%2d): %4d / %4u mV\n", name, pin, sampleADC(pin), analogReadMilliVolts(pin));
}

void setup() {
  Serial.begin(115200);
  analogReadResolution(10);
  analogSetAttenuation(ADC_11db);
  pinMode(PIN_MODE,      INPUT_PULLUP);
  pinMode(PIN_DISP,      INPUT_PULLUP);
  pinMode(PIN_SW_WALL,   INPUT_PULLUP);
  pinMode(PIN_BTN_CLEAR, INPUT_PULLUP);
  idlePanel();
  delay(300);
  Serial.println();
  Serial.println("=== hardware_onepanel controls test ===");
  Serial.println("Turn each pot / flip each switch / press the panel and watch the values.");
}

void loop() {
  // ---- panel ----
  bool t = panelTouched();
  int  rx = -1, ry = -1;
  if (t) { rx = readXlong(); ry = readYshort(); }
  idlePanel();

  Serial.println("---------------------------------------------");
  Serial.printf("PANEL : touch=%d  rawX(long)=%4d  rawY(short)=%4d\n", t, rx, ry);
  Serial.printf("PROBE : (34) %4d / %4u mV   [meaningful in Mode 1]\n",
                sampleADC(PIN_PROBE), analogReadMilliVolts(PIN_PROBE));

  Serial.println("POTS (raw / mV):");
  showPot("amp",   PIN_POT_AMP);
  showPot("cond",  PIN_POT_COND);
  showPot("field", PIN_FIELD_POT);
  showPot("yaw",   PIN_POT_YAW);
  showPot("pitch", PIN_POT_PITCH);
  showPot("zoom",  PIN_POT_ZOOM);
  showPot("zscale",PIN_POT_ZSCALE);   // if stuck at 0/4095, GPIO36/VP may be missing

  Serial.printf("SWITCHES: mode(21)=%s  disp(19)=%s  wall(5)=%s  clear(15)=%s\n",
                digitalRead(PIN_MODE)      ? "HIGH(Mode1)" : "LOW(Mode2)",
                digitalRead(PIN_DISP)      ? "HIGH(2D)"    : "LOW(3D)",
                digitalRead(PIN_SW_WALL)   ? "HIGH(source)": "LOW(wall)",
                digitalRead(PIN_BTN_CLEAR) ? "HIGH(up)"    : "LOW(pressed)");

  delay(300);                                  // ~3 updates/second
}
