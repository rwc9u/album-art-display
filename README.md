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

## shairport-sync config

Relevant blocks in `/etc/shairport-sync.conf`:

```
alsa = {
  output_device = "null";   // discard audio; Pi is art-only
};

metadata = {
  enabled = "yes";
  include_cover_art = "yes";
};

mqtt = {
  enabled = "yes";
  hostname = "localhost";           // or the broker host
  port = 1883;
  topic = "shairport-sync/rpih1";   // must match TOPIC_PREFIX in display.py
  publish_parsed = "yes";           // artist/album/title/…
  publish_cover  = "yes";           // binary cover art
  publish_retain = "yes";           // broker keeps last art → shows on boot
};
```

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
