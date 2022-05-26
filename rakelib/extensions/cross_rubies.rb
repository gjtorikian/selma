# frozen_string_literal: true

WINDOWS_PLATFORM_REGEX = /mingw|mswin/
MINGWUCRT_PLATFORM_REGEX = /mingw-ucrt/
MINGW32_PLATFORM_REGEX = /mingw32/
LINUX_PLATFORM_REGEX = /linux/
X86_LINUX_PLATFORM_REGEX = /x86.*linux/
ARM_LINUX_PLATFORM_REGEX = /aarch.*linux/
DARWIN_PLATFORM_REGEX = /darwin/

CrossRuby = Struct.new(:version, :platform) do
  def windows?
    !!(platform =~ WINDOWS_PLATFORM_REGEX)
  end

  def linux?
    !!(platform =~ LINUX_PLATFORM_REGEX)
  end

  def darwin?
    !!(platform =~ DARWIN_PLATFORM_REGEX)
  end

  def ver
    @ver ||= version[/\A[^-]+/]
  end

  def minor_ver
    @minor_ver ||= ver[/\A\d\.\d(?=\.)/]
  end

  def api_ver_suffix
    case minor_ver
    when nil
      raise "CrossRuby.api_ver_suffix: unsupported version: #{ver}"
    else
      minor_ver.delete(".") << "0"
    end
  end

  def host
    @host ||= case platform
    when "x64-mingw-ucrt", "x64-mingw32"
      "x86_64-w64-mingw32"
    when "x86-mingw32"
      "i686-w64-mingw32"
    when "x86_64-linux"
      "x86_64-linux-gnu"
    when "x86-linux"
      "i686-linux-gnu"
    when "aarch64-linux"
      "aarch64-linux"
    when "x86_64-darwin"
      "x86_64-darwin"
    when "arm64-darwin"
      "aarch64-darwin"
    else
      raise "CrossRuby.platform: unsupported platform: #{platform}"
    end
  end

  def tool(name)
    (@binutils_prefix ||= case platform
     when "x64-mingw-ucrt", "x64-mingw32"
       "x86_64-w64-mingw32-"
     when "x86-mingw32"
       "i686-w64-mingw32-"
     when "x86_64-linux"
       "x86_64-redhat-linux-"
     when "x86-linux"
       "i686-redhat-linux-"
     when "aarch64-linux"
       "aarch64-linux-gnu-"
     when "x86_64-darwin"
       "x86_64-apple-darwin-"
     when "arm64-darwin"
       "aarch64-apple-darwin-"
     else
       raise "CrossRuby.tool: unmatched platform: #{platform}"
     end) + name
  end

  def target_file_format
    case platform
    when "x64-mingw-ucrt", "x64-mingw32"
      "pei-x86-64"
    when "x86-mingw32"
      "pei-i386"
    when "x86_64-linux"
      "elf64-x86-64"
    when "x86-linux"
      "elf32-i386"
    when "aarch64-linux"
      "elf64-littleaarch64"
    when "x86_64-darwin"
      "Mach-O 64-bit x86-64" # hmm
    when "arm64-darwin"
      "Mach-O arm64"
    else
      raise "CrossRuby.target_file_format: unmatched platform: #{platform}"
    end
  end

  def dll_ext
    darwin? ? "bundle" : "so"
  end

  def dll_staging_path
    "tmp/#{platform}/stage/lib/#{SELMA_SPEC.name}/#{minor_ver}/#{SELMA_SPEC.name}.#{dll_ext}"
  end

  def libruby_dll
    case platform
    when "x64-mingw-ucrt"
      "x64-ucrt-ruby#{api_ver_suffix}.dll"
    when "x64-mingw32"
      "x64-msvcrt-ruby#{api_ver_suffix}.dll"
    when "x86-mingw32"
      "msvcrt-ruby#{api_ver_suffix}.dll"
    else
      raise "CrossRuby.libruby_dll: unmatched platform: #{platform}"
    end
  end

  def allowed_dlls
    case platform
    when MINGW32_PLATFORM_REGEX
      [
        "kernel32.dll",
        "msvcrt.dll",
        "ws2_32.dll",
        "user32.dll",
        "advapi32.dll",
        libruby_dll,
      ]
    when MINGWUCRT_PLATFORM_REGEX
      [
        "kernel32.dll",
        "ws2_32.dll",
        "advapi32.dll",
        "api-ms-win-crt-convert-l1-1-0.dll",
        "api-ms-win-crt-environment-l1-1-0.dll",
        "api-ms-win-crt-filesystem-l1-1-0.dll",
        "api-ms-win-crt-heap-l1-1-0.dll",
        "api-ms-win-crt-locale-l1-1-0.dll",
        "api-ms-win-crt-math-l1-1-0.dll",
        "api-ms-win-crt-private-l1-1-0.dll",
        "api-ms-win-crt-runtime-l1-1-0.dll",
        "api-ms-win-crt-stdio-l1-1-0.dll",
        "api-ms-win-crt-string-l1-1-0.dll",
        "api-ms-win-crt-time-l1-1-0.dll",
        "api-ms-win-crt-utility-l1-1-0.dll",
        libruby_dll,
      ]
    when X86_LINUX_PLATFORM_REGEX
      [
        "libm.so.6",
        "libc.so.6",
        "libdl.so.2", # on old dists only - now in libc
      ].tap do |dlls|
        dlls << "libpthread.so.0" if ver < "2.6.0"
      end
    when ARM_LINUX_PLATFORM_REGEX
      [
        "libm.so.6",
        "libc.so.6",
        "libdl.so.2", # on old dists only - now in libc
        "ld-linux-aarch64.so.1",
      ].tap do |dlls|
        dlls << "libpthread.so.0" if ver < "2.6.0"
      end
    when DARWIN_PLATFORM_REGEX
      [
        "/usr/lib/libSystem.B.dylib",
        "/usr/lib/liblzma.5.dylib",
        "/usr/lib/libobjc.A.dylib",
      ]
    else
      raise "CrossRuby.allowed_dlls: unmatched platform: #{platform}"
    end
  end

  def dll_ref_versions
    case platform
    when X86_LINUX_PLATFORM_REGEX
      { "GLIBC" => "2.17" }
    when ARM_LINUX_PLATFORM_REGEX
      { "GLIBC" => "2.29" }
    else
      raise "CrossRuby.dll_ref_versions: unmatched platform: #{platform}"
    end
  end
end

CROSS_RUBIES = File.read(".cross_rubies").split("\n").map do |line|
  case line
  when /\A([^#]+):([^#]+)/
    CrossRuby.new(Regexp.last_match(1), Regexp.last_match(2))
  end
end
