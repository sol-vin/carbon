module Carbon
  module Badges
    class Injector
      PAIRED_TAG_REGEX = /(<!--\s*(?:carbon:)?badges\s*-->)([\s\S]*?)(<!--\s*\/(?:carbon:)?badges\s*-->)/i
      SINGLE_TAG_REGEX = /^[ \t]*<!--\s*(?:carbon:)?badges\s*-->[ \t]*$/mi

      # Checks if the markdown content contains a badge tag (paired or single)
      def self.has_tag?(content : String) : Bool
        PAIRED_TAG_REGEX.matches?(content) || SINGLE_TAG_REGEX.matches?(content)
      end

      # Extracts currently rendered badges between paired tags
      def self.extract_badges(content : String) : String?
        if match = PAIRED_TAG_REGEX.match(content)
          match[2].strip
        else
          nil
        end
      end

      # Checks if the badges in the content match the expected badges
      def self.badges_up_to_date?(content : String, expected_badges : String) : Bool
        existing = extract_badges(content)
        return false unless existing
        existing.gsub("\r\n", "\n").strip == expected_badges.gsub("\r\n", "\n").strip
      end

      # Renders badges into the markdown content
      def self.render_into(
        content : String,
        badges_markdown : String,
        inject_if_missing : Bool = false,
        tag_name : String = "carbon:badges",
      ) : String
        newline = content.includes?("\r\n") ? "\r\n" : "\n"
        cleaned_badges = badges_markdown.gsub("\r\n", "\n").strip.gsub("\n", newline)

        # 1. Try paired tags
        if match = PAIRED_TAG_REGEX.match(content)
          open_tag = match[1]
          close_tag = match[3]
          replacement = "#{open_tag}#{newline}#{cleaned_badges}#{newline}#{close_tag}"
          return content.sub(PAIRED_TAG_REGEX, replacement)
        end

        # 2. Try single unclosed tag
        if match = SINGLE_TAG_REGEX.match(content)
          replacement = "<!-- #{tag_name} -->#{newline}#{cleaned_badges}#{newline}<!-- /#{tag_name} -->"
          return content.sub(SINGLE_TAG_REGEX, replacement)
        end

        # 3. If missing and injection is allowed
        if inject_if_missing
          inject_tag_block(content, cleaned_badges, tag_name, newline)
        else
          content
        end
      end

      # Injects badge tag block into content without prior tags
      def self.inject_tag_block(
        content : String,
        badges_markdown : String,
        tag_name : String = "carbon:badges",
        newline : String = "\n",
      ) : String
        cleaned_badges = badges_markdown.gsub("\r\n", "\n").strip.gsub("\n", newline)
        block = "<!-- #{tag_name} -->#{newline}#{cleaned_badges}#{newline}<!-- /#{tag_name} -->#{newline}"

        # Search for first H1 header: # Heading
        if match = content.match(/^(#[ \t]+[^\r\n]+)/m)
          header_line = match[1]
          content.sub(header_line, "#{header_line}#{newline}#{newline}#{block}")
        else
          "#{block}#{newline}#{content}"
        end
      end
    end
  end
end
