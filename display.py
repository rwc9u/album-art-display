#!/usr/bin/env python3
"""Show shairport-sync album art (via MQTT) on a 64x64 RGB LED matrix.

After each track change the title and artist are shown in a translucent bar
across the bottom for OVERLAY_SECONDS, then the bar disappears leaving just the
album art. Lines too wide for the panel scroll horizontally (marquee).

When nothing new arrives for a while the panel dims (IDLE_DIM_SECONDS) and then
blanks entirely (IDLE_BLANK_SECONDS), so an always-on display isn't left holding
one bright static image for hours. Any new cover restores full brightness.
"""
import io
import threading
import time

import paho.mqtt.client as mqtt
from PIL import Image, ImageDraw, ImageEnhance, ImageFont
from rgbmatrix import RGBMatrix, RGBMatrixOptions

BROKER = "localhost"
PORT = 1883
TOPIC_PREFIX = "shairport-sync/rpih1"
COVER_TOPIC = TOPIC_PREFIX + "/cover"
ARTIST_TOPIC = TOPIC_PREFIX + "/artist"
TITLE_TOPIC = TOPIC_PREFIX + "/title"

OVERLAY_SECONDS = 10      # how long the title/artist bar stays after a track change
SCROLL_SPEED = 16.0       # pixels/second for text too wide to fit
SCROLL_START_DELAY = 1.0  # seconds to hold the start of a line before scrolling
SCROLL_GAP = 12           # pixels of gap between the end and the wrapped start
FPS = 30                  # animation frame rate while the overlay is showing
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"

# Idle behaviour for an always-on panel. A new cover only arrives on a track
# change, so these must be longer than a typical track to avoid dimming during
# playback — the trade-off is that a paused session stays lit until the timeout.
IDLE_DIM_SECONDS = 15 * 60    # dim the art after this long with no new cover
IDLE_BLANK_SECONDS = 60 * 60  # blank the panel entirely after this long
IDLE_DIM_LEVEL = 0.35         # brightness multiplier (0-1) while dimmed

options = RGBMatrixOptions()
options.rows = 64
options.cols = 64
options.chain_length = 1
options.parallel = 1
options.hardware_mapping = "adafruit-hat"
options.gpio_slowdown = 4
# Higher refresh rate hides the dark banding a camera/phone catches when it
# photographs or films the panel (the eye doesn't see it, a fast shutter does).
# Fewer PWM bits and a shorter LSB pulse both raise refresh at the cost of color
# gradation; dithering recovers some of that. Tune on the Pi — set
# show_refresh_rate = True to print the achieved Hz, aim for a few hundred.
options.pwm_bits = 8            # default 11; lower = higher refresh, less color depth
options.pwm_lsb_nanoseconds = 80  # default 130; lower = higher refresh, more ghosting risk
options.pwm_dither_bits = 1     # trade a little temporal dither back for color depth
# options.show_refresh_rate = True  # uncomment to print achieved refresh rate
matrix = RGBMatrix(options=options)
W, H = matrix.width, matrix.height

try:
    FONT_TITLE = ImageFont.truetype(FONT_PATH, 8)
    FONT_ARTIST = ImageFont.truetype(FONT_PATH, 7)
except OSError:
    FONT_TITLE = FONT_ARTIST = ImageFont.load_default()

# Shared state (guarded by state_lock)
state_lock = threading.Lock()
current_art = None      # PIL.Image (RGB, WxH) or None
artist = ""
title = ""
overlay_start = 0.0     # monotonic time the current overlay began
overlay_deadline = 0.0  # monotonic time the overlay should disappear
last_cover_time = 0.0   # monotonic time the most recent cover arrived (idle clock)


def _draw_line(draw, text, font, y, elapsed, fill):
    """Draw a bar line, scrolling horizontally if it's wider than the panel."""
    if not text:
        return
    tw = draw.textlength(text, font=font)
    if tw <= W - 2:
        draw.text((1, y), text, font=font, fill=fill)
        return
    period = tw + SCROLL_GAP
    off = (max(0.0, elapsed - SCROLL_START_DELAY) * SCROLL_SPEED) % period
    x = 1 - off
    draw.text((x, y), text, font=font, fill=fill)           # scrolling copy
    draw.text((x + period, y), text, font=font, fill=fill)  # wrapped copy


def _dim(art, level):
    """Return a darkened copy of the art for the idle-dim state."""
    return ImageEnhance.Brightness(art).enhance(level)


def _compose(art, title_text, artist_text, elapsed):
    img = art.copy()
    draw = ImageDraw.Draw(img, "RGBA")
    bar_h = 18
    draw.rectangle([0, H - bar_h, W, H], fill=(0, 0, 0, 170))
    _draw_line(draw, title_text, FONT_TITLE, H - bar_h + 1, elapsed, (255, 255, 255, 255))
    _draw_line(draw, artist_text, FONT_ARTIST, H - 9, elapsed, (210, 210, 210, 255))
    return img


def animator():
    """Continuously drive the panel; scroll the overlay while it's active."""
    prev_overlay = False
    last_art = None
    idle_state = None  # "full" | "dim" | "blank" — what the panel currently shows
    while True:
        with state_lock:
            art, a, t = current_art, artist, title
            start, deadline = overlay_start, overlay_deadline
            cover_time = last_cover_time
        now = time.monotonic()
        overlay_on = art is not None and now < deadline and (a or t)

        if art is None:
            if last_art is not None:
                matrix.Clear()
                last_art, idle_state = None, None
            time.sleep(0.1)
        elif overlay_on:
            matrix.SetImage(_compose(art, t, a, now - start))
            last_art, prev_overlay, idle_state = art, True, "full"
            time.sleep(1.0 / FPS)
        else:
            idle = now - cover_time
            if idle >= IDLE_BLANK_SECONDS:
                want = "blank"
            elif idle >= IDLE_DIM_SECONDS:
                want = "dim"
            else:
                want = "full"
            # Redraw only on a transition (new art, overlay expiry, or an idle
            # state change); otherwise idle cheaply.
            if art is not last_art or prev_overlay or want != idle_state:
                if want == "blank":
                    matrix.Clear()
                elif want == "dim":
                    matrix.SetImage(_dim(art, IDLE_DIM_LEVEL))
                else:
                    matrix.SetImage(art)
                last_art, prev_overlay, idle_state = art, False, want
            time.sleep(0.5)


def on_connect(client, userdata, flags, reason_code, properties=None):
    print(f"[mqtt] connected (rc={reason_code})", flush=True)
    client.subscribe([(COVER_TOPIC, 0), (ARTIST_TOPIC, 0), (TITLE_TOPIC, 0)])


def on_message(client, userdata, msg):
    global current_art, artist, title, overlay_start, overlay_deadline
    global last_cover_time
    if msg.topic == COVER_TOPIC:
        if len(msg.payload) > 100:
            try:
                img = (Image.open(io.BytesIO(msg.payload)).convert("RGB")
                       .resize((W, H), Image.LANCZOS))
            except Exception as e:
                print(f"[display] decode failed: {e}", flush=True)
                return
            now = time.monotonic()
            with state_lock:
                current_art = img
                overlay_start = now
                overlay_deadline = now + OVERLAY_SECONDS
                last_cover_time = now
            print(f"[display] new cover ({len(msg.payload)} bytes)", flush=True)
        else:
            with state_lock:
                current_art = None
    elif msg.topic == ARTIST_TOPIC:
        with state_lock:
            artist = msg.payload.decode("utf-8", "replace")
    elif msg.topic == TITLE_TOPIC:
        with state_lock:
            title = msg.payload.decode("utf-8", "replace")


threading.Thread(target=animator, daemon=True).start()

client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
client.on_connect = on_connect
client.on_message = on_message
client.connect(BROKER, PORT, 60)
print("[display] running MQTT loop", flush=True)
client.loop_forever()
