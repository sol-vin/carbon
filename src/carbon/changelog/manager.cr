require "./models"
require "./commit"
require "../vcs/git"

module Carbon
  module Changelog
    class Manager
      YAML_FILE = "changelog.yml"

      def self.yaml_path(repo_root : Path | String = ".") : Path
        Path.new(repo_root).join(YAML_FILE)
      end

      def self.load(repo_root : Path | String = ".") : Manifest
        path = yaml_path(repo_root)
        if File.exists?(path)
          Manifest.from_yaml(File.read(path))
        else
          # Generate initial default manifest
          Manifest.new(
            settings: Settings.new,
            releases: [] of Release
          )
        end
      rescue ex
        # If YAML had syntax error, print warning and return fresh manifest
        STDERR.puts "[carbon warning] Failed to parse #{YAML_FILE}: #{ex.message}"
        Manifest.new(
          settings: Settings.new,
          releases: [] of Release
        )
      end

      def self.save(manifest : Manifest, repo_root : Path | String = ".") : Nil
        path = yaml_path(repo_root)
        File.write(path, manifest.to_yaml)
      end

      # Fetches commits from Git for the specified range
      def self.fetch_git_commits(
        repo_root : Path | String = ".",
        from_ref : String? = nil,
        to_ref : String = "HEAD",
      ) : Array(GitCommit)
        git = VCS::Git.new(repo_root)
        return [] of GitCommit unless git.initialized?

        base_ref = from_ref
        if base_ref.nil?
          # Try to discover latest tag
          stdout = IO::Memory.new
          res = Process.run("git", ["describe", "--tags", "--abbrev=0"], chdir: repo_root.to_s, output: stdout)
          if res.success?
            tag = stdout.to_s.strip
            base_ref = tag unless tag.empty?
          end
        end

        range_arg = base_ref ? "#{base_ref}..#{to_ref}" : to_ref
        log_stdout = IO::Memory.new
        # Format: %H<unit-sep>%h<unit-sep>%s<unit-sep>%an<unit-sep>%cI
        status = Process.run(
          "git",
          ["log", range_arg, "--pretty=format:%H%x1f%h%x1f%s%x1f%an%x1f%cI"],
          chdir: repo_root.to_s,
          output: log_stdout
        )

        return [] of GitCommit unless status.success?

        commits = [] of GitCommit
        log_stdout.to_s.each_line do |line|
          next if line.strip.empty?
          parts = line.split("\x1f")
          next unless parts.size >= 5

          hash = parts[0]
          short_hash = parts[1]
          subject = parts[2]
          author = parts[3]
          date = Time.parse_iso8601(parts[4]) rescue Time.local

          commits << GitCommit.new(hash, short_hash, subject, author, date)
        end

        # Return chronologically (oldest to newest)
        commits.reverse
      end

      # Non-destructive synchronization:
      # ONLY touches the active release. Existing entries are NEVER overwritten or reverted!
      def self.sync(
        repo_root : Path | String = ".",
        version_override : String? = nil,
        from_ref : String? = nil,
        to_ref : String = "HEAD",
      ) : Manifest
        manifest = load(repo_root)
        target_version = version_override || Carbon.current(repo_root).to_s

        # Find or create active release
        active_rel = manifest.active_release
        if active_rel.nil? || active_rel.version != target_version
          # If there was a previous active release, mark it released if different
          if active_rel && active_rel.version != target_version
            active_rel.status = "released"
          end

          existing = manifest.find_release(target_version)
          if existing
            active_rel = existing
            active_rel.status = "active"
          else
            new_rel = Release.new(
              version: target_version,
              date: Time.local.to_s("%Y-%m-%d"),
              status: "active"
            )
            manifest.releases.unshift(new_rel)
            active_rel = new_rel
          end
        end

        # Gathers commits
        commits = fetch_git_commits(repo_root, from_ref, to_ref)

        # Build lookup of existing hashes and descriptions to guarantee non-destructive preservation
        existing_hashes = Set(String).new
        existing_descs = Set(String).new
        active_rel.entries.each do |e|
          existing_hashes << e.hash.not_nil! if e.hash
          existing_descs << e.description.strip
        end

        # Append only new commits that have not been entered yet
        commits.each do |commit|
          next if existing_hashes.includes?(commit.short_hash) || existing_hashes.includes?(commit.hash)
          next if existing_descs.includes?(commit.subject.strip)
          # Skip automated version bump commits
          next if commit.subject.includes?("[carbon] Auto-bumped") || commit.subject.starts_with?("chore(release):")

          parsed = commit.parse_conventional
          cat_cfg = manifest.settings.categories[parsed[:category]]?
          bullet = cat_cfg ? cat_cfg.bullet : "•"

          entry = Entry.new(
            type: parsed[:type],
            description: parsed[:description],
            bullet: bullet,
            badge: parsed[:badge],
            hash: commit.short_hash,
            author: commit.author
          )

          active_rel.entries << entry
        end

        # Save changelog.yml
        save(manifest, repo_root)

        # Compile changelog.yml -> CHANGELOG.md
        compile(manifest, repo_root)

        manifest
      end

      # Compiles changelog.yml into a beautifully styled markdown document
      def self.compile(manifest : Manifest, repo_root : Path | String = ".") : String
        settings = manifest.settings
        io = IO::Memory.new

        git = VCS::Git.new(repo_root)
        slug = if settings.auto_link_github
                 settings.github_slug || (git.initialized? ? git.github_slug : nil)
               else
                 nil
               end

        io.puts "# #{settings.title}\n"

        if banner = settings.ascii_banner
          io.puts "```text"
          io.puts banner.strip
          io.puts "```\n"
        end

        if header = settings.header
          io.puts header.strip
          io.puts ""
        end

        manifest.releases.each_with_index do |release, idx|
          io.puts "## [#{release.version}] - #{release.date}\n"

          if summary = release.summary
            io.puts "> #{summary.strip}\n"
          end

          # Group entries by category
          grouped = Hash(String, Array(Entry)).new { |h, k| h[k] = [] of Entry }
          release.entries.each do |entry|
            cat = entry_category(entry.type)
            grouped[cat] << entry
          end

          # Print according to ordered categories
          order = ["breaking", "features", "fixes", "perf", "docs", "maintenance"]
          order.each do |cat_key|
            entries = grouped[cat_key]?
            next if entries.nil? || entries.empty?

            cat_cfg = settings.categories[cat_key]?
            cat_title = cat_cfg ? cat_cfg.title : cat_key.capitalize
            cat_default_bullet = cat_cfg ? cat_cfg.bullet : "•"

            io.puts "### #{cat_title}"
            entries.each do |e|
              bullet = e.bullet || cat_default_bullet
              badge = e.badge ? "**#{e.badge}** " : ""

              desc = e.description
              if slug
                desc = desc.gsub(/(?<=\s|^)#(\d+)\b/, "[#\\1](https://github.com/#{slug}/issues/\\1)")
              end

              hash_ref = if (h = e.hash) && !h.empty?
                           if slug
                             " ([`#{h}`](https://github.com/#{slug}/commit/#{h}))"
                           else
                             " (`#{h}`)"
                           end
                         else
                           ""
                         end

              io.puts "- #{bullet} #{badge}#{desc}#{hash_ref}"
            end
            io.puts ""
          end

          # Separator between releases
          if idx < manifest.releases.size - 1
            io.puts "---\n"
          end
        end

        output_content = io.to_s
        out_path = Path.new(repo_root).join(settings.output_file)
        File.write(out_path, output_content)
        output_content
      end

      # Seals the specified or active release
      def self.seal_release(version : String? = nil, repo_root : Path | String = ".") : Manifest
        manifest = load(repo_root)
        rel = version ? manifest.find_release(version) : manifest.active_release

        if rel
          rel.status = "released"
          rel.date = Time.local.to_s("%Y-%m-%d")
          save(manifest, repo_root)
          compile(manifest, repo_root)
        end

        manifest
      end

      private def self.entry_category(type : String) : String
        case type.downcase
        when "breaking"
          "breaking"
        when "feat", "feature"
          "features"
        when "fix", "bugfix"
          "fixes"
        when "perf"
          "perf"
        when "docs"
          "docs"
        else
          "maintenance"
        end
      end
    end
  end
end
