module Carbon
  module VCS
    class Git < Base
      getter repo_root : Path

      def initialize(root : String | Path = ".")
        @repo_root = Path.new(root).expand
      end

      # Discovers the Git repository root using `git rev-parse --show-toplevel`
      def self.discover(start_path : String | Path = ".") : Git?
        git = new(start_path)
        return git if git.initialized?
        nil
      end

      def initialized? : Bool
        res = run_git(["rev-parse", "--is-inside-work-tree"])
        res[:status].success? && res[:output].strip == "true"
      rescue
        false
      end

      def vcs_dir : Path
        res = run_git(["rev-parse", "--git-dir"])
        if res[:status].success?
          git_path = res[:output].strip
          Path.new(git_path).expand(@repo_root)
        else
          @repo_root.join(".git")
        end
      end

      def repo_root : Path
        res = run_git(["rev-parse", "--show-toplevel"])
        if res[:status].success?
          Path.new(res[:output].strip).expand
        else
          @repo_root
        end
      end

      # Returns commit count of HEAD.
      # If repository is empty (unborn branch / 0 commits), returns 0.
      def commit_count : Int32
        res = run_git(["rev-list", "--count", "HEAD"])
        if res[:status].success?
          res[:output].strip.to_i? || 0
        else
          # Repository has no commits yet (unborn HEAD)
          0
        end
      end

      def head_hash : String?
        res = run_git(["rev-parse", "--short", "HEAD"])
        res[:status].success? ? res[:output].strip : nil
      end

      def branch_name : String?
        res = run_git(["rev-parse", "--abbrev-ref", "HEAD"])
        if res[:status].success?
          branch = res[:output].strip
          branch.empty? ? nil : branch
        else
          nil
        end
      end

      def stage(files : Enumerable(String | Path)) : Bool
        args = ["add"] + files.map(&.to_s).to_a
        res = run_git(args)
        res[:status].success?
      end

      def dirty? : Bool
        res = run_git(["status", "--porcelain"])
        res[:status].success? && !res[:output].strip.empty?
      end

      private def run_git(args : Array(String)) : NamedTuple(status: Process::Status, output: String, error: String)
        stdout = IO::Memory.new
        stderr = IO::Memory.new

        status = Process.run(
          "git",
          args,
          chdir: @repo_root.to_s,
          output: stdout,
          error: stderr
        )

        {status: status, output: stdout.to_s, error: stderr.to_s}
      end
    end
  end
end
