#include "settings.h"
#include <Preferences.h>

#if __has_include("secrets.h")
#include "secrets.h"
#endif
#ifndef WIFI_SSID
#define WIFI_SSID ""
#endif
#ifndef WIFI_PASS
#define WIFI_PASS ""
#endif
#ifndef VOX_EMAIL
#define VOX_EMAIL ""
#endif
#ifndef VOX_PASSWORD
#define VOX_PASSWORD ""
#endif
#ifndef TIME_ZONE
#define TIME_ZONE "IST-5:30"
#endif

const char* const SCREEN_NAMES[SCR_COUNT] = {"Face", "Clock", "Today", "Tomorrow", "Upcoming", "Tasks"};

static const char* NS = "vox";

// secrets.h copied from the example still has its placeholder text. Treat that as empty.
static String real(const String& value) {
  if (value.startsWith("your ") || value == "you@example.com") return "";
  return value;
}

void settingsLoad(Settings& s) {
  Preferences p;
  p.begin(NS, false);  // read-write, so the first boot creates the namespace instead of logging an error
  s.wifiSSID = real(p.getString("ssid", WIFI_SSID));
  s.wifiPass = real(p.getString("wpass", WIFI_PASS));
  s.email = real(p.getString("email", VOX_EMAIL));
  s.password = real(p.getString("vpass", VOX_PASSWORD));
  s.timeZone = p.getString("tz", TIME_ZONE);
  s.brightness = p.getUChar("bright", 200);
  s.screens = p.getUChar("screens", 0x3F);
  s.idle = p.getUChar("idle", SCR_FACE);
  s.idleAfter = p.getUShort("idleAfter", 60);
  s.flip = p.getBool("flip", false);
  s.clock24 = p.getBool("clock24", true);
  p.end();
  if (s.screens == 0) s.screens = 1 << SCR_CLOCK;
  if (s.idle >= SCR_COUNT || !s.shows((Screen)s.idle)) {
    for (int i = 0; i < SCR_COUNT; i++) if (s.shows((Screen)i)) { s.idle = i; break; }
  }
}

void settingsSave(const Settings& s) {
  Preferences p;
  p.begin(NS, false);
  p.putString("ssid", s.wifiSSID);
  p.putString("wpass", s.wifiPass);
  p.putString("email", s.email);
  p.putString("vpass", s.password);
  p.putString("tz", s.timeZone);
  p.putUChar("bright", s.brightness);
  p.putUChar("screens", s.screens);
  p.putUChar("idle", s.idle);
  p.putUShort("idleAfter", s.idleAfter);
  p.putBool("flip", s.flip);
  p.putBool("clock24", s.clock24);
  p.end();
}
