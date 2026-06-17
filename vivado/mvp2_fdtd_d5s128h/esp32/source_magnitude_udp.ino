// ESP32 -> PYNQ PS : UDP source-magnitude control
// Reads the probe (analog), sends the raw value as an ASCII datagram to the
// PYNQ over WiFi/UDP. The PS maps it to the FDTD source amplitude.
//
// Packet format : one ASCII integer per datagram, e.g. "2731\n"
// Rate          : ~100 Hz (every 10 ms)
// Both devices must be on the SAME local network (ESP32 on the same WiFi
// router the PYNQ Ethernet is plugged into).

#include <WiFi.h>
#include <WiFiUdp.h>

const char*    WIFI_SSID = "YOUR_WIFI";
const char*    WIFI_PASS = "YOUR_PASS";
const char*    PYNQ_IP   = "192.168.1.50";   // PYNQ IP  (run `hostname -I` on the board)
const uint16_t PYNQ_PORT = 5005;
const int      PROBE_PIN  = 34;               // ADC1 pin reading the probe (0..4095)

WiFiUDP udp;

void setup() {
  Serial.begin(115200);
  analogReadResolution(12);                   // ESP32 ADC: 0..4095
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  while (WiFi.status() != WL_CONNECTED) { delay(200); Serial.print('.'); }
  Serial.print("\nESP32 IP: "); Serial.println(WiFi.localIP());
  Serial.print("sending to "); Serial.print(PYNQ_IP);
  Serial.print(':'); Serial.println(PYNQ_PORT);
}

void loop() {
  int raw = analogRead(PROBE_PIN);            // probe magnitude, 0..4095
  char buf[12];
  int n = snprintf(buf, sizeof(buf), "%d", raw);
  udp.beginPacket(PYNQ_IP, PYNQ_PORT);
  udp.write((const uint8_t*)buf, n);
  udp.endPacket();
  delay(10);                                  // ~100 Hz
}
