# frozen_string_literal: true

require 'ffi'
require 'rbconfig'
require_relative 'tre_regex/version'

module TreRegex
  class Error < StandardError; end

  # The FFI Native Bridge
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
      File.expand_path("tre_regex/bin/#{filename}", __dir__),
      File.expand_path(filename, __dir__)
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

    # Memory layout for TRE match offsets
    class RegMatch < FFI::Struct
      layout :rm_so, :int,
             :rm_eo, :int
    end

    # Memory layout for TRE approximate matching parameters
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

    # Memory layout for TRE approximate match results
    class RegAMatch < FFI::Struct
      layout :nmatch,    :size_t,
             :pmatch,    :pointer,
             :cost,      :int,
             :num_ins,   :int,
             :num_del,   :int,
             :num_subst, :int
    end

    attach_function :tre_regcomp, %i[pointer string int], :int
    attach_function :tre_regfree, [:pointer], :void
    attach_function :tre_regaexec, [:pointer, :string, :pointer, RegAParams.by_value, :int], :int
    attach_function :tre_regaparams_default, [:pointer], :void
  end

  # User-Facing Ruby Class
  class Regex
    attr_reader :pattern

    def initialize(pattern, ignore_case: false)
      @pattern = pattern
      # Allocate a safe 256-byte buffer in C memory for the regex_t struc
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
      result = execute_match(text, options)
      return nil unless result

      result.delete(:byte_index)
      result.delete(:byte_end_index)
      result
    end

    def test?(text, options = {})
      !exec(text, options).nil?
    end

    def match_all(text, options = {})
      return enum_for(:match_all, text, options) unless block_given?

      byte_off = 0
      char_off = 0

      while byte_off <= text.bytesize
        substring = text.byteslice(byte_off..) || ''

        # Use the private execute_match so we get the byte cursors!
        break unless (result = execute_match(substring, options))

        adv_bytes, adv_chars = process_match!(result, char_off)
        yield result

        break if adv_bytes.zero? && byte_off == text.bytesize

        if adv_bytes.zero?
          adv_bytes = substring[0].bytesize
          adv_chars = 1
        end

        byte_off += adv_bytes
        char_off += adv_chars
      end
    end

    private

    def execute_match(text, options)
      params = build_params(options)
      pmatch = FFI::MemoryPointer.new(Native::RegMatch)
      match_data = prepare_match_data(pmatch)

      res = Native.tre_regaexec(@preg, text, match_data, params, 0)
      res.zero? ? parse_result(text, match_data, pmatch) : nil
    end

    def build_params(opts)
      params = Native::RegAParams.new
      Native.tre_regaparams_default(params.to_ptr)
      return params.tap { |p| p[:max_err] = 0 } if opts.empty?

      apply_limits(params, opts)
      apply_costs(params, opts)
      params
    end

    def apply_limits(params, opts)
      params[:max_err]   = opts[:max_errors] if opts.key?(:max_errors)
      params[:max_ins]   = opts.fetch(:max_insertions, opts.key?(:max_errors) ? params[:max_ins] : 0)
      params[:max_del]   = opts.fetch(:max_deletions, opts.key?(:max_errors) ? params[:max_del] : 0)
      params[:max_subst] = opts.fetch(:max_substitutions, opts.key?(:max_errors) ? params[:max_subst] : 0)
      params[:max_cost]  = opts[:max_cost] if opts.key?(:max_cost)

      # Bound max_err if not explicitly set
      return unless !opts.key?(:max_errors) && !opts.key?(:max_cost)

      params[:max_err] =
        params[:max_ins] + params[:max_del] + params[:max_subst]
    end

    def apply_costs(params, opts)
      params[:cost_ins]   = opts[:weight_insertion] if opts.key?(:weight_insertion)
      params[:cost_del]   = opts[:weight_deletion] if opts.key?(:weight_deletion)
      params[:cost_subst] = opts[:weight_substitution] if opts.key?(:weight_substitution)
    end

    def prepare_match_data(pmatch)
      Native::RegAMatch.new.tap do |m|
        m[:nmatch] = 1
        m[:pmatch] = pmatch
      end
    end

    def process_match!(result, char_offset)
      result.delete(:byte_index)
      adv_bytes = result.delete(:byte_end_index)
      adv_chars = result[:end_index]

      result[:index] += char_offset
      result[:end_index] += char_offset

      [adv_bytes, adv_chars]
    end

    def parse_result(text, match_data, pmatch)
      rm = Native::RegMatch.new(pmatch)
      byte_match = text.byteslice(rm[:rm_so]...rm[:rm_eo])
      char_start = text.byteslice(0...rm[:rm_so]).length

      {
        match: byte_match,
        index: char_start,
        end_index: char_start + byte_match.length,
        byte_index: rm[:rm_so],
        byte_end_index: rm[:rm_eo],
        cost: match_data[:cost],
        errors: parse_errors(match_data)
      }
    end

    def parse_errors(match_data)
      {
        insertions: match_data[:num_ins],
        deletions: match_data[:num_del],
        substitutions: match_data[:num_subst]
      }
    end
  end
end
