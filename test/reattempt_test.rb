require "test_helper"

class ReattemptTest < Minitest::Test
  include Reattempt

  def test_that_it_has_a_version_number
    refute_nil ::Reattempt::VERSION
  end

  def test_backoff_defaults
    bo = Backoff.new
    delays = bo.take(100).to_a
    assert_operator delays.min, :>=, bo.min_delay - bo.jitter
    assert_operator delays.max, :<=, bo.max_delay + bo.jitter
    assert_equal delays.first, delays.min
  end

  def test_backoff_zero_jitter
    bo = Backoff.new(jitter: 0)
    delays = bo.take(100).to_a
    assert_equal delays.min, bo.min_delay
    assert_equal delays.max, bo.max_delay
    assert_equal delays.dup.sort, delays
  end

  SomeError = Class.new(StandardError)
  OtherError = Class.new(SomeError)
  BrokenError = Class.new(StandardError)
  def test_retry
    slept = 0
    except = 0

    rt = Retry.new(tries: 2,
                   sleep_proc: ->(delay) { slept += 1;assert_kind_of(Float, delay) },
                   rescue_proc: ->(ex) { except += 1;assert_kind_of(Exception, ex) })
    assert_raises(RetriesExceeded) do
      rt.each { raise "uh oh" }
    end

    assert_equal slept, 2
    assert_equal except, 2

    rt = Retry.new(tries: 1, rescue: SomeError)
    assert_raises(RetriesExceeded) do
      rt.each { raise SomeError }
    end

    assert_raises(RetriesExceeded) do
      rt.each { raise OtherError }
    end

    assert_raises(BrokenError) do
      rt.each { raise BrokenError }
    end

    assert_raises(RetriesExceeded) do
      Retry.new(tries: 0).each { assert false }
    end

    begin
      Retry.new(tries: 1).each { raise SomeError }
    rescue RetriesExceeded => e
      assert_kind_of(SomeError, e.cause)
    end
  end
end
