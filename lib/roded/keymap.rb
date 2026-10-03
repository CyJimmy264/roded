require "yaml"
require_relative "default_key_bindings"

module Roded
  # Normalizes keyboard chords and exposes the active bindings for help.
  class Keymap
    DEFAULT = DefaultKeyBindings::BINDINGS

    def self.default_path
      File.join(Dir.home, ".config", "roded", "keymap.yml")
    end

    def self.load(path = default_path)
      map = DEFAULT.dup
      if File.exist?(path)
        yaml = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
        map.merge!(symbolize_entries(yaml)) if yaml.is_a?(Hash)
      end
      new(map)
    rescue Psych::SyntaxError
      new(DEFAULT)
    end

    def self.symbolize_entries(raw)
      raw.each_with_object({}) do |(key, value), acc|
        next unless value.is_a?(Hash)

        type = value["type"] || value[:type]
        payload = value["payload"] || value[:payload]
        next unless type

        acc[key.to_s] = { type: type.to_sym, payload: payload || {} }
      end
    end

    def initialize(map)
      @map = map
    end

    def resolve(key)
      entry = @map[key]
      return unless entry

      { type: entry[:type], payload: entry[:payload] || {} }
    end

    def bindings
      @map.keys.sort.map do |key|
        entry = @map.fetch(key)
        {
          key: key.to_s.dup.freeze,
          type: entry.fetch(:type).to_s.freeze,
          payload: entry.fetch(:payload, {}).inspect.freeze
        }.freeze
      end.freeze
    end

    def bind(key, type:, payload: {})
      name = key.to_s.strip
      raise ArgumentError, "binding key is required" if name.empty?

      @map[name] = { type: type.to_sym, payload: payload.dup.freeze }.freeze
    end

    def prefix?(key)
      prefix = "#{key} "
      @map.keys.any? { |binding| binding.start_with?(prefix) }
    end
  end
end
