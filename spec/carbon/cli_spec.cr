require "../spec_helper"

describe "Carbon CLI" do
  bin_name = HostPlatform.windows? ? "carbon.exe" : "carbon"
  bin_path = Path.new(__DIR__, "..", "..", "bin", bin_name).expand.to_s

  before_all do
    # Ensure binary is built for testing
    unless File.exists?(bin_path)
      Process.run("shards", ["build", "carbon"], chdir: Path.new(__DIR__, "..", "..").to_s)
    end
  end

  it "displays help and exits with status 0" do
    stdout = IO::Memory.new
    status = Process.run(bin_path, ["--help"], output: stdout)
    status.success?.should be_true
    stdout.to_s.includes?("Automated Version Control").should be_true
  end

  it "initializes a repository and creates shard.yml" do
    with_temp_git_repo do |dir|
      stdout = IO::Memory.new
      status = Process.run(bin_path, ["init", "--major=1", "--minor=0"], chdir: dir.to_s, output: stdout)
      status.success?.should be_true

      shard_file = dir.join("shard.yml")
      File.exists?(shard_file).should be_true
      File.read(shard_file).includes?("version: 1.0.0").should be_true
      Carbon::HookManager.installed?(dir).should be_true
    end
  end

  it "bumps version via pre-commit hook mode (--hook)" do
    with_temp_git_repo do |dir|
      shard_file = dir.join("shard.yml")
      File.write(shard_file, "name: demo\nversion: 0.1.0\n")

      stdout = IO::Memory.new
      status = Process.run(bin_path, ["bump", "--hook"], chdir: dir.to_s, output: stdout)
      status.success?.should be_true

      # First commit index will be 1
      File.read(shard_file).includes?("version: 0.1.1").should be_true
    end
  end

  it "sets major and minor versions" do
    with_temp_dir do |dir|
      shard_file = dir.join("shard.yml")
      File.write(shard_file, "name: demo\nversion: 0.1.42\n")

      status = Process.run(bin_path, ["set", "2.5"], chdir: dir.to_s)
      status.success?.should be_true
      File.read(shard_file).includes?("version: 2.5.42").should be_true
    end
  end

  it "retrieves porcelain version string" do
    with_temp_dir do |dir|
      shard_file = dir.join("shard.yml")
      File.write(shard_file, "name: demo\nversion: 3.4.100\n")

      stdout = IO::Memory.new
      status = Process.run(bin_path, ["get", "--porcelain"], chdir: dir.to_s, output: stdout)
      status.success?.should be_true
      stdout.to_s.strip.should eq("3.4.100")
    end
  end

  it "previews badges with carbon badges --dry-run" do
    with_temp_dir do |dir|
      shard_file = dir.join("shard.yml")
      File.write(shard_file, "name: demo\nversion: 1.0.5\nlicense: MIT\n")

      stdout = IO::Memory.new
      status = Process.run(bin_path, ["badges", "--dry-run"], chdir: dir.to_s, output: stdout)
      status.success?.should be_true
      stdout.to_s.includes?("version-1.0.5-blue.svg").should be_true
    end
  end

  it "initializes badges and checks sync status" do
    with_temp_dir do |dir|
      shard_file = dir.join("shard.yml")
      File.write(shard_file, "name: demo\nversion: 0.5.0\nlicense: MIT\n")

      readme_file = dir.join("README.md")
      File.write(readme_file, "# Demo App\n\nDemo description.")

      status = Process.run(bin_path, ["badges", "init"], chdir: dir.to_s)
      status.success?.should be_true

      File.exists?(dir.join("badges.yml")).should be_true
      File.read(readme_file).includes?("<!-- carbon:badges -->").should be_true
      File.read(readme_file).includes?("version-0.5.0-blue.svg").should be_true

      # Verify check succeeds
      stdout = IO::Memory.new
      check_status = Process.run(bin_path, ["badges", "check"], chdir: dir.to_s, output: stdout)
      check_status.success?.should be_true
      stdout.to_s.includes?("In sync").should be_true
    end
  end
end

module HostPlatform
  def self.windows? : Bool
    {% if flag?(:windows) %}
      true
    {% else %}
      false
    {% end %}
  end
end
