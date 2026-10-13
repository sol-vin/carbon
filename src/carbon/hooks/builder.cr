require "./type"
require "./installer"

module Carbon
  module Hooks
    # Declarative Builder enabling ergonomic configuration of repository hooks
    # Adheres to the Two-Tier DSL Codex: ergonomic block receiver over pure engine primitives
    class Builder
      getter installer : HookInstaller
      getter enabled_hooks : Hash(HookType, String?)

      def initialize(repo_root : Path | String = ".")
        @installer = HookInstaller.new(repo_root)
        @enabled_hooks = Hash(HookType, String?).new
      end

      # Enables a specific hook type with optional custom command
      def enable(type : HookType, command : String? = nil) : self
        @enabled_hooks[type] = command
        self
      end

      # Enables a hook via symbol (e.g. :pre_commit, :post_merge)
      def enable(name : Symbol, command : String? = nil) : self
        case name
        when :pre_commit, :precommit
          enable(HookType::PreCommit, command)
        when :post_merge, :postmerge
          enable(HookType::PostMerge, command)
        when :post_checkout, :postcheckout
          enable(HookType::PostCheckout, command)
        when :pre_push, :prepush
          enable(HookType::PrePush, command)
        else
          raise ArgumentError.new("Unknown hook symbol: :#{name}. Valid symbols: :pre_commit, :post_merge, :post_checkout, :pre_push")
        end
      end

      # Configures standard suite (pre-commit and post-merge)
      def standard : self
        enable(HookType::PreCommit)
        enable(HookType::PostMerge)
        self
      end

      # Configures all supported hooks
      def all : self
        HookType.all_hooks.each { |h| enable(h) }
        self
      end

      # Applies configuration to disk and returns list of installed hooks
      def apply : Array(HookType)
        installed = [] of HookType
        @enabled_hooks.each do |type, cmd|
          if @installer.install(type, cmd)
            installed << type
          end
        end
        installed
      end
    end
  end
end
