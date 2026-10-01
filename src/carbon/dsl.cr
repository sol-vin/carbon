require "./version"
require "./vcs/git"
require "./file_manager"
require "./hook_manager"

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

  # Synchronizes shard.yml's commit number with the exact current Git commit count
  def self.sync!(repo_root : Path | String = ".", stage : Bool = false) : Version
    root = Path.new(repo_root)
    git = VCS::Git.new(root)
    curr = current(root)
    actual_commits = git.commit_count

    synced = curr.bump_commit(actual_commits)
    FileManager.update_shard_version(root.join("shard.yml"), synced)

    if stage && git.initialized?
      git.stage(["shard.yml"])
    end

    synced
  end

  # Bumps the version.
  # For :commit (e.g. pre-commit hook), next_commit is calculated as current commit_count + 1
  def self.bump!(
    type : BumpType = BumpType::Commit,
    repo_root : Path | String = ".",
    stage : Bool = false,
  ) : Version
    root = Path.new(repo_root)
    git = VCS::Git.new(root)
    curr = current(root)

    new_version = case type
                  in .commit?
                    target_commits = git.initialized? ? git.commit_count + 1 : curr.commit + 1
                    curr.bump_commit(target_commits)
                  in .minor?
                    curr.bump_minor
                  in .major?
                    curr.bump_major
                  end

    FileManager.update_shard_version(root.join("shard.yml"), new_version)

    if stage && git.initialized?
      git.stage(["shard.yml"])
    end

    new_version
  end

  # Sets major and minor version numbers explicitly while keeping commit count in sync with Git
  def self.set(
    major : Int32,
    minor : Int32,
    repo_root : Path | String = ".",
    stage : Bool = false,
  ) : Version
    root = Path.new(repo_root)
    git = VCS::Git.new(root)
    curr = current(root)

    commits = git.initialized? ? git.commit_count : curr.commit
    new_version = Version.new(major, minor, commits, curr.prerelease, curr.build_metadata)

    FileManager.update_shard_version(root.join("shard.yml"), new_version)

    if stage && git.initialized?
      git.stage(["shard.yml"])
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
      synced = diff == 0
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
