#!/usr/bin/env python3
"""Show shairport-sync album art (via MQTT) on a 64x64 RGB LED matrix.

After each track change the title and artist are shown in a translucent bar
across the bottom for OVERLAY_SECONDS, then the bar disappears leaving just the
album art.
"""
import io
import threading

import paho.mqtt.client as mqtt
from PIL import Image, ImageDraw, ImageFont
from rgbmatrix import RGBMatrix, RGBMatrixOptions

BROKER = "localhost"
PORT = 1883
TOPIC_PREFIX = "shairport-sync/rpih1"
COVER_TOPIC = TOPIC_PREFIX + "/cover"
ARTIST_TOPIC = TOPIC_PREFIX + "/artist"
TITLE_TOPIC = TOPIC_PREFIX + "/title"

OVERLAY_SECONDS = 20  # how long the title/artist bar stays after a track change
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"

options = RGBMatrixOptions()
options.rows = 64
options.cols = 64
options.chain_length = 1
options.parallel = 1
options.hardware_mapping = "adafruit-hat"
options.gpio_slowdown = 4
matrix = RGBMatrix(options=options)
W, H = matrix.width, matrix.height

try:
    FONT_TITLE = ImageFont.truetype(FONT_PATH, 10)
    FONT_ARTIST = ImageFont.truetype(FONT_PATH, 9)
except OSError:
    FONT_TITLE = FONT_ARTIST = ImageFont.load_default()

# Shared state (guarded by state_lock)
state_lock = threading.Lock()
current_art = None      # PIL.Image sized to WxH, or None
artist = ""
title = ""
overlay_active = False
overlay_timer = None


def _fit(draw, text, font, max_w):
    """Truncate text with an ellipsis so it fits within max_w pixels."""
    if not text or draw.textlength(text, font=font) <= max_w:
        return text
    while text and draw.textlength(text + "…", font=font) > max_w:
        text = text[:-1]
    return text + "…"


def _render_locked():
    """Draw the current art (+ overlay if active). Caller must hold state_lock."""
    if current_art is None:
        return
    img = current_art.copy()
    if overlay_active and (artist or title):
        draw = ImageDraw.Draw(img, "RGBA")
        bar_h = 23
        draw.rectangle([0, H - bar_h, W, H], fill=(0, 0, 0, 170))
        draw.text((1, H - bar_h + 1), _fit(draw, title, FONT_TITLE, W - 2),
                  font=FONT_TITLE, fill=(255, 255, 255, 255))
        draw.text((1, H - 11), _fit(draw, artist, FONT_ARTIST, W - 2),
                  font=FONT_ARTIST, fill=(210, 210, 210, 255))
    matrix.SetImage(img.convert("RGB"))


def _expire_overlay():
    global overlay_active
    with state_lock:
        overlay_active = False
        _render_locked()


def on_connect(client, userdata, flags, reason_code, properties=None):
    print(f"[mqtt] connected (rc={reason_code})", flush=True)
    client.subscribe([(COVER_TOPIC, 0), (ARTIST_TOPIC, 0), (TITLE_TOPIC, 0)])


def on_message(client, userdata, msg):
    global current_art, artist, title, overlay_active, overlay_timer
    if msg.topic == COVER_TOPIC:
        if len(msg.payload) > 100:
            try:
                img = (Image.open(io.BytesIO(msg.payload)).convert("RGB")
                       .resize((W, H), Image.LANCZOS))
            except Exception as e:
                print(f"[display] decode failed: {e}", flush=True)
                return
            with state_lock:
                current_art = img
                overlay_active = True
                _render_locked()
                if overlay_timer:
                    overlay_timer.cancel()
                overlay_timer = threading.Timer(OVERLAY_SECONDS, _expire_overlay)
                overlay_timer.daemon = True
                overlay_timer.start()
            print(f"[display] new cover ({len(msg.payload)} bytes)", flush=True)
        else:
            with state_lock:
                current_art = None
                overlay_active = False
                matrix.Clear()
    elif msg.topic in (ARTIST_TOPIC, TITLE_TOPIC):
        value = msg.payload.decode("utf-8", "replace")
        with state_lock:
            if msg.topic == ARTIST_TOPIC:
                artist = value
            else:
                title = value
            # Refresh the bar if it's currently showing (also covers the case
            # where retained artist/title arrive after the retained cover).
            if overlay_active:
                _render_locked()


client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
client.on_connect = on_connect
client.on_message = on_message
client.connect(BROKER, PORT, 60)
print("[display] running MQTT loop", flush=True)
client.loop_forever()
