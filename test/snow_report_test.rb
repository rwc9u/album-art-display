# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "albumart/snow_report"
require "albumart/stats"

class SnowReportTest < Minitest::Test
  # Trimmed from the resort's real feeds; newest report first.
  REPORTS = <<~JSON
    [{"name":"Snow Report 2026-11-13 05:00:00","amount":0,"base_depth":18,"unit_of_measurement":"in",
      "updated":1794570980},
     {"name":"Snow Report 2026-11-12 05:00:00","amount":0,"base_depth":17,"unit_of_measurement":"in",
      "updated":1794484662}]
  JSON

  TRAILS = <<~JSON
    [{"name":"Rhapsody","status":"open","season":"winter","type":"alpine_trail","include":true},
     {"name":"Far East","status":"closed","season":"winter","type":"alpine_trail","include":true},
     {"name":"Timber Road","status":"open","season":"all","type":"alpine_trail","include":true},
     {"name":"Andy's Encore","status":"closed","season":"winter","type":"alpine_trail","include":true},
     {"name":"Nastar","status":"open","season":"winter","type":"alpine_trail","include":false},
     {"name":"1 Buck","status":"open","season":"summer","type":"mountain_bike_trail","include":true},
     {"name":"Colorado Trail","status":"open","season":"summer","type":"hiking_trail","include":true},
     {"name":"Aerie/PHQ (Route 1)","status":"open","season":"winter","type":"uphill_trail","include":true}]
  JSON

  REPORTED_AT = 1_794_570_980

  def trails(open:, closed:)
    trail = { status: "open", season: "winter", type: "alpine_trail", include: true }
    JSON.generate(Array.new(open, trail) + Array.new(closed, trail.merge(status: "closed")))
  end

  def fetcher(clock: FakeClock.new, now: -> { REPORTED_AT }, http: nil, stats: nil)
    http ||= ->(uri) { uri.path.end_with?("trails") ? TRAILS : REPORTS }
    Albumart::SnowReport::Fetcher.new(clock:, now:, http:, stats:)
  end

  def test_parses_the_newest_report_and_the_share_of_trails_open
    reading = Albumart::SnowReport.parse(REPORTS, TRAILS, fetched_at: 5.0)

    expected = Albumart::SnowReport::Reading.new(
      base_depth: 18, percent_open: 50, reported_at: REPORTED_AT, fetched_at: 5.0,
    )
    assert_equal expected, reading
  end

  def test_counts_only_included_winter_and_all_season_alpine_trails
    # Open but ineligible trails would push this above 2 of 4.
    assert_equal 50, Albumart::SnowReport.parse(REPORTS, TRAILS, fetched_at: 0.0).percent_open
  end

  def test_rounds_to_the_nearest_percent
    assert_equal 33, Albumart::SnowReport.parse(REPORTS, trails(open: 1, closed: 2), fetched_at: 0.0).percent_open
  end

  def test_any_open_trail_shows_at_least_one_percent
    body = trails(open: 1, closed: 200)

    assert_equal 1, Albumart::SnowReport.parse(REPORTS, body, fetched_at: 0.0).percent_open
  end

  def test_no_open_trails_is_zero_percent
    assert_equal 0, Albumart::SnowReport.parse(REPORTS, trails(open: 0, closed: 5), fetched_at: 0.0).percent_open
  end

  def test_rounds_a_fractional_base_depth
    body = REPORTS.sub('"base_depth":18', '"base_depth":18.6')

    assert_equal 19, Albumart::SnowReport.parse(body, TRAILS, fetched_at: 0.0).base_depth
  end

  def test_parse_rejects_non_json_reports
    assert_raises(Albumart::SnowReport::ResponseError) do
      Albumart::SnowReport.parse("<html>", TRAILS, fetched_at: 0.0)
    end
  end

  def test_parse_rejects_non_json_trails
    assert_raises(Albumart::SnowReport::ResponseError) do
      Albumart::SnowReport.parse(REPORTS, "<html>", fetched_at: 0.0)
    end
  end

  def test_parse_rejects_a_hash_of_reports
    assert_raises(Albumart::SnowReport::ResponseError) do
      Albumart::SnowReport.parse('{"base_depth":18,"unit_of_measurement":"in","updated":1}', TRAILS, fetched_at: 0.0)
    end
  end

  def test_parse_rejects_a_hash_of_trails
    assert_raises(Albumart::SnowReport::ResponseError) do
      Albumart::SnowReport.parse(REPORTS, '{"trails":[]}', fetched_at: 0.0)
    end
  end

  def test_parse_rejects_no_reports
    assert_raises(Albumart::SnowReport::ResponseError) { Albumart::SnowReport.parse("[]", TRAILS, fetched_at: 0.0) }
  end

  def test_parse_rejects_a_report_that_is_not_an_object
    assert_raises(Albumart::SnowReport::ResponseError) { Albumart::SnowReport.parse("[18]", TRAILS, fetched_at: 0.0) }
  end

  def test_parse_rejects_a_trail_that_is_not_an_object
    body = TRAILS.sub("[{", '["Rhapsody",{')

    assert_raises(Albumart::SnowReport::ResponseError) { Albumart::SnowReport.parse(REPORTS, body, fetched_at: 0.0) }
  end

  def test_parse_rejects_a_null_base_depth
    body = REPORTS.sub('"base_depth":18', '"base_depth":null')

    assert_raises(Albumart::SnowReport::ResponseError) { Albumart::SnowReport.parse(body, TRAILS, fetched_at: 0.0) }
  end

  def test_parse_rejects_a_depth_not_in_inches
    body = REPORTS.sub('"unit_of_measurement":"in"', '"unit_of_measurement":"cm"')

    assert_raises(Albumart::SnowReport::ResponseError) { Albumart::SnowReport.parse(body, TRAILS, fetched_at: 0.0) }
  end

  def test_parse_rejects_trails_with_no_eligible_alpine_trail
    body = JSON.generate([{ status: "open", season: "summer", type: "hiking_trail", include: true }])

    assert_raises(Albumart::SnowReport::ResponseError) { Albumart::SnowReport.parse(REPORTS, body, fetched_at: 0.0) }
  end

  def test_fetcher_has_nothing_before_the_first_fetch
    assert_nil fetcher.current
  end

  def test_fetcher_stores_a_reading_from_both_feeds
    requested = []
    snow = fetcher(http: ->(uri) { requested << uri.to_s; uri.path.end_with?("trails") ? TRAILS : REPORTS })

    assert snow.refresh
    assert_equal 18, snow.current.base_depth
    assert_equal 50, snow.current.percent_open
    assert_equal [Albumart::SNOW_REPORTS_URL, Albumart::SNOW_TRAILS_URL], requested
  end

  def test_fetcher_keeps_the_last_good_reading_when_a_fetch_fails
    responses = [REPORTS, TRAILS, nil]
    snow = fetcher(http: ->(_uri) { responses.shift || raise(Albumart::Weather::ResponseError, "HTTP 503") })
    snow.refresh

    assert_output("[snow] fetch failed: Albumart::Weather::ResponseError: HTTP 503\n") { refute snow.refresh }
    assert_equal 18, snow.current.base_depth
  end

  def test_fetcher_survives_an_unexpected_error
    snow = fetcher(http: ->(_uri) { nil.fetch(:body) })

    assert_output(/\A\[snow\] fetch failed: NoMethodError: /) { refute snow.refresh }
    assert_nil snow.current
  end

  def test_fetcher_treats_old_data_as_missing
    clock = FakeClock.new
    snow = fetcher(clock:)
    snow.refresh

    clock.advance(Albumart::SNOW_MAX_AGE_SECONDS)
    refute_nil snow.current
    clock.advance(1)
    assert_nil snow.current
  end

  def test_fetcher_hides_a_stale_report
    now = REPORTED_AT
    snow = fetcher(now: -> { now })
    snow.refresh

    now = REPORTED_AT + Albumart::SNOW_REPORT_STALE_SECONDS
    refute_nil snow.current
    now += 1
    assert_nil snow.current
  end

  def test_fetcher_treats_a_report_from_the_future_as_fresh
    snow = fetcher(now: -> { REPORTED_AT - (30 * 24 * 60 * 60) })
    snow.refresh

    refute_nil snow.current
  end

  def test_fetcher_records_successes_and_failures_in_stats
    clock = FakeClock.new
    stats = Albumart::Stats.new(clock:)
    responses = [REPORTS, TRAILS, "<html>", TRAILS]
    snow = fetcher(clock:, http: ->(_uri) { responses.shift }, stats:)
    snow.refresh
    clock.advance(60)

    assert_output("[snow] fetch failed: Albumart::SnowReport::ResponseError: response is not JSON\n") { snow.refresh }
    assert_equal 60.0, stats.snapshot.snow_age_seconds
    assert_equal 1, stats.snapshot.snow_fetch_errors_total
  end
end
