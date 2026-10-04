module Carbon
  module VCS
    abstract class Base
      # Total count of commits in the current branch history
      abstract def commit_count : Int32

      # The current HEAD commit hash (short or full)
      abstract def head_hash : String?

      # The name of the active branch
      abstract def branch_name : String?

      # Root directory of the repository
      abstract def repo_root : Path

      # Internal directory storing VCS metadata (e.g. .git)
      abstract def vcs_dir : Path

      # Stage a set of files into index
      abstract def stage(files : Enumerable(String | Path)) : Bool

      # Returns true if working directory has uncommitted or untracked changes
      abstract def dirty? : Bool

      # Returns true if VCS repository is properly initialized
      abstract def initialized? : Bool

      # Returns file contents at specified revision (default HEAD), or nil if absent / no commits
      def show_file(path : String | Path, rev : String = "HEAD") : String?
        nil
      end
    end
  end
end
