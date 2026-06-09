// =====================================================================
//  ESP32-WROOM-32 — 4-wire touch panel test (hardware_onepanel)
//  The single panel is wired DIRECTLY (no DG413) — just press it.
//  Prints touch state + raw X/Y to the Serial Monitor @ 115200.
//
//  WIRING (6-pin split drive/sense):
//    Panel X+  -> GPIO18 (drive) + GPIO32 (sense Y-coord)
//    Panel X-  -> GPIO23 (drive)
//    Panel Y+  -> GPIO25/DAC1 (drive) + GPIO35 (sense X-coord)
//    Panel Y-  -> GPIO22 (drive)
//    Panel GND shares ESP32 GND
//  Connector (resistivetouchpanel.jpg): X+=pin4(X2) X-=pin2(X1) Y+=pin3(Y2) Y-=pin1(Y1)
// =====================================================================

#define XP  18   // X+ : GPIO, drives HIGH during X read
#define XM  23   // X- : GPIO, drives LOW  during X read
#define YP  25   // Y+ : DAC1, drives ~3.3V during Y read
#define YM  22   // Y- : GPIO, drives LOW  during Y read

#define SENSE_X 35   // ADC on the Y+ terminal (Y-layer); read while driving the X-layer
#define SENSE_Y 32   // ADC on the X+ terminal (X-layer); has pull-up (touch detect)

#define SETTLE_MS 5  // Panel 1 has a 10k/100nF filter -> 5 ms settle (Panel 2: 1 ms)

void idle() {                 // all four terminals high-Z
  pinMode(XP, INPUT);
  pinMode(XM, INPUT);
  pinMode(YP, INPUT);         // releases the DAC pad
  pinMode(YM, INPUT);
}

// median-of-3: discards the single worst spike
int sampleADC(uint8_t pin) {
  int a = analogRead(pin), b = analogRead(pin), c = analogRead(pin);
  return a + b + c - max(a, max(b, c)) - min(a, min(b, c));
}

int readX() {
  pinMode(XP, OUTPUT); digitalWrite(XP, HIGH);  // X ladder +
  pinMode(XM, OUTPUT); digitalWrite(XM, LOW);   // X ladder -
  pinMode(YP, INPUT);                           // Y layer floats = sense
  pinMode(YM, INPUT);
  delay(SETTLE_MS);
  return sampleADC(SENSE_X);                     // read on the Y layer
}

int readY() {
  pinMode(XP, INPUT);                           // X layer floats = sense
  pinMode(XM, INPUT);
  pinMode(YM, OUTPUT); digitalWrite(YM, LOW);   // Y ladder -
  dacWrite(YP, 255);                            // Y ladder + (~3.3 V)
  delay(SETTLE_MS);
  return sampleADC(SENSE_Y);                     // read on the X layer
}

// Touch detect: drive Y- low, read the X-layer sense through a pull-up.
//   touched   -> contact pulls SENSE_Y toward 0 -> reads LOW
//   untouched -> internal pull-up holds it HIGH
// SENSE_Y (GPIO32) has an internal pull-up; GPIO35 does NOT, so detect here.
bool touched() {
  pinMode(XP, INPUT);
  pinMode(XM, INPUT);
  pinMode(YP, INPUT);
  pinMode(YM, OUTPUT); digitalWrite(YM, LOW);
  pinMode(SENSE_Y, INPUT_PULLUP);
  delayMicroseconds(100);
  bool down = (digitalRead(SENSE_Y) == LOW);
  pinMode(SENSE_Y, INPUT);                       // restore for analogRead
  return down;
}

void setup() {
  Serial.begin(115200);
  analogReadResolution(10);          // 0..1023
  analogSetAttenuation(ADC_11db);    // ~0..3.3 V input range
  idle();
  Serial.println("Panel test ready. Press the panel...");
}

void loop() {
  if (touched()) {
    // The panel's X-layer is the 9.8 cm (short) edge and its Y-layer the 16.4 cm (long)
    // edge, so the LONG edge is our X coordinate: X = readY(), Y = readX().
    int x = readY();   // drive Y-layer -> 16.4 cm long edge -> X
    int y = readX();   // drive X-layer ->  9.8 cm short edge -> Y
    Serial.printf("TOUCH   X=%4d  Y=%4d\n", x, y);
  } else {
    Serial.println("-- no touch --");
  }
  idle();
  delay(100);                        // ~10 Hz
}
