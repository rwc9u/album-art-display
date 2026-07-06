# album-art-display

Show the album art of whatever's playing over AirPlay on a 64×64 RGB LED matrix.

A small MQTT client that subscribes to cover art published by
[shairport-sync](https://github.com/mikebrady/shairport-sync) and renders it to
an [hzeller/rpi-rgb-led-matrix](https://github.com/hzeller/rpi-rgb-led-matrix)
panel. After each track change it briefly shows the title and artist in a bar
across the bottom, then fades back to just the album art. Lines too long to fit
scroll horizontally.

## Architecture

```
Mac / iPhone (Music app, AirPlay)
        │  audio + metadata + cover art
        ▼
shairport-sync  ──publishes──▶  MQTT broker (mosquitto)
                                        │  shairport-sync/<name>/cover (PNG)
                                        ▼
                                  display.py  ──▶  64×64 RGB LED matrix
```

Audio is not played on the Pi — shairport-sync uses the ALSA `null` sink, so the
Pi is a pure metadata/art endpoint. Listen on your Mac (or another AirPlay
speaker) by selecting both "Computer" and this device in the Music app's AirPlay
control.

## Hardware

- Raspberry Pi 4
- Adafruit RGB Matrix Bonnet (`hardware_mapping = "adafruit-hat"`)
- 64×64 RGB LED matrix (HUB75)
- 5V power supply for the panel

## Dependencies

- `mosquitto` MQTT broker (with `persistence true` so retained art survives reboots)
- `shairport-sync` built with `--with-metadata` and `--with-mqtt-client`
- Python: [`rgbmatrix`](https://github.com/hzeller/rpi-rgb-led-matrix) bindings,
  `paho-mqtt` (v2.x), `Pillow`
- `fonts-dejavu-core` (for the title/artist overlay text)

## Config

Sample configs live in [`config/`](config/):

- [`config/mosquitto.conf`](config/mosquitto.conf) — the MQTT broker config
  (drop into `/etc/mosquitto/conf.d/`). Anonymous access on port 1883 — trusted
  LAN only.
- [`config/shairport-sync.conf.example`](config/shairport-sync.conf.example) —
  the relevant blocks to merge into `/etc/shairport-sync.conf`.

### mosquitto

Copy `config/mosquitto.conf` to `/etc/mosquitto/conf.d/mosquitto.conf`. Retained
cover art only survives a reboot if broker persistence is on — Debian's default
`/etc/mosquitto/mosquitto.conf` already sets `persistence true` /
`persistence_location /var/lib/mosquitto/`; keep it.

### shairport-sync

Merge `config/shairport-sync.conf.example` into `/etc/shairport-sync.conf`. Key
points: `alsa.output_device = "null"` (art-only, no audio hardware),
`metadata.enabled`/`include_cover_art`, and in the `mqtt` block
`publish_parsed` + `publish_cover` + `publish_retain` all set to `"yes"` with
`topic` matching `TOPIC_PREFIX` in `display.py`.

## Install

One-command bootstrap (from the repo checkout):

```bash
sudo ./setup.sh
```

This installs the MQTT broker + Python deps, builds the LED-matrix bindings,
installs `config/mosquitto.conf`, and enables the `mosquitto` and
`albumart-display` services (the display service is generated to run
`display.py` from wherever you cloned the repo). shairport-sync is not installed
by the script — see below.

<details>
<summary>Manual steps (what setup.sh automates)</summary>

```bash
# MQTT broker + Python deps
sudo apt-get install -y mosquitto mosquitto-clients python3-dev python3-pip \
  cython3 cmake git python3-paho-mqtt python3-pil

# Python bindings for the matrix (from the rpi-rgb-led-matrix checkout)
cd rpi-rgb-led-matrix && sudo pip3 install . --break-system-packages

# Broker config + display service (needs root for GPIO)
sudo cp config/mosquitto.conf /etc/mosquitto/conf.d/
sudo cp albumart-display.service /etc/systemd/system/
sudo systemctl enable --now mosquitto albumart-display
```
</details>

### shairport-sync (not automated)

Build shairport-sync with `--with-metadata --with-mqtt-client` (plus alsa,
avahi, ssl), then merge `config/shairport-sync.conf.example` into
`/etc/shairport-sync.conf` and `sudo systemctl restart shairport-sync`.

## Configuration

Edit the constants at the top of `display.py`:

- `BROKER` / `PORT` — MQTT broker
- `TOPIC_PREFIX` — must match shairport-sync's `topic`

- `OVERLAY_SECONDS` — how long the title/artist bar stays after a track change
- `FONT_PATH` — TrueType font used for the overlay text
- `SCROLL_SPEED` / `SCROLL_START_DELAY` / `SCROLL_GAP` / `FPS` — marquee tuning
  for lines that are wider than the panel

Matrix geometry and GPIO options are set in `display.py` via `RGBMatrixOptions`
(`rows`, `cols`, `hardware_mapping`, `gpio_slowdown`).
