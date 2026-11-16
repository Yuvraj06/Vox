// Vox desk viewer.
// A resting face, the clock, Today, Tomorrow, what is coming up, and the important tasks,
// straight from Supabase over Wi-Fi. When a task is ticked done anywhere, it shows "Completed".
//
// Setup and settings live in an admin page the board serves itself (see portal.cpp).
// It opens by itself when Wi-Fi is not set or will not connect, and when the sensor is held for 7 s.
//
// Touch (TTP223):
//   tap              next screen
//   hold 1 s         on Tasks: mark the top task done. Elsewhere: refresh now
//   hold 7 s         open or close the setup page
//   tap while ringing  stop the alarm

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <time.h>

#include "settings.h"
#include "portal.h"

#if __has_include("secrets.h")
#include "secrets.h"
#endif
#ifndef SUPABASE_URL
#define SUPABASE_URL "https://suzmgshfjscxzngcqjdh.supabase.co"
#endif
#ifndef SUPABASE_KEY
#define SUPABASE_KEY "sb_publishable_fyjXegNWaquUwHkbk_TvRw_f8mBKU3H"
#endif

// ---------- Wiring ----------
// OLED: VCC -> 3V3, GND -> GND, SDA -> GPIO21, SCL -> GPIO22
// TTP223: VCC -> 3V3, GND -> GND, SIG (I/O) -> GPIO4
constexpr int OLED_SDA = 21;
constexpr int OLED_SCL = 22;
constexpr uint8_t OLED_ADDRESS = 0x3C;
constexpr int TOUCH_PIN = 4;
constexpr int W = 128, H = 64;

// ---------- Timing ----------
constexpr uint32_t FETCH_EVERY_MS = 10000;
constexpr uint32_t WIFI_WAIT_MS = 10000;     // then the setup page opens
constexpr uint32_t WIFI_RETRY_MS = 30000;    // while in setup, keep trying the saved Wi-Fi
constexpr uint32_t HOLD_MS = 1000;
constexpr uint32_t SETUP_HOLD_MS = 7000;
constexpr uint32_t DONE_SHOW_MS = 4000;
constexpr uint32_t RING_MS = 60000;

Adafruit_SSD1306 display(W, H, &Wire, -1);
Settings settings;

// ---------- Data shared between the two cores ----------

constexpr int TITLE_LEN = 40;
constexpr int MAX_REMINDERS = 10;
constexpr int MAX_ALARMS = 6;
constexpr int MAX_DEADLINES = 8;
constexpr int MAX_TASKS = 6;

enum Repeat : uint8_t { REPEAT_NONE, REPEAT_DAILY, REPEAT_WEEKLY };

struct Timed {
  char title[TITLE_LEN];
  time_t fireAt;
  Repeat repeat;
  int weekday;      // weekly: 0 = Sunday ... 6 = Saturday
};

struct Deadline {
  char title[TITLE_LEN];
  time_t due;
};

struct Task {
  char id[37];
  char title[TITLE_LEN];
  bool doing;
  time_t due;       // 0 = none
};

struct Snapshot {
  Timed reminders[MAX_REMINDERS];
  int reminderCount = 0;
  Timed alarms[MAX_ALARMS];
  int alarmCount = 0;
  Deadline deadlines[MAX_DEADLINES];
  int deadlineCount = 0;
  Task tasks[MAX_TASKS];
  int taskCount = 0;
  int doneToday = 0;
  bool loaded = false;
  char status[24] = "Starting";
};

SemaphoreHandle_t lock;
Snapshot shared;

constexpr int DONE_QUEUE = 4;
char doneQueue[DONE_QUEUE][TITLE_LEN];
int doneHead = 0, doneTail = 0;

volatile bool refreshNow = false;
volatile bool completeWanted = false;
char completeID[37];
volatile bool setupWanted = false;     // hold 7 s: open (or close) the setup page
volatile bool reconnectWanted = false; // settings changed Wi-Fi or account
volatile bool reloginWanted = false;

// ---------- Small helpers ----------

void copyTitle(char* out, const char* in) {
  int n = 0;
  for (const char* p = in ? in : ""; *p && n < TITLE_LEN - 1; p++) {
    unsigned char c = *p;
    if (c >= 32 && c < 127) out[n++] = c;
  }
  out[n] = 0;
  if (n == 0) strcpy(out, "(untitled)");
}

void setStatus(const char* text) {
  xSemaphoreTake(lock, portMAX_DELAY);
  strlcpy(shared.status, text, sizeof shared.status);
  xSemaphoreGive(lock);
}

long daysFromCivil(int y, int m, int d) {
  y -= m <= 2;
  const long era = (y >= 0 ? y : y - 399) / 400;
  const long yoe = y - era * 400;
  const long doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
  const long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return era * 146097 + doe - 719468;
}

// "2026-11-16T09:30:00.123+00:00" -> UTC seconds. 0 if empty or unreadable.
time_t parseTime(const char* text) {
  if (!text || !*text) return 0;
  int y, mo, d, h, mi, s;
  if (sscanf(text, "%d-%d-%dT%d:%d:%d", &y, &mo, &d, &h, &mi, &s) != 6) return 0;
  const char* p = text + 19;
  while (*p == '.' || isdigit((unsigned char)*p)) p++;
  long offset = 0;
  if (*p == '+' || *p == '-') {
    int oh = 0, om = 0;
    sscanf(p + 1, "%d:%d", &oh, &om);
    offset = (oh * 3600L + om * 60L) * (*p == '-' ? -1 : 1);
  }
  return daysFromCivil(y, mo, d) * 86400L + h * 3600L + mi * 60L + s - offset;
}

String isoTime(time_t t) {
  struct tm utc;
  gmtime_r(&t, &utc);
  char buf[24];
  strftime(buf, sizeof buf, "%Y-%m-%dT%H:%M:%SZ", &utc);
  return String(buf);
}

time_t midnightOf(time_t t, int plusDays = 0) {
  struct tm d;
  localtime_r(&t, &d);
  d.tm_mday += plusDays;
  d.tm_hour = d.tm_min = d.tm_sec = 0;
  d.tm_isdst = -1;
  return mktime(&d);
}

// Next time a reminder goes off after `after`. 0 if never again.
time_t nextFire(const Timed& t, time_t after) {
  if (t.repeat == REPEAT_NONE) return t.fireAt > after ? t.fireAt : 0;
  struct tm fire;
  localtime_r(&t.fireAt, &fire);
  const time_t base = after > t.fireAt ? after : t.fireAt - 1;
  struct tm day;
  localtime_r(&base, &day);
  for (int i = 0; i < 9; i++) {
    struct tm c = day;
    c.tm_mday += i;
    c.tm_hour = fire.tm_hour;
    c.tm_min = fire.tm_min;
    c.tm_sec = 0;
    c.tm_isdst = -1;
    const time_t when = mktime(&c);
    struct tm check;
    localtime_r(&when, &check);
    if (when > after && (t.repeat == REPEAT_DAILY || check.tm_wday == t.weekday)) return when;
  }
  return 0;
}

// The time it goes off on the day starting at `dayStart`, or 0.
time_t fireOnDay(const Timed& t, time_t dayStart) {
  const time_t when = nextFire(t, dayStart - 1);
  return when && when < dayStart + 86400 ? when : 0;
}

bool sameDay(time_t a, time_t b) {
  struct tm x, y;
  localtime_r(&a, &x);
  localtime_r(&b, &y);
  return x.tm_year == y.tm_year && x.tm_yday == y.tm_yday;
}

bool clockReady() { return time(nullptr) > 1700000000; }

// ---------- Supabase (network core only) ----------

WiFiClientSecure tls;
HTTPClient http;
String accessToken, refreshToken;
time_t tokenExpires = 0;
String doneCursor;

int request(const char* method, const String& path, const String& body, String& reply) {
  http.setReuse(true);
  http.setTimeout(8000);
  if (!http.begin(tls, String(SUPABASE_URL) + path)) return -1;
  http.addHeader("apikey", SUPABASE_KEY);
  http.addHeader("Content-Type", "application/json");
  if (accessToken.length()) http.addHeader("Authorization", "Bearer " + accessToken);
  if (strcmp(method, "PATCH") == 0) http.addHeader("Prefer", "return=minimal");
  const int code = http.sendRequest(method, body);
  reply = code > 0 ? http.getString() : "";
  http.end();
  if (code == 401) accessToken = "";
  return code;
}

bool signIn(const String& email, const String& password) {
  if (!email.length() || !password.length()) { setStatus("No account"); return false; }
  setStatus("Signing in");
  accessToken = "";
  String reply;
  int code = -1;
  if (refreshToken.length()) {
    code = request("POST", "/auth/v1/token?grant_type=refresh_token", "{\"refresh_token\":\"" + refreshToken + "\"}", reply);
  }
  if (code != 200) {
    JsonDocument body;
    body["email"] = email;
    body["password"] = password;
    String text;
    serializeJson(body, text);
    code = request("POST", "/auth/v1/token?grant_type=password", text, reply);
  }
  if (code != 200) {
    Serial.printf("Sign in failed (%d): %s\n", code, reply.c_str());
    setStatus(code > 0 ? "Login failed" : "Offline");
    refreshToken = "";
    return false;
  }
  JsonDocument doc;
  deserializeJson(doc, reply);
  accessToken = doc["access_token"] | "";
  refreshToken = doc["refresh_token"] | "";
  tokenExpires = time(nullptr) + (doc["expires_in"] | 3600);
  Serial.println("Signed in");
  return accessToken.length() > 0;
}

void readTimed(JsonObject row, Timed& out) {
  copyTitle(out.title, row["title"] | "");
  out.fireAt = parseTime(row["fire_at"] | "");
  const char* rule = row["repeat_rule"] | "";
  out.repeat = REPEAT_NONE;
  out.weekday = 0;
  if (strcmp(rule, "daily") == 0) {
    out.repeat = REPEAT_DAILY;
  } else if (strncmp(rule, "weekly:", 7) == 0) {
    static const char* days[] = {"sun", "mon", "tue", "wed", "thu", "fri", "sat"};
    for (int i = 0; i < 7; i++) if (strcmp(rule + 7, days[i]) == 0) { out.repeat = REPEAT_WEEKLY; out.weekday = i; }
  }
}

// Soonest next time first. Ones that went off today stay (shown dimmed on Today); older one-offs are dropped.
int sortUpcoming(Timed* list, int count, time_t now) {
  const time_t today = midnightOf(now);
  time_t when[32];
  int kept = 0;
  for (int i = 0; i < count; i++) {
    time_t next = nextFire(list[i], now);
    if (!next) {
      if (list[i].repeat != REPEAT_NONE || list[i].fireAt < today) continue;
      next = list[i].fireAt;  // earlier today
    }
    list[kept] = list[i];
    when[kept++] = next;
  }
  for (int i = 1; i < kept; i++)
    for (int j = i; j > 0 && when[j] < when[j - 1]; j--) { std::swap(when[j], when[j - 1]); std::swap(list[j], list[j - 1]); }
  return kept;
}

bool fetchAll() {
  const time_t now = time(nullptr);
  const time_t today = midnightOf(now);
  Snapshot next;
  String reply;

  // Reminders and alarms: repeating ones, and one-offs from today on. Done one-offs that fired today still show.
  int code = request("GET", "/rest/v1/reminders?select=title,fire_at,kind,repeat_rule&deleted=eq.false"
                     "&or=(done.is.false,fire_at.gte.%22" + isoTime(today) + "%22)"
                     "&or=(repeat_rule.not.is.null,fire_at.gte.%22" + isoTime(today) + "%22)&order=fire_at.asc&limit=40", "", reply);
  if (code != 200) return false;
  {
    JsonDocument doc;
    deserializeJson(doc, reply);
    Timed reminders[32], alarms[32];
    int r = 0, a = 0;
    for (JsonObject row : doc.as<JsonArray>()) {
      const bool alarm = strcmp(row["kind"] | "", "alarm") == 0;
      if (alarm && a < 32) readTimed(row, alarms[a++]);
      if (!alarm && r < 32) readTimed(row, reminders[r++]);
    }
    r = sortUpcoming(reminders, r, now);
    a = sortUpcoming(alarms, a, now);
    next.reminderCount = min(r, MAX_REMINDERS);
    next.alarmCount = min(a, MAX_ALARMS);
    memcpy(next.reminders, reminders, sizeof(Timed) * next.reminderCount);
    memcpy(next.alarms, alarms, sizeof(Timed) * next.alarmCount);
  }

  // Deadlines today and tomorrow.
  code = request("GET", "/rest/v1/nodes?select=title,due_at&kind=eq.item&deleted=eq.false&status=in.(todo,doing)"
                 "&due_at=gte." + isoTime(today) + "&due_at=lt." + isoTime(midnightOf(now, 2)) + "&order=due_at.asc&limit=" + String(MAX_DEADLINES), "", reply);
  if (code != 200) return false;
  {
    JsonDocument doc;
    deserializeJson(doc, reply);
    for (JsonObject row : doc.as<JsonArray>()) {
      if (next.deadlineCount >= MAX_DEADLINES) break;
      Deadline& d = next.deadlines[next.deadlineCount++];
      copyTitle(d.title, row["title"] | "");
      d.due = parseTime(row["due_at"] | "");
    }
  }

  // Important tasks: soonest deadline first, then ones in progress.
  code = request("GET", "/rest/v1/nodes?select=id,title,status,due_at&kind=eq.item&deleted=eq.false"
                 "&status=in.(todo,doing)&order=due_at.asc.nullslast,status.asc,updated_at.desc&limit=" + String(MAX_TASKS), "", reply);
  if (code != 200) return false;
  {
    JsonDocument doc;
    deserializeJson(doc, reply);
    for (JsonObject row : doc.as<JsonArray>()) {
      if (next.taskCount >= MAX_TASKS) break;
      Task& t = next.tasks[next.taskCount++];
      strlcpy(t.id, row["id"] | "", sizeof t.id);
      copyTitle(t.title, row["title"] | "");
      t.doing = strcmp(row["status"] | "", "doing") == 0;
      t.due = parseTime(row["due_at"] | "");
    }
  }

  // Done since midnight.
  code = request("GET", "/rest/v1/nodes?select=id&kind=eq.item&deleted=eq.false&status=eq.done&updated_at=gte." + isoTime(today) + "&limit=200", "", reply);
  if (code != 200) return false;
  {
    JsonDocument doc;
    deserializeJson(doc, reply);
    next.doneToday = doc.as<JsonArray>().size();
  }

  // Newly done since the last look, for the "Completed" screen. The first look only sets the bookmark.
  if (doneCursor.isEmpty()) doneCursor = isoTime(now);
  String cursor = doneCursor;
  cursor.replace("+", "%2B");
  code = request("GET", "/rest/v1/nodes?select=title,updated_at&kind=eq.item&deleted=eq.false&status=eq.done&updated_at=gt." + cursor + "&order=updated_at.asc&limit=4", "", reply);
  if (code != 200) return false;
  {
    JsonDocument doc;
    deserializeJson(doc, reply);
    xSemaphoreTake(lock, portMAX_DELAY);
    for (JsonObject row : doc.as<JsonArray>()) {
      copyTitle(doneQueue[doneTail], row["title"] | "");
      doneTail = (doneTail + 1) % DONE_QUEUE;
      if (doneTail == doneHead) doneHead = (doneHead + 1) % DONE_QUEUE;
      doneCursor = row["updated_at"] | doneCursor.c_str();
    }
    xSemaphoreGive(lock);
  }

  next.loaded = true;
  strcpy(next.status, "Live");
  xSemaphoreTake(lock, portMAX_DELAY);
  shared = next;
  xSemaphoreGive(lock);
  return true;
}

// Same as ticking it on the phone: a board card moves to its board's first Done column, reminders are cancelled.
void completeTask(const String& id) {
  setStatus("Saving");
  String reply, newParent;
  if (request("GET", "/rest/v1/nodes?select=parent_id&id=eq." + id, "", reply) != 200) return;
  JsonDocument card;
  deserializeJson(card, reply);
  const char* parent = card[0]["parent_id"] | "";
  if (*parent && request("GET", "/rest/v1/nodes?select=parent_id,column_type&id=eq." + String(parent), "", reply) == 200) {
    JsonDocument column;
    deserializeJson(column, reply);
    const char* type = column[0]["column_type"] | "";
    const char* board = column[0]["parent_id"] | "";
    if (*type && strcmp(type, "done") != 0 && *board &&
        request("GET", "/rest/v1/nodes?select=id&parent_id=eq." + String(board) + "&column_type=eq.done&deleted=eq.false&order=position.asc&limit=1", "", reply) == 200) {
      JsonDocument done;
      deserializeJson(done, reply);
      newParent = done[0]["id"] | "";
    }
  }
  const String stamp = isoTime(time(nullptr));
  String body = "{\"status\":\"done\",\"updated_at\":\"" + stamp + "\"";
  if (newParent.length()) body += ",\"parent_id\":\"" + newParent + "\"";
  body += "}";
  const int code = request("PATCH", "/rest/v1/nodes?id=eq." + id, body, reply);
  Serial.printf("Complete %s -> %d\n", id.c_str(), code);
  request("PATCH", "/rest/v1/reminders?node_id=eq." + id + "&done=eq.false", "{\"done\":true,\"updated_at\":\"" + stamp + "\"}", reply);
}

// Settings are read on this core through a copy taken under the lock.
Settings netSettings;
void copySettings() {
  xSemaphoreTake(lock, portMAX_DELAY);
  netSettings = settings;
  xSemaphoreGive(lock);
}

void networkTask(void*) {
  tls.setInsecure();  // no certificate check; fine for a desk gadget
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  copySettings();
  uint32_t lastFetch = 0, lastWiFiTry = 0, apSince = 0;
  bool fetchedOnce = false, connecting = false, portalByUser = false;

  for (;;) {
    if (reconnectWanted) {
      reconnectWanted = false;
      copySettings();
      WiFi.disconnect();
      connecting = false;
      lastWiFiTry = 0;
    }
    if (reloginWanted) {
      reloginWanted = false;
      copySettings();
      accessToken = "";
      refreshToken = "";
      fetchedOnce = false;
    }
    if (setupWanted) {
      setupWanted = false;
      if (portalAPOpen() && portalByUser) { portalCloseAP(); portalByUser = false; }
      else { portalOpenAP(); portalByUser = true; apSince = millis(); }
    }

    const bool wifiUp = WiFi.status() == WL_CONNECTED;
    if (!wifiUp) {
      if (!netSettings.hasWiFi()) {
        if (!portalAPOpen()) { portalOpenAP(); apSince = millis(); }
        setStatus("Setup");
        vTaskDelay(pdMS_TO_TICKS(500));
        continue;
      }
      if (!connecting && millis() - lastWiFiTry >= (portalAPOpen() ? WIFI_RETRY_MS : 0)) {
        setStatus("Wi-Fi...");
        WiFi.begin(netSettings.wifiSSID.c_str(), netSettings.wifiPass.c_str());
        connecting = true;
        lastWiFiTry = millis();
      }
      if (connecting && millis() - lastWiFiTry > WIFI_WAIT_MS) {
        connecting = false;
        if (!portalAPOpen()) { portalOpenAP(); apSince = millis(); }
        setStatus("Setup");
      }
      vTaskDelay(pdMS_TO_TICKS(250));
      continue;
    }

    if (connecting) {
      connecting = false;
      Serial.printf("Wi-Fi up: %s\n", WiFi.localIP().toString().c_str());
      configTzTime(netSettings.timeZone.c_str(), "pool.ntp.org", "time.google.com");
    }
    // Connected again: close the automatic setup network once nobody is using it.
    if (portalAPOpen() && !portalByUser && millis() - apSince > 60000 && WiFi.softAPgetStationNum() == 0) portalCloseAP();

    if (!clockReady()) {
      setStatus("Clock...");
      vTaskDelay(pdMS_TO_TICKS(500));
      continue;
    }
    if (accessToken.isEmpty() || time(nullptr) > tokenExpires - 120) {
      if (!signIn(netSettings.email, netSettings.password)) {
        if (!netSettings.hasAccount() && !portalAPOpen()) { portalOpenAP(); apSince = millis(); }
        vTaskDelay(pdMS_TO_TICKS(10000));
        continue;
      }
    }
    if (completeWanted) {
      completeTask(String(completeID));
      completeWanted = false;
      refreshNow = true;
    }
    if (!fetchedOnce || refreshNow || millis() - lastFetch >= FETCH_EVERY_MS) {
      refreshNow = false;
      lastFetch = millis();
      fetchedOnce = fetchAll();
      if (!fetchedOnce) setStatus(WiFi.status() == WL_CONNECTED ? "Server error" : "Offline");
    }
    vTaskDelay(pdMS_TO_TICKS(100));
  }
}

// ---------- Screen (main core) ----------

int page = SCR_HOME;
Snapshot view;
uint32_t lastTouch = 0;

char doneTitle[TITLE_LEN];
uint32_t doneShownAt = 0;
bool doneShowing = false;

char ringTitle[TITLE_LEN];
uint32_t ringStartedAt = 0;
bool ringing = false;
time_t ringCheckedUntil = 0;

void centered(const char* text, int y, int size) {
  display.setTextSize(size);
  const int width = strlen(text) * 6 * size;
  display.setCursor(max(0, (W - width) / 2), y);
  display.print(text);
}

String fit(const char* text, int chars) {
  String s(text);
  if ((int)s.length() <= chars) return s;
  return s.substring(0, chars - 2) + "..";
}

String clockText(time_t when) {
  struct tm t;
  localtime_r(&when, &t);
  char buf[8];
  strftime(buf, sizeof buf, settings.clock24 ? "%H:%M" : "%I:%M", &t);
  String s(buf);
  if (!settings.clock24 && s[0] == '0') s = s.substring(1);
  return s;
}

String countdown(long seconds) {
  char buf[16];
  if (seconds < 0) seconds = 0;
  if (seconds < 86400) snprintf(buf, sizeof buf, "%02ld:%02ld:%02ld", seconds / 3600, seconds / 60 % 60, seconds % 60);
  else snprintf(buf, sizeof buf, "%ldd %02ld:%02ld", seconds / 86400, seconds / 3600 % 24, seconds / 60 % 60);
  return String(buf);
}

String dayLabel(time_t when, time_t now) {
  if (sameDay(when, now)) return "Tdy";
  if (sameDay(when, now + 86400)) return "Tmr";
  struct tm t;
  localtime_r(&when, &t);
  char buf[8];
  strftime(buf, sizeof buf, when - now < 6 * 86400 ? "%a" : "%d/%m", &t);
  return String(buf);
}

// Tiny page dots at the bottom, so you know where you are. Skipped on Home.
void pageDots() {
  int shown = 0, index = 0;
  for (int i = 0; i < SCR_COUNT; i++) if (settings.shows((Screen)i)) { if (i == page) index = shown; shown++; }
  if (shown < 2) return;
  const int x0 = (W - (shown * 6 - 2)) / 2;
  for (int i = 0; i < shown; i++) {
    if (i == index) display.fillRect(x0 + i * 6, H - 2, 4, 2, SSD1306_WHITE);
    else display.drawPixel(x0 + i * 6 + 1, H - 1, SSD1306_WHITE);
  }
}

// Small label top left. The status replaces it when something is wrong.
void label(const char* text) {
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.print(strcmp(view.status, "Live") == 0 ? text : view.status);
}

// One thing on the clock.
struct Entry {
  time_t when;
  char kind;  // 'r' reminder, 'a' alarm, 'd' deadline
  const char* title;
};

int entriesOn(time_t dayStart, Entry* out, int max) {
  int n = 0;
  for (int i = 0; i < view.reminderCount && n < max; i++) { const time_t w = fireOnDay(view.reminders[i], dayStart); if (w) out[n++] = {w, 'r', view.reminders[i].title}; }
  for (int i = 0; i < view.alarmCount && n < max; i++) { const time_t w = fireOnDay(view.alarms[i], dayStart); if (w) out[n++] = {w, 'a', view.alarms[i].title}; }
  for (int i = 0; i < view.deadlineCount && n < max; i++) { const time_t d = view.deadlines[i].due; if (d >= dayStart && d < dayStart + 86400) out[n++] = {d, 'd', view.deadlines[i].title}; }
  for (int i = 1; i < n; i++) for (int j = i; j > 0 && out[j].when < out[j - 1].when; j--) std::swap(out[j], out[j - 1]);
  return n;
}

int entriesUpcoming(time_t now, Entry* out, int max) {
  int n = 0;
  for (int i = 0; i < view.reminderCount && n < max; i++) { const time_t w = nextFire(view.reminders[i], now); if (w) out[n++] = {w, 'r', view.reminders[i].title}; }
  for (int i = 0; i < view.alarmCount && n < max; i++) { const time_t w = nextFire(view.alarms[i], now); if (w) out[n++] = {w, 'a', view.alarms[i].title}; }
  for (int i = 0; i < view.deadlineCount && n < max; i++) { const time_t d = view.deadlines[i].due; if (d > now) out[n++] = {d, 'd', view.deadlines[i].title}; }
  for (int i = 1; i < n; i++) for (int j = i; j > 0 && out[j].when < out[j - 1].when; j--) std::swap(out[j], out[j - 1]);
  return n;
}

// "14:22" under an hour, "1:14:22" under a day, then "2d 4h". Short, so it can be drawn big.
String shortCountdown(long s) {
  if (s < 0) s = 0;
  char buf[12];
  if (s >= 86400) snprintf(buf, sizeof buf, "%ldd %ldh", s / 86400, s / 3600 % 24);
  else if (s >= 3600) snprintf(buf, sizeof buf, "%ld:%02ld:%02ld", s / 3600, s / 60 % 60, s % 60);
  else snprintf(buf, sizeof buf, "%02ld:%02ld", s / 60, s % 60);
  return String(buf);
}

const char* kindWord(char kind) { return kind == 'a' ? "alarm" : kind == 'd' ? "due" : "reminder"; }

const Timed* nextAlarm(time_t now, time_t* when) {
  const Timed* best = nullptr;
  *when = 0;
  for (int i = 0; i < view.alarmCount; i++) {
    const time_t next = nextFire(view.alarms[i], now);
    if (next && (!best || next < *when)) { best = &view.alarms[i]; *when = next; }
  }
  return best;
}

// ----- Home -----
// Something still due today: a big countdown to it. Otherwise the face, with the next thing in one line at the bottom.

void drawNext(const Entry& e, time_t now) {
  label(kindWord(e.kind));
  const String clock = clockText(e.when);
  display.setCursor(W - clock.length() * 6, 0);
  display.print(clock);
  const String cd = shortCountdown(e.when - now);
  centered(cd.c_str(), cd.length() <= 7 ? 14 : 18, cd.length() <= 7 ? 3 : 2);
  centered(fit(e.title, 10).c_str(), 44, 2);
}

struct Face {
  float lookX = 0, lookY = 0, targetX = 0, targetY = 0;
  uint32_t nextLook = 0, blinkAt = 0, happyUntil = 0;
} face;

void drawFace(uint32_t ms, time_t now, const Entry* next) {
  struct tm t;
  localtime_r(&now, &t);
  const bool sleepy = t.tm_hour >= 23 || t.tm_hour < 6;
  const bool happy = ms < face.happyUntil;

  if (ms > face.nextLook) {
    face.targetX = random(-8, 9);
    face.targetY = random(-3, 4);
    face.nextLook = ms + random(1500, 4500);
  }
  face.lookX += (face.targetX - face.lookX) * 0.15f;
  face.lookY += (face.targetY - face.lookY) * 0.15f;
  if (ms > face.blinkAt + 160) face.blinkAt = ms + random(2500, 6000);
  const bool blink = ms >= face.blinkAt && ms < face.blinkAt + 160;

  const int cx = 64, cy = 24;
  const int ex = 24, eyeW = 18, eyeH = happy ? 7 : 20;
  for (int side = -1; side <= 1; side += 2) {
    const int x = cx + side * ex + (int)face.lookX - eyeW / 2;
    const int y = cy + (int)face.lookY - eyeH / 2;
    if (blink || sleepy) {
      display.fillRoundRect(x, cy + (int)face.lookY - 1, eyeW, 3, 1, SSD1306_WHITE);
    } else if (happy) {
      for (int i = 0; i < eyeW; i++) {
        const float u = (i - eyeW / 2.0f) / (eyeW / 2.0f);
        display.fillRect(x + i, y + eyeH - (int)((1 - u * u) * eyeH), 1, 3, SSD1306_WHITE);
      }
    } else {
      display.fillRoundRect(x, y, eyeW, eyeH, 6, SSD1306_WHITE);
    }
  }
  const int my = cy + 20;
  const int mw = happy ? 26 : 12, depth = happy ? 8 : 3;
  for (int i = -mw / 2; i <= mw / 2; i++) {
    const float u = (float)i / (mw / 2.0f);
    const int yy = my + (int)((1 - u * u) * depth);
    display.drawPixel(cx + i + (int)(face.lookX / 2), yy, SSD1306_WHITE);
    display.drawPixel(cx + i + (int)(face.lookX / 2), yy + 1, SSD1306_WHITE);
  }
  if (sleepy) {
    display.setTextSize(1);
    const int phase = (ms / 700) % 3;
    for (int i = 0; i <= phase; i++) { display.setCursor(100 + i * 7, 18 - i * 7); display.print("z"); }
  }

  // Clock top right, status top left only when something is wrong.
  display.setTextSize(1);
  const String clock = clockText(now);
  display.setCursor(W - clock.length() * 6, 0);
  display.print(clock);
  if (strcmp(view.status, "Live") != 0) { display.setCursor(0, 0); display.print(view.status); }

  // One line: countdown to the next thing, whenever it is.
  if (next) {
    const String cd = shortCountdown(next->when - now);
    const String line = cd + "  " + fit(next->title, 21 - cd.length() - 2);
    centered(line.c_str(), 56, 1);
  }
}

void drawHome(uint32_t ms, time_t now) {
  Entry e[1];
  const bool any = entriesUpcoming(now, e, 1) > 0;
  if (any && sameDay(e[0].when, now)) drawNext(e[0], now);
  else drawFace(ms, now, any ? &e[0] : nullptr);
}

void drawClock(time_t now) {
  struct tm t;
  localtime_r(&now, &t);
  if (strcmp(view.status, "Live") != 0) label("");
  centered(clockText(now).c_str(), 12, 4);
  char buf[24];
  strftime(buf, sizeof buf, "%A %d %b", &t);
  centered(buf, 50, 1);
}

// Three rows: big time, small title. Starts from the next thing still to come.
void drawDay(const char* title, time_t dayStart, time_t now) {
  label(title);
  Entry e[16];
  const int n = entriesOn(dayStart, e, 16);
  if (n == 0) { centered("nothing", 28, 2); return; }
  int first = 0;
  while (first < n && e[first].when < now && n - first > 3) first++;
  for (int i = first, row = 0; i < n && row < 3; i++, row++) {
    const int y = 12 + row * 17;
    display.setTextSize(2);
    display.setCursor(0, y);
    display.print(clockText(e[i].when));
    display.setTextSize(1);
    display.setCursor(66, y + 4);
    display.print(fit(e[i].title, 10));
    if (e[i].when < now) display.drawFastHLine(66, y + 7, 60, SSD1306_WHITE);
  }
  if (n - first > 3) { display.setTextSize(1); display.setCursor(W - 18, 0); display.printf("+%d", n - first - 3); }
}

// The top task, big. Hold to complete it.
void drawTasks(time_t now) {
  if (view.taskCount == 0) { label("tasks"); centered("all clear", 28, 2); return; }
  const Task& task = view.tasks[0];
  const bool late = task.due && task.due < now;
  label(late ? "late" : task.doing ? "doing" : "task");
  if (task.due) {
    const String due = dayLabel(task.due, now) + " " + clockText(task.due);
    display.setCursor(W - due.length() * 6, 0);
    display.print(due);
  }
  // Two lines of 10 big characters.
  String t(task.title);
  display.setTextSize(2);
  display.setCursor(0, 14);
  display.print(t.substring(0, 10));
  if (t.length() > 10) { display.setCursor(0, 32); display.print(fit(t.substring(10).c_str(), 10)); }
  display.setTextSize(1);
  if (view.taskCount > 1) {
    display.setCursor(0, 52);
    display.print("then " + fit(view.tasks[1].title, 14));
    if (view.taskCount > 2) { display.setCursor(W - 18, 52); display.printf("+%d", view.taskCount - 2); }
  }
}

void drawDone() {
  display.drawCircle(16, 20, 13, SSD1306_WHITE);
  display.drawCircle(16, 20, 12, SSD1306_WHITE);
  for (int d = 0; d < 2; d++) {
    display.drawLine(9, 20 + d, 14, 26 + d, SSD1306_WHITE);
    display.drawLine(14, 26 + d, 24, 13 + d, SSD1306_WHITE);
  }
  display.setTextSize(2);
  display.setCursor(36, 12);
  display.print("Done");
  String t(doneTitle);
  display.setTextSize(1);
  display.setCursor(0, 42);
  display.print(t.substring(0, 21));
  if (t.length() > 21) { display.setCursor(0, 52); display.print(fit(t.substring(21).c_str(), 21)); }
}

void drawRinging() {
  centered("ALARM", 4, 3);
  centered(fit(ringTitle, 10).c_str(), 32, 2);
  centered("tap to stop", 54, 1);
}

void drawSetup() {
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.print("setup");
  if (portalAPOpen()) {
    display.setCursor(0, 14); display.print("Join Wi-Fi:");
    display.setCursor(0, 24); display.print(" " + portalAPName());
    display.setCursor(0, 36); display.print("then open:");
    display.setCursor(0, 46); display.print(" " + WiFi.softAPIP().toString());
  }
  if (WiFi.status() == WL_CONNECTED) {
    display.setCursor(0, 56);
    display.print("or " + WiFi.localIP().toString());
  }
}

// A bar along the bottom fills while the sensor is held: 1 s for the hold action, then on to 7 s for setup.
void drawHoldBar(uint32_t heldFor) {
  if (heldFor < 200) return;
  if (heldFor < HOLD_MS) {
    display.fillRect(0, H - 2, heldFor * W / HOLD_MS, 2, SSD1306_WHITE);
  } else {
    display.fillRect(0, H - 2, W, 2, SSD1306_WHITE);
    const int w = (heldFor - HOLD_MS) * W / (SETUP_HOLD_MS - HOLD_MS);
    display.fillRect(0, H - 5, w, 2, SSD1306_WHITE);
    if (heldFor > HOLD_MS + 600) {
      display.setTextSize(1);
      const String s = "setup in " + String((SETUP_HOLD_MS - heldFor) / 1000 + 1);
      display.fillRect(W - s.length() * 6 - 2, H - 16, s.length() * 6 + 2, 9, SSD1306_BLACK);
      display.setCursor(W - s.length() * 6, H - 15);
      display.print(s);
    }
  }
}

void checkAlarms(time_t now) {
  if (!ringCheckedUntil) ringCheckedUntil = now;
  for (int i = 0; i < view.alarmCount && !ringing; i++) {
    const time_t next = nextFire(view.alarms[i], ringCheckedUntil);
    if (next && next <= now) {
      strlcpy(ringTitle, view.alarms[i].title, TITLE_LEN);
      ringing = true;
      ringStartedAt = millis();
    }
  }
  ringCheckedUntil = now;
}

int nextPage(int from) {
  for (int i = 1; i <= SCR_COUNT; i++) {
    const int p = (from + i) % SCR_COUNT;
    if (settings.shows((Screen)p)) return p;
  }
  return from;
}

bool showingSetup = false;

void onTap() {
  if (ringing) { ringing = false; return; }
  if (doneShowing) { doneShowing = false; return; }
  if (showingSetup) { showingSetup = false; return; }
  page = nextPage(page);
}

void onHold() {
  if (page == SCR_TASKS && view.taskCount > 0 && !completeWanted) {
    strlcpy(completeID, view.tasks[0].id, sizeof completeID);
    completeWanted = true;
  } else {
    refreshNow = true;
  }
}

void applyDisplaySettings() {
  display.setRotation(settings.flip ? 2 : 0);
  display.ssd1306_command(SSD1306_SETCONTRAST);
  display.ssd1306_command(settings.brightness);
  if (!settings.shows((Screen)page)) page = settings.idle;
}

void setup() {
  Serial.begin(115200);
  pinMode(TOUCH_PIN, INPUT);
  lock = xSemaphoreCreateMutex();
  settingsLoad(settings);
  page = settings.idle;

  Wire.begin(OLED_SDA, OLED_SCL);
  if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDRESS)) {
    Serial.println("OLED not found. Check SDA/SCL wiring and the address (0x3C or 0x3D).");
  }
  applyDisplaySettings();
  display.setTextColor(SSD1306_WHITE);
  display.clearDisplay();
  centered("VOX", 18, 3);
  centered("desk viewer", 48, 1);
  display.display();

  // The web server needs the Wi-Fi stack running first.
  WiFi.mode(WIFI_STA);
  portalBegin(&settings);
  xTaskCreatePinnedToCore(networkTask, "network", 16384, nullptr, 1, nullptr, 0);
}

void loop() {
  static bool wasDown = false;
  static uint32_t downAt = 0;
  static bool holdArmed = false, setupFired = false;

  // Touch. The TTP223 output is HIGH while touched.
  const bool down = digitalRead(TOUCH_PIN) == HIGH;
  const uint32_t ms = millis();
  if (down && !wasDown) { downAt = ms; holdArmed = false; setupFired = false; lastTouch = ms; }
  const uint32_t heldFor = down ? ms - downAt : 0;
  if (down && heldFor >= HOLD_MS && !ringing) holdArmed = true;
  if (down && heldFor >= SETUP_HOLD_MS && !setupFired) {
    setupFired = true;
    setupWanted = true;
    showingSetup = !showingSetup || !portalAPOpen();
  }
  if (!down && wasDown) {
    const uint32_t held = ms - downAt;
    if (setupFired) {}                                  // already handled
    else if (holdArmed) onHold();                       // 1 s to 7 s: hold action on release
    else if (held > 30) onTap();
  }
  wasDown = down;

  if (page != settings.idle && !showingSetup && ms - lastTouch > settings.idleAfter * 1000UL) page = settings.idle;

  // The admin page and anything it changed.
  PortalStatus ps;
  ps.wifi = WiFi.status() == WL_CONNECTED ? "Connected to " + WiFi.SSID() + " (" + WiFi.localIP().toString() + ")" : "Not connected";
  ps.account = view.status;
  portalLoop(ps);
  bool wifiChanged = false, accountChanged = false;
  if (portalTakeSaved(&wifiChanged, &accountChanged)) {
    applyDisplaySettings();
    configTzTime(settings.timeZone.c_str(), "pool.ntp.org", "time.google.com");
    if (wifiChanged) reconnectWanted = true;
    if (accountChanged) reloginWanted = true;
    showingSetup = false;
  }
  if (portalTakeRestart()) { delay(300); ESP.restart(); }

  xSemaphoreTake(lock, portMAX_DELAY);
  view = shared;
  if (!doneShowing && doneHead != doneTail) {
    strlcpy(doneTitle, doneQueue[doneHead], TITLE_LEN);
    doneHead = (doneHead + 1) % DONE_QUEUE;
    doneShowing = true;
    doneShownAt = ms;
    face.happyUntil = ms + DONE_SHOW_MS + 6000;
  }
  xSemaphoreGive(lock);

  const time_t now = time(nullptr);
  if (clockReady() && view.loaded) checkAlarms(now);
  if (ringing && ms - ringStartedAt > RING_MS) ringing = false;
  if (doneShowing && ms - doneShownAt > DONE_SHOW_MS) doneShowing = false;
  // The setup screen shows itself when the board cannot get online.
  const bool needsSetup = portalAPOpen() && (WiFi.status() != WL_CONNECTED || strcmp(view.status, "No account") == 0 || strcmp(view.status, "Login failed") == 0);

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  if (ringing) drawRinging();
  else if (doneShowing) drawDone();
  else if (showingSetup || needsSetup) drawSetup();
  else if (!clockReady()) { centered("VOX", 14, 3); centered(view.status, 48, 1); }
  else {
    switch (page) {
      case SCR_HOME: drawHome(ms, now); break;
      case SCR_CLOCK: drawClock(now); break;
      case SCR_TODAY: drawDay("today", midnightOf(now), now); break;
      case SCR_TOMORROW: drawDay("tomorrow", midnightOf(now, 1), now); break;
      case SCR_TASKS: drawTasks(now); break;
      default: break;
    }
    if (page != SCR_HOME) pageDots();
  }
  if (down && !setupFired) drawHoldBar(heldFor);
  display.invertDisplay(ringing && (ms / 500) % 2);
  display.display();
  delay(30);
}
