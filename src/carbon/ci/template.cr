require "./models"

module Carbon
  module CI
    # Core engine for generating, auditing, and non-destructively upgrading Crystal CI workflows
    class WorkflowTemplate
      NON_GODOT_SHARDS = [
        "carbon",
        "jasper",
        "crowbar",
        "fluorite",
        "rubellite",
        "bakelite",
        "opal",
        "sunstone",
        "cradare2",
      ]

      SHARD_CACHE_STEP = <<-YAML
            - name: Cache Shards
              uses: actions/cache@v4
              with:
                path: lib
                key: ${{ runner.os }}-shards-${{ hashFiles('**/shard.lock', '**/shard.yml') }}
                restore-keys: |
                  ${{ runner.os }}-shards-
      YAML

      FORMAT_CHECK_STEP = <<-YAML
            - name: Check Formatting
              run: crystal tool format --check src spec
      YAML

      SPEC_GATE_STEP = <<-YAML
            - name: Run Specifications
              run: crystal spec --error-trace
      YAML

      # Audits a repository directory's .github/workflows/ci.yml
      def self.audit(repo_root : Path | String) : WorkflowAudit
        root = Path.new(repo_root)
        name = root.basename
        wf_path = root.join(".github", "workflows", "ci.yml")

        unless File.exists?(wf_path)
          return WorkflowAudit.new(
            repo_name: name,
            workflow_path: wf_path,
            exists: false,
            has_concurrency_cancellation: false,
            has_shard_caching: false,
            has_format_check: false,
            has_spec_gate: false
          )
        end

        audit_content(File.read(wf_path), repo_name: name, workflow_path: wf_path)
      end

      # Pure audit of workflow YAML content
      def self.audit_content(
        content : String,
        repo_name : String = "repo",
        workflow_path : Path = Path.new(".github/workflows/ci.yml"),
      ) : WorkflowAudit
        normalized = content.gsub("\r\n", "\n")

        has_concurrency = normalized.includes?("concurrency:") &&
                          normalized.includes?("cancel-in-progress:") &&
                          !normalized.includes?("cancel-in-progress: false")

        has_cache = normalized.includes?("actions/cache@v4") &&
                    (normalized.includes?("path: lib") || normalized.includes?("-shards-"))

        has_format = normalized.includes?("crystal tool format --check")
        has_spec = normalized.includes?("crystal spec")

        WorkflowAudit.new(
          repo_name: repo_name,
          workflow_path: workflow_path,
          exists: true,
          has_concurrency_cancellation: has_concurrency,
          has_shard_caching: has_cache,
          has_format_check: has_format,
          has_spec_gate: has_spec
        )
      end

      # Renders a complete canonical Crystal CI workflow from a WorkflowConfig
      def self.render(config : WorkflowConfig = WorkflowConfig.new) : String
        branches_str = "[ " + config.branches.join(", ") + " ]"
        os_str = "[ " + config.os_matrix.join(", ") + " ]"

        String.build do |io|
          io << "name: #{config.workflow_name}\n\n"
          io << "on:\n"
          io << "  push:\n"
          io << "    branches: #{branches_str}\n"
          io << "  pull_request:\n"
          io << "    branches: #{branches_str}\n"

          if config.concurrency_cancel?
            io << "\nconcurrency:\n"
            io << "  group: ci-${{ github.workflow }}-${{ github.ref }}\n"
            io << "  cancel-in-progress: true\n"
          end

          io << "\njobs:\n"
          io << "  test:\n"
          io << "    name: Test (${{ matrix.os }})\n"
          io << "    runs-on: ${{ matrix.os }}\n"
          io << "    strategy:\n"
          io << "      fail-fast: false\n"
          io << "      matrix:\n"
          io << "        os: #{os_str}\n"
          io << "    steps:\n"
          io << "      - name: Checkout repository\n"
          io << "        uses: actions/checkout@v4\n"
          io << "        with:\n"
          io << "          fetch-depth: 0\n\n"
          io << "      - name: Update apt package index\n"
          io << "        if: runner.os == 'Linux'\n"
          io << "        run: sudo apt-get update\n\n"
          io << "      - name: Install Crystal\n"
          io << "        uses: crystal-lang/install-crystal@v1\n"
          io << "        with:\n"
          io << "          crystal: #{config.crystal_version}\n"

          if config.shard_caching?
            io << "\n" << SHARD_CACHE_STEP << "\n"
          end

          io << "\n      - name: Install Shards\n"
          io << "        run: shards install\n"

          if config.format_check?
            io << "\n" << FORMAT_CHECK_STEP << "\n"
          end

          if config.spec_gate?
            io << "\n" << SPEC_GATE_STEP << "\n"
          end

          if bin = config.binary_target
            io << "\n      - name: Build #{bin.capitalize} Binary\n"
            io << "        run: shards build #{bin}\n"
          end
        end
      end

      # Non-destructively upgrades an existing .github/workflows/ci.yml to include
      # concurrency cancellation, shard caching (path: lib), format check (src spec), and spec gate
      def self.upgrade(content : String) : String
        result = content.gsub("\r\n", "\n")

        # 1. Ensure concurrency cancellation is present and active
        if result.includes?("concurrency:")
          if result.includes?("cancel-in-progress: false")
            result = result.gsub("cancel-in-progress: false", "cancel-in-progress: true")
          end
        elsif result.includes?("\njobs:\n")
          concurrency_block = "\nconcurrency:\n  group: ci-${{ github.workflow }}-${{ github.ref }}\n  cancel-in-progress: true\n\njobs:\n"
          result = result.sub("\njobs:\n", concurrency_block)
        end

        # 2. Scope bare `crystal tool format --check` to `src spec` so cached `lib/` is never linted
        result = result.gsub(/crystal tool format --check(\s*)$/m, "crystal tool format --check src spec\\1")

        # 3. Ensure shard caching (`actions/cache@v4` with `path: lib`) is present
        has_shard_cache = result.includes?("actions/cache@v4") &&
                          (result.includes?("path: lib") || result.includes?("-shards-"))
        unless has_shard_cache
          # Insert before the first Install Shards / Verify Shards / Check Formatting step
          inserted = false
          anchor_patterns = [
            /^[ \t]*- name: (?:Install|Verify) Shards[^\n]*\n/m,
            /^[ \t]*- name: Check [Ff]ormatting[^\n]*\n/m,
            /^[ \t]*- name: Check code formatting[^\n]*\n/m,
            /^[ \t]*- name: Run (?:Test|Specs)[^\n]*\n/m,
          ]

          anchor_patterns.each do |pat|
            if match = pat.match(result)
              result = result.sub(match[0], "#{SHARD_CACHE_STEP}\n\n#{match[0]}")
              inserted = true
              break
            end
          end

          unless inserted
            result = result.rstrip + "\n\n" + SHARD_CACHE_STEP + "\n"
          end
        end

        # 4. Ensure format check is present
        unless result.includes?("crystal tool format --check")
          if match = /^[ \t]*- name: Run (?:Test|Specs|Specifications)[^\n]*\n/m.match(result)
            result = result.sub(match[0], "#{FORMAT_CHECK_STEP}\n\n#{match[0]}")
          else
            result = result.rstrip + "\n\n" + FORMAT_CHECK_STEP + "\n"
          end
        end

        # 5. Ensure spec gate is present
        unless result.includes?("crystal spec")
          result = result.rstrip + "\n\n" + SPEC_GATE_STEP + "\n"
        end

        result.rstrip + "\n"
      end
    end
  end
end
