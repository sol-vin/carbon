require "yaml"

module Carbon
  module Badges
    class BadgeConfig
      include YAML::Serializable

      property type : String
      property label : String? = nil
      property message : String? = nil
      property color : String? = nil
      property style : String? = nil
      property logo : String? = nil
      property logo_color : String? = nil
      property url : String? = nil
      property image_url : String? = nil
      property workflow : String? = nil
      property branch : String? = nil
      property markdown : String? = nil
      property server_id : String? = nil

      def initialize(
        @type : String,
        @label : String? = nil,
        @message : String? = nil,
        @color : String? = nil,
        @style : String? = nil,
        @logo : String? = nil,
        @logo_color : String? = nil,
        @url : String? = nil,
        @image_url : String? = nil,
        @workflow : String? = nil,
        @branch : String? = nil,
        @markdown : String? = nil,
        @server_id : String? = nil,
      )
      end
    end

    class Settings
      include YAML::Serializable

      property target_file : String = "README.md"
      property tag : String = "carbon:badges"
      property style : String = "flat"
      property layout : String = "inline" # "inline" (space-separated) or "block" (newline-separated)

      def initialize(
        @target_file : String = "README.md",
        @tag : String = "carbon:badges",
        @style : String = "flat",
        @layout : String = "inline",
      )
      end
    end

    class Manifest
      include YAML::Serializable

      property settings : Settings = Settings.new
      property badges : Array(BadgeConfig) = [] of BadgeConfig

      def initialize(
        @settings : Settings = Settings.new,
        @badges : Array(BadgeConfig) = [] of BadgeConfig,
      )
      end
    end
  end
end
