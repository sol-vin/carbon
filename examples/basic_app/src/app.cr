require "carbon"

module BasicApp
  # Embeds Lapis-style version from shard.yml at compile time!
  Carbon.version!

  def self.run
    puts "================================================="
    puts "  Welcome to BasicApp powered by Carbon!"
    puts "================================================="
    puts "  Application Version: #{VERSION}"
    puts "  Major Component:     #{MAJOR_VERSION}"
    puts "  Minor Component:     #{MINOR_VERSION}"
    puts "  Commit Index:        #{COMMIT_VERSION}"
    puts "  Object Version:      #{carbon_version}"
    puts "================================================="
  end
end

BasicApp.run
