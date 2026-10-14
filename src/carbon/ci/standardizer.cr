require "file_utils"
require "./models"
require "./template"

module Carbon
  module CI
    # Cross-repository scanner and automated Crystal CI workflow standardizer
    class WorkflowStandardizer
      # Audits a single repository's .github/workflows/ci.yml
      def self.audit_repo(repo_path : Path | String) : WorkflowAudit
        WorkflowTemplate.audit(repo_path)
      end

      # Standardizes a single repository's .github/workflows/ci.yml
      def self.standardize_repo(
        repo_path : Path | String,
        config : WorkflowConfig = WorkflowConfig.new,
      ) : RepoCIStandardizeReport
        path = Path.new(repo_path)
        name = path.basename
        wf_dir = path.join(".github", "workflows")
        wf_path = wf_dir.join("ci.yml")

        before = WorkflowTemplate.audit(path)

        if File.exists?(wf_path)
          original = File.read(wf_path)
          upgraded = WorkflowTemplate.upgrade(original)
          modified = upgraded != original.gsub("\r\n", "\n")
          if modified
            File.write(wf_path, upgraded)
          end
        else
          FileUtils.mkdir_p(wf_dir)
          rendered = WorkflowTemplate.render(config)
          File.write(wf_path, rendered)
          modified = true
        end

        after = WorkflowTemplate.audit(path)

        RepoCIStandardizeReport.new(
          repo_name: name,
          repo_path: path,
          audit_before: before,
          audit_after: after,
          modified: modified
        )
      end

      # Audits all target non-Godot Crystal shard repositories within a parent directory
      def self.audit_all(
        parent_dir : Path | String,
        targets : Array(String) = WorkflowTemplate::NON_GODOT_SHARDS,
      ) : Array(WorkflowAudit)
        base = Path.new(parent_dir)
        audits = [] of WorkflowAudit
        return audits unless Dir.exists?(base)

        targets.each do |shard|
          shard_path = base.join(shard)
          if Dir.exists?(shard_path)
            audits << audit_repo(shard_path)
          end
        end

        audits
      end

      # Standardizes .github/workflows/ci.yml across all target non-Godot Crystal shards in a parent directory
      def self.standardize_all(
        parent_dir : Path | String,
        targets : Array(String) = WorkflowTemplate::NON_GODOT_SHARDS,
      ) : Array(RepoCIStandardizeReport)
        base = Path.new(parent_dir)
        reports = [] of RepoCIStandardizeReport
        return reports unless Dir.exists?(base)

        targets.each do |shard|
          shard_path = base.join(shard)
          if Dir.exists?(shard_path)
            reports << standardize_repo(shard_path)
          end
        end

        reports
      end
    end
  end
end
