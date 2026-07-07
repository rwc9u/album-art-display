# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-file Python client (`display.py`) that renders AirPlay album art on a
64×64 RGB LED matrix. It is a leaf node in this pipeline:

```
Mac/iPhone (AirPlay) → shairport-sync → MQTT broker (mosquitto) → display.py → LED matrix
```

shairport-sync publishes cover art + parsed metadata to MQTT topics; `display.py`
subscribes and paints the panel. The Pi plays no audio (ALSA `null` sink) — it is
a pure metadata/art endpoint.

## Runs only on a Raspberry Pi

This code **cannot run or be tested on a dev machine**. It imports `rgbmatrix`
(hzeller/rpi-rgb-led-matrix C bindings, built on-device) and drives GPIO, which
requires running as root on a Pi with the Adafruit RGB Matrix Bonnet. There is
no test suite and no configured linter — verification means deploying to the Pi
and watching `journalctl -u albumart-display`. Treat edits as untestable locally
and reason about correctness by reading the code.

## Architecture of display.py

Two threads share state guarded by `state_lock`:

- **MQTT loop** (main thread, `client.loop_forever()`): `on_message` decodes
  incoming cover PNGs into a resized `PIL.Image`, and updates `artist`/`title`.
  A new cover resets `overlay_start`/`overlay_deadline` to trigger the overlay.
- **animator** (daemon thread): the render loop. Draws plain art when idle;
  while the overlay is active (`now < overlay_deadline`) it composites a
  translucent bottom bar with title/artist at `FPS` and scrolls any line wider
  than the panel (marquee). Redraws the plain image once on each transition, then
  idles cheaply — it does not repaint every tick.

A cover payload of ≤100 bytes is treated as "no art" (clears the panel), not an
image to decode.

## Critical coupling

`TOPIC_PREFIX` in `display.py` **must exactly match** the `topic` in the
shairport-sync `mqtt` block (`config/shairport-sync.conf.example`). If they
diverge, the panel silently shows nothing. All tunables (overlay duration, scroll
speed, fonts, matrix geometry/GPIO) are constants at the top of `display.py`.

## Deploy

`sudo ./setup.sh` (run on the Pi, from the checkout) installs deps, builds the
matrix bindings, installs the mosquitto config, and generates + enables the
`albumart-display` systemd service pointing at wherever the repo was cloned.
shairport-sync is **not** installed by the script — it must be built separately
with `--with-metadata --with-mqtt-client`. See README.md for the full manual path.

## Hardware gotcha

64×64 panels need the fourth address line (E), which the Adafruit Bonnet does not
wire by default — a jumper must be soldered on the PCB or only half the panel
lights up. This is a hardware fact that shapes nothing in code but explains
"half the panel is dark" reports.
