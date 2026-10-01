require "../spec_helper"

describe Carbon::ReleaseManager do
  it "creates git release tag and floating latest tag" do
    with_temp_git_repo do |dir|
      File.write(dir.join("file.txt"), "content")
      Process.run("git", ["add", "."], chdir: dir.to_s)
      Process.run("git", ["commit", "-m", "release prep"], chdir: dir.to_s)

      res = Carbon::ReleaseManager.create_tag("0.2.0", message: "Version 0.2.0", floating_latest: true, repo_root: dir)
      res.should be_true

      # Verify tag exists
      tag_out = IO::Memory.new
      Process.run("git", ["tag", "-l"], chdir: dir.to_s, output: tag_out)
      tags = tag_out.to_s.split("\n").map(&.strip)
      tags.includes?("v0.2.0").should be_true
      tags.includes?("latest").should be_true
    end
  end
end
