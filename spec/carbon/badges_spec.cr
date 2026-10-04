require "../spec_helper"

describe Carbon::Badges do
  describe Carbon::Badges::Detector do
    it "detects metadata from shard.yml and repository" do
      with_temp_dir do |dir|
        shard_path = dir.join("shard.yml")
        File.write(shard_path, <<-YAML
        name: test_app
        version: 1.2.3
        crystal: ">= 1.20.0"
        license: MIT
        YAML
        )

        workflows_dir = dir.join(".github", "workflows")
        FileUtils.mkdir_p(workflows_dir)
        File.write(workflows_dir.join("ci.yml"), "name: CI\n")

        docs_dir = dir.join("docs")
        FileUtils.mkdir_p(docs_dir)

        meta = Carbon::Badges::Detector.detect(dir)
        meta.shard_name.should eq("test_app")
        meta.version.should eq("1.2.3")
        meta.crystal_version.should eq(">= 1.20.0")
        meta.license.should eq("MIT")
        meta.ci_workflow.should eq("ci.yml")
      end
    end

    it "parses GitHub slug from various git remote URL formats" do
      Carbon::VCS::Git.parse_github_slug("https://github.com/sol-vin/carbon.git").should eq("sol-vin/carbon")
      Carbon::VCS::Git.parse_github_slug("https://github.com/sol-vin/opal").should eq("sol-vin/opal")
      Carbon::VCS::Git.parse_github_slug("git@github.com:sol-vin/carbon.git").should eq("sol-vin/carbon")
      Carbon::VCS::Git.parse_github_slug("ssh://git@github.com/crystal-lang/crystal.git").should eq("crystal-lang/crystal")
      Carbon::VCS::Git.parse_github_slug("https://gitlab.com/user/repo.git").should be_nil
    end
  end

  describe Carbon::Badges::Builder do
    meta = Carbon::Badges::RepoMetadata.new(
      github_slug: "sol-vin/carbon",
      default_branch: "main",
      ci_workflow: "ci.yml",
      shard_name: "carbon",
      version: "0.1.9",
      crystal_version: ">= 1.20.0",
      license: "MIT",
      docs_url: "https://sol-vin.github.io/carbon/",
      commit_count: 42
    )

    it "properly escapes Shields.io URL paths" do
      Carbon::Badges::Builder.escape_path(">= 1.20.0").should eq("%3E%3D%201.20.0")
      Carbon::Badges::Builder.escape_path("License-MIT").should eq("License--MIT")
      Carbon::Badges::Builder.escape_path("foo_bar").should eq("foo__bar")
    end

    it "builds version badge" do
      cfg = Carbon::Badges::BadgeConfig.new(type: "version")
      badge = Carbon::Badges::Builder.build(cfg, meta)
      badge.should eq("[![Version](https://img.shields.io/badge/version-0.1.9-blue.svg)](https://github.com/sol-vin/carbon/releases)")
    end

    it "builds version badge with override" do
      cfg = Carbon::Badges::BadgeConfig.new(type: "version")
      badge = Carbon::Badges::Builder.build(cfg, meta, version_override: "1.0.0")
      badge.should eq("[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/sol-vin/carbon/releases)")
    end

    it "builds CI badge" do
      cfg = Carbon::Badges::BadgeConfig.new(type: "ci")
      badge = Carbon::Badges::Builder.build(cfg, meta)
      badge.should eq("[![CI](https://github.com/sol-vin/carbon/actions/workflows/ci.yml/badge.svg)](https://github.com/sol-vin/carbon/actions/workflows/ci.yml)")
    end

    it "builds Crystal badge" do
      cfg = Carbon::Badges::BadgeConfig.new(type: "crystal")
      badge = Carbon::Badges::Builder.build(cfg, meta)
      badge.should eq("[![Crystal](https://img.shields.io/badge/crystal-%3E%3D%201.20.0-black.svg)](https://crystal-lang.org)")
    end

    it "builds License badge" do
      cfg = Carbon::Badges::BadgeConfig.new(type: "license")
      badge = Carbon::Badges::Builder.build(cfg, meta)
      badge.should eq("[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)")
    end

    it "builds Docs badge" do
      cfg = Carbon::Badges::BadgeConfig.new(type: "docs")
      badge = Carbon::Badges::Builder.build(cfg, meta)
      badge.should eq("[![Docs](https://img.shields.io/badge/docs-GitHub%20Pages-blue.svg)](https://sol-vin.github.io/carbon/)")
    end

    it "builds Commits badge" do
      cfg = Carbon::Badges::BadgeConfig.new(type: "commits")
      badge = Carbon::Badges::Builder.build(cfg, meta)
      badge.should eq("[![Commits](https://img.shields.io/badge/commits-42-blue.svg)](https://github.com/sol-vin/carbon/commits)")
    end

    it "builds GitHub Release badge" do
      cfg = Carbon::Badges::BadgeConfig.new(type: "github_release")
      badge = Carbon::Badges::Builder.build(cfg, meta)
      badge.should eq("[![Release](https://img.shields.io/github/v/release/sol-vin/carbon)](https://github.com/sol-vin/carbon/releases)")
    end

    it "builds custom Shields.io badge with logo and style" do
      cfg = Carbon::Badges::BadgeConfig.new(
        type: "custom",
        label: "discord",
        message: "join",
        color: "7289da",
        logo: "discord",
        logo_color: "white",
        style: "flat-square",
        url: "https://discord.gg/test"
      )
      badge = Carbon::Badges::Builder.build(cfg, meta)
      badge.should eq("[![discord](https://img.shields.io/badge/discord-join-7289da.svg?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/test)")
    end

    it "builds raw badge snippet verbatim" do
      cfg = Carbon::Badges::BadgeConfig.new(type: "raw", markdown: "[![Asciicast](demo.svg)](demo)")
      badge = Carbon::Badges::Builder.build(cfg, meta)
      badge.should eq("[![Asciicast](demo.svg)](demo)")
    end
  end

  describe Carbon::Badges::Injector do
    it "detects paired tags" do
      content = "<!-- carbon:badges -->\n[![Badge](img)](url)\n<!-- /carbon:badges -->"
      Carbon::Badges::Injector.has_tag?(content).should be_true
      Carbon::Badges::Injector.extract_badges(content).should eq("[![Badge](img)](url)")
    end

    it "detects shorthand paired tags" do
      content = "<!-- badges -->\n[![Badge](img)](url)\n<!-- /badges -->"
      Carbon::Badges::Injector.has_tag?(content).should be_true
      Carbon::Badges::Injector.extract_badges(content).should eq("[![Badge](img)](url)")
    end

    it "detects single unclosed tag" do
      content = "# Project\n\n<!-- carbon:badges -->\n\nDescription"
      Carbon::Badges::Injector.has_tag?(content).should be_true
    end

    it "replaces content inside paired tags idempotently" do
      content = <<-MD
      # My Project

      <!-- carbon:badges -->
      [![Old](old.svg)](old)
      <!-- /carbon:badges -->

      Some description here.
      MD

      new_badges = "[![New1](new1.svg)](new1)\n[![New2](new2.svg)](new2)"
      updated = Carbon::Badges::Injector.render_into(content, new_badges)

      updated.includes?("[![Old](old.svg)](old)").should be_false
      updated.includes?("[![New1](new1.svg)](new1)").should be_true
      updated.includes?("Some description here.").should be_true
      updated.includes?("<!-- carbon:badges -->").should be_true
      updated.includes?("<!-- /carbon:badges -->").should be_true
    end

    it "preserves surrounding HTML tags such as div align=center" do
      content = <<-MD
      <div align="center">

      # [*] Opal

      <!-- carbon:badges -->
      [![Old](old.svg)](old)
      <!-- /carbon:badges -->

      *Subtitle text*

      </div>
      MD

      new_badges = "[![CI](ci.svg)](ci)\n[![Docs](docs.svg)](docs)"
      updated = Carbon::Badges::Injector.render_into(content, new_badges)

      updated.includes?("<div align=\"center\">").should be_true
      updated.includes?("</div>").should be_true
      updated.includes?("*Subtitle text*").should be_true
      updated.includes?("[![CI](ci.svg)](ci)").should be_true
    end

    it "expands single unclosed tag into paired tags" do
      content = "# Title\n\n<!-- carbon:badges -->\n\nBody"
      new_badges = "[![Badge](img)](url)"
      updated = Carbon::Badges::Injector.render_into(content, new_badges)

      updated.includes?("<!-- carbon:badges -->\n[![Badge](img)](url)\n<!-- /carbon:badges -->").should be_true
      updated.includes?("Body").should be_true
    end

    it "injects tag block after H1 header when requested" do
      content = "# My Cool Project\n\nThis is a cool project description."
      new_badges = "[![Version](v.svg)](v)"
      updated = Carbon::Badges::Injector.render_into(content, new_badges, inject_if_missing: true)

      updated.includes?("<!-- carbon:badges -->\n[![Version](v.svg)](v)\n<!-- /carbon:badges -->").should be_true
      updated.includes?("This is a cool project description.").should be_true
    end
  end

  describe Carbon::Badges::Manager do
    it "synchronizes badges to README.md in repository" do
      with_temp_dir do |dir|
        readme = dir.join("README.md")
        File.write(readme, <<-MD
        # Sample Repo

        <!-- carbon:badges -->
        <!-- /carbon:badges -->

        Welcome to sample repo!
        MD
        )

        shard = dir.join("shard.yml")
        File.write(shard, "name: sample\nversion: 0.2.5\nlicense: MIT\n")

        res_path = Carbon::Badges::Manager.sync(dir)
        res_path.should_not be_nil

        updated_content = File.read(readme)
        updated_content.includes?("version-0.2.5-blue.svg").should be_true
        updated_content.includes?("License-MIT-yellow.svg").should be_true
        updated_content.includes?("Welcome to sample repo!").should be_true

        # Verify check reports in sync
        check_res = Carbon::Badges::Manager.check(dir)
        check_res[:synced].should be_true
      end
    end

    it "auto-updates version badge on Carbon.bump!" do
      with_temp_git_repo do |dir|
        readme = dir.join("README.md")
        File.write(readme, <<-MD
        # Bump Test

        <!-- carbon:badges -->
        [![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](shard.yml)
        <!-- /carbon:badges -->
        MD
        )

        shard = dir.join("shard.yml")
        File.write(shard, "name: bump_test\nversion: 0.1.0\n")

        # Bump commit count
        new_v = Carbon.bump!(Carbon::BumpType::Commit, dir)
        new_v.to_s.should eq("0.1.1")

        # Check README.md was automatically updated with new version
        readme_content = File.read(readme)
        readme_content.includes?("version-0.1.1-blue.svg").should be_true
      end
    end
  end
end
