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
      major = 0
      minor = 1

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: carbon init [options]"
        opts.on("--no-hook", "Do not install git pre-commit hook") { install_hook = false }
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

      if install_hook
        if git.initialized?
          HookManager.install(".")
          puts "\e[32m✓\e[0m Installed Git pre-commit hook in \e[36m.git/hooks/pre-commit\e[0m"
        else
          puts "\e[33m!\e[0m Git repository not initialized. Run 'git init' then 'carbon hook install'."
        end
      end

      puts "\e[32m✓\e[0m \e[1mCarbon initialization complete!\e[0m"
      puts "  Commits will now automatically bump the version in 'shard.yml' (lapis-style)."
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
        opts.on("--stage", "Stage shard.yml with git after bumping") { stage = true }
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
        opts.on("--stage", "Stage shard.yml with git after syncing") { stage = true }
        opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
      end
      parser.parse(args)

      new_ver = Carbon.sync!(".", stage: stage)
      puts "\e[32m✓\e[0m Synchronized shard.yml version to \e[1m#{new_ver}\e[0m (matching Git commit count)"
    end

    private def cmd_set(args : Array(String))
      stage = false
      remaining = [] of String

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: carbon set <major.minor> [options]"
        opts.on("--stage", "Stage shard.yml after setting version") { stage = true }
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

    private def print_help
      puts <<-HELP
      \e[1mCarbon\e[0m - Version Control & Lapis-Style Auto-Versioning for Crystal Apps

      \e[1mUSAGE:\e[0m
        carbon <command> [options]

      \e[1mCOMMANDS:\e[0m
        \e[36minit\e[0m                 Initialize Carbon in the current project & install Git hook
        \e[36mbump\e[0m                 Bump version (default: next commit count)
        \e[36msync\e[0m                 Align shard.yml commit number with exact Git commit count
        \e[36mset <major.minor>\e[0m    Set major and minor versions (e.g. 'carbon set 1.2')
        \e[36mget, version\e[0m         Display current project version (use -p for raw output)
        \e[36mcheck\e[0m                Verify whether shard.yml is in sync with Git commits
        \e[36mhook\e[0m                 Manage Git pre-commit hook (install | uninstall | status)
        \e[36mhelp\e[0m                 Show this help manual

      \e[1mOPTIONS FOR BUMP:\e[0m
        --hook               Silent pre-commit hook mode (calculates upcoming commit index)
        --commit             Bump commit counter (default)
        --minor              Increment minor version (e.g. 0.1.X -> 0.2.X)
        --major              Increment major version (e.g. 0.X.Y -> 1.0.Y)
        --stage              Stage shard.yml with Git after bumping

      \e[1mEXAMPLES:\e[0m
        carbon init
        carbon set 1.0
        carbon bump --minor
        carbon sync
        carbon get --porcelain
        carbon check
      HELP
    end
  end
end

Carbon::CLI.run
