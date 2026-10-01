require "../spec_helper"

describe Carbon::VCS do
  describe Carbon::VCS::Mock do
    it "implements base VCS interface" do
      mock = Carbon::VCS::Mock.new(commit_count: 42, branch_name: "feature")
      mock.commit_count.should eq(42)
      mock.branch_name.should eq("feature")
      mock.dirty?.should be_false

      mock.stage(["shard.yml"]).should be_true
      mock.staged_files.should eq(["shard.yml"])
    end
  end

  describe Carbon::VCS::Git do
    it "accurately measures commit counts and staging in a live Git repo" do
      with_temp_git_repo do |dir|
        git = Carbon::VCS::Git.new(dir)
        git.initialized?.should be_true

        # Initial repository has 0 commits
        git.commit_count.should eq(0)
        git.head_hash.should be_nil

        # Create first commit
        test_file = dir.join("README.md")
        File.write(test_file, "# Hello Carbon")
        git.stage(["README.md"]).should be_true
        Process.run("git", ["commit", "-m", "first commit"], chdir: dir.to_s)

        git.commit_count.should eq(1)
        git.head_hash.should_not be_nil

        # Create second commit
        File.write(test_file, "# Hello Carbon\nLine 2")
        git.stage(["README.md"]).should be_true
        Process.run("git", ["commit", "-m", "second commit"], chdir: dir.to_s)

        git.commit_count.should eq(2)
      end
    end

    it "handles uninitialized directory gracefully" do
      with_temp_dir do |dir|
        git = Carbon::VCS::Git.new(dir)
        git.initialized?.should be_false
        git.commit_count.should eq(0)
      end
    end
  end
end
