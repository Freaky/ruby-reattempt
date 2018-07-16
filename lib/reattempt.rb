# frozen_string_literal: true

require 'reattempt/version'

require 'dry-initializer'
require 'dry-types'

module Reattempt
  # Exception raised by +Retry.each+, with the error from the loop available
  # in +RetriesExceeded#cause+.
  RetriesExceeded = Class.new(StandardError)

  # Calculate exponential backoff times between +min_delay+ and +max_delay+,
  # with +jitter+ of between 0 and 1 and +factor+ of, by default, 2.
  #
  # Minimum delay is min_delay * jitter / 2, maximum is max_delay * jitter / 2.
  #
  # Instances are +Enumerable+.
  #
  # Example:
  #
  # ```ruby
  # # Start delay 0.075-0.125 seconds, doubling to a limit of 0.75-1.25
  # bo = Reattempt::Backoff.new(min_delay: 0.1, max_delay: 1.0, jitter: 0.5)
  # bo.take(4).map { |x| x.round(4) } # => [0.1151, 0.1853, 0.4972, 0.9316]
  # ```
  class Backoff
    include Enumerable
    extend Dry::Initializer[undefined: false]

    option :min_delay,
           default: -> { 0.02 },
           type: Dry::Types['coercible.float'].constrained(gteq: 0)

    option :max_delay,
           default: -> { 1.0 },
           type: Dry::Types['coercible.float'].constrained(gteq: 0)

    option :jitter,
           default: -> { 0.2 },
           type: Dry::Types['coercible.float'].constrained(lt: 1, gteq: 0)

    option :factor,
           default: -> { 2 },
           type: Dry::Types['coercible.float'].constrained(gt: 0)

    # Iterate over calls to +delay_for_attempt+ with a counter.  If no block
    # given, return an +Enumerator+.
    def each
      return enum_for(:each) unless block_given?

      0.upto(Float::INFINITY) do |try|
        yield delay_for_attempt(try)
      end
    end

    # Calculate a randomised delay for attempt number +try+, starting from 0.
    #
    # Aliased to +[]+
    def delay_for_attempt(try)
      delay = (min_delay * (factor ** try)).clamp(min_delay, max_delay)
      delay * Random.rand(jitter_range)
    end

    alias [] delay_for_attempt

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
  # try = Reattempt::Retry.new(tries: 5, rescue: TempError, backoff: bo)
  # begin
  #   try.each do |attempt|
  #     raise TempError, "Failed in attempt #{attempt}"
  #   end
  # rescue Reattempt::RetriesExceeded => e
  #   p e.cause # => #<TempError: "Failed in attempt 5">
  # end
  # ```
  class Retry
    include Enumerable
    extend Dry::Initializer[undefined: false]

    option :tries,
           default: -> { 5 },
           type: Dry::Types['strict.integer'].constrained(gteq: 0)

    option :rescue,
           default: -> { StandardError },
           type: Dry::Types['coercible.array'].constrained(min_size: 1)
                           .of(Dry::Types::Any.constrained(attr: :===))

    option :backoff,
           default: -> { Backoff.new },
           type: Dry::Types::Definition.new(Backoff).constrained(type: Backoff)

    option :sleep_proc,
           default: -> { method(:sleep) },
           type: Dry::Types::Any.constrained(attr: :call)

    option :rescue_proc,
           default: -> { ->(_ex) {} },
           type: Dry::Types::Any.constrained(attr: :call)

    # Yield the block with the current attempt number, starting from 1.
    #
    # If any of the configured +rescue+ exceptions are raised (as matched by
    # +===+), call +rescue_proc+ with the exception, call +sleep_proc+ with the
    # delay as configured by +backoff+, and try again up to +retries+ times.
    #
    # +rescue_proc+ defaults to a no-op.
    #
    # +sleep_proc+ defaults to +Kernel#sleep+.
    #
    # Raise +RetriesExceeded+ when the count is exceeded, setting +cause+ to
    # the previous exception.
    def each
      return enum_for(:each) unless block_given?

      ex = nil

      backoff.lazy.take(tries).each_with_index do |delay, try|
        return yield(try + 1)
      rescue Exception => ex
        raise unless self.rescue.any? { |r| r === ex }
        rescue_proc.call ex
        sleep_proc.call delay
      end

      raise RetriesExceeded, cause: ex
    end
  end
end
