require "./version"
require "./vcs/git"
require "./file_manager"
require "./hook_manager"
require "./changelog/manager"

module Carbon
  enum BumpType
    Commit
    Minor
    Major
  end

  # Returns the current version parsed from shard.yml, or derived from Git
  def self.current(repo_root : Path | String = ".") : Version
    root = Path.new(repo_root)
    shard_path = root.join("shard.yml")

    if ver = FileManager.read_shard_version(shard_path)
      ver
    else
      git = VCS::Git.new(root)
      Version.new(0, 1, git.commit_count)
    end
  end

  # Synchronizes all target files with the Git commit count (preserving monotonic count unless force: true)
  def self.sync!(repo_root : Path | String = ".", stage : Bool = false, force : Bool = false) : Version
    root = Path.new(repo_root)
    git = VCS::Git.new(root)
    curr = current(root)
    actual_commits = git.commit_count

    # If force is true, strictly force to git commit count; otherwise preserve monotonic count
    synced_commits = force ? actual_commits : Math.max(actual_commits, curr.commit)
    synced = curr.bump_commit(synced_commits)
    updated_files = FileManager.sync_all_targets(synced, root)

    # Sync changelog if present
    if File.exists?(Changelog::Manager.yaml_path(root))
      Changelog::Manager.sync(root, version_override: synced.to_s)
      updated_files << Changelog::Manager.yaml_path(root)
      updated_files << root.join("CHANGELOG.md")
    end

    # Sync badges if present or configured
    if Badges::Manager.configured?(root)
      if badge_target = Badges::Manager.sync(root, version_override: synced.to_s)
        updated_files << badge_target
      end
    end

    if stage && git.initialized? && !updated_files.empty?
      git.stage(updated_files.map(&.to_s))
    end

    synced
  end

  # Bumps the version and updates all target files
  def self.bump!(
    type : BumpType = BumpType::Commit,
    repo_root : Path | String = ".",
    stage : Bool = false,
    reset_commit : Bool = false,
  ) : Version
    root = Path.new(repo_root)
    git = VCS::Git.new(root)
    curr = current(root)

    new_version = case type
                  in .commit?
                    # Squash-resilient: commit number monotonically increases and never decreases even if Git history was squashed.
                    head_commit = 0
                    if git.initialized? && git.commit_count > 0
                      if head_shard = git.show_file(root.join("shard.yml"))
                        if head_ver = FileManager.parse_shard_version(head_shard)
                          head_commit = head_ver.commit
                        end
                      end
                    end

                    target_commits = if git.initialized?
                                       base = Math.max(git.commit_count, head_commit)
                                       if curr.commit > base
                                         curr.commit == base + 1 ? curr.commit : Math.max(base + 1, curr.commit)
                                       else
                                         base + 1
                                       end
                                     else
                                       curr.commit + 1
                                     end
                    curr.bump_commit(target_commits)
                  in .minor?
                    curr.bump_minor(reset_commit: reset_commit)
                  in .major?
                    curr.bump_major(reset_commit: reset_commit)
                  end

    updated_files = FileManager.sync_all_targets(new_version, root)

    # Sync changelog if present
    if File.exists?(Changelog::Manager.yaml_path(root))
      Changelog::Manager.sync(root, version_override: new_version.to_s)
      updated_files << Changelog::Manager.yaml_path(root)
      updated_files << root.join("CHANGELOG.md")
    end

    # Sync badges if present or configured
    if Badges::Manager.configured?(root)
      if badge_target = Badges::Manager.sync(root, version_override: new_version.to_s)
        updated_files << badge_target
      end
    end

    if stage && git.initialized? && !updated_files.empty?
      git.stage(updated_files.map(&.to_s))
    end

    new_version
  end

  # Sets major and minor version numbers explicitly across all targets (legacy signature)
  def self.set(
    major : Int32,
    minor : Int32,
    repo_root : Path | String,
    stage : Bool = false,
  ) : Version
    set(major, minor, commit: nil, repo_root: repo_root, stage: stage)
  end

  # Sets major and minor (and optionally commit) version numbers explicitly across all targets
  def self.set(
    major : Int32,
    minor : Int32,
    commit : Int32? = nil,
    repo_root : Path | String = ".",
    stage : Bool = false,
  ) : Version
    root = Path.new(repo_root)
    git = VCS::Git.new(root)
    curr = current(root)

    target_commit = if explicit = commit
                      explicit
                    elsif git.initialized?
                      Math.max(git.commit_count, curr.commit)
                    else
                      curr.commit
                    end

    new_version = Version.new(major, minor, target_commit, curr.prerelease, curr.build_metadata)

    updated_files = FileManager.sync_all_targets(new_version, root)

    # Sync changelog if present
    if File.exists?(Changelog::Manager.yaml_path(root))
      Changelog::Manager.sync(root, version_override: new_version.to_s)
      updated_files << Changelog::Manager.yaml_path(root)
      updated_files << root.join("CHANGELOG.md")
    end

    # Sync badges if present or configured
    if Badges::Manager.configured?(root)
      if badge_target = Badges::Manager.sync(root, version_override: new_version.to_s)
        updated_files << badge_target
      end
    end

    if stage && git.initialized? && !updated_files.empty?
      git.stage(updated_files.map(&.to_s))
    end

    new_version
  end

  # Checks if shard.yml commit number matches current Git commit count
  def self.check(repo_root : Path | String = ".") : NamedTuple(
    synced: Bool,
    shard_version: Version?,
    git_commits: Int32,
    diff: Int32)
    root = Path.new(repo_root)
    git = VCS::Git.new(root)
    shard_ver = FileManager.read_shard_version(root.join("shard.yml"))
    git_commits = git.initialized? ? git.commit_count : 0

    if shard_ver
      diff = shard_ver.commit - git_commits
      # Synced if matches or monotonically ahead due to squashed history
      synced = diff >= 0
      {synced: synced, shard_version: shard_ver, git_commits: git_commits, diff: diff}
    else
      {synced: false, shard_version: nil, git_commits: git_commits, diff: -git_commits}
    end
  end

  # Declarative compile-time macro to define VERSION constants inside any module or class
  macro version!(path = "shard.yml")
    {% begin %}
      {%
        raw = read_file?("#{__DIR__}/" + path) ||
              read_file?("#{__DIR__}/../" + path) ||
              read_file?("#{__DIR__}/../../" + path) ||
              read_file?("#{__DIR__}/../../../" + path)

        ver_str = "0.1.0"
      %}
      {% if raw %}
        {% for line in raw.split("\n") %}
          {% if line.strip.starts_with?("version:") %}
            {%
              colon_parts = line.strip.split(":")
              if colon_parts.size > 1
                val = colon_parts[1].strip.split("#")[0].strip
                ver_str = val.gsub(/["']/, "").strip
              end
            %}
          {% end %}
        {% end %}
      {% end %}
      {%
        parts = ver_str.split(".")
        maj = parts[0] ? parts[0].to_i : 0
        min = parts[1] ? parts[1].to_i : 0
        com_str = parts[2] ? parts[2].split("-")[0].split("+")[0] : "0"
        com = com_str.to_i
      %}

      VERSION = {{ ver_str }}
      MAJOR_VERSION = {{ maj }}
      MINOR_VERSION = {{ min }}
      COMMIT_VERSION = {{ com }}

      def self.version : String
        VERSION
      end

      def self.carbon_version : Carbon::Version
        Carbon::Version.new({{ maj }}, {{ min }}, {{ com }})
      end
    {% end %}
  end
end
