require "./type"

module Carbon
  module Hooks
    # Detailed status of a Git hook in a repository
    struct HookStatus
      getter hook_type : HookType
      getter path : Path
      getter? exists : Bool
      getter? installed : Bool
      getter? has_foreign_scripts : Bool
      getter active_command : String?

      def initialize(
        @hook_type : HookType,
        @path : Path,
        @exists : Bool,
        @installed : Bool,
        @has_foreign_scripts : Bool,
        @active_command : String? = nil,
      )
      end

      # Human-readable state summary
      def summary : String
        if !@exists
          "not created"
        elsif !@installed
          "foreign script present (unmanaged)"
        elsif @has_foreign_scripts
          "active (chained with user scripts)"
        else
          "active (managed by carbon)"
        end
      end
    end
  end
end
