require "./models"
require "./detector"
require "./builder"
require "./injector"

module Carbon
  module Badges
    class Manager
      YAML_FILE = "badges.yml"

      def self.yaml_path(repo_root : Path | String = ".") : Path
        Path.new(repo_root).join(YAML_FILE)
      end

      # Returns true if badges are configured via badges.yml or if target file has badge tags
      def self.configured?(repo_root : Path | String = ".") : Bool
        root = Path.new(repo_root)
        return true if File.exists?(yaml_path(root))

        # Check default README.md for tag
        readme_path = root.join("README.md")
        if File.exists?(readme_path)
          content = File.read(readme_path)
          return Injector.has_tag?(content)
        end

        false
      end

      # Loads Manifest from badges.yml or generates smart defaults
      def self.load(repo_root : Path | String = ".") : Manifest
        path = yaml_path(repo_root)
        if File.exists?(path)
          Manifest.from_yaml(File.read(path))
        else
          generate_default_manifest(repo_root)
        end
      rescue ex
        STDERR.puts "[carbon warning] Failed to parse #{YAML_FILE}: #{ex.message}"
        generate_default_manifest(repo_root)
      end

      # Saves manifest to badges.yml
      def self.save(manifest : Manifest, repo_root : Path | String = ".") : Nil
        path = yaml_path(repo_root)
        File.write(path, manifest.to_yaml)
      end

      # Generates sensible default manifest based on repository metadata
      def self.generate_default_manifest(repo_root : Path | String = ".") : Manifest
        meta = Detector.detect(repo_root)
        badges = [] of BadgeConfig

        # 1. CI workflow if present
        if meta.ci_workflow && meta.github_slug
          badges << BadgeConfig.new(type: "ci")
        end

        # 2. Docs badge if present
        if meta.docs_url
          badges << BadgeConfig.new(type: "docs")
        end

        # 3. Crystal version if present
        if meta.crystal_version
          badges << BadgeConfig.new(type: "crystal")
        end

        # 4. Version badge
        badges << BadgeConfig.new(type: "version")

        # 5. License badge
        if meta.license
          badges << BadgeConfig.new(type: "license")
        end

        Manifest.new(
          settings: Settings.new,
          badges: badges
        )
      end

      # Renders badges markdown according to manifest and current repo state
      def self.render(
        repo_root : Path | String = ".",
        version_override : String? = nil,
        manifest : Manifest? = nil,
      ) : String
        root = Path.new(repo_root)
        m = manifest || load(root)
        meta = Detector.detect(root)

        Builder.build_all(m.badges, meta, version_override, m.settings)
      end

      # Synchronizes badges into the target file (default: README.md)
      # Returns Path of updated file, or nil if no update performed
      def self.sync(
        repo_root : Path | String = ".",
        version_override : String? = nil,
        inject_if_missing : Bool = false,
      ) : Path?
        root = Path.new(repo_root)
        manifest = load(root)
        target = root.join(manifest.settings.target_file)
        return nil unless File.exists?(target)

        content = File.read(target)
        return nil unless Injector.has_tag?(content) || inject_if_missing

        rendered_badges = render(root, version_override, manifest)
        updated = Injector.render_into(
          content,
          rendered_badges,
          inject_if_missing: inject_if_missing,
          tag_name: manifest.settings.tag
        )

        if content != updated
          File.write(target, updated)
        end

        target
      end

      # Checks if the target file exists, has tags, and has up-to-date badges
      def self.check(repo_root : Path | String = ".") : NamedTuple(synced: Bool, target_file: Path, message: String)
        root = Path.new(repo_root)
        manifest = load(root)
        target = root.join(manifest.settings.target_file)

        unless File.exists?(target)
          return {synced: false, target_file: target, message: "#{manifest.settings.target_file} does not exist"}
        end

        content = File.read(target)
        unless Injector.has_tag?(content)
          return {synced: false, target_file: target, message: "No badge tags (<!-- carbon:badges -->) found in #{manifest.settings.target_file}"}
        end

        expected = render(root, manifest: manifest)
        if Injector.badges_up_to_date?(content, expected)
          {synced: true, target_file: target, message: "Badges in #{manifest.settings.target_file} are synchronized"}
        else
          {synced: false, target_file: target, message: "Badges in #{manifest.settings.target_file} are out of date"}
        end
      end
    end
  end
end
