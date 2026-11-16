// The admin page. Runs on the board as a captive portal: join the "Vox Desk" Wi-Fi and it pops up.
// While the board is on your home Wi-Fi it is also at http://<board ip>/.
#pragma once
#include <Arduino.h>
#include "settings.h"

// What the page shows under "Status".
struct PortalStatus {
  String wifi;      // "Connected to X (192.168.1.5)" or "Not connected"
  String account;   // "Live", "Login failed", ...
};

void portalBegin(Settings* settings);
// Starts the Wi-Fi access point and the captive portal DNS.
void portalOpenAP();
void portalCloseAP();
bool portalAPOpen();
// Call often from loop(). Serves pages.
void portalLoop(const PortalStatus& status);
// True once after the page saved something; tells the caller to apply the new settings.
bool portalTakeSaved(bool* wifiChanged, bool* accountChanged);
bool portalTakeRestart();
String portalAPName();
