# frozen_string_literal: true

# For local development only. On the Pi the service runs without Bundler,
# using apt's ruby-ffi and ruby-rmagick plus `gem install mqtt`.
source "https://rubygems.org"

ruby "~> 3.3"

gem "ffi"
gem "mqtt"
gem "rmagick"

group :development do
  gem "minitest"
  gem "rake"
end
