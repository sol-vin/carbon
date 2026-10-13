require "../spec_helper"

describe Carbon::Hooks do
  describe Carbon::Hooks::HookType do
    it "parses hook names correctly" do
      Carbon::Hooks::HookType.parse("pre-commit").should eq(Carbon::Hooks::HookType::PreCommit)
      Carbon::Hooks::HookType.parse("post-merge").should eq(Carbon::Hooks::HookType::PostMerge)
      Carbon::Hooks::HookType.parse("post-checkout").should eq(Carbon::Hooks::HookType::PostCheckout)
      Carbon::Hooks::HookType.parse("pre-push").should eq(Carbon::Hooks::HookType::PrePush)
      Carbon::Hooks::HookType.parse("pre_commit").should eq(Carbon::Hooks::HookType::PreCommit)
      Carbon::Hooks::HookType.parse?("invalid").should be_nil
    end

    it "provides filenames and default commands" do
      Carbon::Hooks::HookType::PreCommit.filename.should eq("pre-commit")
      Carbon::Hooks::HookType::PreCommit.default_command.should eq("bump --hook")

      Carbon::Hooks::HookType::PostMerge.filename.should eq("post-merge")
      Carbon::Hooks::HookType::PostMerge.default_command.should eq("sync")

      Carbon::Hooks::HookType::PostCheckout.filename.should eq("post-checkout")
      Carbon::Hooks::HookType::PostCheckout.default_command.should eq("sync")

      Carbon::Hooks::HookType::PrePush.filename.should eq("pre-push")
      Carbon::Hooks::HookType::PrePush.default_command.should eq("check")
    end

    it "identifies standard hooks suite" do
      Carbon::Hooks::HookType.standard_hooks.should eq([
        Carbon::Hooks::HookType::PreCommit,
        Carbon::Hooks::HookType::PostMerge,
      ])
    end
  end

  describe Carbon::Hooks::HookTemplate do
    it "renders pre-commit hook script with fallback chains" do
      rendered = Carbon::Hooks::HookTemplate.pre_commit
      rendered.includes?(Carbon::Hooks::HookTemplate::START_DELIMITER).should be_true
      rendered.includes?(Carbon::Hooks::HookTemplate::END_DELIMITER).should be_true
      rendered.includes?("bump --hook").should be_true
      rendered.includes?("./bin/carbon bump --hook").should be_true
      rendered.includes?("crystal run lib/carbon/src/carbon/cli.cr -- bump --hook").should be_true
    end

    it "renders post-merge hook script with sync command" do
      rendered = Carbon::Hooks::HookTemplate.post_merge
      rendered.includes?("carbon sync").should be_true
    end

    it "supports custom commands in templates" do
      template = Carbon::Hooks::HookTemplate.new(Carbon::Hooks::HookType::PreCommit, command: "bump --major")
      rendered = template.render
      rendered.includes?("carbon bump --major").should be_true
    end
  end

  describe Carbon::Hooks::HookInstaller do
    it "installs standard hooks suite idempotently" do
      with_temp_git_repo do |dir|
        installer = Carbon::Hooks::HookInstaller.new(dir)
        installer.installed?(Carbon::Hooks::HookType::PreCommit).should be_false
        installer.installed?(Carbon::Hooks::HookType::PostMerge).should be_false

        installed = installer.install_standard
        installed.should eq(Carbon::Hooks::HookType.standard_hooks)

        installer.installed?(Carbon::Hooks::HookType::PreCommit).should be_true
        installer.installed?(Carbon::Hooks::HookType::PostMerge).should be_true

        # Verify HookStatus reports
        st_pre = installer.status(Carbon::Hooks::HookType::PreCommit)
        st_pre.installed?.should be_true
        st_pre.has_foreign_scripts?.should be_false
        st_pre.active_command.should eq("bump --hook")

        st_post = installer.status(Carbon::Hooks::HookType::PostMerge)
        st_post.installed?.should be_true
        st_post.active_command.should eq("sync")
      end
    end

    it "uninstalls all managed hooks cleanly" do
      with_temp_git_repo do |dir|
        installer = Carbon::Hooks::HookInstaller.new(dir)
        installer.install_all

        installer.installed?(Carbon::Hooks::HookType::PreCommit).should be_true
        installer.installed?(Carbon::Hooks::HookType::PostMerge).should be_true
        installer.installed?(Carbon::Hooks::HookType::PostCheckout).should be_true
        installer.installed?(Carbon::Hooks::HookType::PrePush).should be_true

        removed = installer.uninstall_all
        removed.size.should eq(4)

        installer.installed?(Carbon::Hooks::HookType::PreCommit).should be_false
        installer.installed?(Carbon::Hooks::HookType::PostMerge).should be_false
      end
    end
  end

  describe Carbon::Hooks::Builder do
    it "implements the Two-Tier Declarative Builder pattern" do
      with_temp_git_repo do |dir|
        builder = Carbon::Hooks::Builder.new(dir)
        builder
          .enable(:pre_commit)
          .enable(:post_merge)

        installed = builder.apply
        installed.size.should eq(2)

        installer = Carbon::Hooks::HookInstaller.new(dir)
        installer.installed?(Carbon::Hooks::HookType::PreCommit).should be_true
        installer.installed?(Carbon::Hooks::HookType::PostMerge).should be_true
      end
    end

    it "supports Carbon.hooks block DSL directly" do
      with_temp_git_repo do |dir|
        installed = Carbon.hooks(dir) do |h|
          h.standard
          h.enable(:pre_push)
        end

        installed.size.should eq(3)

        installer = Carbon::Hooks::HookInstaller.new(dir)
        installer.installed?(Carbon::Hooks::HookType::PreCommit).should be_true
        installer.installed?(Carbon::Hooks::HookType::PostMerge).should be_true
        installer.installed?(Carbon::Hooks::HookType::PrePush).should be_true
      end
    end
  end

  describe Carbon::Hooks::HookStandardizer do
    it "standardizes hooks on a single repo" do
      with_temp_git_repo do |dir|
        File.write(dir.join("shard.yml"), "name: test_repo\nversion: 0.1.0\n")

        report = Carbon::Hooks::HookStandardizer.standardize_repo(dir)
        report.is_git_repo?.should be_true
        report.has_shard_yml?.should be_true
        report.installed_hooks.should eq(Carbon::Hooks::HookType.standard_hooks)
        report.fully_standardized?.should be_true
      end
    end

    it "standardizes hooks across multiple sibling repositories" do
      with_temp_dir do |parent|
        # Create 2 repo subdirs
        repo1 = parent.join("repo_alpha")
        repo2 = parent.join("repo_beta")

        Dir.mkdir_p(repo1)
        Dir.mkdir_p(repo2)

        Process.run("git", ["init"], chdir: repo1.to_s)
        Process.run("git", ["init"], chdir: repo2.to_s)

        File.write(repo1.join("shard.yml"), "name: repo_alpha\nversion: 0.1.0\n")
        File.write(repo2.join("shard.yml"), "name: repo_beta\nversion: 0.1.0\n")

        reports = Carbon::Hooks::HookStandardizer.standardize_all(parent)
        reports.size.should eq(2)
        reports.all?(&.fully_standardized?).should be_true

        # Verify hooks exist in both
        installer1 = Carbon::Hooks::HookInstaller.new(repo1)
        installer2 = Carbon::Hooks::HookInstaller.new(repo2)

        installer1.installed?(Carbon::Hooks::HookType::PreCommit).should be_true
        installer1.installed?(Carbon::Hooks::HookType::PostMerge).should be_true
        installer2.installed?(Carbon::Hooks::HookType::PreCommit).should be_true
        installer2.installed?(Carbon::Hooks::HookType::PostMerge).should be_true
      end
    end
  end
end
