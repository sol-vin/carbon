require "../spec_helper"

describe Carbon::Doctor do
  it "detects uninstalled hook and repairs it with fix" do
    with_temp_git_repo do |dir|
      File.write(dir.join("shard.yml"), "name: app\nversion: 0.1.0\n")

      doc = Carbon::Doctor.new(dir)
      issues = doc.run

      hook_issue = issues.find { |i| i.category == "Hooks" }
      hook_issue.should_not be_nil
      hook_issue.not_nil!.fixable.should be_true

      # Run fix
      fixed_count = doc.fix
      fixed_count.should be > 0

      # Re-audit
      doc.run.any? { |i| i.category == "Hooks" }.should be_false
      Carbon::HookManager.installed?(dir).should be_true
    end
  end

  it "detects version parity between shard.yml and Git commit count" do
    with_temp_git_repo do |dir|
      File.write(dir.join("shard.yml"), "name: app\nversion: 0.1.10\n")
      # Repo has 0 commits, so 0.1.10 is out of sync

      doc = Carbon::Doctor.new(dir)
      issues = doc.run

      ver_issue = issues.find { |i| i.category == "Version" }
      ver_issue.should_not be_nil

      doc.fix
      Carbon::FileManager.read_shard_version(dir.join("shard.yml")).should eq(Carbon::Version.new(0, 1, 0))
    end
  end

  it "detects and repairs out-of-sync badges in README.md" do
    with_temp_git_repo do |dir|
      File.write(dir.join("shard.yml"), "name: app\nversion: 0.1.0\nlicense: MIT\n")
      readme = dir.join("README.md")
      File.write(readme, <<-MD
      # App

      <!-- carbon:badges -->
      [![Version](https://img.shields.io/badge/version-0.0.1-blue.svg)](shard.yml)
      <!-- /carbon:badges -->
      MD
      )

      doc = Carbon::Doctor.new(dir)
      issues = doc.run

      badge_issue = issues.find { |i| i.category == "Badges" }
      badge_issue.should_not be_nil
      badge_issue.not_nil!.fixable.should be_true

      # Repair
      doc.fix

      # Re-audit
      doc.run.any? { |i| i.category == "Badges" }.should be_false
      File.read(readme).includes?("version-0.1.0-blue.svg").should be_true
    end
  end
end
