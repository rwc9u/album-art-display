# frozen_string_literal: true

# For local development only. On the Pi the service runs without Bundler,
# using apt's ruby-ffi, ruby-rmagick and ruby-webrick plus
# `gem install mqtt prometheus-client`.
source "https://rubygems.org"

ruby "~> 3.3"

gem "ffi"
gem "mqtt"
gem "prometheus-client"
gem "rmagick"
gem "webrick"

group :development do
  gem "minitest"
  gem "rake"
end
