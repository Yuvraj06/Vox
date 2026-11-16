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

1. Copy `include/secrets.example.h` to `include/secrets.h`.
2. Fill in your Wi-Fi name and password, and the Vox email and password (same as the app).
3. Set `TIME_ZONE`. India is `IST-5:30`.
4. Plug in the board and run `pio run -t upload` from this folder. Then `pio device monitor` to watch it connect.

Wi-Fi must be 2.4 GHz. The ESP32 cannot join 5 GHz networks.

## Using it

| Touch | Does |
|---|---|
| Tap | Next screen: Home, Next alarm, Reminders, Tasks |
| Hold 1 s on Tasks | Marks the top task done |
| Hold 1 s elsewhere | Refreshes now |
| Tap while an alarm rings | Stops it |

Screens:

- **Home**: date, big clock, "Alarm in 07:42:10", tasks done today and still to do. Top right shows Live, or what is wrong (No Wi-Fi, Login failed, Offline).
- **Next alarm**: countdown, name, day and time.
- **Reminders**: the next four, with day and time.
- **Tasks**: the four most important: soonest deadline first, then ones in progress. `!` means late, `>` means doing. The top one is highlighted; hold to complete it.
- **Completed**: pops up for 4 seconds whenever a task becomes done, with a tick and the task name.
- **Alarm**: flashes and shows the alarm name when its time comes. Tap to stop.

It asks Supabase every 10 seconds. After 60 seconds without a touch it goes back to Home.

## How it talks to Supabase

Plain HTTPS from the ESP32: signs in with email and password at `/auth/v1/token`, then reads
`/rest/v1/reminders` and `/rest/v1/nodes` with the user's token. Row Level Security means it can only
see that user's rows. Completing a task is a `PATCH` on the node, moved to its board's Done column and
its reminders marked done, the same way the phone does it.
