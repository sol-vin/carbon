require "./vcs/git"
require "./hooks"

module Carbon
  # Manages Git lifecycle hooks, delegating to the Hooks engine and providing ergonomic class methods
  class HookManager
    START_DELIMITER = Hooks::HookTemplate::START_DELIMITER
    END_DELIMITER   = Hooks::HookTemplate::END_DELIMITER

    HOOK_BODY            = Hooks::HookTemplate.pre_commit
    POST_MERGE_HOOK_BODY = Hooks::HookTemplate.post_merge

    # Renders the hook script body for a given hook name
    def self.hook_body(hook_name : String = "pre-commit") : String
      if type = Hooks::HookType.parse?(hook_name)
        Hooks::HookTemplate.new(type).render
      else
        hook_name == "post-merge" ? POST_MERGE_HOOK_BODY : HOOK_BODY
      end
    end

    # Returns the absolute or relative Path for a hook in a repo
    def self.hook_path(repo_root : Path | String = ".", hook_name : String = "pre-commit") : Path
      Hooks::HookInstaller.new(repo_root).hook_path(hook_name)
    end

    # Returns true if the specified hook is installed with Carbon's managed block
    def self.installed?(repo_root : Path | String = ".", hook_name : String = "pre-commit") : Bool
      Hooks::HookInstaller.new(repo_root).installed?(hook_name)
    end

    # Inspects the detailed status of a specific hook
    def self.status(repo_root : Path | String = ".", hook_name : String = "pre-commit") : Hooks::HookStatus
      type = Hooks::HookType.parse(hook_name)
      Hooks::HookInstaller.new(repo_root).status(type)
    end

    # Inspects status for all supported hooks
    def self.status_all(repo_root : Path | String = ".") : Array(Hooks::HookStatus)
      Hooks::HookInstaller.new(repo_root).status_all
    end

    # Inspects status for standard hooks (pre-commit & post-merge)
    def self.status_standard(repo_root : Path | String = ".") : Array(Hooks::HookStatus)
      Hooks::HookInstaller.new(repo_root).status_standard
    end

    # Installs or updates a managed hook non-destructively
    def self.install(repo_root : Path | String = ".", hook_name : String = "pre-commit") : Bool
      Hooks::HookInstaller.new(repo_root).install(hook_name)
    end

    # Installs the standard suite of hooks (pre-commit & post-merge)
    def self.install_standard(repo_root : Path | String = ".") : Array(Hooks::HookType)
      Hooks::HookInstaller.new(repo_root).install_standard
    end

    # Installs all supported hooks
    def self.install_all(repo_root : Path | String = ".") : Array(Hooks::HookType)
      Hooks::HookInstaller.new(repo_root).install_all
    end

    # Safely removes Carbon's managed block from a hook script
    def self.uninstall(repo_root : Path | String = ".", hook_name : String = "pre-commit") : Bool
      Hooks::HookInstaller.new(repo_root).uninstall(hook_name)
    end

    # Removes Carbon's managed blocks from all supported hooks
    def self.uninstall_all(repo_root : Path | String = ".") : Array(Hooks::HookType)
      Hooks::HookInstaller.new(repo_root).uninstall_all
    end

    # Standardizes hooks on a single repository
    def self.standardize_repo(repo_root : Path | String = ".") : Hooks::RepoStandardizeReport
      Hooks::HookStandardizer.standardize_repo(repo_root)
    end

    # Standardizes hooks across all sibling repositories in a parent directory
    def self.standardize_all(parent_dir : Path | String = "..") : Array(Hooks::RepoStandardizeReport)
      Hooks::HookStandardizer.standardize_all(parent_dir)
    end
  end
end
