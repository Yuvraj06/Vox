// Tests the keychain parts together. The OLED and Serial Monitor both show
// the live mic level and button state. Nothing here talks to the phone yet.

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <ESP_I2S.h>
#include <math.h>

// Wiring. See Hardware/README.md.
const int PIN_OLED_SDA = D4;
const int PIN_OLED_SCL = D5;
const int PIN_MIC_SCK = D2;
const int PIN_MIC_WS = D3;
const int PIN_MIC_SD = D10;
const int PIN_BUTTON = D1;
const int PIN_LED = LED_BUILTIN;  // On when the pin is LOW.

const int SCREEN_WIDTH = 128;
const int SCREEN_HEIGHT = 64;

const uint32_t SAMPLE_RATE = 16000;
const int READ_SAMPLES = 256;          // One read is 16 ms of audio.
const int WINDOW_SAMPLES = 1600;       // Level is measured every 100 ms.
const float FULL_SCALE = 8388608.0f;   // The mic sends 24 bit samples.
const float METER_MIN_DB = -80.0f;
const float METER_MAX_DB = -20.0f;

const uint32_t DEBOUNCE_MS = 25;
const uint32_t SERIAL_EVERY_MS = 500;
const uint32_t LED_EVERY_MS = 500;

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1, 100000UL, 100000UL);
I2SClass mic;

bool displayReady = false;
bool micReady = false;

// Mic results from the last full window.
bool micHasSignal = false;
float micRmsDb = -120.0f;
float micPeakDb = -120.0f;

// Running totals for the window being measured.
int windowCount = 0;
double windowSum = 0;
double windowSumSquares = 0;
int32_t windowMin = INT32_MAX;
int32_t windowMax = INT32_MIN;

// Button state.
bool buttonRawDown = false;
bool buttonDown = false;
uint32_t buttonRawChangedAt = 0;
uint32_t buttonPressedAt = 0;
uint32_t buttonHeldMs = 0;
int buttonPresses = 0;

float toDb(float level) {
  return level > 0 ? 20.0f * log10f(level) : -120.0f;
}

void scanI2C() {
  Serial.println("I2C scan:");
  int found = 0;
  for (uint8_t address = 1; address < 127; address++) {
    Wire.beginTransmission(address);
    if (Wire.endTransmission() == 0) {
      Serial.printf("  found device at 0x%02X\n", address);
      found++;
    }
  }
  if (found == 0) {
    Serial.println("  nothing found. Check OLED power, SDA and SCL.");
  }
}

void setupDisplay() {
  Wire.begin(PIN_OLED_SDA, PIN_OLED_SCL);
  scanI2C();

  // These screens use one of two addresses.
  uint8_t address = 0;
  for (uint8_t candidate : {0x3C, 0x3D}) {
    Wire.beginTransmission(candidate);
    if (Wire.endTransmission() == 0) {
      address = candidate;
      break;
    }
  }
  if (address == 0) {
    Serial.println("OLED: FAIL, no screen at 0x3C or 0x3D");
    return;
  }

  displayReady = display.begin(SSD1306_SWITCHCAPVCC, address, false, false);
  Serial.println(displayReady ? "OLED: OK" : "OLED: FAIL, out of memory");
}

void setupMic() {
  mic.setPins(PIN_MIC_SCK, PIN_MIC_WS, -1, PIN_MIC_SD);
  // The mic sends 24 bit audio in 32 bit slots. L/R tied to GND means left.
  micReady = mic.begin(I2S_MODE_STD, SAMPLE_RATE, I2S_DATA_BIT_WIDTH_32BIT,
                       I2S_SLOT_MODE_MONO, I2S_STD_SLOT_LEFT);
  Serial.println(micReady ? "Mic I2S: started" : "Mic I2S: FAIL to start");
}

void finishWindow() {
  // A working mic always has some noise, so a flat line means no real data.
  micHasSignal = windowMax != windowMin;

  // Remove any constant offset so it does not count as sound.
  double mean = windowSum / windowCount;
  double variance = windowSumSquares / windowCount - mean * mean;
  float rms = variance > 0 ? sqrt(variance) : 0;
  float peak = max(fabs(windowMax - mean), fabs(windowMin - mean));

  micRmsDb = toDb(rms / FULL_SCALE);
  micPeakDb = toDb(peak / FULL_SCALE);

  windowCount = 0;
  windowSum = 0;
  windowSumSquares = 0;
  windowMin = INT32_MAX;
  windowMax = INT32_MIN;
}

void readMic() {
  if (!micReady) return;

  static int32_t samples[READ_SAMPLES];
  size_t bytes = mic.readBytes(reinterpret_cast<char *>(samples), sizeof(samples));
  int count = bytes / sizeof(int32_t);

  for (int i = 0; i < count; i++) {
    int32_t sample = samples[i] >> 8;  // Audio sits in the top 24 bits.
    windowSum += sample;
    windowSumSquares += static_cast<double>(sample) * sample;
    windowMin = min(windowMin, sample);
    windowMax = max(windowMax, sample);
    windowCount++;
    if (windowCount >= WINDOW_SAMPLES) finishWindow();
  }
}

void readButton() {
  uint32_t now = millis();
  bool rawDown = digitalRead(PIN_BUTTON) == LOW;

  if (rawDown != buttonRawDown) {
    buttonRawDown = rawDown;
    buttonRawChangedAt = now;
  }
  if (rawDown == buttonDown || now - buttonRawChangedAt < DEBOUNCE_MS) return;

  buttonDown = rawDown;
  if (buttonDown) {
    buttonPresses++;
    buttonPressedAt = now;
    Serial.printf("Button: DOWN (press %d)\n", buttonPresses);
  } else {
    buttonHeldMs = now - buttonPressedAt;
    Serial.printf("Button: UP (held %lu ms)\n", static_cast<unsigned long>(buttonHeldMs));
  }
}

void drawDisplay() {
  if (!displayReady) return;

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.print("VOX HARDWARE TEST");

  display.setCursor(0, 16);
  if (!micReady) {
    display.print("MIC: I2S FAILED");
  } else if (!micHasSignal) {
    display.print("MIC: NO SIGNAL");
  } else {
    display.printf("MIC: %.0f dB", micRmsDb);
  }

  float level = (micRmsDb - METER_MIN_DB) / (METER_MAX_DB - METER_MIN_DB);
  level = constrain(level, 0.0f, 1.0f);
  display.drawRect(0, 27, SCREEN_WIDTH, 9, SSD1306_WHITE);
  if (micHasSignal) {
    display.fillRect(2, 29, static_cast<int>(level * (SCREEN_WIDTH - 4)), 5, SSD1306_WHITE);
  }

  display.setCursor(0, 42);
  display.printf("BTN: %s  count %d", buttonDown ? "DOWN" : "up", buttonPresses);
  display.setCursor(0, 54);
  display.printf("Last hold: %lu ms", static_cast<unsigned long>(buttonHeldMs));

  display.display();
}

void printStatus() {
  if (!micReady) {
    Serial.println("Mic: I2S failed to start");
  } else if (!micHasSignal) {
    Serial.println("Mic: NO SIGNAL. Check SD, SCK, WS, L/R and power.");
  } else {
    Serial.printf("Mic: level %.1f dB, peak %.1f dB\n", micRmsDb, micPeakDb);
  }
}

void setup() {
  Serial.begin(115200);
  delay(1500);  // Gives the Mac time to reconnect to the USB port.
  Serial.println("\n=== Vox hardware test ===");

  pinMode(PIN_LED, OUTPUT);
  pinMode(PIN_BUTTON, INPUT_PULLUP);

  setupDisplay();
  setupMic();
}

void loop() {
  static uint32_t lastSerialAt = 0;
  static uint32_t lastLedAt = 0;
  static int lastDrawnWindow = 0;

  readMic();
  readButton();

  uint32_t now = millis();

  // The LED blinks while the code runs, even if the screen is not working.
  if (now - lastLedAt >= LED_EVERY_MS) {
    lastLedAt = now;
    digitalWrite(PIN_LED, !digitalRead(PIN_LED));
  }
  if (now - lastSerialAt >= SERIAL_EVERY_MS) {
    lastSerialAt = now;
    printStatus();
  }

  // Redraw about 10 times a second. A redraw takes about 25 ms.
  int window = now / 100;
  if (window != lastDrawnWindow) {
    lastDrawnWindow = window;
    drawDisplay();
  }
}
