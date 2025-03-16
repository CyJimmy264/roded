# frozen_string_literal: true

require_relative "roded/version"
require_relative "roded/editor"
require_relative "roded/buffer"
require_relative "roded/mini_buffer"
require_relative "roded/window"
require_relative "roded/status_bar"
require_relative "roded/curses_app"

module Roded
  class Error < StandardError; end
end
