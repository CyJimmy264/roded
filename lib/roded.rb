require_relative "roded/version"
require_relative "roded/application"
require_relative "roded/event"
require_relative "roded/command"
require_relative "roded/buffer"
require_relative "roded/mini_buffer"
require_relative "roded/window"
require_relative "roded/status_bar"
require_relative "roded/frontends/curses"

require "concurrent"
require "concurrent-edge"

module Roded
  class Error < StandardError; end
end
