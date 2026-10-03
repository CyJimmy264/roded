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
        raise ArgumentError, "keymap must be a mapping" unless yaml.is_a?(Hash)

        map.merge!(symbolize_entries(yaml))
      end
      new(map)
    rescue Psych::Exception, ArgumentError, IOError, SystemCallError => e
      new(DEFAULT, load_warning: "Ignoring keymap #{path}: #{e.message}")
    end

    def self.symbolize_entries(raw)
      known_types = DEFAULT.values.map { |entry| entry[:type] }.uniq + [:custom_command]
      errors = raw.filter_map do |key, value|
        problem = invalid_entry(key, value, known_types)
        "#{key.inspect}: #{problem}" if problem
      end
      raise ArgumentError, errors.join("; ") unless errors.empty?

      raw.transform_values { |value| symbolize_entry(value) }
    end

    def self.invalid_entry(key, value, known_types)
      return "key sequence must use single spaces between chords" unless valid_binding_key?(key)
      return "entry must be a mapping" unless value.is_a?(Hash)
      return binding_type_error(value, known_types) if binding_type_error(value, known_types)
      return "payload must be a mapping" unless valid_payload?(value)

      nil
    end

    def self.valid_binding_key?(key)
      key.is_a?(String) && key.match?(/\A\S+(?: \S+)*\z/)
    end

    def self.binding_type_error(value, known_types)
      type = config_value(value, "type")
      return "type must be a string" unless type.is_a?(String)

      "unknown command type #{type.inspect}" unless known_types.include?(type.to_sym)
    end

    def self.valid_payload?(value)
      payload = config_value(value, "payload")
      payload.nil? || payload.is_a?(Hash)
    end

    def self.symbolize_entry(value)
      type = config_value(value, "type")
      payload = config_value(value, "payload")
      { type: type.to_sym, payload: payload || {} }
    end

    def self.config_value(value, key)
      value.key?(key) ? value[key] : value[key.to_sym]
    end

    def initialize(map, load_warning: nil)
      @map = map
      @load_warning = load_warning
    end

    attr_reader :load_warning

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
