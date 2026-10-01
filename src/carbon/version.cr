module Carbon
  struct Version
    include Comparable(Version)

    property major : Int32
    property minor : Int32
    property commit : Int32
    property prerelease : String?
    property build_metadata : String?

    def initialize(
      @major : Int32,
      @minor : Int32,
      @commit : Int32 = 0,
      @prerelease : String? = nil,
      @build_metadata : String? = nil,
    )
      raise ArgumentError.new("Major version cannot be negative: #{@major}") if @major < 0
      raise ArgumentError.new("Minor version cannot be negative: #{@minor}") if @minor < 0
      raise ArgumentError.new("Commit number cannot be negative: #{@commit}") if @commit < 0
    end

    # Parse version strings such as:
    # "0.1.42", "v0.1.42", "1.0", "0.0.149-alpha.1", "2.1.5+build.10"
    def self.parse(raw : String) : Version
      trimmed = raw.strip
      clean = trimmed.starts_with?('v') || trimmed.starts_with?('V') ? trimmed[1..] : trimmed

      # Regex matching major.minor(.commit)?(-prerelease)?(+build)?
      regex = /^(\d+)\.(\d+)(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$/
      match = regex.match(clean)
      unless match
        raise ArgumentError.new("Invalid version string format: '#{raw}'. Expected 'major.minor.commit_number'")
      end

      major = match[1].to_i
      minor = match[2].to_i
      commit = match[3]?.try(&.to_i) || 0
      prerelease = match[4]?
      build_metadata = match[5]?

      new(major, minor, commit, prerelease, build_metadata)
    end

    def self.parse?(raw : String) : Version?
      parse(raw)
    rescue ArgumentError
      nil
    end

    # Returns next version bumped for a new commit count
    def bump_commit(new_commit_count : Int32? = nil) : Version
      target_commit = new_commit_count ? new_commit_count : @commit + 1
      Version.new(@major, @minor, target_commit, @prerelease, @build_metadata)
    end

    # Bumps minor version by 1, leaving commit unchanged or optionally resetting to 0
    def bump_minor(reset_commit : Bool = false) : Version
      target_commit = reset_commit ? 0 : @commit
      Version.new(@major, @minor + 1, target_commit, @prerelease, @build_metadata)
    end

    # Bumps major version by 1 and resets minor to 0
    def bump_major(reset_commit : Bool = false) : Version
      target_commit = reset_commit ? 0 : @commit
      Version.new(@major + 1, 0, target_commit, @prerelease, @build_metadata)
    end

    # Sets specific major and minor while keeping commit number synced
    def with_major_minor(new_major : Int32, new_minor : Int32) : Version
      Version.new(new_major, new_minor, @commit, @prerelease, @build_metadata)
    end

    def to_tuple : Tuple(Int32, Int32, Int32)
      {@major, @minor, @commit}
    end

    def <=>(other : Version) : Int32
      cmp = @major <=> other.major
      return cmp unless cmp == 0

      cmp = @minor <=> other.minor
      return cmp unless cmp == 0

      cmp = @commit <=> other.commit
      return cmp unless cmp == 0

      # Versions without prerelease have higher precedence than those with prerelease
      case {@prerelease, other.prerelease}
      when {nil, nil}
        0
      when {nil, String}
        1
      when {String, nil}
        -1
      when {String, String}
        @prerelease.not_nil! <=> other.prerelease.not_nil!
      else
        0
      end
    end

    def to_s(io : IO) : Nil
      io << "#{@major}.#{@minor}.#{@commit}"
      if pre = @prerelease
        io << "-#{pre}"
      end
      if meta = @build_metadata
        io << "+#{meta}"
      end
    end
  end
end
