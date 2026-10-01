require "../spec_helper"

describe Carbon::Version do
  describe ".parse" do
    it "parses standard major.minor.commit strings" do
      v = Carbon::Version.parse("0.1.42")
      v.major.should eq(0)
      v.minor.should eq(1)
      v.commit.should eq(42)
      v.to_s.should eq("0.1.42")
    end

    it "handles leading 'v' or 'V' prefixes" do
      v1 = Carbon::Version.parse("v1.2.3")
      v1.major.should eq(1)
      v1.minor.should eq(2)
      v1.commit.should eq(3)

      v2 = Carbon::Version.parse("V0.0.149")
      v2.major.should eq(0)
      v2.minor.should eq(0)
      v2.commit.should eq(149)
    end

    it "defaults commit number to 0 when given major.minor only" do
      v = Carbon::Version.parse("1.5")
      v.major.should eq(1)
      v.minor.should eq(5)
      v.commit.should eq(0)
    end

    it "parses prerelease tags and build metadata" do
      v = Carbon::Version.parse("0.2.10-alpha.1+20261001")
      v.major.should eq(0)
      v.minor.should eq(2)
      v.commit.should eq(10)
      v.prerelease.should eq("alpha.1")
      v.build_metadata.should eq("20261001")
      v.to_s.should eq("0.2.10-alpha.1+20261001")
    end

    it "raises ArgumentError on invalid syntax" do
      expect_raises(ArgumentError, /Invalid version string format/) do
        Carbon::Version.parse("invalid-version")
      end
    end

    it "returns nil on parse? with invalid string" do
      Carbon::Version.parse?("bad").should be_nil
    end
  end

  describe "bumping & mutations" do
    it "bumps commit number incrementally" do
      v = Carbon::Version.new(0, 1, 5)
      v.bump_commit.should eq(Carbon::Version.new(0, 1, 6))
    end

    it "bumps commit to an exact count" do
      v = Carbon::Version.new(0, 1, 5)
      v.bump_commit(25).should eq(Carbon::Version.new(0, 1, 25))
    end

    it "bumps minor version while keeping commit count intact" do
      v = Carbon::Version.new(0, 1, 149)
      v.bump_minor.should eq(Carbon::Version.new(0, 2, 149))
    end

    it "optionally resets commit when bumping minor" do
      v = Carbon::Version.new(0, 1, 149)
      v.bump_minor(reset_commit: true).should eq(Carbon::Version.new(0, 2, 0))
    end

    it "bumps major version and resets minor" do
      v = Carbon::Version.new(0, 5, 200)
      v.bump_major.should eq(Carbon::Version.new(1, 0, 200))
    end

    it "sets arbitrary major and minor versions" do
      v = Carbon::Version.new(0, 1, 42)
      v.with_major_minor(2, 5).should eq(Carbon::Version.new(2, 5, 42))
    end
  end

  describe "comparison" do
    it "compares by major first, then minor, then commit" do
      v1 = Carbon::Version.new(0, 1, 10)
      v2 = Carbon::Version.new(0, 1, 11)
      v3 = Carbon::Version.new(0, 2, 1)
      v4 = Carbon::Version.new(1, 0, 0)

      (v1 < v2).should be_true
      (v2 < v3).should be_true
      (v3 < v4).should be_true
      (v1 == Carbon::Version.new(0, 1, 10)).should be_true
    end
  end

  describe "#to_tuple" do
    it "returns a 3-element tuple" do
      Carbon::Version.new(1, 2, 3).to_tuple.should eq({1, 2, 3})
    end
  end
end
