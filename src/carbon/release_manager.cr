require "./version"
require "./changelog/manager"
require "./vcs/git"

module Carbon
  class ReleaseManager
    # Creates an annotated release tag, seals the changelog, and optionally updates floating latest
    def self.create_tag(
      version : Version | String,
      message : String? = nil,
      floating_latest : Bool = true,
      repo_root : Path | String = ".",
    ) : Bool
      git = VCS::Git.new(repo_root)
      return false unless git.initialized?

      ver_str = version.to_s
      tag_name = ver_str.starts_with?('v') ? ver_str : "v#{ver_str}"
      tag_msg = message || "Release #{tag_name}"

      # 1. Seal changelog
      Changelog::Manager.seal_release(ver_str, repo_root)

      # 2. Stage changelog if modified
      changelog_file = Changelog::Manager.yaml_path(repo_root)
      compiled_md = Path.new(repo_root).join("CHANGELOG.md")
      files_to_stage = [] of String
      files_to_stage << changelog_file.to_s if File.exists?(changelog_file)
      files_to_stage << compiled_md.to_s if File.exists?(compiled_md)
      git.stage(files_to_stage) unless files_to_stage.empty?

      # 3. Create annotated tag
      res = Process.run("git", ["tag", "-a", tag_name, "-m", tag_msg], chdir: repo_root.to_s)
      return false unless res.success?

      # 4. Floating latest tag
      if floating_latest
        Process.run("git", ["tag", "-f", "latest"], chdir: repo_root.to_s)
      end

      true
    end

    # Pushes branch and release tags to remote
    def self.push_release(
      remote : String = "origin",
      version : Version | String? = nil,
      floating_latest : Bool = true,
      repo_root : Path | String = ".",
    ) : Bool
      git = VCS::Git.new(repo_root)
      return false unless git.initialized?

      # Push current branch
      branch = git.branch_name || "main"
      res = Process.run("git", ["push", remote, branch], chdir: repo_root.to_s)
      return false unless res.success?

      # Push version tag
      if ver = version
        ver_str = ver.to_s
        tag_name = ver_str.starts_with?('v') ? ver_str : "v#{ver_str}"
        Process.run("git", ["push", remote, tag_name], chdir: repo_root.to_s)
      end

      # Push floating latest tag
      if floating_latest
        Process.run("git", ["push", "-f", remote, "latest"], chdir: repo_root.to_s)
      end

      true
    end
  end
end
