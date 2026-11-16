// Vox desk viewer.
// Shows the clock, a countdown to the next alarm, upcoming reminders and the most important tasks.
// When a task is ticked done anywhere (phone, website, here), it shows "Completed".
//
// Data comes straight from Supabase over Wi-Fi, every few seconds.
// The network work runs on its own core, so the clock and countdown never freeze.
//
// Touch sensor (TTP223):
//   tap        -> next screen
//   hold 1 s   -> on the Tasks screen: mark the top task done. Elsewhere: refresh now.
//   tap while an alarm rings -> stop it

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <time.h>

#include "secrets.h"

// ---------- Wiring ----------
// OLED: VCC -> 3V3, GND -> GND, SDA -> GPIO21, SCL -> GPIO22
// TTP223: VCC -> 3V3, GND -> GND, SIG (I/O) -> GPIO4
constexpr int OLED_SDA = 21;
constexpr int OLED_SCL = 22;
constexpr uint8_t OLED_ADDRESS = 0x3C;
constexpr int TOUCH_PIN = 4;

constexpr int SCREEN_W = 128;
constexpr int SCREEN_H = 64;

// ---------- Timing ----------
constexpr uint32_t FETCH_EVERY_MS = 10000;  // how often to ask Supabase
constexpr uint32_t HOLD_MS = 1000;          // a press this long is a hold
constexpr uint32_t BACK_HOME_MS = 60000;    // no touch this long -> back to the clock
constexpr uint32_t DONE_SHOW_MS = 4000;     // how long "Completed" stays up
constexpr uint32_t RING_MS = 60000;         // an alarm flashes this long unless tapped

Adafruit_SSD1306 display(SCREEN_W, SCREEN_H, &Wire, -1);

// ---------- Data shared between the two cores ----------

constexpr int TITLE_LEN = 40;
constexpr int MAX_REMINDERS = 8;
constexpr int MAX_ALARMS = 6;
constexpr int MAX_TASKS = 6;

enum Repeat : uint8_t { REPEAT_NONE, REPEAT_DAILY, REPEAT_WEEKLY };

struct Timed {
  char title[TITLE_LEN];
  time_t fireAt;    // first (or only) time, UTC seconds
  Repeat repeat;
  int weekday;      // for weekly: 0 = Sunday ... 6 = Saturday
};

struct Task {
  char id[37];
  char title[TITLE_LEN];
  bool doing;
  time_t due;       // 0 = no deadline
};

struct Snapshot {
  Timed reminders[MAX_REMINDERS];
  int reminderCount = 0;
  Timed alarms[MAX_ALARMS];
  int alarmCount = 0;
  Task tasks[MAX_TASKS];
  int taskCount = 0;
  int doneToday = 0;
  bool loaded = false;
  char status[24] = "Starting";
};

SemaphoreHandle_t lock;
Snapshot shared;  // written by the network core, read by the screen core

// Tasks that just became done, waiting to be shown.
constexpr int DONE_QUEUE = 4;
char doneQueue[DONE_QUEUE][TITLE_LEN];
int doneHead = 0;
int doneTail = 0;

// Set by the screen core, handled by the network core.
volatile bool refreshNow = false;
volatile bool completeWanted = false;
char completeID[37];

// ---------- Small helpers ----------

// Copies text the OLED font can draw. Emoji and accents are dropped.
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

// Days since 1970-01-01 for a calendar date. Works without time zones.
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

// UTC seconds -> "2026-11-16T09:30:00Z", ready for a URL.
String isoTime(time_t t) {
  struct tm utc;
  gmtime_r(&t, &utc);
  char buf[24];
  strftime(buf, sizeof buf, "%Y-%m-%dT%H:%M:%SZ", &utc);
  return String(buf);
}

// Next time a reminder or alarm goes off after `after`. 0 if never again.
time_t nextFire(const Timed& t, time_t after) {
  if (t.repeat == REPEAT_NONE) return t.fireAt > after ? t.fireAt : 0;
  struct tm fire;
  localtime_r(&t.fireAt, &fire);
  const time_t base = after > t.fireAt ? after : t.fireAt - 1;
  struct tm day;
  localtime_r(&base, &day);
  for (int i = 0; i < 9; i++) {
    struct tm candidate = day;
    candidate.tm_mday += i;
    candidate.tm_hour = fire.tm_hour;
    candidate.tm_min = fire.tm_min;
    candidate.tm_sec = 0;
    candidate.tm_isdst = -1;
    const time_t when = mktime(&candidate);
    struct tm check;
    localtime_r(&when, &check);
    if (when > after && (t.repeat == REPEAT_DAILY || check.tm_wday == t.weekday)) return when;
  }
  return 0;
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
String accessToken;
String refreshToken;
time_t tokenExpires = 0;
String doneCursor;  // newest "done" change already shown

// One request to Supabase. Returns the HTTP status, or a negative number when the network failed.
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
  // A rejected token: sign in again next round.
  if (code == 401) accessToken = "";
  return code;
}

bool signIn() {
  setStatus("Signing in");
  accessToken = "";
  String reply;
  int code = -1;
  // Try the saved refresh token first, then the password.
  if (refreshToken.length()) {
    code = request("POST", "/auth/v1/token?grant_type=refresh_token", "{\"refresh_token\":\"" + refreshToken + "\"}", reply);
  }
  if (code != 200) {
    JsonDocument body;
    body["email"] = VOX_EMAIL;
    body["password"] = VOX_PASSWORD;
    String text;
    serializeJson(body, text);
    code = request("POST", "/auth/v1/token?grant_type=password", text, reply);
  }
  if (code != 200) {
    Serial.printf("Sign in failed (%d): %s\n", code, reply.c_str());
    setStatus(code > 0 ? "Login failed" : "Offline");
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
    for (int i = 0; i < 7; i++) {
      if (strcmp(rule + 7, days[i]) == 0) {
        out.repeat = REPEAT_WEEKLY;
        out.weekday = i;
      }
    }
  }
}

// Sorts by the next time each one goes off. Ones that never go off again are dropped.
int sortUpcoming(Timed* list, int count, time_t now) {
  time_t when[MAX_REMINDERS > MAX_ALARMS ? MAX_REMINDERS : MAX_ALARMS];
  int kept = 0;
  for (int i = 0; i < count; i++) {
    const time_t next = nextFire(list[i], now);
    if (!next) continue;
    list[kept] = list[i];
    when[kept++] = next;
  }
  for (int i = 1; i < kept; i++) {
    for (int j = i; j > 0 && when[j] < when[j - 1]; j--) {
      std::swap(when[j], when[j - 1]);
      std::swap(list[j], list[j - 1]);
    }
  }
  return kept;
}

bool fetchAll() {
  const time_t now = time(nullptr);
  Snapshot next;
  String reply;

  // Reminders and alarms still to come. Repeating ones are always kept.
  const String upcoming = "or=(repeat_rule.not.is.null,fire_at.gte.%22" + isoTime(now) + "%22)";
  int code = request("GET", "/rest/v1/reminders?select=title,fire_at,kind,repeat_rule&done=eq.false&deleted=eq.false&" +
                     upcoming + "&order=fire_at.asc&limit=30", "", reply);
  if (code != 200) return false;
  {
    JsonDocument doc;
    deserializeJson(doc, reply);
    Timed reminders[30];
    Timed alarms[30];
    int r = 0, a = 0;
    for (JsonObject row : doc.as<JsonArray>()) {
      const bool alarm = strcmp(row["kind"] | "", "alarm") == 0;
      if (alarm && a < 30) readTimed(row, alarms[a++]);
      if (!alarm && r < 30) readTimed(row, reminders[r++]);
    }
    r = sortUpcoming(reminders, r, now);
    a = sortUpcoming(alarms, a, now);
    next.reminderCount = min(r, MAX_REMINDERS);
    next.alarmCount = min(a, MAX_ALARMS);
    memcpy(next.reminders, reminders, sizeof(Timed) * next.reminderCount);
    memcpy(next.alarms, alarms, sizeof(Timed) * next.alarmCount);
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
      Task& task = next.tasks[next.taskCount++];
      strlcpy(task.id, row["id"] | "", sizeof task.id);
      copyTitle(task.title, row["title"] | "");
      task.doing = strcmp(row["status"] | "", "doing") == 0;
      task.due = parseTime(row["due_at"] | "");
    }
  }

  // Tasks done since midnight.
  struct tm midnight;
  localtime_r(&now, &midnight);
  midnight.tm_hour = midnight.tm_min = midnight.tm_sec = 0;
  code = request("GET", "/rest/v1/nodes?select=id&kind=eq.item&deleted=eq.false&status=eq.done&updated_at=gte." +
                 isoTime(mktime(&midnight)) + "&limit=200", "", reply);
  if (code != 200) return false;
  {
    JsonDocument doc;
    deserializeJson(doc, reply);
    next.doneToday = doc.as<JsonArray>().size();
  }

  // Tasks that became done since the last look. The first look only sets the bookmark.
  if (doneCursor.isEmpty()) doneCursor = isoTime(now);
  String cursor = doneCursor;
  cursor.replace("+", "%2B");
  code = request("GET", "/rest/v1/nodes?select=title,updated_at&kind=eq.item&deleted=eq.false&status=eq.done&updated_at=gt." +
                 cursor + "&order=updated_at.asc&limit=4", "", reply);
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

// Marks a task done the same way the phone does:
// a card on a board moves to its board's first Done column, and its reminders are cancelled.
void completeTask(const String& id) {
  setStatus("Saving");
  String reply;
  String newParent;
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
        request("GET", "/rest/v1/nodes?select=id&parent_id=eq." + String(board) +
                "&column_type=eq.done&deleted=eq.false&order=position.asc&limit=1", "", reply) == 200) {
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
  request("PATCH", "/rest/v1/reminders?node_id=eq." + id + "&done=eq.false",
          "{\"done\":true,\"updated_at\":\"" + stamp + "\"}", reply);
}

void networkTask(void*) {
  tls.setInsecure();  // skips certificate checks; fine for a desk gadget
  WiFi.mode(WIFI_STA);
  uint32_t lastFetch = 0;
  bool fetchedOnce = false;
  for (;;) {
    if (WiFi.status() != WL_CONNECTED) {
      setStatus("Wi-Fi...");
      WiFi.begin(WIFI_SSID, WIFI_PASS);
      for (int i = 0; i < 60 && WiFi.status() != WL_CONNECTED; i++) vTaskDelay(pdMS_TO_TICKS(250));
      if (WiFi.status() != WL_CONNECTED) {
        setStatus("No Wi-Fi");
        vTaskDelay(pdMS_TO_TICKS(3000));
        continue;
      }
      Serial.printf("Wi-Fi up: %s\n", WiFi.localIP().toString().c_str());
      configTzTime(TIME_ZONE, "pool.ntp.org", "time.google.com");
    }
    if (!clockReady()) {
      setStatus("Clock...");
      vTaskDelay(pdMS_TO_TICKS(500));
      continue;
    }
    if (accessToken.isEmpty() || time(nullptr) > tokenExpires - 120) {
      if (!signIn()) {
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

enum Page { PAGE_HOME, PAGE_ALARM, PAGE_REMINDERS, PAGE_TASKS, PAGE_COUNT };

Page page = PAGE_HOME;
Snapshot view;  // the screen's own copy of `shared`
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
  display.setCursor(max(0, (SCREEN_W - width) / 2), y);
  display.print(text);
}

// Cuts text to fit `chars` characters, with ".." when it was longer.
String fit(const char* text, int chars) {
  String s(text);
  if ((int)s.length() <= chars) return s;
  return s.substring(0, chars - 2) + "..";
}

void header(const char* title) {
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.print(title);
  for (int i = 0; i < PAGE_COUNT; i++) {
    const int x = SCREEN_W - (PAGE_COUNT - i) * 7 + 2;
    if (i == page) display.fillCircle(x, 3, 2, SSD1306_WHITE);
    else display.drawCircle(x, 3, 2, SSD1306_WHITE);
  }
  display.drawFastHLine(0, 10, SCREEN_W, SSD1306_WHITE);
}

// "07:42:10" under a day, "2d 07:42" above it.
String countdown(long seconds) {
  char buf[16];
  if (seconds < 86400) {
    snprintf(buf, sizeof buf, "%02ld:%02ld:%02ld", seconds / 3600, seconds / 60 % 60, seconds % 60);
  } else {
    snprintf(buf, sizeof buf, "%ldd %02ld:%02ld", seconds / 86400, seconds / 3600 % 24, seconds / 60 % 60);
  }
  return String(buf);
}

// "Tdy", "Tmr" or a weekday like "Fri".
String dayLabel(time_t when, time_t now) {
  if (sameDay(when, now)) return "Tdy";
  if (sameDay(when, now + 86400)) return "Tmr";
  struct tm t;
  localtime_r(&when, &t);
  char buf[8];
  strftime(buf, sizeof buf, when - now < 6 * 86400 ? "%a" : "%d/%m", &t);
  return String(buf);
}

String clockText(time_t when) {
  struct tm t;
  localtime_r(&when, &t);
  char buf[8];
  strftime(buf, sizeof buf, "%H:%M", &t);
  return String(buf);
}

const Timed* nextAlarm(time_t now, time_t* when) {
  const Timed* best = nullptr;
  *when = 0;
  for (int i = 0; i < view.alarmCount; i++) {
    const time_t next = nextFire(view.alarms[i], now);
    if (next && (!best || next < *when)) {
      best = &view.alarms[i];
      *when = next;
    }
  }
  return best;
}

void drawHome(time_t now) {
  struct tm t;
  localtime_r(&now, &t);
  char buf[24];
  display.setTextSize(1);
  strftime(buf, sizeof buf, "%a %d %b", &t);
  display.setCursor(0, 0);
  display.print(buf);
  // Status on the right: "Live" or what is wrong.
  display.setCursor(SCREEN_W - strlen(view.status) * 6, 0);
  display.print(view.status);

  strftime(buf, sizeof buf, "%H:%M", &t);
  centered(buf, 13, 3);

  display.setTextSize(1);
  time_t when;
  const Timed* alarm = nextAlarm(now, &when);
  const String line = alarm ? "Alarm in " + countdown(when - now) : String("No alarm set");
  centered(line.c_str(), 42, 1);

  int open = view.taskCount;
  snprintf(buf, sizeof buf, "%d done  %d%s to do", view.doneToday, open, open >= MAX_TASKS ? "+" : "");
  centered(buf, 55, 1);
}

void drawAlarm(time_t now) {
  header("NEXT ALARM");
  time_t when;
  const Timed* alarm = nextAlarm(now, &when);
  if (!alarm) {
    centered("No alarms", 26, 1);
    centered("Set one on the phone", 42, 1);
    return;
  }
  centered(countdown(when - now).c_str(), 18, 2);
  centered(fit(alarm->title, 21).c_str(), 40, 1);
  const String at = dayLabel(when, now) + " " + clockText(when);
  centered(at.c_str(), 53, 1);
}

void drawReminders(time_t now) {
  header("REMINDERS");
  if (view.reminderCount == 0) {
    centered("Nothing coming up", 30, 1);
    return;
  }
  display.setTextSize(1);
  for (int i = 0; i < view.reminderCount && i < 4; i++) {
    const time_t when = nextFire(view.reminders[i], now);
    const int y = 14 + i * 12;
    display.setCursor(0, y);
    display.print(dayLabel(when, now) + " " + clockText(when));
    display.setCursor(60, y);
    display.print(fit(view.reminders[i].title, 11));
  }
}

void drawTasks(time_t now) {
  header("TASKS");
  if (view.taskCount == 0) {
    centered("All clear!", 30, 1);
    return;
  }
  display.setTextSize(1);
  for (int i = 0; i < view.taskCount && i < 4; i++) {
    const Task& task = view.tasks[i];
    const int y = 14 + i * 12;
    // The top task is the one a hold marks done, so it is highlighted.
    if (i == 0) display.fillRect(0, y - 2, SCREEN_W, 11, SSD1306_WHITE);
    display.setTextColor(i == 0 ? SSD1306_BLACK : SSD1306_WHITE);
    const bool late = task.due && task.due < now;
    display.setCursor(1, y);
    display.print(late ? '!' : task.doing ? '>' : '-');
    display.setCursor(9, y);
    String due = task.due ? (late ? String("late") : dayLabel(task.due, now)) : String("");
    display.print(fit(task.title, due.length() ? 15 : 19));
    if (due.length()) {
      display.setCursor(SCREEN_W - due.length() * 6 - 1, y);
      display.print(due);
    }
    display.setTextColor(SSD1306_WHITE);
  }
}

void drawDone() {
  // A ring with a tick, then the task name.
  display.drawCircle(18, 32, 14, SSD1306_WHITE);
  display.drawCircle(18, 32, 13, SSD1306_WHITE);
  for (int d = 0; d < 2; d++) {
    display.drawLine(11, 32 + d, 16, 38 + d, SSD1306_WHITE);
    display.drawLine(16, 38 + d, 26, 25 + d, SSD1306_WHITE);
  }
  display.setTextSize(1);
  display.setCursor(40, 14);
  display.print("COMPLETED");
  display.drawFastHLine(40, 24, 54, SSD1306_WHITE);
  // Up to three lines of 14 characters.
  String title(doneTitle);
  for (int line = 0; line < 3 && title.length(); line++) {
    display.setCursor(40, 30 + line * 10);
    display.print(title.substring(0, 14));
    title = title.length() > 14 ? title.substring(14) : "";
  }
}

void drawRinging() {
  centered("ALARM", 6, 2);
  centered(fit(ringTitle, 21).c_str(), 32, 1);
  centered("tap to stop", 52, 1);
}

// A bar along the bottom fills up while the sensor is held.
void drawHoldBar(uint32_t heldFor) {
  if (heldFor < 250) return;
  const int width = (heldFor > HOLD_MS ? HOLD_MS : heldFor) * SCREEN_W / HOLD_MS;
  display.fillRect(0, SCREEN_H - 2, width, 2, SSD1306_WHITE);
}

// Starts ringing when an alarm's time passes.
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

void onTap() {
  if (ringing) {
    ringing = false;
    return;
  }
  if (doneShowing) {
    doneShowing = false;
    return;
  }
  page = Page((page + 1) % PAGE_COUNT);
}

void onHold() {
  if (page == PAGE_TASKS && view.taskCount > 0 && !completeWanted) {
    strlcpy(completeID, view.tasks[0].id, sizeof completeID);
    completeWanted = true;
  } else {
    refreshNow = true;
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(TOUCH_PIN, INPUT);
  Wire.begin(OLED_SDA, OLED_SCL);
  if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDRESS)) {
    Serial.println("OLED not found. Check SDA/SCL wiring and the address (0x3C or 0x3D).");
  }
  display.setTextColor(SSD1306_WHITE);
  display.clearDisplay();
  centered("VOX", 18, 3);
  centered("desk viewer", 48, 1);
  display.display();

  lock = xSemaphoreCreateMutex();
  // Network work on core 0. The screen loop stays on core 1.
  xTaskCreatePinnedToCore(networkTask, "network", 16384, nullptr, 1, nullptr, 0);
}

void loop() {
  static bool wasDown = false;
  static uint32_t downAt = 0;
  static bool holdFired = false;

  // Touch: the TTP223 output is HIGH while touched.
  const bool down = digitalRead(TOUCH_PIN) == HIGH;
  const uint32_t ms = millis();
  if (down && !wasDown) {
    downAt = ms;
    holdFired = false;
    lastTouch = ms;
  }
  if (down && !holdFired && ms - downAt >= HOLD_MS && !ringing) {
    holdFired = true;
    onHold();
  }
  if (!down && wasDown && !holdFired && ms - downAt > 30) onTap();
  wasDown = down;

  if (page != PAGE_HOME && ms - lastTouch > BACK_HOME_MS) page = PAGE_HOME;

  // Take a fresh copy of the data and any newly done task.
  xSemaphoreTake(lock, portMAX_DELAY);
  view = shared;
  if (!doneShowing && doneHead != doneTail) {
    strlcpy(doneTitle, doneQueue[doneHead], TITLE_LEN);
    doneHead = (doneHead + 1) % DONE_QUEUE;
    doneShowing = true;
    doneShownAt = ms;
  }
  xSemaphoreGive(lock);

  const time_t now = time(nullptr);
  if (clockReady() && view.loaded) checkAlarms(now);
  if (ringing && ms - ringStartedAt > RING_MS) ringing = false;
  if (doneShowing && ms - doneShownAt > DONE_SHOW_MS) doneShowing = false;

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  if (ringing) {
    drawRinging();
  } else if (doneShowing) {
    drawDone();
  } else if (!clockReady()) {
    centered("VOX", 14, 3);
    centered(view.status, 48, 1);
  } else {
    switch (page) {
      case PAGE_HOME: drawHome(now); break;
      case PAGE_ALARM: drawAlarm(now); break;
      case PAGE_REMINDERS: drawReminders(now); break;
      case PAGE_TASKS: drawTasks(now); break;
      default: break;
    }
  }
  if (down && !holdFired) drawHoldBar(ms - downAt);
  // Ringing alarms flash the whole screen twice a second.
  display.invertDisplay(ringing && (ms / 500) % 2);
  display.display();
  delay(30);
}
