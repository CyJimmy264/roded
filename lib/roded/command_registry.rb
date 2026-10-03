module Roded
  # Stores named actions shared by M-x, bindings, and the Ruby editor API.
  class CommandRegistry
    def initialize
      @commands = {}
    end

    def register(name, description: nil, &action)
      key = normalize_name(name)
      raise ArgumentError, "command name is required" if key.empty?
      raise ArgumentError, "command action is required" unless action

      description = description.to_s.dup.freeze if description
      @commands[key] = { description:, action: }.freeze
    end

    def registered?(name)
      @commands.key?(normalize_name(name))
    end

    def call(name, editor)
      command = @commands[normalize_name(name)]
      return unless command

      command.fetch(:action).call(editor)
    end

    def names
      @commands.keys.sort.map { |name| name.dup.freeze }.freeze
    end

    def catalog
      @commands.keys.sort.map do |name|
        { name: name.dup.freeze, description: @commands.fetch(name).fetch(:description) }.freeze
      end.freeze
    end

    private

    def normalize_name(name)
      name.to_s.strip
    end
  end
end
