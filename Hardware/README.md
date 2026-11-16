# Vox keychain hardware

Parts:
- Seeed Studio XIAO ESP32-C6
- 0.96 inch OLED, 128x64, I2C, 4 pins (SSD1306 or SSD1315)
- INMP441 I2S microphone
- Push button

## Wiring

Hold the XIAO with the USB port at the top.

```
                  USB
              +---------+
 (free)   D0  |         |  5V    (do not use)
 BUTTON   D1  |         |  GND   ground rail
 mic SCK  D2  |  XIAO   |  3V3   power rail
 mic WS   D3  | ESP32C6 |  D10   mic SD
 OLED SDA D4  |         |  D9    (keep free)
 OLED SCL D5  |         |  D8    (keep free)
 (free)   D6  |         |  D7    (keep free)
              +---------+
```

### OLED
| OLED pin | XIAO pin |
|---|---|
| VCC | 3V3 |
| GND | GND |
| SDA | D4 (GPIO22) |
| SCL | D5 (GPIO23) |

The pin order differs between OLED boards. Follow the printed labels.

### INMP441 mic
| Mic pin | XIAO pin |
|---|---|
| VDD | 3V3 |
| GND | GND |
| L/R | GND |
| SCK | D2 (GPIO2) |
| WS | D3 (GPIO21) |
| SD | D10 (GPIO18) |

L/R must go to GND. Do not leave it unconnected.

### Button
| Button leg | XIAO pin |
|---|---|
| Leg A | D1 (GPIO1) |
| Leg B, diagonally opposite leg A | GND |

No resistor is needed. The chip has one built in.

## Test firmware

From `Hardware/hardware_test`:

```
pio run -t upload
pio device monitor
```

Stop the monitor with Ctrl+C.

If the upload cannot find the board:
1. Hold BOOT.
2. Tap RESET.
3. Release BOOT.
4. Upload again.
5. Tap RESET once it finishes.

### What a pass looks like
- The small LED on the XIAO blinks once a second.
- Serial Monitor prints `OLED: OK` and `Mic I2S: started`.
- The I2C scan finds a device at `0x3C` or `0x3D`.
- The OLED shows the mic level and button state.
- The mic bar jumps when you talk.
- One button press adds exactly 1 to the count.

### If something fails
| Symptom | Check |
|---|---|
| I2C scan finds nothing | OLED VCC, GND, and SDA and SCL swapped |
| Device found, screen stays blank | Screen may be a different driver. Note the label on the board |
| `MIC: NO SIGNAL` | Mic power, SCK, WS, SD |
| Mic number stays flat when you talk | SD wire, L/R to GND, solder joints on the mic header |
| Button count never changes | Use legs diagonally opposite each other |
| Button count jumps by 2 or more | Loose wire or a worn button |
| `riscv32-esp-elf-g++: command not found` | Run `ln -s riscv32-esp-elf/bin ~/.platformio/packages/toolchain-riscv32-esp/bin` |
