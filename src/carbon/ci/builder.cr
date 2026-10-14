require "./models"
require "./template"
require "./standardizer"

module Carbon
  module CI
    # Declarative Builder enabling ergonomic configuration of Crystal CI workflows
    # Adheres to the Two-Tier DSL Codex: ergonomic block receiver over pure engine primitives
    class Builder
      getter repo_root : Path
      getter config : WorkflowConfig

      def initialize(repo_root : Path | String = ".")
        @repo_root = Path.new(repo_root)
        @config = WorkflowConfig.new
      end

      def workflow_name(name : String) : self
        @config.workflow_name = name
        self
      end

      def branches(*names : String) : self
        @config.branches = names.to_a
        self
      end

      def branches(names : Array(String)) : self
        @config.branches = names
        self
      end

      def os_matrix(*runners : String) : self
        @config.os_matrix = runners.to_a
        self
      end

      def os_matrix(runners : Array(String)) : self
        @config.os_matrix = runners
        self
      end

      def crystal_version(version : String) : self
        @config.crystal_version = version
        self
      end

      def shard_caching(enabled : Bool = true) : self
        @config.shard_caching = enabled
        self
      end

      def format_check(enabled : Bool = true) : self
        @config.format_check = enabled
        self
      end

      def spec_gate(enabled : Bool = true) : self
        @config.spec_gate = enabled
        self
      end

      def concurrency_cancel(enabled : Bool = true) : self
        @config.concurrency_cancel = enabled
        self
      end

      def binary_target(name : String?) : self
        @config.binary_target = name
        self
      end

      # Renders the configured workflow YAML string without modifying disk
      def render : String
        WorkflowTemplate.render(@config)
      end

      # Applies standardization to the target repository and returns the report
      def apply : RepoCIStandardizeReport
        WorkflowStandardizer.standardize_repo(@repo_root, @config)
      end
    end
  end
end
