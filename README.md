# album-art-display

Show the album art of whatever's playing over AirPlay on a 64×64 RGB LED matrix.

A small MQTT client that subscribes to cover art published by
[shairport-sync](https://github.com/mikebrady/shairport-sync) and renders it to
an [hzeller/rpi-rgb-led-matrix](https://github.com/hzeller/rpi-rgb-led-matrix)
panel.

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

```bash
# Python bindings for the matrix (from the rpi-rgb-led-matrix checkout)
sudo apt-get install -y python3-dev cython3 cmake python3-paho-mqtt
cd rpi-rgb-led-matrix && sudo pip install . --break-system-packages

# Run as a service (needs root for GPIO)
sudo cp albumart-display.service /etc/systemd/system/
sudo systemctl enable --now albumart-display
```

## Configuration

Edit the constants at the top of `display.py`:

- `BROKER` / `PORT` — MQTT broker
- `TOPIC_PREFIX` — must match shairport-sync's `topic`

Matrix geometry and GPIO options are set in `display.py` via `RGBMatrixOptions`
(`rows`, `cols`, `hardware_mapping`, `gpio_slowdown`).
