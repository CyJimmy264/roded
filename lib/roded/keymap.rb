require "yaml"

module Roded
  class Keymap
    DEFAULT = {
      "C-n" => { type: :move_down },
      "C-p" => { type: :move_up },
      "C-f" => { type: :move_right },
      "C-b" => { type: :move_left },
      "C-v" => { type: :page_down },
      "M-v" => { type: :page_up },
      "C-a" => { type: :line_start },
      "C-e" => { type: :line_end },
      "C-d" => { type: :delete },
      "C-k" => { type: :kill_line },
      "C-g" => { type: :cancel },
      "M-x" => { type: :start_command },
      "Enter" => { type: :enter },
      "Backspace" => { type: :backspace },
      "Delete" => { type: :delete },
      "C-x C-c" => { type: :quit },
      "C-x C-s" => { type: :save_buffer },
      "Down" => { type: :move_down },
      "Up" => { type: :move_up },
      "Left" => { type: :move_left },
      "Right" => { type: :move_right }
    }.freeze

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
  end
end
