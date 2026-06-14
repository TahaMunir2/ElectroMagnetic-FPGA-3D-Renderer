// ESP32 -> PYNQ PS over USB SERIAL : source-POSITION control
// Reads a 2-axis probe (two pots / a joystick) and streams "x,y" lines over the
// USB serial link. The PS maps each axis to a grid coordinate and moves the FDTD
// SOURCE there live -- "drag the probe to move the source".
//
// This is a DIFFERENT demo from:
//   * source_magnitude_udp.ino  -> one axis, WiFi/UDP, controls source AMPLITUDE
//   * the in-PL Doppler sweep    -> source auto-moves at a fixed velocity (move_en=1)
// Here move_en=0 and the PS owns the position.
//
// Packet format : two ASCII ints per line, e.g. "2731,1840\n"  (0..4095 each)
// Rate          : ~100 Hz
// Wiring        : plug the ESP32 into the PYNQ USB; it enumerates as
//                 /dev/ttyUSB0 (CP210x) or /dev/ttyACM0. No WiFi needed.

const int X_PIN = 34;        // ADC1 channel - X axis (0..4095)
const int Y_PIN = 35;        // ADC1 channel - Y axis (0..4095)

void setup() {
  Serial.begin(115200);      // matches ProbePositionSerial(baud=115200)
  analogReadResolution(12);  // ESP32 ADC: 0..4095
}

void loop() {
  int xr = analogRead(X_PIN);
  int yr = analogRead(Y_PIN);
  Serial.print(xr);
  Serial.print(',');
  Serial.println(yr);        // "x,y\n" -- the comma convention the PS parser expects
  delay(10);                 // ~100 Hz
}
