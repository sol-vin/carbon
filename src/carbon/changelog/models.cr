require "yaml"

module Carbon
  module Changelog
    class CategoryConfig
      include YAML::Serializable

      property title : String
      property bullet : String

      def initialize(@title : String, @bullet : String)
      end
    end

    class Settings
      include YAML::Serializable

      property title : String = "CARBON CHANGELOG"
      property output_file : String = "CHANGELOG.md"
      property ascii_banner : String? = nil
      property header : String? = nil
      property auto_link_github : Bool = true
      property github_slug : String? = nil
      property categories : Hash(String, CategoryConfig) = Settings.default_categories

      def initialize(
        @title : String = "CARBON CHANGELOG",
        @output_file : String = "CHANGELOG.md",
        @ascii_banner : String? = nil,
        @header : String? = nil,
        @auto_link_github : Bool = true,
        @github_slug : String? = nil,
        @categories : Hash(String, CategoryConfig) = Settings.default_categories,
      )
      end

      def self.default_categories : Hash(String, CategoryConfig)
        {
          "breaking"    => CategoryConfig.new("💥 Breaking Changes", "▲"),
          "features"    => CategoryConfig.new("✨ Features & Improvements", "✦"),
          "fixes"       => CategoryConfig.new("🐛 Bug Fixes", "✓"),
          "perf"        => CategoryConfig.new("⚡ Performance Optimizations", "🚀"),
          "docs"        => CategoryConfig.new("📚 Documentation", "📖"),
          "maintenance" => CategoryConfig.new("🛠️ Chores & Tooling", "•"),
        }
      end
    end

    class Entry
      include YAML::Serializable

      property type : String
      property description : String
      property bullet : String? = nil
      property badge : String? = nil
      property hash : String? = nil
      property author : String? = nil

      def initialize(
        @type : String,
        @description : String,
        @bullet : String? = nil,
        @badge : String? = nil,
        @hash : String? = nil,
        @author : String? = nil,
      )
      end
    end

    class Release
      include YAML::Serializable

      property version : String
      property date : String
      property status : String = "active" # "active" or "released"
      property summary : String? = nil
      property entries : Array(Entry) = [] of Entry

      def initialize(
        @version : String,
        @date : String,
        @status : String = "active",
        @summary : String? = nil,
        @entries : Array(Entry) = [] of Entry,
      )
      end

      def active? : Bool
        @status == "active"
      end

      def released? : Bool
        @status == "released"
      end
    end

    class Manifest
      include YAML::Serializable

      property settings : Settings = Settings.new
      property releases : Array(Release) = [] of Release

      def initialize(
        @settings : Settings = Settings.new,
        @releases : Array(Release) = [] of Release,
      )
      end

      def active_release : Release?
        @releases.find(&.active?)
      end

      def find_release(ver : String) : Release?
        @releases.find { |r| r.version == ver || r.version == ver.lstrip('v') }
      end
    end
  end
end
