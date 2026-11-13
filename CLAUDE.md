# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A small Ruby program (`bin/albumart-display` + `lib/albumart/`) that renders
AirPlay album art, the time, the local weather and Copper Mountain's snow report
on a 64×64 RGB LED matrix. It is a leaf node in this pipeline:

```
Mac/iPhone (AirPlay) → shairport-sync → MQTT broker (mosquitto) → bin/albumart-display → LED matrix
```

shairport-sync publishes cover art + parsed metadata to MQTT topics; the program
subscribes and paints the panel. The Pi plays no audio (ALSA `null` sink) — it is
a pure metadata/art endpoint. Weather comes from Open-Meteo (keyless) for a
location read from `/etc/albumart-display.env`, which is private and never
committed. The snow report comes from Copper Mountain's undocumented, keyless
JSON feeds (`api.coppercolorado.com`), with its weather icon from Open-Meteo for
the resort's fixed public coordinates.

`display.py` is the legacy Python implementation, kept untouched as a rollback.

Runtime: Ruby 3.3 from apt (`/usr/bin/ruby`), apt `ruby-ffi`, `ruby-rmagick`
(6.0.1 on trixie) and `ruby-webrick`, and the `mqtt` and `prometheus-client`
gems installed with `gem install`. No Bundler at runtime; the `Gemfile` is for
local development only.

## What runs where

The matrix code (`lib/albumart/matrix.rb`) needs `librgbmatrix.so.1`, GPIO and
root, so it **only runs on the Pi** (Raspberry Pi 4 + Adafruit RGB Matrix
Bonnet). Everything else can be exercised on a dev machine:

```bash
rake test                        # minitest suite, warnings on
bin/preview /tmp/albumart-preview  # every slide as PNG + 8x copies (needs rmagick)
ruby -wc lib/albumart/*.rb bin/*   # syntax/warning check
```

The scheduler, weather and snow report clients/parsers, stats and clock
formatting are pure Ruby and must keep loading without `ffi`, `rmagick`, `mqtt`,
`webrick` or `prometheus-client` (`test/pure_load_test.rb` enforces this). Tests inject the
clock and the HTTP call; nothing else is mocked. On the Pi, verify by watching
`journalctl -u albumart-display`.

## Architecture

- `config.rb` — every tunable constant (topics, timings, font, matrix options).
- `scheduler.rb` — pure. Decides the current slide: after a new cover, art with
  the title/artist bar for `OVERLAY_SECONDS`, then weather → forecast → snow →
  time → art, `SLIDE_SECONDS` each, skipping slides with nothing to show. The art
  slide drops out `ART_IDLE_SECONDS` after the last cover; the others run all
  day and are never dimmed or blanked.
- `weather.rb` — pure. Env settings, Open-Meteo request/parse, WMO code →
  condition, and a `Fetcher` that refreshes on its own thread and treats data
  older than an hour as missing. One request carries today and the next three
  days; today's fields are parsed strictly, the forecast leniently (anything
  malformed yields an empty forecast, never an error). Forecast weekdays come
  from the response's location-local dates, not the Pi's clock. `bin` runs a
  second `Fetcher` (`label: "mountain weather"`, no stats) for Copper Mountain's
  coordinates; the snow slide uses its condition and day for the icon, and
  today's high and low.
- `snow_report.rb` — pure. Parses the two Copper feeds all-or-nothing into base
  depth and percent of trails open (by count: `alpine_trail`, `include`,
  `winter`/`all` season), and a `Fetcher` that refreshes hourly. Its `refresh`
  rescues every `StandardError` because the feeds are undocumented. `#current`
  hides data older than `SNOW_MAX_AGE_SECONDS`, and a report older than
  `SNOW_REPORT_STALE_SECONDS` by the wall clock (off-season).
- `clock_face.rb`, `scene.rb` — pure value objects for the time text and one frame.
- `display.rb` — shared track state under one mutex, and the render loop. Redraws
  only when the scene key changes, or at `FPS` while the bar is visible (marquee).
- `renderer.rb`, `icons.rb` — RMagick. Decodes covers (JPEG/PNG only), composes
  each slide, and draws weather icons and the snow slide's snowboard from
  primitives without anti-aliasing. The snow slide is four rows (label with a
  16px snowboard, depth and BASE on one baseline, weather icon with high and
  low, percent open); without mountain weather it drops the third row and
  re-spaces the rest.
- `matrix.rb` — `ffi` binding to hzeller's C API, double-buffered with
  `led_matrix_swap_on_vsync`.
- `mqtt_listener.rb` — the `mqtt` gem does not auto-reconnect, so this wraps it
  in a reconnect loop with backoff.
- `stats.rb` — pure. Thread-safe counters and monotonic last-seen times, fed by
  `Display`, `MqttListener`, the local `Weather::Fetcher` and
  `SnowReport::Fetcher` through an optional `stats:`
  keyword; `#snapshot` computes ages at call time.
- `metrics_server.rb` — the only file that loads `webrick` and
  `prometheus-client`. Serves `GET /metrics` on `METRICS_PORT` (9101), building
  a fresh registry from `stats.snapshot` on every scrape.

Six threads: render, MQTT, weather, mountain weather, snow, metrics.
`Thread.abort_on_exception = true`, so any unhandled exception exits the process
and systemd restarts it. All timing uses `CLOCK_MONOTONIC`; wall-clock time is
only used for the text on the time slide and to hide a stale (off-season) snow
report, where a report dated in the future counts as fresh because the Pi has
no RTC.

## Critical coupling and landmines

- `TOPIC_PREFIX` in `lib/albumart/config.rb` **must exactly match** the `topic`
  in the shairport-sync `mqtt` block (`config/shairport-sync.conf.example`). If
  they diverge, the panel silently shows no art.
- The FFI structs in `matrix.rb` must mirror `led-matrix-c.h` field for field. In
  that C API a zero field means "library default", not "off".
- The matrix drops root to `daemon:daemon` right after init (the library default,
  matching the old Python binding). Anything that reads root-only files must load
  before `Albumart::Matrix.new`.
- A metrics failure must never exit the process (`Thread.abort_on_exception` is
  on). `bin/albumart-display` rescues load and bind errors (WEBrick binds in
  `MetricsServer.new`) and anything raised by `#start`, logs
  `[metrics] ...; metrics disabled` and keeps the panel running.
- rmagick < 7.1 (the Pi's apt 6.0.1) interprets `%` escapes, backslashes and a
  leading `@file` in text; `Renderer#literal` escapes them. Keep all text going
  through it.

## Deploy

`sudo ./setup.sh` (run on the Pi, from the checkout) installs deps, builds the
matrix shared library (`make -C $MATRIX_DIR/lib`), installs the mosquitto config
and the env template, and generates + enables the `albumart-display` service
pointing at wherever the repo was cloned. shairport-sync is **not** installed by
the script — it must be built separately with `--with-metadata
--with-mqtt-client`. See README.md for the full manual path.

## Hardware gotcha

64×64 panels need the fourth address line (E), which the Adafruit Bonnet does not
wire by default — a jumper must be soldered on the PCB or only half the panel
lights up. This is a hardware fact that shapes nothing in code but explains
"half the panel is dark" reports.
