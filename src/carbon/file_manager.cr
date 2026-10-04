require "./version"

module Carbon
  class FileManager
    # Regex to capture:
    # 1: Leading whitespace and "version:"
    # 2: Opening quote (optional)
    # 3: Version value
    # 4: Trailing whitespace and optional comment
    VERSION_LINE_REGEX = /^(\s*version:\s*)(["']?)([^"'\r\n#]+)\2(\s*(?:#.*)?)$/

    # Regex for Crystal VERSION constant: VERSION = "0.1.0"
    CRYSTAL_VERSION_REGEX = /^(\s*(?:pub\s+)?(?:[A-Z0-9_]+::)?VERSION\s*=\s*)(["'])([^"'\r\n]+)\2(\s*(?:#.*)?)$/

    # Regex for C/C++ header #define ...VERSION "..."
    C_HEADER_VERSION_REGEX = /^(\s*#define\s+[A-Za-z0-9_]*VERSION\s+)(["'])([^"'\r\n]+)\2(\s*(?:\/.*)?)$/

    # Parses the version string from shard.yml content and returns a Carbon::Version
    def self.parse_shard_version(content : String) : Version?
      content.each_line do |line|
        if match = VERSION_LINE_REGEX.match(line)
          ver_str = match[3].strip
          return Version.parse?(ver_str)
        end
      end
      nil
    end

    # Reads the version string from shard.yml and parses it into a Carbon::Version
    def self.read_shard_version(shard_path : Path | String = "shard.yml") : Version?
      path = Path.new(shard_path)
      return nil unless File.exists?(path)

      parse_shard_version(File.read(path))
    end

    # Updates shard.yml with the new version, preserving quotes, indentation, and comments
    def self.update_shard_version(shard_path : Path | String, new_version : Version | String) : Bool
      path = Path.new(shard_path)
      return false unless File.exists?(path)

      version_str = new_version.is_a?(Version) ? new_version.to_s : new_version.strip
      content = File.read(path)
      lines = content.split("\n")
      found = false

      updated_lines = lines.map do |line|
        if !found && (match = VERSION_LINE_REGEX.match(line))
          found = true
          prefix = match[1]
          quote = match[2]
          trailing = match[4]
          "#{prefix}#{quote}#{version_str}#{quote}#{trailing}"
        else
          line
        end
      end

      return false unless found

      File.write(path, updated_lines.join("\n"))
      true
    end

    # Updates a Crystal version.cr file, preserving structure
    def self.update_crystal_version_file(file_path : Path | String, new_version : Version | String) : Bool
      path = Path.new(file_path)
      return false unless File.exists?(path)

      version_str = new_version.is_a?(Version) ? new_version.to_s : new_version.strip
      content = File.read(path)
      lines = content.split("\n")
      found = false

      updated_lines = lines.map do |line|
        if !found && (match = CRYSTAL_VERSION_REGEX.match(line))
          found = true
          prefix = match[1]
          quote = match[2]
          trailing = match[4]
          "#{prefix}#{quote}#{version_str}#{quote}#{trailing}"
        else
          line
        end
      end

      return false unless found

      File.write(path, updated_lines.join("\n"))
      true
    end

    # Updates a C/C++ header #define VERSION file
    def self.update_c_header_version_file(file_path : Path | String, new_version : Version | String) : Bool
      path = Path.new(file_path)
      return false unless File.exists?(path)

      version_str = new_version.is_a?(Version) ? new_version.to_s : new_version.strip
      content = File.read(path)
      lines = content.split("\n")
      found = false

      updated_lines = lines.map do |line|
        if !found && (match = C_HEADER_VERSION_REGEX.match(line))
          found = true
          prefix = match[1]
          quote = match[2]
          trailing = match[4]
          "#{prefix}#{quote}#{version_str}#{quote}#{trailing}"
        else
          line
        end
      end

      return false unless found

      File.write(path, updated_lines.join("\n"))
      true
    end

    # Automatically finds and synchronizes all version-bearing files in the project
    def self.sync_all_targets(new_version : Version | String, repo_root : Path | String = ".") : Array(Path)
      root = Path.new(repo_root)
      updated_paths = [] of Path

      # 1. shard.yml
      shard_yml = root.join("shard.yml")
      if File.exists?(shard_yml) && update_shard_version(shard_yml, new_version)
        updated_paths << shard_yml
      end

      # 2. Auto-discover version.cr files in src/
      src_dir = root.join("src")
      if Dir.exists?(src_dir)
        Dir.glob(src_dir.join("**", "version.cr").to_posix.to_s).each do |vfile|
          p = Path.new(vfile)
          if update_crystal_version_file(p, new_version)
            updated_paths << p
          end
        end

        # 3. Auto-discover C/C++ version header files in src/
        Dir.glob(src_dir.join("**", "*version*.h").to_posix.to_s).each do |hfile|
          p = Path.new(hfile)
          if update_c_header_version_file(p, new_version)
            updated_paths << p
          end
        end
      end

      updated_paths
    end

    # Creates a default shard.yml if one does not exist
    def self.ensure_shard_yml(
      shard_path : Path | String = "shard.yml",
      name : String? = nil,
      initial_version : Version = Version.new(0, 1, 0),
    ) : Bool
      path = Path.new(shard_path)
      return false if File.exists?(path)

      proj_name = name || path.parent.basename.presence || "my_app"
      template = <<-YAML
      name: #{proj_name}
      version: #{initial_version}

      authors:
        - Developer

      crystal: ">= 1.20.0"

      license: MIT
      YAML

      File.write(path, template.strip + "\n")
      true
    end

    # Optional helper to generate or update a typed version.cr file
    def self.sync_version_cr(version_cr_path : Path | String, version : Version, module_name : String) : Bool
      path = Path.new(version_cr_path)
      parent = path.parent
      Dir.mkdir_p(parent) unless Dir.exists?(parent)

      content = <<-CRYSTAL
      # This file is automatically maintained by Carbon.
      # Manual edits to the commit number will be overwritten.
      module #{module_name}
        VERSION = "#{version}"
        MAJOR   = #{version.major}
        MINOR   = #{version.minor}
        COMMIT  = #{version.commit}
      end
      CRYSTAL

      File.write(path, content.strip + "\n")
      true
    end
  end
end
