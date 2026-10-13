require "./type"
require "./status"
require "./installer"

module Carbon
  module Hooks
    # Audit and execution report for a repository undergoing hook standardization
    struct RepoStandardizeReport
      getter repo_name : String
      getter repo_path : Path
      getter? is_git_repo : Bool
      getter? has_shard_yml : Bool
      getter installed_hooks : Array(HookType)
      getter status_before : Array(HookStatus)
      getter status_after : Array(HookStatus)
      getter error : String?

      def initialize(
        @repo_name : String,
        @repo_path : Path,
        @is_git_repo : Bool,
        @has_shard_yml : Bool,
        @installed_hooks : Array(HookType),
        @status_before : Array(HookStatus),
        @status_after : Array(HookStatus),
        @error : String? = nil,
      )
      end

      # Returns true if all requested hooks are fully active after standardization
      def fully_standardized? : Bool
        return false unless @is_git_repo
        @status_after.all?(&.installed?)
      end
    end

    # Orchestrates automated hook discovery, auditing, and standardization across repositories
    class HookStandardizer
      # Scans standard hook statuses for a single repository
      def self.scan_repo(repo_path : Path | String, hooks : Array(HookType) = HookType.standard_hooks) : Array(HookStatus)
        installer = HookInstaller.new(repo_path)
        hooks.map { |type| installer.status(type) }
      end

      # Standardizes hooks in a single repository
      def self.standardize_repo(
        repo_path : Path | String,
        hooks : Array(HookType) = HookType.standard_hooks
      ) : RepoStandardizeReport
        path = Path.new(repo_path)
        name = path.basename
        git = VCS::Git.new(path)
        is_git = git.initialized?
        has_shard = File.exists?(path.join("shard.yml"))

        unless is_git
          return RepoStandardizeReport.new(
            repo_name: name,
            repo_path: path,
            is_git_repo: false,
            has_shard_yml: has_shard,
            installed_hooks: [] of HookType,
            status_before: [] of HookStatus,
            status_after: [] of HookStatus,
            error: "Not a git repository"
          )
        end

        installer = HookInstaller.new(path)
        before_statuses = hooks.map { |h| installer.status(h) }
        installed = [] of HookType

        hooks.each do |hook_type|
          if installer.install(hook_type)
            installed << hook_type
          end
        end

        after_statuses = hooks.map { |h| installer.status(h) }

        RepoStandardizeReport.new(
          repo_name: name,
          repo_path: path,
          is_git_repo: true,
          has_shard_yml: has_shard,
          installed_hooks: installed,
          status_before: before_statuses,
          status_after: after_statuses
        )
      end

      # Discovers all Git repositories in a directory and standardizes their hooks
      def self.standardize_all(
        parent_dir : Path | String,
        hooks : Array(HookType) = HookType.standard_hooks
      ) : Array(RepoStandardizeReport)
        p = Path.new(parent_dir)
        reports = [] of RepoStandardizeReport
        return reports unless Dir.exists?(p)

        Dir.each_child(p) do |child|
          child_path = p.join(child)
          next unless Dir.exists?(child_path)

          # Only evaluate directories that contain a .git directory or file (worktree/submodule)
          git_entry = child_path.join(".git")
          if Dir.exists?(git_entry) || File.exists?(git_entry)
            reports << standardize_repo(child_path, hooks)
          end
        end

        reports.sort_by!(&.repo_name)
      end

      # Audits all Git repositories in a directory without altering files
      def self.audit_all(
        parent_dir : Path | String,
        hooks : Array(HookType) = HookType.standard_hooks
      ) : Array(RepoStandardizeReport)
        p = Path.new(parent_dir)
        reports = [] of RepoStandardizeReport
        return reports unless Dir.exists?(p)

        Dir.each_child(p) do |child|
          child_path = p.join(child)
          next unless Dir.exists?(child_path)

          git_entry = child_path.join(".git")
          if Dir.exists?(git_entry) || File.exists?(git_entry)
            installer = HookInstaller.new(child_path)
            statuses = hooks.map { |h| installer.status(h) }
            has_shard = File.exists?(child_path.join("shard.yml"))

            reports << RepoStandardizeReport.new(
              repo_name: child_path.basename,
              repo_path: child_path,
              is_git_repo: true,
              has_shard_yml: has_shard,
              installed_hooks: [] of HookType,
              status_before: statuses,
              status_after: statuses
            )
          end
        end

        reports.sort_by!(&.repo_name)
      end
    end
  end
end
