# frozen_string_literal: true

require 'mkmf'
require 'rbconfig'
require 'open-uri'
require 'net/http'
require 'fileutils'
require 'digest'

is_windows = RbConfig::CONFIG['host_os'] =~ /mingw|mswin/
is_darwin  = RbConfig::CONFIG['host_os'].include?('darwin')

build_env = {
  'CC' => RbConfig::CONFIG['CC'],
  'CFLAGS' => RbConfig::CONFIG['CFLAGS'],
  'CPPFLAGS' => RbConfig::CONFIG['CPPFLAGS'],
  'LDFLAGS' => RbConfig::CONFIG['LDFLAGS']
}

# Embed standard C libraries directly into the DLL on Windows so it doesn't crash on bare machines
if is_windows
  # append static flags directly to CC! Libtool doesn't strip flags from the CC variable.
  build_env['CC'] = "#{build_env['CC']} -static-libgcc -static-libstdc++"

  # force MinGW to statically link the hidden winpthread dependency
  build_env['LDFLAGS'] = "#{build_env['LDFLAGS']} -Wl,-Bstatic -lpthread -Wl,-Bdynamic"
end

gnu_host = RbConfig::CONFIG['host_alias']
gnu_host = RbConfig::CONFIG['host'] if gnu_host.nil? || gnu_host.empty?

# Convert 'arm64' to 'aarch64' (Apple Silicon) and 'x64' to 'x86_64' (Windows)
gnu_host = gnu_host.sub('arm64', 'aarch64').sub(/^x64/, 'x86_64')

# Pass the translated, safe name to configure
host_flag = "--host=#{gnu_host}"

root_dir = File.expand_path(__dir__)
root_dir = File.dirname(root_dir) until Dir.exist?(File.join(root_dir, 'lib')) || root_dir == '/'

# Download Configuration
github_repo = 'laurikari/tre'
version = '5ac28057f648debda76f9bf4d39dfdfa85b0df18'
tarball_url = "https://github.com/#{github_repo}/archive/#{version}.tar.gz"
expected_tarball_sha256 = '528a8f8a4672cd3a0e5354629323a17d0cfa98b3792a57d764b64db30e2d5e9a'
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

    actual_sha256 = Digest::SHA256.hexdigest(content)

    if actual_sha256 != expected_tarball_sha256
      abort [
        'SECURITY ERROR:',
        'Checksum mismatch for TRE source!',
        "Expected: #{expected_tarball_sha256}",
        "Actual:   #{actual_sha256}"
      ].join("\n")
    end

    File.binwrite(tarball_file, content)
  rescue StandardError => e
    abort "Error: #{e.message}"
  end

  puts '========== Extracting TRE Source =========='
  # Ensure we use -z for gzip
  system('tar', '-xzf', tarball_file, '-C', __dir__) || abort('Extraction failed')
end

# Build TRE synchronously using Ruby

puts '========== Building TRE =========='
Dir.chdir(tre_src_dir) do
  system(build_env, './utils/autogen.sh') || raise('autogen.sh failed') unless File.exist?('configure')

  system(build_env, './configure', host_flag, '--enable-shared', '--disable-static', '--disable-agrep') ||
    raise('configure failed')
  system(build_env, 'make') || raise('make failed')
end

puts '========== Staging Shared Library for FFI =========='
FileUtils.mkdir_p(dest_lib_dir)

# Find the shared library, ignoring static archives
src_lib = Dir.glob("#{tre_src_dir}/lib/.libs/*").find do |f|
  (f.include?('.so') || f.include?('.dylib') || f.end_with?('.dll')) && !f.end_with?('.a')
end

if src_lib
  # Determine the clean target filename based on the OS
  dest_name = if is_windows
                'tre.dll'
              elsif is_darwin
                'libtre.dylib'
              else
                'libtre.so'
              end

  # Use File.realpath to guarantee we are copying raw bytes
  FileUtils.cp(File.realpath(src_lib), File.join(dest_lib_dir, dest_name))
end

# Create a standard dummy ruby extension to satisfy rake-compiler completely
create_makefile('tre_regex')
