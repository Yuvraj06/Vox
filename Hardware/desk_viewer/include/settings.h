// Everything the admin page can change. Saved in the ESP32's own flash (NVS), so it survives power loss.
// secrets.h, if present, only gives the first-time defaults.
#pragma once
#include <Arduino.h>

enum Screen : uint8_t { SCR_FACE, SCR_CLOCK, SCR_TODAY, SCR_TOMORROW, SCR_UPCOMING, SCR_TASKS, SCR_COUNT };
extern const char* const SCREEN_NAMES[SCR_COUNT];

struct Settings {
  String wifiSSID;
  String wifiPass;
  String email;
  String password;
  String timeZone;      // POSIX form, like "IST-5:30"
  uint8_t brightness;   // 0..255, OLED contrast
  uint8_t screens;      // bit per Screen: which ones a tap cycles through
  uint8_t idle;         // Screen shown after a while with no touch
  uint16_t idleAfter;   // seconds
  bool flip;            // screen mounted upside down
  bool clock24;

  bool hasWiFi() const { return wifiSSID.length() > 0; }
  bool hasAccount() const { return email.length() > 0 && password.length() > 0; }
  bool shows(Screen s) const { return screens & (1 << s); }
};

void settingsLoad(Settings& s);
void settingsSave(const Settings& s);
