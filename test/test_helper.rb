# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"

# A monotonic clock the test moves by hand.
class FakeClock
  attr_reader :now

  def initialize(now = 1000.0)
    @now = now
  end

  def call
    @now
  end

  def advance(seconds)
    @now += seconds
  end
end
