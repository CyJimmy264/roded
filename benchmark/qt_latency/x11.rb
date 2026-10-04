require "ffi"

module Roded
  module Benchmarking
    # Separate-process X11 input and frame observation, used only under private Xvfb.
    module LatencyX11
      extend FFI::Library

      ffi_lib "libX11.so.6", "libXtst.so.6"
      attach_function :XOpenDisplay, [:string], :pointer
      attach_function :XCloseDisplay, [:pointer], :int
      attach_function :XDefaultRootWindow, [:pointer], :ulong
      attach_function :XStringToKeysym, [:string], :ulong
      attach_function :XKeysymToKeycode, %i[pointer ulong], :uint
      attach_function :XTestFakeKeyEvent, %i[pointer uint int ulong], :int
      attach_function :XFlush, [:pointer], :int
      attach_function :XGetImage, %i[pointer ulong int int uint uint ulong int], :pointer
      attach_function :XGetPixel, %i[pointer int int], :ulong
      attach_function :XDestroyImage, [:pointer], :int
    end
  end
end
