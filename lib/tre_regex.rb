# frozen_string_literal: true

require 'ffi'
require 'rbconfig'
require_relative 'tre_regex/version'

module TreRegex
  class Error < StandardError; end

  # FFI Native Bridge
  module Native
    extend FFI::Library

    # Determine OS and expected filename
    host_os = RbConfig::CONFIG['host_os']
    filename = case host_os
               when /linux/ then 'libtre.so'
               when /darwin/ then 'libtre.dylib'
               when /mingw|mswin/ then 'tre.dll'
               else raise "Unsupported OS: #{host_os}"
               end

    # Search for the compiled binary (checks both your extconf.rb path and standard path)
    search_paths = [
      File.expand_path("tre_regex/bin/#{filename}", __dir__), # The precompiled path
      File.expand_path(filename, __dir__)                     # The fallback path
    ]

    lib_path = search_paths.find { |p| File.exist?(p) }

    unless lib_path
      raise LoadError, "Could not find #{filename} in #{search_paths.first}. Did you compile the C extension?"
    end

    ffi_lib lib_path

    # TRE Regex Configuration Flags
    REG_EXTENDED = 1
    REG_ICASE    = 2
    REG_NEWLINE  = 4
    REG_NOSUB    = 8

    # C-Struct Memory Layouts
    class RegMatch < FFI::Struct
      layout :rm_so, :int,
             :rm_eo, :int
    end

    class RegAParams < FFI::Struct
      layout :cost_ins,   :int,
             :cost_del,   :int,
             :cost_subst, :int,
             :max_cost,   :int,
             :max_ins,    :int,
             :max_del,    :int,
             :max_subst,  :int,
             :max_err,    :int
    end

    class RegAMatch < FFI::Struct
      layout :nmatch,    :size_t,
             :pmatch,    :pointer,
             :cost,      :int,
             :num_ins,   :int,
             :num_del,   :int,
             :num_subst, :int
    end

    # Bind the C Functions
    attach_function :tre_regcomp, %i[pointer string int], :int
    attach_function :tre_regfree, [:pointer], :void
    attach_function :tre_reganexec, [:pointer, :string, :pointer, RegAParams.by_value, :int], :int
    attach_function :tre_regaparams_default, [:pointer], :void
  end

  # The User-Facing Ruby Class
  class Regex
    attr_reader :pattern

    def initialize(pattern, ignore_case: false)
      @pattern = pattern

      # Allocate a safe 256-byte buffer in C memory for the regex_t struct
      @preg = FFI::MemoryPointer.new(:char, 256)

      flags = Native::REG_EXTENDED
      flags |= Native::REG_ICASE if ignore_case

      res = Native.tre_regcomp(@preg, pattern, flags)
      raise TreRegex::Error, "Failed to compile regex pattern: #{pattern}" if res != 0

      # Garbage Collection Hook: Tell Ruby to free the C memory when this object is destroyed
      ObjectSpace.define_finalizer(self, self.class.finalize(@preg))
    end

    # The GC finalizer proc
    def self.finalize(preg_ptr)
      proc do
        Native.tre_regfree(preg_ptr)
        preg_ptr.free
      end
    end

    def exec(text, options = {})
      # Initialize TRE's default parameters
      params = Native::RegAParams.new
      Native.tre_regaparams_default(params.to_ptr)

      # Apply granular fuzzy options
      params[:max_err]   = options[:max_errors] if options.key?(:max_errors)
      params[:max_ins]   = options[:max_insertions] if options.key?(:max_insertions)
      params[:max_del]   = options[:max_deletions] if options.key?(:max_deletions)
      params[:max_subst] = options[:max_substitutions] if options.key?(:max_substitutions)
      params[:max_cost]  = options[:max_cost] if options.key?(:max_cost)
      params[:cost_ins]  = options[:weight_insertion] if options.key?(:weight_insertion)
      params[:cost_del]  = options[:weight_deletion] if options.key?(:weight_deletion)
      params[:cost_subst] = options[:weight_substitution] if options.key?(:weight_substitution)

      # Allocate memory to receive the match data
      pmatch = FFI::MemoryPointer.new(Native::RegMatch)
      match_data = Native::RegAMatch.new
      match_data[:nmatch] = 1
      match_data[:pmatch] = pmatch

      # Execute the search
      res = Native.tre_reganexec(@preg, text, match_data, params, 0)

      # Return nil if no match
      return nil unless res.zero?

      # Extract byte offsets from C
      rm = Native::RegMatch.new(pmatch)
      byte_start = rm[:rm_so]
      byte_end = rm[:rm_eo]

      # Unicode Safety: Convert C byte-offsets back to Ruby character indices
      byte_match = text.byteslice(byte_start...byte_end)
      char_index = text.byteslice(0...byte_start).length

      {
        match: byte_match,
        index: char_index,
        end_index: char_index + byte_match.length,
        cost: match_data[:cost],
        errors: {
          insertions: match_data[:num_ins],
          deletions: match_data[:num_del],
          substitutions: match_data[:num_subst]
        }
      }
    end

    def test?(text, options = {})
      !exec(text, options).nil?
    end

    def match_all(text, options = {})
      return enum_for(:match_all, text, options) unless block_given?

      current_char_offset = 0
      search_text = text

      while current_char_offset < text.length
        result = exec(search_text, options)
        break unless result

        # Adjust indices relative to the original full string
        result[:index] += current_char_offset
        result[:end_index] += current_char_offset

        yield result

        # Advance the search text past the last match to prevent infinite loops
        match_length = result[:end_index] - result[:index]
        advance_by = match_length.zero? ? 1 : match_length
        current_char_offset += advance_by
        search_text = text[current_char_offset..] || ''
      end
    end
  end
end
