require "uri"
require "./models"
require "./detector"

module Carbon
  module Badges
    class Builder
      # Builds a single badge markdown snippet based on config, repository metadata, and version
      def self.build(
        config : BadgeConfig,
        meta : RepoMetadata,
        version_override : String? = nil,
        default_style : String = "flat",
      ) : String
        case config.type
        when "version"
          build_version(config, meta, version_override, default_style)
        when "ci"
          build_ci(config, meta, default_style)
        when "crystal"
          build_crystal(config, meta, default_style)
        when "license"
          build_license(config, meta, default_style)
        when "docs"
          build_docs(config, meta, default_style)
        when "commits"
          build_commits(config, meta, default_style)
        when "github_release"
          build_github_release(config, meta, default_style)
        when "github_stars"
          build_github_stars(config, meta)
        when "code_size"
          build_code_size(config, meta, default_style)
        when "discord"
          build_discord(config, default_style)
        when "custom"
          build_custom(config, default_style)
        when "raw"
          config.markdown || ""
        else
          # Fallback to custom badge
          build_custom(config, default_style)
        end
      end

      # Builds the full markdown block for a list of badges
      def self.build_all(
        configs : Array(BadgeConfig),
        meta : RepoMetadata,
        version_override : String? = nil,
        settings : Settings = Settings.new,
      ) : String
        rendered = configs.compact_map do |cfg|
          b = build(cfg, meta, version_override, settings.style).strip
          b.empty? ? nil : b
        end

        separator = settings.layout == "inline_compact" ? " " : "\n"
        rendered.join(separator)
      end

      # Version Badge: [![Version](https://img.shields.io/badge/version-0.1.9-blue.svg)](...)
      private def self.build_version(config : BadgeConfig, meta : RepoMetadata, version_override : String?, default_style : String) : String
        ver = version_override || config.message || meta.version
        label = config.label || "version"
        color = config.color || "blue"
        alt = config.label ? config.label.not_nil!.capitalize : "Version"
        link = config.url || (meta.github_slug ? "https://github.com/#{meta.github_slug}/releases" : "shard.yml")
        query = query_string(config, default_style)
        img = "https://img.shields.io/badge/#{escape_path(label)}-#{escape_path(ver)}-#{color}.svg#{query}"
        "[![#{alt}](#{img})](#{link})"
      end

      # CI Badge: [![CI](https://github.com/owner/repo/actions/workflows/ci.yml/badge.svg)](...)
      private def self.build_ci(config : BadgeConfig, meta : RepoMetadata, default_style : String) : String
        slug = meta.github_slug
        return "" unless slug

        wf = config.workflow || meta.ci_workflow || "ci.yml"
        label = config.label || "CI"
        branch = config.branch

        img = if config.style && config.style != "flat"
                # Shields.io workflow status supports styling
                q = query_string(config, default_style)
                b_param = branch ? "&branch=#{URI.encode_www_form(branch)}" : ""
                "https://img.shields.io/github/actions/workflow/status/#{slug}/#{wf}#{q}#{b_param}"
              else
                b_query = branch ? "?branch=#{URI.encode_www_form(branch)}" : ""
                "https://github.com/#{slug}/actions/workflows/#{wf}/badge.svg#{b_query}"
              end

        link = config.url || "https://github.com/#{slug}/actions/workflows/#{wf}"
        "[![#{label}](#{img})](#{link})"
      end

      # Crystal Version Badge: [![Crystal](https://img.shields.io/badge/crystal-%3E%3D1.20.0-black.svg)](...)
      private def self.build_crystal(config : BadgeConfig, meta : RepoMetadata, default_style : String) : String
        c_ver = config.message || meta.crystal_version || ">= 1.20.0"
        label = config.label || "crystal"
        color = config.color || "black"
        link = config.url || "https://crystal-lang.org"
        query = query_string(config, default_style)
        img = "https://img.shields.io/badge/#{escape_path(label)}-#{escape_path(c_ver)}-#{color}.svg#{query}"
        "[![Crystal](#{img})](#{link})"
      end

      # License Badge: [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](...)
      private def self.build_license(config : BadgeConfig, meta : RepoMetadata, default_style : String) : String
        lic = config.message || meta.license || "MIT"
        label = config.label || "License"
        color = config.color || (lic.upcase == "MIT" ? "yellow" : "blue")
        link = config.url || "LICENSE"
        query = query_string(config, default_style)
        img = "https://img.shields.io/badge/#{escape_path(label)}-#{escape_path(lic)}-#{color}.svg#{query}"
        "[![License: #{lic}](#{img})](#{link})"
      end

      # Documentation Badge: [![Docs](https://img.shields.io/badge/docs-GitHub%20Pages-blue.svg)](...)
      private def self.build_docs(config : BadgeConfig, meta : RepoMetadata, default_style : String) : String
        label = config.label || "docs"
        msg = config.message || (meta.docs_url ? "GitHub Pages" : "available")
        color = config.color || "blue"
        link = config.url || meta.docs_url || (meta.github_slug ? "https://#{meta.github_slug.not_nil!.split('/')[0]}.github.io/#{meta.github_slug.not_nil!.split('/')[1]}/" : "#")
        query = query_string(config, default_style)
        img = "https://img.shields.io/badge/#{escape_path(label)}-#{escape_path(msg)}-#{color}.svg#{query}"
        "[![Docs](#{img})](#{link})"
      end

      # Commits Badge: [![Commits](https://img.shields.io/badge/commits-42-blue.svg)](...)
      private def self.build_commits(config : BadgeConfig, meta : RepoMetadata, default_style : String) : String
        count = config.message || meta.commit_count.to_s
        label = config.label || "commits"
        color = config.color || "blue"
        link = config.url || (meta.github_slug ? "https://github.com/#{meta.github_slug}/commits" : "#")
        query = query_string(config, default_style)
        img = "https://img.shields.io/badge/#{escape_path(label)}-#{escape_path(count)}-#{color}.svg#{query}"
        "[![Commits](#{img})](#{link})"
      end

      # GitHub Release Badge: [![Release](https://img.shields.io/github/v/release/owner/repo)](...)
      private def self.build_github_release(config : BadgeConfig, meta : RepoMetadata, default_style : String) : String
        slug = meta.github_slug
        return "" unless slug

        query = query_string(config, default_style)
        img = "https://img.shields.io/github/v/release/#{slug}#{query}"
        link = config.url || "https://github.com/#{slug}/releases"
        "[![Release](#{img})](#{link})"
      end

      # GitHub Stars Badge: [![GitHub Stars](https://img.shields.io/github/stars/owner/repo?style=social)](...)
      private def self.build_github_stars(config : BadgeConfig, meta : RepoMetadata) : String
        slug = meta.github_slug
        return "" unless slug

        img = "https://img.shields.io/github/stars/#{slug}?style=social"
        link = config.url || "https://github.com/#{slug}/stargazers"
        "[![GitHub Stars](#{img})](#{link})"
      end

      # Code Size Badge: [![Code Size](https://img.shields.io/github/languages/code-size/owner/repo)](...)
      private def self.build_code_size(config : BadgeConfig, meta : RepoMetadata, default_style : String) : String
        slug = meta.github_slug
        return "" unless slug

        query = query_string(config, default_style)
        img = "https://img.shields.io/github/languages/code-size/#{slug}#{query}"
        link = config.url || "https://github.com/#{slug}"
        "[![Code Size](#{img})](#{link})"
      end

      # Discord Badge: [![Discord](https://img.shields.io/discord/123456?logo=discord&label=Discord)](...)
      private def self.build_discord(config : BadgeConfig, default_style : String) : String
        server_id = config.server_id || config.message || ""
        label = config.label || "Discord"
        link = config.url || "https://discord.gg"

        params = ["logo=discord", "label=#{URI.encode_www_form(label)}"]
        style = config.style || default_style
        params << "style=#{style}" unless style == "flat" || style.empty?

        img = "https://img.shields.io/discord/#{server_id}?#{params.join("&")}"
        "[![Discord](#{img})](#{link})"
      end

      # Custom Shields.io Badge
      private def self.build_custom(config : BadgeConfig, default_style : String) : String
        if img = config.image_url
          link = config.url || "#"
          alt = config.label || "Badge"
          return "[![#{alt}](#{img})](#{link})"
        end

        label = config.label || "badge"
        msg = config.message || "ok"
        color = config.color || "blue"
        link = config.url || "#"
        query = query_string(config, default_style)
        img = "https://img.shields.io/badge/#{escape_path(label)}-#{escape_path(msg)}-#{color}.svg#{query}"
        "[![#{label}](#{img})](#{link})"
      end

      # Builds URL query string for style, logo, and logoColor
      private def self.query_string(config : BadgeConfig, default_style : String) : String
        params = [] of String
        style = config.style || default_style
        params << "style=#{style}" unless style == "flat" || style.empty?

        if logo = config.logo
          params << "logo=#{URI.encode_www_form(logo)}"
        end
        if logo_color = config.logo_color
          params << "logoColor=#{URI.encode_www_form(logo_color)}"
        end

        params.empty? ? "" : "?#{params.join("&")}"
      end

      # Escape path components according to Shields.io specifications
      def self.escape_path(text : String) : String
        text
          .gsub("_", "__")
          .gsub("-", "--")
          .gsub(" ", "%20")
          .gsub(">", "%3E")
          .gsub("<", "%3C")
          .gsub("=", "%3D")
      end
    end
  end
end
