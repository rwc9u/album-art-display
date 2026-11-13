# frozen_string_literal: true

# Used on the Pi and for development. Gemfile.lock pins every version; on the
# Pi, setup.sh installs the bundle to /var/lib/albumart-display/bundle.
source "https://rubygems.org"

ruby "~> 3.3"

gem "falcon"
gem "ffi"
gem "mqtt"
gem "prometheus-client"
# Matches what the Pi has been running, so rendering does not change.
gem "rmagick", "6.0.1"

group :development do
  gem "minitest"
  gem "rake"
end
