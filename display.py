#!/usr/bin/env python3
"""Show shairport-sync album art (via MQTT) on a 64x64 RGB LED matrix."""
import io
import paho.mqtt.client as mqtt
from PIL import Image
from rgbmatrix import RGBMatrix, RGBMatrixOptions

BROKER = "localhost"
PORT = 1883
TOPIC_PREFIX = "shairport-sync/rpih1"
COVER_TOPIC = TOPIC_PREFIX + "/cover"

options = RGBMatrixOptions()
options.rows = 64
options.cols = 64
options.chain_length = 1
options.parallel = 1
options.hardware_mapping = "adafruit-hat"
options.gpio_slowdown = 4
matrix = RGBMatrix(options=options)

def show_cover(data):
    try:
        img = Image.open(io.BytesIO(data)).convert("RGB")
    except Exception as e:
        print(f"[display] decode failed: {e}", flush=True)
        return
    img = img.resize((matrix.width, matrix.height), Image.LANCZOS)
    matrix.SetImage(img)
    print(f"[display] cover shown ({len(data)} bytes, {img.size})", flush=True)

def on_connect(client, userdata, flags, reason_code, properties=None):
    print(f"[mqtt] connected (rc={reason_code}); subscribing {COVER_TOPIC}", flush=True)
    client.subscribe(COVER_TOPIC)

def on_message(client, userdata, msg):
    if len(msg.payload) > 100:
        show_cover(msg.payload)
    else:
        matrix.Clear()
        print("[display] empty payload -> cleared", flush=True)

client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
client.on_connect = on_connect
client.on_message = on_message
client.connect(BROKER, PORT, 60)
print("[display] running MQTT loop", flush=True)
client.loop_forever()
