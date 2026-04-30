# frozen_string_literal: true

require 'mkmf'
require 'rbconfig'
require 'open-uri'
require 'net/http'
require 'fileutils'

# Download Configuration
github_repo = 'laurikari/tre'
branch = 'master'
tarball_url = "https://github.com/#{github_repo}/archive/refs/heads/#{branch}.tar.gz"
tarball_file = File.expand_path("./tre-#{branch}.tar.gz", __dir__)
tre_src_dir = File.expand_path("./tre-#{branch}", __dir__)
dest_lib_dir = File.expand_path('../../lib/tre_regex/bin', __dir__)

# Automatically Download and Extract
unless Dir.exist?(tre_src_dir)
  puts '========== Downloading TRE from GitHub =========='
  uri = URI(tarball_url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    request = Net::HTTP::Get.new(uri)
    http.request(request) do |response|
      File.binwrite(tarball_file, response.body)
    end
  end
  puts '========== Extracting TRE Source =========='
  system("tar -xzf #{tarball_file} -C #{__dir__}")
end

# Build TRE synchronously using Ruby
host_flag = enable_config('cross-build') ? "--host=#{RbConfig::CONFIG['host']} " : ''
is_windows = RbConfig::CONFIG['host_os'] =~ /mingw|mswin/
so_ext = RbConfig::CONFIG['SOEXT'] || RbConfig::CONFIG['DLEXT'] || (is_windows ? 'dll' : 'so')

puts '========== Building TRE =========='
Dir.chdir(tre_src_dir) do
  system('./utils/autogen.sh') || raise('autogen.sh failed')
  system("./configure #{host_flag} --enable-shared --disable-static --disable-agrep") || raise('configure failed')
  system('make') || raise('make failed')
end

puts '========== Staging Shared Library for FFI =========='
FileUtils.mkdir_p(dest_lib_dir)

# Safely copy the compiled binaries
libs = if is_windows
         Dir.glob("#{tre_src_dir}/lib/.libs/*.dll")
       else
         Dir.glob("#{tre_src_dir}/lib/.libs/libtre.#{so_ext}*")
       end
FileUtils.cp(libs, dest_lib_dir) if libs.any?

# Create a standard dummy ruby extension to satisfy rake-compiler completely
create_makefile('tre_regex')
