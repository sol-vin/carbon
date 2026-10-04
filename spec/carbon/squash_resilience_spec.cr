require "../spec_helper"

describe "Carbon Squash Resilience & Huge Commit Numbers" do
  it "monotonically increments commit number even when Git history is squashed to fewer commits" do
    with_temp_git_repo do |dir|
      # Simulate a repository where previous commits were squashed into 1 commit,
      # but shard.yml was at 0.1.24
      File.write(dir.join("shard.yml"), "name: demo\nversion: 0.1.24\n")
      File.write(dir.join("app.cr"), "puts 1\n")
      Process.run("git", ["add", "."], chdir: dir.to_s)
      Process.run("git", ["commit", "-m", "squashed milestone commit"], chdir: dir.to_s)

      # Git commit count is 1, but shard.yml is at 0.1.24
      vcs = Carbon::VCS::Git.new(dir)
      vcs.commit_count.should eq(1)

      # Bump for next commit
      new_ver = Carbon.bump!(Carbon::BumpType::Commit, repo_root: dir)

      # Must bump to 25, NOT 2!
      new_ver.should eq(Carbon::Version.new(0, 1, 25))
      Carbon::FileManager.read_shard_version(dir.join("shard.yml")).should eq(Carbon::Version.new(0, 1, 25))
    end
  end

  it "supports arbitrary huge commit numbers in Carbon.set" do
    with_temp_dir do |dir|
      File.write(dir.join("shard.yml"), "name: demo\nversion: 0.1.0\n")

      new_ver = Carbon.set(0, 1, commit: 50000, repo_root: dir)
      new_ver.should eq(Carbon::Version.new(0, 1, 50000))
      Carbon::FileManager.read_shard_version(dir.join("shard.yml")).should eq(Carbon::Version.new(0, 1, 50000))
    end
  end

  it "resets commit to 0 when bumping minor version" do
    with_temp_dir do |dir|
      File.write(dir.join("shard.yml"), "name: demo\nversion: 0.1.271\n")

      new_ver = Carbon.bump!(Carbon::BumpType::Minor, repo_root: dir, reset_commit: true)
      new_ver.should eq(Carbon::Version.new(0, 2, 0))
      Carbon::FileManager.read_shard_version(dir.join("shard.yml")).should eq(Carbon::Version.new(0, 2, 0))
    end
  end

  it "allows setting explicit commit count via CLI carbon set <major.minor.commit>" do
    bin_name = HostPlatform.windows? ? "carbon.exe" : "carbon"
    bin_path = Path.new(__DIR__, "..", "..", "bin", bin_name).expand.to_s

    # Ensure binary exists
    unless File.exists?(bin_path)
      Process.run("shards", ["build", "carbon"], chdir: Path.new(__DIR__, "..", "..").to_s)
    end

    with_temp_dir do |dir|
      File.write(dir.join("shard.yml"), "name: demo\nversion: 0.0.4\n")

      status = Process.run(bin_path, ["set", "0.1.295"], chdir: dir.to_s)
      status.success?.should be_true
      Carbon::FileManager.read_shard_version(dir.join("shard.yml")).should eq(Carbon::Version.new(0, 1, 295))
    end
  end
end
