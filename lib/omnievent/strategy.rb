# frozen_string_literal: true

module OmniEvent
  # The Strategy is the base unit of OmniEvent's ability to handle
  # multiple event providers. It's substantially based on OmniAuth::Strategy.
  module Strategy
    class NotImplementedError < NotImplementedError; end
    class Options < OmniEvent::KeyStore; end

    def self.included(base)
      OmniEvent.strategies << base
      base.extend ClassMethods
      base.class_eval do
        option :uid_delimiter, "-"
        option :from_time
        option :to_time
        option :match_name
      end
    end

    # Class methods for Strategy
    module ClassMethods
      # Default options for all strategies which can be overriden at the class-level
      # for each strategy.
      def default_options
        @default_options ||= begin
          d_opts = OmniEvent::Strategy::Options.new
          d_opts.merge!(superclass.default_options) if superclass.respond_to?(:default_options)
          d_opts
        end
      end

      # This allows for more declarative subclassing of strategies by allowing
      # default options to be set using a simple configure call.
      #
      # @param options [Hash] If supplied, these will be the default options
      #    (deep-merged into the superclass's default options).
      # @yield [Options] The options Mash that allows you to set your defaults as you'd like.
      #
      # @example Using a yield to configure the default options.
      #
      #   class MyStrategy
      #     include OmniEvent::Strategy
      #
      #     configure do |c|
      #       c.foo = 'bar'
      #     end
      #   end
      #
      # @example Using a hash to configure the default options.
      #
      #   class MyStrategy
      #     include OmniEvent::Strategy
      #     configure foo: 'bar'
      #   end
      def configure(options = nil)
        if block_given?
          yield default_options
        else
          default_options.deep_merge!(options)
        end
      end

      # Directly declare a default option for your class. This is a useful from
      # a documentation perspective as it provides a simple line-by-line analysis
      # of the kinds of options your strategy provides by default.
      #
      # @param name [Symbol] The key of the default option in your configuration hash.
      # @param value [Object] The value your object defaults to. Nil if not provided.
      #
      # @example
      #
      #   class MyStrategy
      #     include OmniEvent::Strategy
      #
      #     option :foo, 'bar'
      #     option
      #   end
      def option(name, value = nil)
        default_options[name] = value
      end

      # Sets (and retrieves) option key names for initializer arguments to be
      # recorded as. This takes care of 90% of the use cases for overriding
      # the initializer in OmniEvent Strategies.
      def args(args = nil)
        if args
          @args = Array(args)
          return
        end
        existing = superclass.respond_to?(:args) ? superclass.args : []
        (instance_variable_defined?(:@args) && @args) || existing
      end
    end

    attr_reader :options

    # Initializes the strategy. An `options` hash is automatically
    # created from the last argument if it is a hash.
    #
    # @overload new(options = {})
    #   If nothing but a hash is supplied, initialized with the supplied options
    #   overriding the strategy's default options via a deep merge.
    # @overload new(*args, options = {})
    #   If the strategy has supplied custom arguments that it accepts, they may
    #   will be passed through and set to the appropriate values.
    #
    # @yield [Options] Yields options to block for further configuration.
    def initialize(*args, &block) # rubocop:disable Lint/UnusedMethodArgument
      @options = self.class.default_options.dup

      options.deep_merge!(args.pop) if args.last.is_a?(Hash)
      options[:name] ||= self.class.to_s.split("::").last.downcase

      self.class.args.each do |arg|
        break if args.empty?

        options[arg] = args.shift
      end

      # Make sure that all of the args have been dealt with, otherwise error out.

      yield options if block_given?

      validate_options
    end

    def validate_options
      if options[:from_time] && !options[:from_time].respond_to?(:strftime)
        raise ArgumentError, "from_time must be a valid ruby time object"
      end
      if options[:to_time] && !options[:to_time].respond_to?(:strftime)
        raise ArgumentError, "to_time must be a valid ruby time object"
      end
      raise ArgumentError, "match_name must be a string" if options[:match_name] && !options[:match_name].is_a?(String)
    end

    def request(method, opts)
      options.deep_merge!(opts)

      authorize
      return unless authorized?

      send(method)
    end

    def authorize; end

    def authorized?
      raise NotImplementedError
    end

    def raw_events
      raise NotImplementedError
    end

    def event_hash
      raise NotImplementedError
    end

    def list_events
      raw_events.each_with_object([]) do |raw_event, result|
        event = event_hash(raw_event)

        next unless event&.valid?
        next if options.from_time && Time.parse(event.data.start_time).utc < options.from_time.utc
        next if options.to_time && Time.parse(event.data.start_time).utc > options.to_time.utc
        next if options.match_name && !event.data.name.downcase.include?(options.match_name.downcase)

        result << event
      end
    end

    def create_event
      raise NotImplementedError
    end

    def update_event
      raise NotImplementedError
    end

    def destroy_event
      raise NotImplementedError
    end

    # Direct access to the OmniEvent logger, automatically prefixed
    # with this strategy's name.
    #
    # @example
    #   log :warn, 'This is a warning.'
    def log(level, message)
      OmniEvent.logger.send(level, "(#{name}) #{message}")
    end

    def name
      options[:name]
    end

    def format_time(time)
      return nil if time.nil? || !time.respond_to?(:to_s)

      OmniEvent::Utils.convert_time_to_iso8601(time.to_s)
    end
  end
end
