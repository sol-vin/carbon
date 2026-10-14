module Carbon
  module CI
    # Strongly-typed configuration model for a standardized Crystal CI workflow
    struct WorkflowConfig
      property workflow_name : String
      property branches : Array(String)
      property os_matrix : Array(String)
      property crystal_version : String
      property? shard_caching : Bool
      property? format_check : Bool
      property? spec_gate : Bool
      property? concurrency_cancel : Bool
      property binary_target : String?

      def initialize(
        @workflow_name : String = "CI",
        @branches : Array(String) = ["main"],
        @os_matrix : Array(String) = ["ubuntu-latest"],
        @crystal_version : String = "latest",
        @shard_caching : Bool = true,
        @format_check : Bool = true,
        @spec_gate : Bool = true,
        @concurrency_cancel : Bool = true,
        @binary_target : String? = nil,
      )
      end
    end

    # Structured audit result for a repository's .github/workflows/ci.yml
    struct WorkflowAudit
      getter repo_name : String
      getter workflow_path : Path
      getter? exists : Bool
      getter? has_concurrency_cancellation : Bool
      getter? has_shard_caching : Bool
      getter? has_format_check : Bool
      getter? has_spec_gate : Bool

      def initialize(
        @repo_name : String,
        @workflow_path : Path,
        @exists : Bool,
        @has_concurrency_cancellation : Bool,
        @has_shard_caching : Bool,
        @has_format_check : Bool,
        @has_spec_gate : Bool,
      )
      end

      # Returns true if the workflow exists and satisfies all 4 standardization pillars
      def compliant? : Bool
        @exists &&
          @has_concurrency_cancellation &&
          @has_shard_caching &&
          @has_format_check &&
          @has_spec_gate
      end

      # Returns list of missing standardization features
      def missing_features : Array(String)
        missing = [] of String
        unless @exists
          missing << "workflow file (.github/workflows/ci.yml)"
          return missing
        end
        missing << "concurrency cancellation" unless @has_concurrency_cancellation
        missing << "shard caching (actions/cache@v4)" unless @has_shard_caching
        missing << "format check (crystal tool format --check)" unless @has_format_check
        missing << "spec gate (crystal spec)" unless @has_spec_gate
        missing
      end
    end

    # Execution report for a repository undergoing CI workflow standardization
    struct RepoCIStandardizeReport
      getter repo_name : String
      getter repo_path : Path
      getter audit_before : WorkflowAudit
      getter audit_after : WorkflowAudit
      getter? modified : Bool

      def initialize(
        @repo_name : String,
        @repo_path : Path,
        @audit_before : WorkflowAudit,
        @audit_after : WorkflowAudit,
        @modified : Bool,
      )
      end

      def compliant? : Bool
        @audit_after.compliant?
      end
    end
  end
end
