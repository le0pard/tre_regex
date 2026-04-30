# frozen_string_literal: true

require 'mkmf'
require 'rbconfig'
require 'open-uri'
require 'net/http'
require 'fileutils'

is_windows = RbConfig::CONFIG['host_os'] =~ /mingw|mswin/
is_darwin  = RbConfig::CONFIG['host_os'].include?('darwin')

root_dir = File.expand_path(__dir__)
root_dir = File.dirname(root_dir) until Dir.exist?(File.join(root_dir, 'lib')) || root_dir == '/'

# Download Configuration
github_repo = 'laurikari/tre'
version = '5ac28057f648debda76f9bf4d39dfdfa85b0df18'
tarball_url = "https://github.com/#{github_repo}/archive/#{version}.tar.gz"
tarball_file = File.expand_path("./tre-#{version}.tar.gz", __dir__)
tre_src_dir = File.expand_path("./tre-#{version}", __dir__)
dest_lib_dir = File.join(root_dir, 'lib', 'tre_regex', 'bin')

def download_file(url, limit = 10)
  raise 'Too many redirects' if limit.zero?

  uri = URI(url)
  response = Net::HTTP.get_response(uri)

  case response
  when Net::HTTPSuccess
    response.body
  when Net::HTTPRedirection
    location = response['location']
    puts "Following redirect to #{location}..."
    download_file(location, limit - 1)
  else
    raise "Download failed: #{response.code} #{response.message}"
  end
end

# Automatically Download and Extract
unless Dir.exist?(tre_src_dir)
  puts '========== Downloading TRE from GitHub =========='
  begin
    content = download_file(tarball_url)
    File.binwrite(tarball_file, content)
  rescue StandardError => e
    abort "Error: #{e.message}"
  end

  puts '========== Extracting TRE Source =========='
  # Ensure we use -z for gzip
  system("tar -xzf #{tarball_file} -C #{__dir__}") || abort('Extraction failed')
end

# Build TRE synchronously using Ruby
host_flag = enable_config('cross-build') ? "--host=#{RbConfig::CONFIG['host']} " : ''
RbConfig::CONFIG['SOEXT'] || RbConfig::CONFIG['DLEXT'] || (is_windows ? 'dll' : 'so')

puts '========== Building TRE =========='
Dir.chdir(tre_src_dir) do
  system('./utils/autogen.sh') || raise('autogen.sh failed') unless File.exist?('configure')

  system("./configure #{host_flag} --enable-shared --disable-static --disable-agrep") || raise('configure failed')
  system('make') || raise('make failed')
end

puts '========== Staging Shared Library for FFI =========='
FileUtils.mkdir_p(dest_lib_dir)

# Grab the compiled library and rename it to a strict, predictable filename
if is_windows
  src_lib = Dir.glob("#{tre_src_dir}/lib/.libs/*.dll").first
  FileUtils.cp(src_lib, File.join(dest_lib_dir, 'tre.dll')) if src_lib
elsif is_darwin
  src_lib = Dir.glob("#{tre_src_dir}/lib/.libs/*.dylib").first
  FileUtils.cp(src_lib, File.join(dest_lib_dir, 'libtre.dylib')) if src_lib
else
  src_lib = Dir.glob("#{tre_src_dir}/lib/.libs/libtre.so*").find { |f| File.file?(f) && !File.symlink?(f) }
  src_lib ||= Dir.glob("#{tre_src_dir}/lib/.libs/*.so").first # Fallback

  FileUtils.cp(src_lib, File.join(dest_lib_dir, 'libtre.so')) if src_lib
end

# Create a standard dummy ruby extension to satisfy rake-compiler completely
create_makefile('tre_regex')
