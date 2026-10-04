require "../spec_helper"

describe Carbon::HookManager do
  it "installs pre-commit hook into a fresh Git repository" do
    with_temp_git_repo do |dir|
      Carbon::HookManager.installed?(dir).should be_false

      Carbon::HookManager.install(dir).should be_true
      Carbon::HookManager.installed?(dir).should be_true

      hook_path = Carbon::HookManager.hook_path(dir)
      File.exists?(hook_path).should be_true

      content = File.read(hook_path)
      content.includes?(Carbon::HookManager::START_DELIMITER).should be_true
      content.includes?(Carbon::HookManager::END_DELIMITER).should be_true
      content.includes?("carbon bump --hook").should be_true
    end
  end

  it "is idempotent and does not duplicate hook blocks on re-installation" do
    with_temp_git_repo do |dir|
      Carbon::HookManager.install(dir).should be_true
      Carbon::HookManager.install(dir).should be_true

      hook_path = Carbon::HookManager.hook_path(dir)
      content = File.read(hook_path)

      # Should only contain exactly one start delimiter
      content.scan(Regex.new(Regex.escape(Carbon::HookManager::START_DELIMITER))).size.should eq(1)
    end
  end

  it "preserves existing user scripts when installing" do
    with_temp_git_repo do |dir|
      hook_path = Carbon::HookManager.hook_path(dir)
      Dir.mkdir_p(hook_path.parent)
      File.write(hook_path, "#!/bin/sh\necho 'running lint checks'\n")

      Carbon::HookManager.install(dir).should be_true

      content = File.read(hook_path)
      content.includes?("echo 'running lint checks'").should be_true
      content.includes?(Carbon::HookManager::START_DELIMITER).should be_true
    end
  end

  it "uninstalls only the managed Carbon block and preserves remaining user scripts" do
    with_temp_git_repo do |dir|
      hook_path = Carbon::HookManager.hook_path(dir)
      Dir.mkdir_p(hook_path.parent)
      File.write(hook_path, "#!/bin/sh\necho 'custom hook'\n")

      Carbon::HookManager.install(dir).should be_true
      Carbon::HookManager.installed?(dir).should be_true

      Carbon::HookManager.uninstall(dir).should be_true
      Carbon::HookManager.installed?(dir).should be_false

      File.exists?(hook_path).should be_true
      content = File.read(hook_path)
      content.includes?("echo 'custom hook'").should be_true
      content.includes?(Carbon::HookManager::START_DELIMITER).should be_false
    end
  end

  it "installs and uninstalls post-merge hook for automated sync" do
    with_temp_git_repo do |dir|
      Carbon::HookManager.installed?(dir, hook_name: "post-merge").should be_false

      Carbon::HookManager.install(dir, hook_name: "post-merge").should be_true
      Carbon::HookManager.installed?(dir, hook_name: "post-merge").should be_true

      hook_path = Carbon::HookManager.hook_path(dir, hook_name: "post-merge")
      File.exists?(hook_path).should be_true
      content = File.read(hook_path)
      content.includes?("carbon sync").should be_true

      Carbon::HookManager.uninstall(dir, hook_name: "post-merge").should be_true
      Carbon::HookManager.installed?(dir, hook_name: "post-merge").should be_false
    end
  end
end
