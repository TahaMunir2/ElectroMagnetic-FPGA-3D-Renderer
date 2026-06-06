// =====================================================================
//  ESP32-WROOM-32  —  single 4-wire touch panel test (Panel 1)
//  Prints touch state + raw X/Y to the Serial Monitor @ 115200
//
//  WIRING (from your excerpt):
//    Panel X+  -> GPIO18 (drive) + GPIO32 (sense Y-coord)
//    Panel X-  -> GPIO23 (drive)
//    Panel Y+  -> GPIO25/DAC1 (drive) + GPIO35 (sense X-coord)
//    Panel Y-  -> GPIO22 (drive)
//    Panel GND reference shares ESP32 GND
// =====================================================================

#define XP  18   // X+ : GPIO, drives HIGH during X read pin3
#define XM  23   // X- : GPIO, drives LOW  during X read pin2
#define YP  25   // Y+ : DAC1, drives ~3.3V during Y read pin4
#define YM  22   // Y- : GPIO, drives LOW  during Y read pin1

#define SENSE_X 35   // ADC: reads X coordinate (sits on the Y layer) pin3
#define SENSE_Y 32   // ADC: reads Y coordinate (sits on the X layer) pin4

#define SETTLE_MS 5  // Panel 1 has the 10k/100nF filter -> 5 ms settle

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
  Serial.println("Panel 1 test ready. Press the panel...");
}

void loop() {
  if (touched()) {
    int x = readX();
    int y = readY();
    Serial.printf("TOUCH   X=%4d  Y=%4d\n", x, y);
  } else {
    Serial.println("-- no touch --");
  }
  idle();
  delay(100);                        // ~10 Hz
}