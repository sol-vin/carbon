require "../carbon"
require "option_parser"

module Carbon
  class CLI
    def self.run(args = ARGV)
      new.run(args)
    end

    def run(args : Array(String))
      if args.empty?
        print_help
        exit 0
      end

      command = args.first
      subargs = args[1..]

      case command
      when "init"
        cmd_init(subargs)
      when "bump"
        cmd_bump(subargs)
      when "sync"
        cmd_sync(subargs)
      when "set"
        cmd_set(subargs)
      when "get", "version", "-v", "--version"
        cmd_get(subargs)
      when "check"
        cmd_check(subargs)
      when "changelog"
        cmd_changelog(subargs)
      when "badges", "badge"
        cmd_badges(subargs)
      when "tag", "release"
        cmd_tag(subargs)
      when "doctor"
        cmd_doctor(subargs)
      when "hook"
        cmd_hook(subargs)
      when "help", "--help", "-h"
        print_help
      else
        STDERR.puts "\e[31m[carbon error]\e[0m Unknown command '#{command}'"
        STDERR.puts "Run 'carbon --help' for usage instructions."
        exit 1
      end
    rescue ex : Exception
      STDERR.puts "\e[31m[carbon error]\e[0m #{ex.message}"
      exit 1
    end

    private def cmd_init(args : Array(String))
      install_hook = true
      init_changelog = true
      init_badges = true
      major = 0
      minor = 1

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: carbon init [options]"
        opts.on("--no-hook", "Do not install git pre-commit hook") { install_hook = false }
        opts.on("--no-changelog", "Do not generate changelog.yml") { init_changelog = false }
        opts.on("--no-badges", "Do not initialize badges.yml or README badges") { init_badges = false }
        opts.on("--major=N", "Set initial major version (default: 0)") { |v| major = v.to_i }
        opts.on("--minor=N", "Set initial minor version (default: 1)") { |v| minor = v.to_i }
        opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
      end
      parser.parse(args)

      git = VCS::Git.new(".")
      commits = git.initialized? ? git.commit_count : 0
      init_version = Version.new(major, minor, commits)

      shard_path = Path.new("shard.yml")
      if File.exists?(shard_path)
        existing = FileManager.read_shard_version(shard_path)
        if existing
          puts "\e[32m✓\e[0m Found existing shard.yml with version: \e[1m#{existing}\e[0m"
        else
          FileManager.update_shard_version(shard_path, init_version)
          puts "\e[32m✓\e[0m Configured shard.yml version to: \e[1m#{init_version}\e[0m"
        end
      else
        FileManager.ensure_shard_yml(shard_path, initial_version: init_version)
        puts "\e[32m✓\e[0m Created new shard.yml with version: \e[1m#{init_version}\e[0m"
      end

      if init_changelog
        manifest = Changelog::Manager.load(".")
        if manifest.releases.empty?
          rel = Changelog::Release.new(
            version: init_version.to_s,
            date: Time.local.to_s("%Y-%m-%d"),
            status: "active",
            summary: "Initial release"
          )
          manifest.releases << rel
          Changelog::Manager.save(manifest, ".")
          Changelog::Manager.compile(manifest, ".")
          puts "\e[32m✓\e[0m Created \e[36mchangelog.yml\e[0m and compiled \e[36mCHANGELOG.md\e[0m"
        end
      end

      if init_badges
        readme_path = Path.new("README.md")
        if File.exists?(readme_path)
          badges_yaml = Badges::Manager.yaml_path(".")
          unless File.exists?(badges_yaml)
            default_m = Badges::Manager.generate_default_manifest(".")
            Badges::Manager.save(default_m, ".")
          end
          Badges::Manager.sync(".", version_override: init_version.to_s, inject_if_missing: true)
          puts "\e[32m✓\e[0m Initialized \e[36mbadges.yml\e[0m and rendered badges in \e[36mREADME.md\e[0m"
        end
      end

      if install_hook
        if git.initialized?
          HookManager.install(".")
          puts "\e[32m✓\e[0m Installed Git pre-commit hook in \e[36m.git/hooks/pre-commit\e[0m"
        else
          puts "\e[33m!\e[0m Git repository not initialized. Run 'git init' then 'carbon hook install'."
        end
      end

      puts "\e[32m✓\e[0m \e[1mCarbon initialization complete!\e[0m"
      puts "  Commits will now automatically bump the version in 'shard.yml'."
    end

    private def cmd_bump(args : Array(String))
      type = BumpType::Commit
      is_hook = false
      stage = false

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: carbon bump [options]"
        opts.on("--hook", "Optimized silent bump called from Git pre-commit hook") { is_hook = true; stage = true }
        opts.on("--commit", "Bump commit number (default)") { type = BumpType::Commit }
        opts.on("--minor", "Bump minor version (keeps commit synced)") { type = BumpType::Minor }
        opts.on("--major", "Bump major version (keeps commit synced)") { type = BumpType::Major }
        opts.on("--stage", "Stage updated files with git after bumping") { stage = true }
        opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
      end
      parser.parse(args)

      new_ver = Carbon.bump!(type, ".", stage: stage)

      if is_hook
        puts "\e[36m[carbon]\e[0m Auto-bumped version to \e[1m#{new_ver}\e[0m (commit ##{new_ver.commit})"
      else
        puts "\e[32m✓\e[0m Bumped version to \e[1m#{new_ver}\e[0m"
      end
    end

    private def cmd_sync(args : Array(String))
      stage = false
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: carbon sync [options]"
        opts.on("--stage", "Stage updated files with git after syncing") { stage = true }
        opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
      end
      parser.parse(args)

      new_ver = Carbon.sync!(".", stage: stage)
      puts "\e[32m✓\e[0m Synchronized project version to \e[1m#{new_ver}\e[0m (matching Git commit count)"
    end

    private def cmd_set(args : Array(String))
      stage = false
      remaining = [] of String

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: carbon set <major.minor> [options]"
        opts.on("--stage", "Stage updated files after setting version") { stage = true }
        opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
        opts.unknown_args { |raw| remaining = raw }
      end
      parser.parse(args)

      if remaining.empty?
        STDERR.puts "\e[31m[carbon error]\e[0m Missing version argument. Example: 'carbon set 1.0'"
        exit 1
      end

      raw_target = remaining.first
      parts = raw_target.split(".")
      if parts.size < 2
        STDERR.puts "\e[31m[carbon error]\e[0m Invalid format '#{raw_target}'. Expected '<major>.<minor>' (e.g. 1.2)"
        exit 1
      end

      maj = parts[0].to_i?
      min = parts[1].to_i?
      if maj.nil? || min.nil?
        STDERR.puts "\e[31m[carbon error]\e[0m Major and minor must be integers: '#{raw_target}'"
        exit 1
      end

      new_ver = Carbon.set(maj, min, ".", stage: stage)
      puts "\e[32m✓\e[0m Updated version to \e[1m#{new_ver}\e[0m (Major: #{maj}, Minor: #{min}, Commits: #{new_ver.commit})"
    end

    private def cmd_get(args : Array(String))
      porcelain = false
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: carbon get [options]"
        opts.on("-p", "--porcelain", "Output raw version string only") { porcelain = true }
        opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
      end
      parser.parse(args)

      ver = Carbon.current(".")
      if porcelain
        puts ver.to_s
      else
        puts "\e[1mCarbon Version:\e[0m \e[32m#{ver}\e[0m (Major: #{ver.major}, Minor: #{ver.minor}, Commits: #{ver.commit})"
      end
    end

    private def cmd_check(args : Array(String))
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: carbon check"
        opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
      end
      parser.parse(args)

      res = Carbon.check(".")
      if res[:synced]
        puts "\e[32m✓ In sync!\e[0m shard.yml version \e[1m#{res[:shard_version]}\e[0m matches Git commit count (#{res[:git_commits]})."
        exit 0
      else
        diff = res[:diff]
        msg = diff > 0 ? "#{diff} ahead of" : "#{diff.abs} behind"
        puts "\e[33m! Out of sync:\e[0m shard.yml (#{res[:shard_version]}) is #{msg} Git HEAD (#{res[:git_commits]} commits)."
        puts "  Run '\e[36mcarbon sync\e[0m' to synchronize shard.yml with Git history."
        exit 1
      end
    end

    private def cmd_changelog(args : Array(String))
      compile_only = false
      dry_run = false
      from_ref : String? = nil
      to_ref = "HEAD"
      target_ver : String? = nil

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: carbon changelog [options]"
        opts.on("--sync", "Synchronize changelog.yml with new Git commits (default)") { }
        opts.on("--compile", "Only compile changelog.yml to CHANGELOG.md without pulling new commits") { compile_only = true }
        opts.on("--dry-run", "Preview compiled CHANGELOG.md on stdout without modifying files") { dry_run = true }
        opts.on("--from=REF", "Start commit reference or tag") { |v| from_ref = v }
        opts.on("--to=REF", "End commit reference (default: HEAD)") { |v| to_ref = v }
        opts.on("--version=VER", "Explicit release version target") { |v| target_ver = v }
        opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
      end
      parser.parse(args)

      if compile_only
        manifest = Changelog::Manager.load(".")
        output = Changelog::Manager.compile(manifest, ".")
        if dry_run
          puts output
        else
          puts "\e[32m✓\e[0m Compiled \e[36mchangelog.yml\e[0m into \e[1m#{manifest.settings.output_file}\e[0m"
        end
      else
        manifest = Changelog::Manager.sync(
          ".",
          version_override: target_ver,
          from_ref: from_ref,
          to_ref: to_ref
        )
        if dry_run
          puts Changelog::Manager.compile(manifest, ".")
        else
          puts "\e[32m✓\e[0m Synchronized \e[36mchangelog.yml\e[0m and compiled \e[1m#{manifest.settings.output_file}\e[0m"
          if active = manifest.active_release
            puts "  Active release: \e[1m#{active.version}\e[0m (#{active.entries.size} entries)"
          end
        end
      end
    end

    private def cmd_tag(args : Array(String))
      latest = true
      push = false
      custom_msg : String? = nil
      remaining = [] of String

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: carbon tag [version] [options]"
        opts.on("--no-latest", "Do not update floating 'latest' tag") { latest = false }
        opts.on("--push", "Push branch and tags to remote origin") { push = true }
        opts.on("-m MSG", "--message=MSG", "Custom release tag message") { |v| custom_msg = v }
        opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
        opts.unknown_args { |raw| remaining = raw }
      end
      parser.parse(args)

      target_version = remaining.first? || Carbon.current(".").to_s
      tag_name = target_version.starts_with?('v') ? target_version : "v#{target_version}"

      puts "Creating release tag \e[1m#{tag_name}\e[0m..."
      if ReleaseManager.create_tag(target_version, message: custom_msg, floating_latest: latest, repo_root: ".")
        puts "\e[32m✓\e[0m Tag \e[1m#{tag_name}\e[0m created and changelog sealed!"
        puts "\e[32m✓\e[0m Floating tag \e[1mlatest\e[0m updated" if latest

        if push
          puts "Pushing to remote origin..."
          if ReleaseManager.push_release("origin", version: target_version, floating_latest: latest, repo_root: ".")
            puts "\e[32m✓\e[0m Pushed branch and tags to origin!"
          else
            STDERR.puts "\e[33m!\e[0m Failed to push tags to origin."
          end
        end
      else
        STDERR.puts "\e[31m[carbon error]\e[0m Failed to create tag #{tag_name}"
        exit 1
      end
    end

    private def cmd_doctor(args : Array(String))
      do_fix = false
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: carbon doctor [options]"
        opts.on("--fix", "Automatically repair detected issues") { do_fix = true }
        opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
      end
      parser.parse(args)

      doc = Doctor.new(Path.new("."))
      issues = doc.run

      if issues.empty?
        puts "\e[32m✓ Carbon Doctor: Everything looks healthy!\e[0m"
        puts "  Git repository, hooks, manifest versioning, and changelogs are synchronized."
        exit 0
      end

      puts "\e[1mCarbon Doctor Audit Findings:\e[0m"
      issues.each_with_index do |issue, idx|
        fixable_badge = issue.fixable ? "\e[32m[auto-fixable]\e[0m" : "\e[33m[manual]\e[0m"
        puts "  #{idx + 1}. \e[1m[#{issue.category}]\e[0m #{issue.message} #{fixable_badge}"
      end

      if do_fix
        fixed = doc.fix
        puts "\n\e[32m✓\e[0m Repaired \e[1m#{fixed}\e[0m issue(s) successfully!"
      else
        puts "\nRun '\e[36mcarbon doctor --fix\e[0m' to automatically repair fixable issues."
        exit 1
      end
    end

    private def cmd_hook(args : Array(String))
      if args.empty?
        STDERR.puts "Usage: carbon hook [install | uninstall | status]"
        exit 1
      end

      sub = args.first
      case sub
      when "install"
        HookManager.install(".")
        puts "\e[32m✓\e[0m Git pre-commit hook installed in .git/hooks/pre-commit"
      when "uninstall", "remove"
        if HookManager.uninstall(".")
          puts "\e[32m✓\e[0m Git pre-commit hook uninstalled"
        else
          puts "No Carbon hook found to uninstall."
        end
      when "status"
        if HookManager.installed?(".")
          puts "\e[32m✓\e[0m Carbon Git pre-commit hook is \e[1minstalled and active\e[0m"
        else
          puts "\e[33m!\e[0m Carbon Git hook is \e[1mnot installed\e[0m. Run 'carbon hook install'."
        end
      else
        STDERR.puts "Unknown hook command: '#{sub}'. Choose from: install, uninstall, status"
        exit 1
      end
    end

    private def cmd_badges(args : Array(String))
      action = "render"
      dry_run = false
      inject = false
      target_file_override : String? = nil
      remaining = [] of String

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: carbon badges [action] [options]"
        opts.on("--render", "Render and update badges in target markdown file (default)") { action = "render" }
        opts.on("--check", "Check if badges in target file are synchronized") { action = "check" }
        opts.on("--init", "Generate badges.yml and inject tags into README.md") { action = "init" }
        opts.on("--list", "List configured and discovered badges") { action = "list" }
        opts.on("--dry-run", "Preview rendered badges on stdout without modifying files") { dry_run = true }
        opts.on("--inject", "Inject badge tags into markdown file if missing") { inject = true }
        opts.on("--file=FILE", "Target markdown file (default: README.md)") { |f| target_file_override = f }
        opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
        opts.unknown_args { |raw| remaining = raw }
      end
      parser.parse(args)

      if first = remaining.first?
        case first
        when "render", "sync"
          action = "render"
        when "check"
          action = "check"
        when "init"
          action = "init"
        when "list"
          action = "list"
        end
      end

      case action
      when "render"
        manifest = Badges::Manager.load(".")
        if file_override = target_file_override
          manifest.settings.target_file = file_override
        end

        rendered = Badges::Manager.render(".", manifest: manifest)

        if dry_run
          puts rendered
          return
        end

        target_path = Path.new(".").join(manifest.settings.target_file)
        unless File.exists?(target_path)
          STDERR.puts "\e[31m[carbon error]\e[0m Target file '#{manifest.settings.target_file}' not found."
          exit 1
        end

        content = File.read(target_path)
        unless Badges::Injector.has_tag?(content) || inject
          STDERR.puts "\e[33m!\e[0m No '<!-- carbon:badges -->' tag found in #{manifest.settings.target_file}."
          STDERR.puts "  Add '<!-- carbon:badges --> <!-- /carbon:badges -->' or run 'carbon badges --inject'."
          exit 1
        end

        updated_path = Badges::Manager.sync(".", inject_if_missing: inject)
        if updated_path
          puts "\e[32m✓\e[0m Synchronized badges in \e[1m#{manifest.settings.target_file}\e[0m"
        else
          puts "Badges in #{manifest.settings.target_file} are already up to date."
        end

      when "check"
        manifest = Badges::Manager.load(".")
        if file_override = target_file_override
          manifest.settings.target_file = file_override
        end

        res = Badges::Manager.check(".")
        if res[:synced]
          puts "\e[32m✓ In sync!\e[0m #{res[:message]}."
          exit 0
        else
          puts "\e[33m! Out of sync:\e[0m #{res[:message]}."
          puts "  Run '\e[36mcarbon badges\e[0m' to update badges."
          exit 1
        end

      when "init"
        badges_yaml = Badges::Manager.yaml_path(".")
        manifest = if File.exists?(badges_yaml)
                     puts "\e[32m✓\e[0m Found existing badges.yml"
                     Badges::Manager.load(".")
                   else
                     default_m = Badges::Manager.generate_default_manifest(".")
                     Badges::Manager.save(default_m, ".")
                     puts "\e[32m✓\e[0m Created \e[36mbadges.yml\e[0m with #{default_m.badges.size} detected badges"
                     default_m
                   end

        if file_override = target_file_override
          manifest.settings.target_file = file_override
        end

        target_path = Path.new(".").join(manifest.settings.target_file)
        if File.exists?(target_path)
          Badges::Manager.sync(".", inject_if_missing: true)
          puts "\e[32m✓\e[0m Injected and rendered badges into \e[1m#{manifest.settings.target_file}\e[0m"
        end

      when "list"
        manifest = Badges::Manager.load(".")
        meta = Badges::Detector.detect(".")
        puts "\e[1mConfigured Badges (#{manifest.badges.size}):\e[0m"
        manifest.badges.each_with_index do |b, idx|
          badge_snippet = Badges::Builder.build(b, meta, default_style: manifest.settings.style)
          puts "  #{idx + 1}. \e[36m#{b.type}\e[0m: #{badge_snippet}"
        end
      end
    end

    private def print_help
      puts <<-HELP
      \e[1mCarbon\e[0m - Automated Version Control & Changelog System for Crystal Apps

      \e[1mUSAGE:\e[0m
        carbon <command> [options]

      \e[1mCOMMANDS:\e[0m
        \e[36minit\e[0m                 Initialize Carbon in the project, install Git hook & changelog
        \e[36mbump\e[0m                 Bump version (default: next commit count)
        \e[36msync\e[0m                 Align shard.yml commit number with exact Git commit count
        \e[36mset <major.minor>\e[0m    Set major and minor versions (e.g. 'carbon set 1.2')
        \e[36mget, version\e[0m         Display current project version (use -p for raw output)
        \e[36mcheck\e[0m                Verify whether shard.yml is in sync with Git commits
        \e[36mchangelog\e[0m            Manage changelog.yml & compile CHANGELOG.md
        \e[36mbadges\e[0m              Manage README badges (render | check | init | list)
        \e[36mtag, release\e[0m         Seal changelog, create release tag, & update floating latest
        \e[36mdoctor\e[0m               Audit repository health, version parity, and fix issues
        \e[36mhook\e[0m                 Manage Git pre-commit hook (install | uninstall | status)
        \e[36mhelp\e[0m                 Show this help manual

      \e[1mBADGES OPTIONS:\e[0m
        --render             Render and update badges in target markdown file (default)
        --check              Verify whether README badges match current versions
        --init               Generate badges.yml and inject tags into README.md
        --list               List configured and discovered badges
        --dry-run            Preview rendered markdown badges without writing to disk
        --inject             Inject badge tags if missing from markdown file
        --file=FILE          Specify markdown target file (default: README.md)

      \e[1mCHANGELOG OPTIONS:\e[0m
        --sync               Synchronize changelog.yml with new Git commits (default)
        --compile            Compile changelog.yml to CHANGELOG.md without fetching commits
        --dry-run            Print compiled CHANGELOG.md without modifying disk
        --from=REF           Target starting tag or commit
        --to=REF             Target ending commit (default: HEAD)

      \e[1mEXAMPLES:\e[0m
        carbon init
        carbon set 1.0
        carbon bump --minor
        carbon changelog
        carbon badges
        carbon tag v1.0.0 --push
        carbon doctor --fix
      HELP
    end
  end
end

Carbon::CLI.run
