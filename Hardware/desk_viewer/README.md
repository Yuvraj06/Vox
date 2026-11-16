# Vox desk viewer

A small always-on screen for the desk. It shows the clock, a countdown to the next alarm, upcoming
reminders and the most important tasks, straight from Supabase over Wi-Fi. When a task is ticked done
anywhere (phone, website or on the viewer itself) it shows "Completed".

## Parts

- ESP32 dev module (the 30 or 38 pin board)
- 0.96 inch OLED, 128x64, I2C (SSD1306)
- TTP223 touch sensor module

## Wiring

| Part | Pin | ESP32 |
|---|---|---|
| OLED | VCC | 3V3 |
| OLED | GND | GND |
| OLED | SDA | GPIO21 |
| OLED | SCL | GPIO22 |
| TTP223 | VCC | 3V3 |
| TTP223 | GND | GND |
| TTP223 | SIG (or I/O) | GPIO4 |

If the OLED stays black, its address may be 0x3D. Change `OLED_ADDRESS` in `src/main.cpp`.

## Setup

1. Plug in the board and run `pio run -t upload` from this folder.
2. If the board has no Wi-Fi saved, or cannot connect within 10 seconds, the screen shows **SETUP**.
3. On your phone, join the Wi-Fi called **Vox Desk** (no password). The setup page pops up by itself.
   If it does not, open **http://192.168.4.1** in the browser.
4. Pick your Wi-Fi (tap **Scan**), type its password, then your Vox email and password. Tap **Save**.
5. The board connects. Once it is online, the same page is also at its address on your Wi-Fi
   (shown at the bottom of the setup screen).

Wi-Fi must be 2.4 GHz. The ESP32 cannot join 5 GHz networks.
`include/secrets.h` is optional. If present, it only fills in the first-time defaults.

## Admin page

- Wi-Fi network and password (with a Scan button)
- Vox account email and password
- Brightness
- Which screens a tap cycles through, and which one is the idle screen
- How long until it goes back to the idle screen
- Upside down mounting, 24 hour clock, time zone
- Status: Wi-Fi and account connection

Everything is saved in the board's own flash, so it survives unplugging.

## Using it

| Touch | Does |
|---|---|
| Tap | Next screen. On Tasks: next task, then the next screen after the last one |
| Hold 1 s, let go | On Tasks: marks the task on screen done. Elsewhere: refreshes now |
| Hold 7 s | Opens the setup page (hold 7 s again to close it) |
| Tap while an alarm rings | Stops it |

A bar along the bottom fills while you hold, with a "setup in 3" countdown after the first second.

Screens. One thing per screen, drawn big enough to read from across the desk:

- **Home** (idle by default): if something is still due today, a big countdown to it with its name and time.
  Otherwise the face: two eyes that blink and look around, a small clock, and one line at the bottom counting
  down to the next thing whenever it is. Sleepy with "zzz" from 11 pm to 6 am. Big smile after a task is completed.
- **Clock**: huge time with the date under it.
- **Today** and **Tomorrow**: up to three rows, big time and small title. Things that already went off are struck through.
- **Tasks**: one task in big text with its number (like 2/5), "then ..." under it. Tap for the next task. Hold 1 s to complete the one on screen.
- **Done**: pops up for 4 seconds whenever a task becomes done anywhere.
- **Alarm**: flashes when an alarm's time comes. Tap to stop.

It asks Supabase every 10 seconds.

## How it talks to Supabase

Plain HTTPS from the ESP32: signs in with email and password at `/auth/v1/token`, then reads
`/rest/v1/reminders` and `/rest/v1/nodes` with the user's token. Row Level Security means it can only
see that user's rows. Completing a task is a `PATCH` on the node, moved to its board's Done column and
its reminders marked done, the same way the phone does it.
