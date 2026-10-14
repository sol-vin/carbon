require "../spec_helper"
require "file_utils"

describe Carbon::CI do
  describe Carbon::CI::WorkflowTemplate do
    it "renders a compliant Crystal CI workflow with concurrency, shard caching, format check, and spec gate" do
      config = Carbon::CI::WorkflowConfig.new(
        workflow_name: "CI",
        branches: ["main"],
        os_matrix: ["ubuntu-latest", "windows-latest"],
        binary_target: "carbon"
      )
      yaml = Carbon::CI::WorkflowTemplate.render(config)
      audit = Carbon::CI::WorkflowTemplate.audit_content(yaml, repo_name: "carbon")

      audit.exists?.should be_true
      audit.has_concurrency_cancellation?.should be_true
      audit.has_shard_caching?.should be_true
      audit.has_format_check?.should be_true
      audit.has_spec_gate?.should be_true
      audit.compliant?.should be_true
      audit.missing_features.should be_empty

      yaml.should contain("group: ci-${{ github.workflow }}-${{ github.ref }}")
      yaml.should contain("cancel-in-progress: true")
      yaml.should contain("uses: actions/cache@v4")
      yaml.should contain("path: lib")
      yaml.should contain("crystal tool format --check src spec")
      yaml.should contain("crystal spec --error-trace")
      yaml.should contain("shards build carbon")
    end

    it "identifies missing pillars in a legacy workflow" do
      legacy = <<-YAML
      name: CI
      on:
        push:
          branches: [ main ]
      jobs:
        test:
          runs-on: ubuntu-latest
          steps:
            - name: Checkout repository
              uses: actions/checkout@v4
            - name: Install Shards
              run: shards install
            - name: Run Specs
              run: crystal spec
      YAML

      audit = Carbon::CI::WorkflowTemplate.audit_content(legacy, repo_name: "legacy")
      audit.compliant?.should be_false
      audit.has_concurrency_cancellation?.should be_false
      audit.has_shard_caching?.should be_false
      audit.has_format_check?.should be_false
      audit.has_spec_gate?.should be_true
      audit.missing_features.should contain("concurrency cancellation")
      audit.missing_features.should contain("shard caching (actions/cache@v4)")
      audit.missing_features.should contain("format check (crystal tool format --check)")
    end

    it "non-destructively upgrades a legacy workflow to full compliance while preserving custom steps" do
      legacy = <<-YAML
      name: CI

      on:
        push:
          branches: [ main ]
        pull_request:
          branches: [ main ]

      jobs:
        test:
          runs-on: ubuntu-latest
          steps:
            - name: Checkout repository
              uses: actions/checkout@v4
            - name: Ensure FFmpeg
              run: ffmpeg -version
            - name: Install Shards
              run: shards install
            - name: Check Formatting
              run: crystal tool format --check
            - name: Run Test Specifications
              run: crystal spec --error-trace
      YAML

      upgraded = Carbon::CI::WorkflowTemplate.upgrade(legacy)
      audit = Carbon::CI::WorkflowTemplate.audit_content(upgraded, repo_name: "fluorite")

      audit.compliant?.should be_true
      upgraded.should contain("Ensure FFmpeg")
      upgraded.should contain("crystal tool format --check src spec")
      upgraded.should contain("uses: actions/cache@v4")
      upgraded.should contain("cancel-in-progress: true")
    end
  end

  describe Carbon::CI::WorkflowStandardizer do
    it "standardizes a repository directory and creates or upgrades .github/workflows/ci.yml" do
      tmp_dir = Path.new(Dir.tempdir).join("carbon_ci_spec_#{Random.rand(100_000)}")
      FileUtils.mkdir_p(tmp_dir)
      begin
        before = Carbon::CI::WorkflowStandardizer.audit_repo(tmp_dir)
        before.exists?.should be_false
        before.compliant?.should be_false

        report = Carbon.ci(tmp_dir) do |b|
          b.branches("main")
            .os_matrix("ubuntu-latest")
            .shard_caching(true)
            .format_check(true)
            .spec_gate(true)
            .concurrency_cancel(true)
        end

        report.modified?.should be_true
        report.compliant?.should be_true

        # Second run is idempotent
        report2 = Carbon::CI::WorkflowStandardizer.standardize_repo(tmp_dir)
        report2.modified?.should be_false
        report2.compliant?.should be_true
      ensure
        FileUtils.rm_rf(tmp_dir)
      end
    end
  end
end
