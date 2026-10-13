module Carbon
  module Hooks
    # Identifies supported Git hook triggers in Carbon
    enum HookType
      PreCommit
      PostMerge
      PostCheckout
      PrePush

      def filename : String
        case self
        in .pre_commit?    then "pre-commit"
        in .post_merge?    then "post-merge"
        in .post_checkout? then "post-checkout"
        in .pre_push?      then "pre-push"
        end
      end

      def to_s(io : IO) : Nil
        io << filename
      end

      def description : String
        case self
        in .pre_commit?
          "Auto-increments version and stages manifests before committing"
        in .post_merge?
          "Synchronizes manifest and changelogs after pulling or merging"
        in .post_checkout?
          "Synchronizes manifest and changelogs after branch checkout"
        in .pre_push?
          "Verifies version alignment and changelog compilation before pushing"
        end
      end

      def default_command : String
        case self
        in .pre_commit?    then "bump --hook"
        in .post_merge?    then "sync"
        in .post_checkout? then "sync"
        in .pre_push?      then "check"
        end
      end

      def self.parse?(str : String) : HookType?
        case str.strip.downcase.gsub('_', '-')
        when "pre-commit", "precommit"
          PreCommit
        when "post-merge", "postmerge"
          PostMerge
        when "post-checkout", "postcheckout"
          PostCheckout
        when "pre-push", "prepush"
          PrePush
        else
          nil
        end
      end

      def self.parse(str : String) : HookType
        parse?(str) || raise ArgumentError.new("Unknown Git hook type: '#{str}'. Valid types: pre-commit, post-merge, post-checkout, pre-push")
      end

      # Standard hooks recommended for all repositories
      def self.standard_hooks : Array(HookType)
        [PreCommit, PostMerge]
      end

      # All supported hooks
      def self.all_hooks : Array(HookType)
        [PreCommit, PostMerge, PostCheckout, PrePush]
      end
    end
  end
end
