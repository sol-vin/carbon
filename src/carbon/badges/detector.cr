require "yaml"
require "../vcs/git"

module Carbon
  module Badges
    struct RepoMetadata
      property github_slug : String?
      property default_branch : String
      property ci_workflow : String?
      property shard_name : String?
      property version : String
      property crystal_version : String?
      property license : String?
      property docs_url : String?
      property commit_count : Int32

      def initialize(
        @github_slug : String? = nil,
        @default_branch : String = "main",
        @ci_workflow : String? = nil,
        @shard_name : String? = nil,
        @version : String = "0.1.0",
        @crystal_version : String? = nil,
        @license : String? = nil,
        @docs_url : String? = nil,
        @commit_count : Int32 = 0,
      )
      end
    end

    class Detector
      def self.detect(repo_root : Path | String = ".") : RepoMetadata
        root = Path.new(repo_root)
        git = VCS::Git.new(root)

        slug = git.initialized? ? git.github_slug : nil
        branch = (git.initialized? ? git.branch_name : nil) || "main"
        commits = git.initialized? ? git.commit_count : 0

        # Scan for CI workflow in .github/workflows
        workflows_dir = root.join(".github", "workflows")
        ci_workflow = nil
        if Dir.exists?(workflows_dir)
          preferred = ["ci.yml", "test.yml", "build.yml", "main.yml"]
          found = Dir.children(workflows_dir).select { |f| f.ends_with?(".yml") || f.ends_with?(".yaml") }
          ci_workflow = preferred.find { |p| found.includes?(p) } || found.first?
        end

        # Shard metadata
        shard_file = root.join("shard.yml")
        shard_name = nil
        version_str = "0.1.0"
        crystal_ver = nil
        license_str = nil

        if File.exists?(shard_file)
          begin
            parsed = YAML.parse(File.read(shard_file))
            shard_name = parsed["name"]?.try(&.as_s?)
            version_str = parsed["version"]?.try(&.as_s?) || "0.1.0"
            crystal_ver = parsed["crystal"]?.try(&.as_s?)
            license_str = parsed["license"]?.try(&.as_s?)
          rescue
            # Fallback regex extraction if YAML parse fails
            content = File.read(shard_file)
            if m = content.match(/name:\s*([^\r\n#]+)/)
              shard_name = m[1].strip
            end
            if m = content.match(/version:\s*([^\r\n#]+)/)
              version_str = m[1].strip.gsub(/["']/, "")
            end
            if m = content.match(/crystal:\s*([^\r\n#]+)/)
              crystal_ver = m[1].strip.gsub(/["']/, "")
            end
            if m = content.match(/license:\s*([^\r\n#]+)/)
              license_str = m[1].strip.gsub(/["']/, "")
            end
          end
        end

        # Check LICENSE file if not in shard.yml
        if license_str.nil?
          ["LICENSE", "LICENSE.md", "LICENSE.txt"].each do |lic_name|
            lic_path = root.join(lic_name)
            if File.exists?(lic_path)
              first_lines = File.read_lines(lic_path).first(5).join(" ")
              if first_lines =~ /MIT/i
                license_str = "MIT"
              elsif first_lines =~ /Apache/i
                license_str = "Apache-2.0"
              elsif first_lines =~ /BSD/i
                license_str = "BSD"
              elsif first_lines =~ /GPL/i
                license_str = "GPL"
              else
                license_str = "Custom"
              end
              break
            end
          end
        end

        # Docs URL
        docs_url = nil
        if slug
          docs_dir = root.join("docs")
          if Dir.exists?(docs_dir)
            owner = slug.split('/')[0]
            repo = slug.split('/')[1]
            docs_url = "https://#{owner}.github.io/#{repo}/"
          end
        end

        RepoMetadata.new(
          github_slug: slug,
          default_branch: branch,
          ci_workflow: ci_workflow,
          shard_name: shard_name,
          version: version_str,
          crystal_version: crystal_ver,
          license: license_str,
          docs_url: docs_url,
          commit_count: commits,
        )
      end
    end
  end
end
