require "../spec_helper"

describe Carbon::FileManager do
  it "reads unquoted version from shard.yml" do
    with_temp_dir do |dir|
      shard_file = dir.join("shard.yml")
      File.write(shard_file, <<-YAML
      name: test_project
      version: 0.1.42
      authors:
        - Tester
      YAML
      )

      ver = Carbon::FileManager.read_shard_version(shard_file)
      ver.should_not be_nil
      ver.not_nil!.should eq(Carbon::Version.new(0, 1, 42))
    end
  end

  it "reads quoted version with inline comment from shard.yml" do
    with_temp_dir do |dir|
      shard_file = dir.join("shard.yml")
      File.write(shard_file, <<-YAML
      name: test_project
      version: "1.2.3" # Auto-managed
      YAML
      )

      ver = Carbon::FileManager.read_shard_version(shard_file)
      ver.should_not be_nil
      ver.not_nil!.should eq(Carbon::Version.new(1, 2, 3))
    end
  end

  it "updates version in shard.yml while preserving quotes, comments, and structure" do
    with_temp_dir do |dir|
      shard_file = dir.join("shard.yml")
      content = <<-YAML
      # Project manifest
      name: sample_app
      version: "0.1.10" # Lapis version
      crystal: ">= 1.20.0"
      YAML
      File.write(shard_file, content)

      res = Carbon::FileManager.update_shard_version(shard_file, Carbon::Version.new(0, 1, 11))
      res.should be_true

      updated = File.read(shard_file)
      updated.includes?(%(version: "0.1.11" # Lapis version)).should be_true
      updated.includes?("# Project manifest").should be_true
      updated.includes?(%(name: sample_app)).should be_true
    end
  end

  it "updates unquoted version without introducing unnecessary quotes" do
    with_temp_dir do |dir|
      shard_file = dir.join("shard.yml")
      content = <<-YAML
      name: sample_app
      version: 0.0.149
      YAML
      File.write(shard_file, content)

      res = Carbon::FileManager.update_shard_version(shard_file, Carbon::Version.new(0, 0, 150))
      res.should be_true

      updated = File.read(shard_file)
      updated.includes?("version: 0.0.150").should be_true
      updated.includes?("\"").should be_false
    end
  end

  it "creates a default shard.yml if one does not exist" do
    with_temp_dir do |dir|
      shard_file = dir.join("shard.yml")
      File.exists?(shard_file).should be_false

      created = Carbon::FileManager.ensure_shard_yml(shard_file, "cool_app", Carbon::Version.new(0, 2, 0))
      created.should be_true
      File.exists?(shard_file).should be_true

      ver = Carbon::FileManager.read_shard_version(shard_file)
      ver.should eq(Carbon::Version.new(0, 2, 0))
    end
  end

  it "generates a typed version.cr file" do
    with_temp_dir do |dir|
      ver_file = dir.join("src", "cool_app", "version.cr")
      res = Carbon::FileManager.sync_version_cr(ver_file, Carbon::Version.new(1, 0, 42), "CoolApp")
      res.should be_true
      File.exists?(ver_file).should be_true

      content = File.read(ver_file)
      content.includes?(%(VERSION = "1.0.42")).should be_true
      content.includes?("MAJOR   = 1").should be_true
      content.includes?("MINOR   = 0").should be_true
      content.includes?("COMMIT  = 42").should be_true
    end
  end
end
