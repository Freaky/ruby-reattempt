# Reattempt

Yet another Ruby gem to implement retries with backoff and jitter.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'reattempt'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install reattempt

## Synopsis

Simplest use with the defaults - 5 attempts, 0.02 to 1 second delay, 0.2 jitter
(delay is randomised ±10%), catching `StandardError`:

```ruby
begin
  Reattempt::Retry.new.each do
    poke_remote_api
  end
rescue Reattempt::RetriesExceeded => e
  handle_repeated_failure(e.cause)
end
```

## Usage

Reattempt consists of two main classes:

### Backoff

`Backoff` implements a simple jittered exponential backoff calculator as an
`Enumerable`:

```ruby
# Start delay 0.075-0.125 seconds, increasing to 0.75-1.25 seconds
bo = Reattempt::Backoff.new(min_delay: 0.1, max_delay: 1.0, jitter: 0.5)

bo.take(4).map { |x| x.round(4) } # => [0.1138, 0.2029, 0.4227, 0.646]
bo.take(2).each { |delay| sleep delay }
bo.delay_for_attempt(4) # => 1.0403524624141058
bo[4] # => 0.8328055668923606

bo.each do |delay|
  printf("Sleeping for about %.2f seconds\n", delay)
  sleep delay
end
```

The iterator is unbounded - the above script will get stuck in the final loop,
which might be useful if you *really* want whatever you're doing in it to
succeed, eventually.

### Retry

`Retry` implements a retrying iterator, catching the given `Exception` types and
sleeping as per a configured `Backoff` instance.

```ruby
bo = Reattempt::Backoff.new(min_delay: 0.1, max_delay: 1.0, jitter: 0.5)
try = Reattempt::Retry.new(tries: 5, rescue: TempError, backoff: bo)
begin
  try.each do |attempt|
    raise TempError, "Failed in attempt #{attempt}"
  end
rescue Reattempt::RetriesExceeded => e
  p e.cause # => #<TempError: "Failed in attempt 5">
end
```

It's intended for you to configure these once in your application for each class
of retry/backoff and share the instances.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Freaky/ruby-reattempt.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
