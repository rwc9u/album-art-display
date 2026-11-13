# album-art-display

Show the album art of whatever's playing over AirPlay on a 64×64 RGB LED matrix,
rotating with the time, the local weather and Copper Mountain's snow report.

A small Ruby MQTT client that subscribes to cover art published by
[shairport-sync](https://github.com/mikebrady/shairport-sync) and renders it to
an [hzeller/rpi-rgb-led-matrix](https://github.com/hzeller/rpi-rgb-led-matrix)
panel. After each track change it shows the art with the title and artist in a
bar across the bottom for 10 seconds, then the panel rotates through five
slides, 5 seconds each: **weather, 3-day forecast, snow report, time, album
art**. The forecast shows the next three days (weekday, condition, high and
low); the snow report shows Copper Mountain's base depth, the share of trails
open, and the mountain's current weather with today's high and low. Lines too
long to fit scroll horizontally.

- No cover yet, or no new cover for an hour: the art slide drops out and the
  panel rotates weather, forecast, snow report and time. The next cover brings
  it back.
- No weather configured, or no fresh data: the weather and forecast slides are
  skipped.
- Forecast data missing or malformed: only the forecast slide is skipped.
- No fresh snow report, or the resort is out of season: the snow slide is
  skipped (see [Snow report](#snow-report)).
- A track with no art (e.g. after joining mid-track) shows a "text card": the
  title/artist bar on black, in the art slide's place.

`display.py` is the legacy Python implementation, kept as a rollback (see
[Rolling back](#rolling-back)).

## Architecture

```
Mac / iPhone (Music app, AirPlay)
        │  audio + metadata + cover art
        ▼
shairport-sync  ──publishes──▶  MQTT broker (mosquitto)
                                        │  shairport-sync/<name>/cover (JPEG/PNG)
                                        ▼
                            bin/albumart-display  ──▶  64×64 RGB LED matrix
                                        ▲
     api.open-meteo.com (weather + Copper's weather, every 10 min)
     api.coppercolorado.com (snow report, hourly)
```

Audio is not played on the Pi — shairport-sync uses the ALSA `null` sink, so the
Pi is a pure metadata/art endpoint. Listen on your Mac (or another AirPlay
speaker) by selecting both "Computer" and this device in the Music app's AirPlay
control.

### Listening on headphones while the panel shows art

macOS won't fan out to AirPlay speakers while Bluetooth headphones (e.g. AirPods
Max) are already the Mac's active output — the multi-select checkboxes stay
disabled and you can only pick one destination.

**Order matters.** With the Bluetooth headphones still off, in Music's AirPlay
menu select **Albumart first, then "Computer"** — so both are active before the
headphones join. Only then enable the headphones. Music stays in multi-output
mode and you get audio in the headphones plus art on the panel. If the
headphones are already the active output when you open the menu, Music collapses
to single-output and Albumart becomes unselectable.

Fallback if that won't stick: create a **Multi-Output Device** in Audio MIDI
Setup combining the headphones + Albumart. Bluetooth has no drift correction
there, but since Albumart discards audio (null sink) that's harmless.

## Hardware

- Raspberry Pi 4
- Adafruit RGB Matrix Bonnet (`hardware_mapping = "adafruit-hat"`)
- 64×64 RGB LED matrix (HUB75)
- 5V power supply for the panel

> **Note:** 64×64 panels need the fourth address line (E), which the Bonnet
> doesn't wire up by default. You must **solder the small jumper on the Bonnet
> PCB** (bridge the center pad to pin 8) to enable it — otherwise only half the
> panel lights up. See Adafruit's
> [RGB Matrix Bonnet guide](https://learn.adafruit.com/adafruit-rgb-matrix-bonnet-for-raspberry-pi).

## Dependencies

- `mosquitto` MQTT broker (with `persistence true` so retained art survives reboots)
- `shairport-sync` built with `--with-metadata` and `--with-mqtt-client`
- Ruby 3.3 from apt (`ruby`, `ruby-dev`) and apt's `bundler`. Every gem is
  installed by Bundler from the committed `Gemfile.lock` into
  `/var/lib/albumart-display/bundle`. `rmagick` is pinned to 6.0.1 and compiled
  on the Pi (needs `libmagickwand-dev` and `pkg-config`); the `openssl` gem needs
  `libssl-dev`, and native extensions such as `io-event` need `build-essential`
  and `ruby-dev`.
- `librgbmatrix.so.1`, built from the hzeller checkout with `make -C lib`
- `fonts-dejavu-core` (for all panel text)

| Python library (legacy) | Ruby replacement |
|---|---|
| `paho-mqtt` | [`mqtt`](https://rubygems.org/gems/mqtt) gem (0.7.x, pure Ruby). It does not reconnect on its own; `lib/albumart/mqtt_listener.rb` does. |
| `Pillow` | `rmagick` (pinned to 6.0.1; the code also runs on 7.x) |
| `rgbmatrix` (hzeller Python binding) | No Ruby gem exists. `lib/albumart/matrix.rb` binds hzeller's C API (`include/led-matrix-c.h`) with `ffi`. |
| — (new, no Python equivalent) | [`falcon`](https://rubygems.org/gems/falcon) (0.57.x) serves `/metrics`; [`prometheus-client`](https://rubygems.org/gems/prometheus-client) (5.x) renders the text format. |

## Config

Sample configs live in [`config/`](config/):

- [`config/mosquitto.conf`](config/mosquitto.conf) — the MQTT broker config
  (drop into `/etc/mosquitto/conf.d/`). Anonymous access on port 1883 — trusted
  LAN only.
- [`config/shairport-sync.conf.example`](config/shairport-sync.conf.example) —
  the relevant blocks to merge into `/etc/shairport-sync.conf`.
- [`config/albumart-display.env.example`](config/albumart-display.env.example) —
  weather location, installed as `/etc/albumart-display.env`.

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
`topic` matching `TOPIC_PREFIX` in `lib/albumart/config.rb`.

### Weather

Weather comes from [Open-Meteo](https://open-meteo.com/), which needs no API key.
The location is private and never committed: set it in
`/etc/albumart-display.env` (mode 0600), which the service reads via
`EnvironmentFile=`:

```bash
WEATHER_LAT=<latitude>
WEATHER_LON=<longitude>
# fahrenheit (default) or celsius; systemd does not allow comments after a value
WEATHER_UNITS=fahrenheit
```

Without `WEATHER_LAT`/`WEATHER_LON` the service logs one line and skips the
weather and forecast slides. Data refreshes every 10 minutes (1 minute after a
failure) and is treated as missing once it is more than an hour old.

### Snow report

The snow slide needs no configuration. It reads two keyless JSON feeds from
Copper Mountain's website:

- `https://api.coppercolorado.com/api/v1/dor/drupal/snow-reports` — base depth
  (in inches) from the newest daily report
- `https://api.coppercolorado.com/api/v1/dor/drupal/trails` — trail status

These feeds are undocumented and may change or disappear without notice. A
response in an unexpected shape is logged as `[snow] fetch failed: ...` and the
slide is skipped; it never stops the panel.

"Open" is a share of trail **count**, not acreage: of the alpine trails marked
`include` for the `winter` or `all` season, the percentage whose status is
`open`, rounded (a single open trail shows at least 1%). The feeds refresh
hourly (10 minutes after a failure), and the slide is skipped once the last
good fetch is more than 3 hours old or the newest report is more than 3 days
old by the Pi's clock, which hides it off-season.

The slide has four rows: the resort name with a snowboard icon, the base depth
with its BASE caption, the mountain's weather icon followed by today's high and
low, and the share of trails open. The weather is the current condition at
Copper Mountain (39.50, -106.15, fixed in `lib/albumart/config.rb`), fetched
from Open-Meteo by a second weather fetcher on the same 10-minute schedule as
the local weather. If it is unavailable that row is dropped and the other three
are spaced out to fill the panel.

## Install

One-command bootstrap (from the repo checkout):

```bash
sudo ./setup.sh
```

This installs the MQTT broker, Ruby and its libraries, builds the LED-matrix
shared library, installs `config/mosquitto.conf`, installs the weather env
template to `/etc/albumart-display.env` if that file doesn't exist yet, and
enables the `mosquitto` and `albumart-display` services. The display service is
generated to run `bundle exec ruby bin/albumart-display` from wherever you
cloned the repo, with `RGBMATRIX_LIB` pointing at the built library. The gems go
to `/var/lib/albumart-display/bundle`, outside the checkout, because `/home` is
unreadable once the display drops root. shairport-sync is not installed by the
script — see below.

<details>
<summary>Manual steps (what setup.sh automates)</summary>

```bash
# MQTT broker, Ruby, build tools
sudo apt-get install -y mosquitto mosquitto-clients ruby ruby-dev bundler \
  build-essential git pkg-config libmagickwand-dev libssl-dev fonts-dejavu-core

# Gems, from the checkout as your normal user
sudo install -d -o "$USER" -g "$(id -gn)" -m 0755 /var/lib/albumart-display/bundle
bundle config set --local deployment true
bundle config set --local path /var/lib/albumart-display/bundle
bundle config set --local without development
bundle config set --local version system
bundle install

# Shared library for the matrix (from the rpi-rgb-led-matrix checkout)
make -C rpi-rgb-led-matrix/lib

# Broker config, weather settings, display service (needs root for GPIO).
# Edit WorkingDirectory and RGBMATRIX_LIB in the unit to match your paths.
sudo cp config/mosquitto.conf /etc/mosquitto/conf.d/
sudo install -m 0600 config/albumart-display.env.example /etc/albumart-display.env
sudo cp albumart-display.service /etc/systemd/system/
sudo systemctl enable --now mosquitto albumart-display
```
</details>

### Updating

After pulling new code on the Pi, run `bundle install` in the checkout (as your
normal user) whenever `Gemfile.lock` changed, then
`sudo systemctl restart albumart-display`. Re-running `sudo ./setup.sh` does the
same.

### shairport-sync (not automated)

Build shairport-sync with `--with-metadata --with-mqtt-client` (plus alsa,
avahi, ssl), then merge `config/shairport-sync.conf.example` into
`/etc/shairport-sync.conf` and `sudo systemctl restart shairport-sync`.

## Configuration

Edit the constants in `lib/albumart/config.rb`:

- `BROKER` / `PORT` — MQTT broker
- `TOPIC_PREFIX` — must match shairport-sync's `topic`
- `OVERLAY_SECONDS` — how long the title/artist bar shows after a track change
- `SLIDE_SECONDS` — each slide's turn in the rotation
- `ART_IDLE_SECONDS` — the art slide leaves the rotation after this long with no
  new cover. A cover only arrives on a track change, so keep it longer than a
  typical track.
- `TIME_24H` — 24-hour clock instead of `h:MM AM/PM`
- `SNOW_*` — snow report feeds, refresh timings, staleness limits, the resort
  label and the coordinates for its weather icon
- `FONT_PATH` — TrueType font used for all text
- `SCROLL_SPEED` / `SCROLL_START_DELAY` / `SCROLL_GAP` / `FPS` — marquee tuning
  for lines that are wider than the panel
- `MATRIX_OPTIONS` / `GPIO_SLOWDOWN` — matrix geometry and GPIO options

- `METRICS_PORT` / `METRICS_BIND` — the metrics endpoint (see [Metrics](#metrics))

`RGBMATRIX_LIB` (environment) overrides the path to `librgbmatrix.so.1`.

## Metrics

The display serves Prometheus metrics at `http://albumart.local:9101/metrics`
(plain HTTP, no auth; trusted LAN only):

| Metric | Type | Meaning |
|---|---|---|
| `albumart_uptime_seconds` | gauge | Seconds since the display started |
| `albumart_last_cover_age_seconds` | gauge | Seconds since the last cover (absent until one arrives) |
| `albumart_covers_total` | counter | Covers received, including empty ones shown as a text card |
| `albumart_mqtt_connected` | gauge | 1 while connected to the broker, else 0 |
| `albumart_mqtt_connects_total` | counter | Broker connections made |
| `albumart_mqtt_disconnects_total` | counter | Disconnects, including failed connection attempts |
| `albumart_weather_age_seconds` | gauge | Seconds since the last successful weather fetch (absent until one succeeds) |
| `albumart_weather_fetch_errors_total` | counter | Failed weather fetches (local weather only) |
| `albumart_snow_age_seconds` | gauge | Seconds since the last successful snow report fetch (absent until one succeeds) |
| `albumart_snow_fetch_errors_total` | counter | Failed snow report fetches |
| `albumart_current_slide{slide="weather\|forecast\|snow\|time\|art"}` | gauge | 1 for the slide on the panel, 0 for the others |

Nothing about the track or the location is exposed. Set `METRICS_PORT` in
`/etc/albumart-display.env` to change the port, or `METRICS_PORT=off` to disable
the endpoint. If the port is taken or the server fails to load, the display logs
`[metrics] ...; metrics disabled` and keeps running.

```yaml
scrape_configs:
  - job_name: albumart
    static_configs:
      - targets: ["albumart.local:9101"]
```

## Development

Off the Pi you can run the tests and render previews; the matrix itself only
works on the device.

```bash
bundle install                 # rmagick needs ImageMagick (e.g. brew install imagemagick)
bundle exec rake test          # minitest, with warnings on
bundle exec bin/preview /tmp/albumart-preview
```

The scheduler, weather, snow report, stats and clock code load without `ffi`,
`rmagick` or `mqtt` (a test enforces it); the metrics server test needs
`prometheus-client` and `falcon`. `bin/preview` renders every slide (each
weather condition by day and night, the forecast with every condition and the
widest numbers, the snow report with and without its weather icon and with the
widest base, percent open and high/low, the time, art with the bar, a text
card) to PNGs plus 8× nearest-neighbour copies for viewing. On macOS it falls back to
Arial Narrow Bold, so text widths differ slightly from the Pi's DejaVu.

## Rolling back

`display.py` is the previous Python implementation and still works with the
Python dependencies the old `setup.sh` installed (`python3-paho-mqtt`,
`python3-pil`, and the `rgbmatrix` binding via pip). It has no time or weather
slides. To switch back, point the unit at it and restart:

```bash
sudo sed -i 's|^ExecStart=.*|ExecStart=/usr/bin/python3 /home/rob/albumart-display/display.py|' \
  /etc/systemd/system/albumart-display.service
sudo systemctl daemon-reload && sudo systemctl restart albumart-display
```
