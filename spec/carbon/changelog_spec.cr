require "../spec_helper"

describe Carbon::Changelog do
  describe Carbon::Changelog::GitCommit do
    it "parses conventional commit with scope" do
      commit = Carbon::Changelog::GitCommit.new(
        hash: "1234567890abcdef",
        short_hash: "1234567",
        subject: "feat(cli): add porcelain output flag",
        author: "Tester",
        date: Time.utc
      )
      res = commit.parse_conventional
      res[:type].should eq("feat")
      res[:scope].should eq("cli")
      res[:description].should eq("add porcelain output flag")
      res[:category].should eq("features")
      res[:badge].should eq("[CLI]")
      res[:breaking].should be_false
    end

    it "detects breaking changes via exclamation mark" do
      commit = Carbon::Changelog::GitCommit.new(
        hash: "abcdef1234567890",
        short_hash: "abcdef1",
        subject: "fix(api)!: change return type of current_version",
        author: "Tester",
        date: Time.utc
      )
      res = commit.parse_conventional
      res[:breaking].should be_true
      res[:category].should eq("breaking")
      res[:badge].should eq("[API]")
    end
  end

  describe Carbon::Changelog::Manager do
    it "preserves user-edited descriptions and custom bullets without overwriting" do
      with_temp_dir do |dir|
        yaml_file = dir.join("changelog.yml")

        # Initial YAML with manual edit
        initial_manifest = Carbon::Changelog::Manifest.new
        entry = Carbon::Changelog::Entry.new(
          type: "feat",
          description: "Hand-edited custom feature note",
          bullet: "🚀",
          hash: "abc1234"
        )
        release = Carbon::Changelog::Release.new("0.1.0", "2026-10-01", "active", entries: [entry])
        initial_manifest.releases << release
        Carbon::Changelog::Manager.save(initial_manifest, dir)

        # Mock Git commit with same hash but raw commit subject
        Carbon::Changelog::Manager.sync(dir, version_override: "0.1.0")

        # Verify entry was NOT overwritten
        loaded = Carbon::Changelog::Manager.load(dir)
        loaded.releases.size.should eq(1)
        first_entry = loaded.releases.first.entries.first
        first_entry.description.should eq("Hand-edited custom feature note")
        first_entry.bullet.should eq("🚀")
        first_entry.hash.should eq("abc1234")
      end
    end

    it "compiles changelog.yml into formatted markdown with badges and custom bullets" do
      with_temp_dir do |dir|
        manifest = Carbon::Changelog::Manifest.new
        manifest.settings.title = "CUSTOM TITLE"
        manifest.settings.ascii_banner = "BANNER ART"

        entry = Carbon::Changelog::Entry.new(
          type: "fix",
          description: "resolve critical memory leak",
          bullet: "✓",
          badge: "[SECURITY]",
          hash: "sec9999"
        )
        release = Carbon::Changelog::Release.new(
          version: "1.0.0",
          date: "2026-10-01",
          status: "released",
          summary: "First major milestone",
          entries: [entry]
        )
        manifest.releases << release

        markdown = Carbon::Changelog::Manager.compile(manifest, dir)
        markdown.includes?("# CUSTOM TITLE").should be_true
        markdown.includes?("BANNER ART").should be_true
        markdown.includes?("## [1.0.0] - 2026-10-01").should be_true
        markdown.includes?("> First major milestone").should be_true
        markdown.includes?("### 🐛 Bug Fixes").should be_true
        markdown.includes?("- ✓ **[SECURITY]** resolve critical memory leak (`sec9999`)").should be_true
      end
    end

    it "seals an active release with status and date" do
      with_temp_dir do |dir|
        manifest = Carbon::Changelog::Manifest.new
        release = Carbon::Changelog::Release.new("0.2.0", "2026-01-01", "active")
        manifest.releases << release
        Carbon::Changelog::Manager.save(manifest, dir)

        Carbon::Changelog::Manager.seal_release("0.2.0", dir)

        loaded = Carbon::Changelog::Manager.load(dir)
        loaded.releases.first.status.should eq("released")
        loaded.releases.first.date.should eq(Time.local.to_s("%Y-%m-%d"))
      end
    end

    it "hyperlinks commit hashes and issue numbers when github_slug is configured" do
      with_temp_dir do |dir|
        manifest = Carbon::Changelog::Manifest.new
        manifest.settings.github_slug = "sol-vin/carbon"

        entry = Carbon::Changelog::Entry.new(
          type: "fix",
          description: "fix issue #42 in CLI parser",
          hash: "a1b2c3d"
        )
        release = Carbon::Changelog::Release.new("0.1.0", "2026-10-01", "active", entries: [entry])
        manifest.releases << release

        markdown = Carbon::Changelog::Manager.compile(manifest, dir)
        markdown.includes?("[#42](https://github.com/sol-vin/carbon/issues/42)").should be_true
        markdown.includes?("[`a1b2c3d`](https://github.com/sol-vin/carbon/commit/a1b2c3d)").should be_true
      end
    end

    it "disables hyperlinking when auto_link_github is false" do
      with_temp_dir do |dir|
        manifest = Carbon::Changelog::Manifest.new
        manifest.settings.github_slug = "sol-vin/carbon"
        manifest.settings.auto_link_github = false

        entry = Carbon::Changelog::Entry.new(
          type: "fix",
          description: "fix issue #42 in CLI parser",
          hash: "a1b2c3d"
        )
        release = Carbon::Changelog::Release.new("0.1.0", "2026-10-01", "active", entries: [entry])
        manifest.releases << release

        markdown = Carbon::Changelog::Manager.compile(manifest, dir)
        markdown.includes?("([`a1b2c3d`]").should be_false
        markdown.includes?("(`a1b2c3d`)").should be_true
        markdown.includes?("fix issue #42 in CLI parser").should be_true
      end
    end
  end
end
