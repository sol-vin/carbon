require "../vcs/git"
require "./type"
require "./template"
require "./status"

module Carbon
  module Hooks
    # Core engine primitive managing Git hook file operations safely and idempotently
    class HookInstaller
      getter repo_root : Path
      getter git : VCS::Git

      def initialize(repo_root : Path | String = ".")
        @repo_root = Path.new(repo_root)
        @git = VCS::Git.new(@repo_root)
      end

      def hooks_dir : Path
        @git.vcs_dir.join("hooks")
      end

      def hook_path(hook_type : HookType) : Path
        hooks_dir.join(hook_type.filename)
      end

      def hook_path(hook_name : String) : Path
        hooks_dir.join(hook_name)
      end

      def installed?(hook_type : HookType) : Bool
        path = hook_path(hook_type)
        return false unless File.exists?(path)
        content = File.read(path)
        content.includes?(HookTemplate::START_DELIMITER)
      end

      def installed?(hook_name : String) : Bool
        if type = HookType.parse?(hook_name)
          installed?(type)
        else
          path = hook_path(hook_name)
          return false unless File.exists?(path)
          File.read(path).includes?(HookTemplate::START_DELIMITER)
        end
      end

      def status(hook_type : HookType) : HookStatus
        path = hook_path(hook_type)
        exists = File.exists?(path)
        unless exists
          return HookStatus.new(hook_type, path, exists: false, installed: false, has_foreign_scripts: false)
        end

        content = File.read(path)
        is_installed = content.includes?(HookTemplate::START_DELIMITER) && content.includes?(HookTemplate::END_DELIMITER)

        foreign = false
        if is_installed
          regex = /#{Regex.escape(HookTemplate::START_DELIMITER)}[\s\S]*?#{Regex.escape(HookTemplate::END_DELIMITER)}/
          remaining = content.gsub(regex, "").strip
          foreign = !remaining.empty? && remaining != "#!/bin/sh" && remaining != "#!/usr/bin/env sh" && remaining != "#!/bin/bash"
        else
          foreign = !content.strip.empty?
        end

        cmd = nil
        if is_installed
          if match = content.match(/carbon\s+([a-zA-Z0-9_\-\s]+?)(?=\n|\"|\;|$)/)
            cmd = match[1].strip
          end
        end

        HookStatus.new(
          hook_type: hook_type,
          path: path,
          exists: true,
          installed: is_installed,
          has_foreign_scripts: foreign,
          active_command: cmd
        )
      end

      def status_all : Array(HookStatus)
        HookType.all_hooks.map { |type| status(type) }
      end

      def status_standard : Array(HookStatus)
        HookType.standard_hooks.map { |type| status(type) }
      end

      def install(hook_type : HookType, command : String? = nil) : Bool
        dir = hooks_dir
        Dir.mkdir_p(dir) unless Dir.exists?(dir)

        path = hook_path(hook_type)
        template = HookTemplate.new(hook_type, command)
        hook_content = template.render.strip

        if File.exists?(path)
          existing = File.read(path)
          if existing.includes?(HookTemplate::START_DELIMITER) && existing.includes?(HookTemplate::END_DELIMITER)
            regex = /#{Regex.escape(HookTemplate::START_DELIMITER)}[\s\S]*?#{Regex.escape(HookTemplate::END_DELIMITER)}/
            new_content = existing.gsub(regex, hook_content)
            File.write(path, new_content)
          else
            separator = existing.ends_with?("\n") ? "" : "\n"
            File.write(path, existing + separator + "\n" + hook_content + "\n")
          end
        else
          script = "#!/bin/sh\n\n" + hook_content + "\n"
          File.write(path, script)
        end

        begin
          File.chmod(path, 0o755)
        rescue
        end

        true
      end

      def install(hook_name : String, command : String? = nil) : Bool
        type = HookType.parse(hook_name)
        install(type, command)
      end

      def install_standard : Array(HookType)
        installed = [] of HookType
        HookType.standard_hooks.each do |hook_type|
          if install(hook_type)
            installed << hook_type
          end
        end
        installed
      end

      def install_all : Array(HookType)
        installed = [] of HookType
        HookType.all_hooks.each do |hook_type|
          if install(hook_type)
            installed << hook_type
          end
        end
        installed
      end

      def uninstall(hook_type : HookType) : Bool
        path = hook_path(hook_type)
        return false unless File.exists?(path)

        existing = File.read(path)
        return false unless existing.includes?(HookTemplate::START_DELIMITER)

        regex = /#{Regex.escape(HookTemplate::START_DELIMITER)}[\s\S]*?#{Regex.escape(HookTemplate::END_DELIMITER)}/
        updated = existing.gsub(regex, "").strip

        if updated.empty? || updated == "#!/bin/sh" || updated == "#!/usr/bin/env sh" || updated == "#!/bin/bash"
          File.delete(path)
        else
          File.write(path, updated + "\n")
        end

        true
      end

      def uninstall(hook_name : String) : Bool
        if type = HookType.parse?(hook_name)
          uninstall(type)
        else
          path = hook_path(hook_name)
          return false unless File.exists?(path)
          existing = File.read(path)
          return false unless existing.includes?(HookTemplate::START_DELIMITER)
          regex = /#{Regex.escape(HookTemplate::START_DELIMITER)}[\s\S]*?#{Regex.escape(HookTemplate::END_DELIMITER)}/
          updated = existing.gsub(regex, "").strip
          if updated.empty? || updated == "#!/bin/sh" || updated == "#!/usr/bin/env sh" || updated == "#!/bin/bash"
            File.delete(path)
          else
            File.write(path, updated + "\n")
          end
          true
        end
      end

      def uninstall_all : Array(HookType)
        removed = [] of HookType
        HookType.all_hooks.each do |type|
          if uninstall(type)
            removed << type
          end
        end
        removed
      end
    end
  end
end
