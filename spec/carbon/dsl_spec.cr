require "../spec_helper"

module SampleApp
  Carbon.version!
end

describe Carbon do
  describe ".version! macro" do
    it "injects VERSION and numeric constants into the calling module" do
      expected = Carbon::FileManager.read_shard_version("shard.yml").not_nil!
      SampleApp::VERSION.should eq(expected.to_s)
      SampleApp::MAJOR_VERSION.should eq(expected.major)
      SampleApp::MINOR_VERSION.should eq(expected.minor)
      SampleApp::COMMIT_VERSION.should eq(expected.commit)

      SampleApp.version.should eq(expected.to_s)
      SampleApp.carbon_version.should eq(expected)
    end
  end

  describe "runtime DSL methods" do
    it "reads current version from shard.yml" do
      with_temp_dir do |dir|
        File.write(dir.join("shard.yml"), "name: app\nversion: 0.3.15\n")
        ver = Carbon.current(dir)
        ver.should eq(Carbon::Version.new(0, 3, 15))
      end
    end

    it "bumps commit count in shard.yml" do
      with_temp_dir do |dir|
        File.write(dir.join("shard.yml"), "name: app\nversion: 0.1.0\n")
        new_ver = Carbon.bump!(Carbon::BumpType::Commit, dir)
        new_ver.should eq(Carbon::Version.new(0, 1, 1))

        read_back = Carbon.current(dir)
        read_back.should eq(Carbon::Version.new(0, 1, 1))
      end
    end

    it "bumps minor version in shard.yml without resetting commit" do
      with_temp_dir do |dir|
        File.write(dir.join("shard.yml"), "name: app\nversion: 0.1.50\n")
        new_ver = Carbon.bump!(Carbon::BumpType::Minor, dir)
        new_ver.should eq(Carbon::Version.new(0, 2, 50))
      end
    end

    it "bumps major version in shard.yml and resets minor" do
      with_temp_dir do |dir|
        File.write(dir.join("shard.yml"), "name: app\nversion: 0.5.120\n")
        new_ver = Carbon.bump!(Carbon::BumpType::Major, dir)
        new_ver.should eq(Carbon::Version.new(1, 0, 120))
      end
    end

    it "sets major and minor versions directly" do
      with_temp_dir do |dir|
        File.write(dir.join("shard.yml"), "name: app\nversion: 0.1.80\n")
        new_ver = Carbon.set(2, 4, dir)
        new_ver.should eq(Carbon::Version.new(2, 4, 80))
      end
    end

    it "checks whether shard.yml is in sync with Git commits" do
      with_temp_git_repo do |dir|
        # Initial commit
        File.write(dir.join("file.txt"), "hello")
        Process.run("git", ["add", "."], chdir: dir.to_s)
        Process.run("git", ["commit", "-m", "first"], chdir: dir.to_s)

        # shard.yml with version 0.1.1 (synced)
        File.write(dir.join("shard.yml"), "name: test\nversion: 0.1.1\n")
        res = Carbon.check(dir)
        res[:synced].should be_true
        res[:git_commits].should eq(1)

        # Add second commit without updating shard.yml (out of sync)
        File.write(dir.join("file.txt"), "hello world")
        Process.run("git", ["add", "."], chdir: dir.to_s)
        Process.run("git", ["commit", "-m", "second"], chdir: dir.to_s)

        res2 = Carbon.check(dir)
        res2[:synced].should be_false
        res2[:git_commits].should eq(2)
        res2[:diff].should eq(-1)

        # Sync
        Carbon.sync!(dir)
        res3 = Carbon.check(dir)
        res3[:synced].should be_true
        res3[:shard_version].not_nil!.should eq(Carbon::Version.new(0, 1, 2))
      end
    end
  end
end
