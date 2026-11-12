#!/usr/bin/env bash
#
# Bootstrap the album-art-display pipeline on a Raspberry Pi (Raspberry Pi OS / Debian).
#
# Installs the MQTT broker and Ruby dependencies, builds the LED-matrix shared
# library, installs the broker config + display service, and enables
# everything to start on boot.
#
# Usage (run from the repo checkout):
#     sudo ./setup.sh
#
# Optional: override where the matrix library is cloned/built:
#     sudo MATRIX_DIR=/path/to/rpi-rgb-led-matrix ./setup.sh
#
# NOTE: shairport-sync is NOT installed by this script. It must be built with
# metadata + MQTT support (--with-metadata --with-mqtt-client). After that,
# merge config/shairport-sync.conf.example into /etc/shairport-sync.conf.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo ./setup.sh" >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# The non-root user who owns the checkout — used to clone the matrix lib into
# their home rather than root's.
RUN_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
RUN_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"
MATRIX_DIR="${MATRIX_DIR:-$RUN_HOME/rpi-rgb-led-matrix}"
MATRIX_LIB="$MATRIX_DIR/lib/librgbmatrix.so.1"
ENV_FILE=/etc/albumart-display.env

echo "==> Installing packages (broker, Ruby, build tools)"
apt-get update -qq
apt-get install -y \
  mosquitto mosquitto-clients \
  ruby ruby-dev ruby-ffi ruby-rmagick ruby-webrick \
  build-essential git \
  fonts-dejavu-core

echo "==> Ruby MQTT client"
if gem list --installed --exact mqtt >/dev/null; then
  echo "    mqtt gem already installed — skipping"
else
  gem install --no-document mqtt
fi

echo "==> Ruby Prometheus client"
if gem list --installed --exact prometheus-client >/dev/null; then
  echo "    prometheus-client gem already installed — skipping"
else
  gem install --no-document prometheus-client
fi

echo "==> LED-matrix shared library"
if [ ! -d "$MATRIX_DIR" ]; then
  echo "    cloning hzeller/rpi-rgb-led-matrix into $MATRIX_DIR"
  sudo -u "$RUN_USER" git clone https://github.com/hzeller/rpi-rgb-led-matrix "$MATRIX_DIR"
fi
# The lib Makefile's default target builds librgbmatrix.a and librgbmatrix.so.1.
sudo -u "$RUN_USER" make -C "$MATRIX_DIR/lib"

echo "==> MQTT broker config"
install -m 0644 "$REPO_DIR/config/mosquitto.conf" /etc/mosquitto/conf.d/mosquitto.conf
systemctl enable mosquitto
systemctl restart mosquitto

echo "==> Weather settings ($ENV_FILE)"
if [ -e "$ENV_FILE" ]; then
  echo "    $ENV_FILE exists — leaving it alone"
else
  install -m 0600 "$REPO_DIR/config/albumart-display.env.example" "$ENV_FILE"
  echo "    installed a template; set WEATHER_LAT/WEATHER_LON there to enable the weather slide"
fi

echo "==> album-art-display service (runs $REPO_DIR/bin/albumart-display)"
sed -e "s|^ExecStart=.*|ExecStart=/usr/bin/ruby $REPO_DIR/bin/albumart-display|" \
  -e "s|^Environment=RGBMATRIX_LIB=.*|Environment=RGBMATRIX_LIB=$MATRIX_LIB|" \
  "$REPO_DIR/albumart-display.service" > /etc/systemd/system/albumart-display.service
systemctl daemon-reload
systemctl enable albumart-display
systemctl restart albumart-display

echo
echo "==> Done. Service status:"
systemctl is-active mosquitto albumart-display || true
echo
echo "Remaining manual steps for shairport-sync:"
echo "  1. Build shairport-sync with: --with-metadata --with-mqtt-client (+ alsa, avahi, ssl)"
echo "  2. Merge config/shairport-sync.conf.example into /etc/shairport-sync.conf"
echo "  3. sudo systemctl restart shairport-sync"
echo "  4. (Optional) flicker-free matrix: set 'dtparam=audio=off' in"
echo "     /boot/firmware/config.txt and reboot."
