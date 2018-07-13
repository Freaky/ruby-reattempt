# frozen_string_literal: true

require 'reattempt/version'

require 'dry-initializer'
require 'dry-types'

module Reattempt
  RetriesExceeded = Class.new(StandardError)

  # Calculate exponential backup times, between min_delay and max_delay,
  # with jitter of between 0 and 1.
  #
  # Minimum delay is min_delay * jitter / 2, maximum is max_delay * jitter / 2.
  #
  # Instances are +Enumerable+.
  #
  # Example:
  #
  # ```ruby
  # # Start delay 0.05-0.15 seconds, increasing to 0.5-2.0
  # bo = Reattempt::Backoff.new(min_delay: 0.1, max_delay: 1.0, jitter: 0.5)
  # bo.take(4).map { |x| x.round(4) } # => [0.1151, 0.1853, 0.4972, 0.9316]
  # ```
  class Backoff
    include Enumerable
    extend Dry::Initializer

    option :min_delay,
           default: -> { 0.02 },
           type: Dry::Types['strict.float'].constrained(gteq: 0)

    option :max_delay,
           default: -> { 1.0 },
           type: Dry::Types['strict.float'].constrained(gteq: 0)

    option :jitter,
           default: -> { 0.2 },
           type: Dry::Types['strict.float'].constrained(lt: 1, gteq: 0)

    # Iterate over calls to +delay_for_attempt+ with a counter.  If no block
    # given, return an +Enumerator+.
    def each
      return enum_for(:each) unless block_given?

      0.upto(Float::INFINITY) do |try|
        yield delay_for_attempt(try)
      end
    end

    # Calculate a randomised delay for attempt number +try+, starting from 0.
    def delay_for_attempt(try)
      delay = (min_delay * (1 << try)).clamp(min_delay, max_delay)
      delay * Random.rand(jitter_range)
    end

    private

    def jitter_range
      @jitter_range ||= Range.new(1 - (jitter / 2), 1 + jitter / 2)
    end
  end

  # Retry the loop iterator if configured caught exceptions are raised and retry
  # count is not exceeded, sleeping as per a given backoff configuration.
  #
  # Example:
  # ```ruby
  # bo = Reattempt::Backoff.new(min_delay: 0.1, max_delay: 1.0, jitter: 0.5)
  # try = Reattempt::Retry.new(retries: 5, catch: TempError, backoff: bo)
  # begin
  #   try.each do |attempt|
  #     raise TempError, "Failed in attempt #{attempt}"
  #   end
  # rescue RetriesExceeded => e
  #   p e.cause # => #<TempError: "Failed in attempt 5">
  # end
  # ```
  class Retry
    include Enumerable
    extend Dry::Initializer

    option :retries,
           default: -> { 5 },
           type: Dry::Types['strict.integer'].constrained(gt: 0)

    option :catch,
           default: -> { StandardError },
           type: Dry::Types['coercible.array'].constrained(min_size: 1)

    option :backoff,
           default: -> { Backoff.new },
           type: Dry::Types::Definition.new(Backoff).constrained(type: Backoff)

    # Yield the block with the current attempt number, starting from 1.
    #
    # If any of the configured +catch+ exceptions are raised, sleep for the
    # delay as configured by +backoff+ and try again up to +retries+.
    #
    # Raise +RetriesExceeded+ when the count is exceeded, setting +cause+ to
    # the previous exception.
    def each
      return enum_for(:each) unless block_given?

      last_exception = nil

      # rubocop:disable Lint/RescueException, Style/CaseEquality
      backoff.lazy.take(retries).each_with_index do |delay, try|
        return yield(try + 1)
      rescue Exception => e
        raise unless catch.find { |ex| ex === e }
        last_exception = e
        sleep delay
      end
      # rubocop:enable Lint/RescueException, Style/CaseEquality

      raise RetriesExceeded, cause: last_exception
    end
  end
end
