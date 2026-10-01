module Carbon
  module Changelog
    struct GitCommit
      property hash : String
      property short_hash : String
      property subject : String
      property author : String
      property date : Time

      def initialize(
        @hash : String,
        @short_hash : String,
        @subject : String,
        @author : String,
        @date : Time,
      )
      end

      # Parses conventional commit details:
      # e.g. "feat(cli): add porcelain output flag"
      # returns { type: "feat", scope: "cli", description: "add porcelain output flag", breaking: false, category: "features" }
      def parse_conventional : NamedTuple(
        type: String,
        scope: String?,
        description: String,
        breaking: Bool,
        category: String,
        badge: String?)
        sub = @subject.strip
        breaking = sub.includes?("BREAKING CHANGE:")

        # Pattern: type(scope)!: description OR type!: description OR type(scope): description OR type: description
        regex = /^([a-zA-Z0-9_-]+)(?:\(([^\)]+)\))?(!)?:\s*(.*)$/
        if match = regex.match(sub)
          raw_type = match[1].downcase
          scope = match[2]?
          is_exclamation = !match[3]?.nil?
          desc = match[4].strip
          is_breaking = breaking || is_exclamation

          category = if is_breaking
                       "breaking"
                     else
                       case raw_type
                       when "feat"
                         "features"
                       when "fix"
                         "fixes"
                       when "perf"
                         "perf"
                       when "docs"
                         "docs"
                       when "refactor"
                         "features"
                       else
                         "maintenance"
                       end
                     end

          badge = scope ? "[#{scope.upcase}]" : (is_breaking ? "[BREAKING]" : nil)

          {
            type:        is_breaking ? "breaking" : raw_type,
            scope:       scope,
            description: desc,
            breaking:    is_breaking,
            category:    category,
            badge:       badge,
          }
        else
          # Fallback for non-conventional commit messages
          {
            type:        "other",
            scope:       nil,
            description: sub,
            breaking:    false,
            category:    "maintenance",
            badge:       nil,
          }
        end
      end
    end
  end
end
