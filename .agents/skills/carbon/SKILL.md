---
name: carbon
description: "Automated commit-based version control, human-friendly YAML changelogs, README badge management, repository doctor audits, and Git release automation for Crystal shards and multi-component repositories."
---

# Carbon ⚡ Skill Reference

Carbon is an automated commit-driven version control system, human-in-the-loop changelog engine, and release toolkit for Crystal applications and multi-component repositories.

It implements **Lapis-style versioning**:
$$\textbf{Version Format:} \quad \mathbf{\langle major \rangle.\langle minor \rangle.\langle commit\_number \rangle}$$

- **`commit_number`**: Automatically advances with every Git commit, ensuring every build and commit is distinctly and monotonically identified.
- **`major.minor`**: Controlled by the developer to bump when cutting feature milestones or breaking changes.
- **Zero-Friction Git Hooks**: Auto-stages updated manifests during `pre-commit` so that each commit carries its exact chronological build number in its own Git tree.

---

## When to Activate This Skill

Activate this skill when:
- Creating or configuring a new Crystal project or shard.
- Automating version numbers, builds, and release tags in a Git repository.
- Generating, updating, or compiling `changelog.yml` and `CHANGELOG.md`.
- Managing and synchronizing README badges (`badges.yml` $\to$ `README.md`).
- Auditing repository health and version alignment (`carbon doctor`).
- Installing or troubleshooting Git pre-commit and post-merge versioning hooks.

---

## Core CLI Command Reference

Carbon provides a fast, standalone binary executable: `carbon <command> [options]`

| Command | Subcommands / Flags | Description |
| :--- | :--- | :--- |
| `carbon init` | `--no-hook`, `--no-changelog`, `--no-badges`, `--major=N`, `--minor=N` | Initialize Carbon in the repository, create `shard.yml` format, install Git hooks, `changelog.yml`, and `badges.yml`. |
| `carbon bump` | `--commit` (default), `--minor`, `--major`, `--hook`, `--stage`, `--reset-commit` | Advances version counter. `--hook` is used by Git pre-commit hooks to stage manifests idempotently. |
| `carbon sync` | `--stage`, `--force` | Synchronizes `shard.yml` with Git commit count (preserving monotonic count unless `--force` is given). |
| `carbon set` | `<major.minor[.commit]>`, `--stage` | Explicitly sets version components (e.g. `carbon set 1.2` or `carbon set 0.1.25`). |
| `carbon get, version` | `-p`, `--porcelain` | Prints current project version. Use `-p` for raw output suitable for CI and scripts. |
| `carbon check` | *(none)* | Audits if `shard.yml` is in sync with Git commits. Returns exit code `0` on sync, `1` on mismatch. |
| `carbon changelog` | `--sync` (default), `--compile`, `--dry-run`, `--links`, `--no-links`, `--from=REF`, `--to=REF` | Synchronizes `changelog.yml` with new commits and compiles `CHANGELOG.md`. |
| `carbon badges` | `render` (default), `check`, `init`, `list`, `--dry-run`, `--inject`, `--file=FILE` | Manages markdown badge blocks between `<!-- carbon:badges -->` tags. |
| `carbon tag, release` | `[version]`, `--latest`, `--no-latest`, `--push`, `-m MSG` | Seals active changelog release, creates annotated Git tag `vX.Y.Z`, updates floating `latest` tag, and pushes to remote. |
| `carbon doctor` | `--fix` | Audits VCS status, hook installation, manifest versioning, changelog parity, and repairs issues automatically. |
| `carbon hook` | `install`, `uninstall`, `status`, `--post-merge` | Manages Git pre-commit and post-merge hooks non-destructively. |

---

## Key Workflows & Patterns

### 1. Adopting Carbon in an Existing Crystal Shard
1. Add to `shard.yml`:
   ```yaml
   development_dependencies:
     carbon:
       github: sol-vin/carbon
       branch: main

   targets:
     carbon:
       main: lib/carbon/src/carbon/cli.cr
   ```
2. Run `shards install`.
3. Initialize in repository root:
   ```bash
   bin/carbon init
   ```
4. Verify health with:
   ```bash
   bin/carbon doctor
   ```

### 2. Compile-Time Macro DSL (`Carbon.version!`)
In your main application file or module:
```crystal
require "carbon"

module MyApp
  # Injects VERSION, MAJOR_VERSION, MINOR_VERSION, COMMIT_VERSION,
  # and MyApp.carbon_version -> Carbon::Version
  Carbon.version!
end

puts "MyApp v#{MyApp::VERSION}"
```

### 3. Non-Destructive Changelog Management
- Carbon tracks each commit by its short hash and subject.
- **Invariant**: Carbon **never overwrites** an existing entry in `changelog.yml`.
- Developers can hand-edit descriptions, rephrase notes, change bullet icons, or add badges in `changelog.yml`, and running `carbon changelog` or `carbon changelog --compile` will safely preserve every manual edit.
- Available entry types: `feat` (✦), `fix` (✓), `perf` (🚀), `docs` (📖), `breaking` (▲), `maintenance` (•).

### 4. Badge Management (`badges.yml` $\to$ `README.md`)
Place the comment tag in `README.md`:
```markdown
<!-- carbon:badges -->
<!-- /carbon:badges -->
```
Run `carbon badges` to discover and inject CI, Crystal version, project version, license, and docs badges automatically.

### 5. Cutting a Milestone Release
```bash
# 1. Bump minor version for new milestone
carbon bump --minor

# 2. Tag release, seal changelog, update 'latest' floating tag, and push to origin
carbon tag v0.2.0 -m "Release v0.2.0 milestone" --push
```

### 6. GitHub Actions CI Configuration
Ensure `fetch-depth: 0` is set in `actions/checkout@v4` so Git has the full history for commit counting:
```yaml
- name: Checkout repository
  uses: actions/checkout@v4
  with:
    fetch-depth: 0

- name: Build Carbon Binary
  run: shards build carbon

- name: Verify Version Alignment & Changelog
  run: |
    bin/carbon check
    bin/carbon doctor
```

---

## Best Practices & Troubleshooting
- **CI Pre-commit Hook Skip**: `carbon doctor` automatically skips pre-commit hook checks in CI environments (`ENV["CI"] == "true"`).
- **Squash History Resilience**: Carbon preserves monotonic commit numbering even if Git history is squashed or rebased.
- **Hook Idempotency**: Multiple `bump --hook` invocations before a commit is created will not double-increment the commit index.
