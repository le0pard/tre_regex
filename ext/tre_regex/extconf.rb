require 'mkmf'
require 'rbconfig'
require 'open-uri'
require 'fileutils'

# 1. Download Configuration
github_repo = 'laurikari/tre'
branch = 'master'
tarball_url = "https://github.com/#{github_repo}/archive/refs/heads/#{branch}.tar.gz"
tarball_file = File.expand_path("./tre-#{branch}.tar.gz", __dir__)
tre_src_dir = File.expand_path("./tre-#{branch}", __dir__)
dest_lib_dir = File.expand_path("../../lib/tre_regex/bin", __dir__)

# 2. Automatically Download and Extract
unless Dir.exist?(tre_src_dir)
  puts "========== Downloading TRE from GitHub =========="
  URI.open(tarball_url) do |remote|
    File.open(tarball_file, 'wb') { |local| local.write(remote.read) }
  end
  puts "========== Extracting TRE Source =========="
  system("tar -xzf #{tarball_file} -C #{__dir__}")
end

# 3. Build TRE synchronously using Ruby
host_flag = enable_config("cross-build") ? "--host=#{RbConfig::CONFIG['host']} " : ""
is_windows = RbConfig::CONFIG['host_os'] =~ /mingw|mswin/
so_ext = RbConfig::CONFIG['SOEXT'] || RbConfig::CONFIG['DLEXT'] || (is_windows ? 'dll' : 'so')

puts "========== Building TRE =========="
Dir.chdir(tre_src_dir) do
  system("./utils/autogen.sh") || raise("autogen.sh failed")
  # Note: Changed to --disable-agrep to fix the unrecognized option warning
  system("./configure #{host_flag} --enable-shared --disable-static --disable-agrep") || raise("configure failed")
  system("make") || raise("make failed")
end

puts "========== Staging Shared Library for FFI =========="
FileUtils.mkdir_p(dest_lib_dir)

# Safely copy the compiled binaries
if is_windows
  libs = Dir.glob("#{tre_src_dir}/lib/.libs/*.dll")
  FileUtils.cp(libs, dest_lib_dir) if libs.any?
else
  libs = Dir.glob("#{tre_src_dir}/lib/.libs/libtre.#{so_ext}*")
  FileUtils.cp(libs, dest_lib_dir) if libs.any?
end

# Create a standard dummy ruby extension to satisfy rake-compiler completely
create_makefile('tre_regex')
