# frozen_string_literal: true

require "json"
require "uuidtools"

module OmniEvent
  module Strategies
    # The Developer strategy can be used for testing purposes.
    #
    # ## Usage
    #
    # All you need to do is add it in like any other strategy:
    #
    # @example Basic Usage
    #
    #   OmniEvent::Builder.new do
    #     provider :developer
    #   end
    #
    class Developer
      include OmniEvent::Strategy

      option :token, "12345"
      option :name, "developer"
      option :domain, "omnievent-gem.com"

      def self.raw_data
        fixture = File.join(File.expand_path("../../..", __dir__), "spec", "fixtures", "list_events.json")
        @raw_data ||= JSON.parse(File.open(fixture).read).to_h
      end

      def location_key_map
        {
          countryCode: "country",
          latitude: "latitude",
          longitude: "longitude",
          address1: "address",
          address2: "address",
          address3: "address",
          city: "city",
          postalCode: "postal_code"
        }
      end

      def map_location(raw_location)
        raw_location.each_with_object({}) do |(raw_key, raw_value), result|
          next unless location_key_map[raw_key.to_sym]

          key = location_key_map[raw_key.to_sym]
          value = result[key]
          if value && key == "address"
            value += " #{raw_value}"
          else
            value = raw_value
          end
          result[key] = value
        end
      end

      def build_event_hash(raw_event)
        event = OmniEvent::EventHash.new(
          provider: name,
          data: raw_event.slice(*OmniEvent::EventHash::DataHash.permitted_attributes),
          metadata: raw_event.slice(*OmniEvent::EventHash::MetadataHash.permitted_attributes),
          associated_data: {
            location: map_location(raw_event["location"]),
            virtual_location: raw_event["virtual_location"]
          }
        )

        %w[start_time end_time].each do |time_attr|
          OmniEvent::Utils.convert_time_to_iso8601(event.data, time_attr)
        end

        %w[created_at updated_at].each do |time_attr|
          OmniEvent::Utils.convert_time_to_iso8601(event.metadata, time_attr)
        end

        event.metadata.uid = OmniEvent::Utils.generate_uuid("#{options.domain}:#{raw_event["id"]}").to_s

        event
      end

      def list_events
        self.class.raw_data["events"].each_with_object([]) do |raw_event, result|
          if Time.parse(raw_event["start_time"]).utc > options[:from_time].utc
            event = build_event_hash(raw_event)
            result << event if event.valid?
          end
        end
      end
    end
  end
end
