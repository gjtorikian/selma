# frozen_string_literal: true

def gem_build_path
  File.join("pkg", SELMA_SPEC.full_name)
end

def verify_dll(dll, cross_ruby)
  allowed_imports = cross_ruby.allowed_dlls

  if cross_ruby.windows?
    dump = %x(#{["env", "LANG=C", cross_ruby.tool("objdump"), "-p", dll].shelljoin})

    raise "unexpected file format for generated dll #{dll}" unless /file format #{Regexp.quote(cross_ruby.target_file_format)}\s/.match?(dump)
    raise "export function Init_selma not in dll #{dll}" unless /Table.*\sInit_selma\s/mi.match?(dump)

    # Verify that the DLL dependencies are all allowed.
    actual_imports = dump.scan(/DLL Name: (.*)$/).map(&:first).map(&:downcase).uniq
    raise "unallowed so imports #{actual_imports.inspect} in #{dll} (allowed #{allowed_imports.inspect})" unless (actual_imports - allowed_imports).empty?

  elsif cross_ruby.linux?
    dump = %x(#{["env", "LANG=C", cross_ruby.tool("objdump"), "-p", dll].shelljoin})
    nm = %x(#{["env", "LANG=C", cross_ruby.tool("nm"), "-D", dll].shelljoin})

    raise "unexpected file format for generated dll #{dll}" unless /file format #{Regexp.quote(cross_ruby.target_file_format)}\s/.match?(dump)
    raise "export function Init_selma not in dll #{dll}" unless / T Init_selma/.match?(nm)

    # Verify that the DLL dependencies are all allowed.
    actual_imports = dump.scan(/NEEDED\s+(.*)/).map(&:first).uniq
    raise "unallowed so imports #{actual_imports.inspect} in #{dll} (allowed #{allowed_imports.inspect})" unless (actual_imports - allowed_imports).empty?

    # Verify that the expected so version requirements match the actual dependencies.
    ref_versions_data = dump.scan(/0x[\da-f]+ 0x[\da-f]+ \d+ (\w+)_([\d.]+)$/i)
    # Build a hash of library versions like {"LIBUDEV"=>"183", "GLIBC"=>"2.17"}
    actual_ref_versions = ref_versions_data.each.with_object({}) do |(lib, ver), h|
      h[lib] = ver if !h[lib] || ver.split(".").map(&:to_i).pack("C*") > h[lib].split(".").map(&:to_i).pack("C*")
    end
    raise "unexpected so version requirements #{actual_ref_versions.inspect} in #{dll}" if actual_ref_versions != cross_ruby.dll_ref_versions

  elsif cross_ruby.darwin?
    dump = %x(#{["env", "LANG=C", cross_ruby.tool("objdump"), "-p", dll].shelljoin})
    nm = %x(#{["env", "LANG=C", cross_ruby.tool("nm"), "-g", dll].shelljoin})

    raise "unexpected file format for generated dll #{dll}" unless /file format #{Regexp.quote(cross_ruby.target_file_format)}\s/.match?(dump)
    raise "export function Init_selma not in dll #{dll}" unless / T _?Init_selma/.match?(nm)

    # if liblzma is being referenced, let's make sure it's referring
    # to the system-installed file and not the homebrew-installed file.
    ldd = %x(#{["env", "LANG=C", cross_ruby.tool("otool"), "-L", dll].shelljoin})
    if (liblzma_refs = ldd.scan(/^\t([^ ]+) /).map(&:first).uniq.grep(/liblzma/))
      liblzma_refs.each do |ref|
        new_ref = File.join("/usr/lib", File.basename(ref))
        sh(["env", "LANG=C", cross_ruby.tool("install_name_tool"), "-change", ref, new_ref, dll].shelljoin)
      end

      # reload!
      ldd = %x(#{["env", "LANG=C", cross_ruby.tool("otool"), "-L", dll].shelljoin})
    end

    # Verify that the DLL dependencies are all allowed.
    actual_imports = ldd.scan(/^\t([^ ]+) /).map(&:first).uniq
    raise "unallowed so imports #{actual_imports.inspect} in #{dll} (allowed #{allowed_imports.inspect})" unless (actual_imports - allowed_imports).empty?
  end
  puts "verify_dll: #{dll}: passed shared library sanity checks"
end
