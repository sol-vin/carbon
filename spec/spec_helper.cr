require "spec"
require "file_utils"
require "../src/carbon"

def with_temp_dir(&block : Path -> Nil)
  dir = Path.new(Dir.tempdir, "carbon_test_#{Time.utc.to_unix_ms}_#{rand(1000..9999)}")
  FileUtils.mkdir_p(dir)
  begin
    block.call(dir)
  ensure
    FileUtils.rm_rf(dir) if Dir.exists?(dir)
  end
end

def with_temp_git_repo(&block : Path -> Nil)
  with_temp_dir do |dir|
    Process.run("git", ["init", "-b", "main"], chdir: dir.to_s)
    Process.run("git", ["config", "user.name", "Carbon Tester"], chdir: dir.to_s)
    Process.run("git", ["config", "user.email", "tester@carbon.dev"], chdir: dir.to_s)
    block.call(dir)
  end
end
