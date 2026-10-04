require "./version"
require "./file_manager"
require "./hook_manager"
require "./changelog/manager"
require "./vcs/git"

module Carbon
  struct DoctorIssue
    property category : String
    property message : String
    property fixable : Bool
    property fix_action : Proc(Nil)?

    def initialize(@category : String, @message : String, @fixable : Bool = false, @fix_action : Proc(Nil)? = nil)
    end
  end

  class Doctor
    getter issues : Array(DoctorIssue)
    property? check_hook_in_ci : Bool

    def initialize(@repo_root : Path = Path.new("."), @check_hook_in_ci : Bool = false)
      @issues = [] of DoctorIssue
    end

    def run : Array(DoctorIssue)
      @issues.clear
      check_git
      check_hook
      check_versions
      check_changelog
      check_badges
      @issues
    end

    def fix : Int32
      fixed_count = 0
      @issues.each do |issue|
        if issue.fixable && (action = issue.fix_action)
          action.call
          fixed_count += 1
        end
      end
      fixed_count
    end

    private def check_git
      git = VCS::Git.new(@repo_root)
      unless git.initialized?
        @issues << DoctorIssue.new("VCS", "Git repository is not initialized", fixable: false)
        return
      end

      if git.dirty?
        @issues << DoctorIssue.new("VCS", "Working directory has uncommitted or untracked changes", fixable: false)
      end
    end

    private def check_hook
      git = VCS::Git.new(@repo_root)
      return unless git.initialized?
      return if ENV["CI"]? == "true" && !@check_hook_in_ci

      unless HookManager.installed?(@repo_root)
        @issues << DoctorIssue.new(
          "Hooks",
          "Carbon pre-commit hook is not installed in .git/hooks/pre-commit",
          fixable: true,
          fix_action: -> { HookManager.install(@repo_root); nil }
        )
      end
    end

    private def check_versions
      shard_yml = @repo_root.join("shard.yml")
      unless File.exists?(shard_yml)
        @issues << DoctorIssue.new(
          "Manifest",
          "shard.yml does not exist",
          fixable: true,
          fix_action: -> { FileManager.ensure_shard_yml(shard_yml); nil }
        )
        return
      end

      shard_ver = FileManager.read_shard_version(shard_yml)
      if shard_ver.nil?
        @issues << DoctorIssue.new("Manifest", "shard.yml has missing or invalid version field", fixable: false)
        return
      end

      git = VCS::Git.new(@repo_root)
      if git.initialized?
        commit_count = git.commit_count
        if shard_ver.commit < commit_count
          @issues << DoctorIssue.new(
            "Version",
            "shard.yml commit count (#{shard_ver.commit}) is behind Git HEAD commits (#{commit_count})",
            fixable: true,
            fix_action: -> { Carbon.sync!(@repo_root); nil }
          )
        end
      end

      # Check version.cr parity
      src_dir = @repo_root.join("src")
      if Dir.exists?(src_dir)
        Dir.glob(src_dir.join("**", "version.cr").to_posix.to_s).each do |vfile|
          p = Path.new(vfile)
          content = File.read(p)
          if match = FileManager::CRYSTAL_VERSION_REGEX.match(content)
            cr_ver_str = match[3].strip
            if cr_ver_str != shard_ver.to_s
              @issues << DoctorIssue.new(
                "Version",
                "#{p.relative_to(@repo_root)} version (#{cr_ver_str}) differs from shard.yml (#{shard_ver})",
                fixable: true,
                fix_action: -> { FileManager.update_crystal_version_file(p, shard_ver); nil }
              )
            end
          end
        end
      end
    end

    private def check_changelog
      yaml_file = Changelog::Manager.yaml_path(@repo_root)
      md_file = @repo_root.join("CHANGELOG.md")

      unless File.exists?(yaml_file)
        @issues << DoctorIssue.new(
          "Changelog",
          "changelog.yml is missing",
          fixable: true,
          fix_action: -> { Changelog::Manager.sync(@repo_root); nil }
        )
        return
      end

      unless File.exists?(md_file)
        @issues << DoctorIssue.new(
          "Changelog",
          "CHANGELOG.md is not compiled",
          fixable: true,
          fix_action: -> { Changelog::Manager.compile(Changelog::Manager.load(@repo_root), @repo_root); nil }
        )
      end
    end

    private def check_badges
      return unless Badges::Manager.configured?(@repo_root)

      res = Badges::Manager.check(@repo_root)
      unless res[:synced]
        @issues << DoctorIssue.new(
          "Badges",
          res[:message],
          fixable: true,
          fix_action: -> { Badges::Manager.sync(@repo_root, inject_if_missing: true); nil }
        )
      end
    end
  end
end
