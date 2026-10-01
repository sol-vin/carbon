module Carbon
  module VCS
    class Mock < Base
      property commit_count : Int32
      property head_hash : String?
      property branch_name : String?
      property repo_root : Path
      property vcs_dir : Path
      property dirty : Bool
      property staged_files : Array(String)
      property initialized : Bool

      def initialize(
        @commit_count : Int32 = 0,
        @head_hash : String? = "abc1234",
        @branch_name : String? = "main",
        root : String | Path = "/mock/repo",
        @dirty : Bool = false,
        @initialized : Bool = true,
      )
        @repo_root = Path.new(root)
        @vcs_dir = @repo_root.join(".git")
        @staged_files = [] of String
      end

      def stage(files : Enumerable(String | Path)) : Bool
        @staged_files.concat(files.map(&.to_s))
        true
      end

      def dirty? : Bool
        @dirty
      end

      def initialized? : Bool
        @initialized
      end
    end
  end
end
