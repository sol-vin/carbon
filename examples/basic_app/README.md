# BasicApp (Carbon Example)

A reference Crystal application demonstrating zero-friction automated versioning with Carbon.

## Features Demonstrated

1. **Compile-Time Version Macro (`Carbon.version!`)**:
   Reads `shard.yml` at compile time and embeds:
   - `BasicApp::VERSION` (String, e.g. `"0.1.0"`)
   - `BasicApp::MAJOR_VERSION` (Int32)
   - `BasicApp::MINOR_VERSION` (Int32)
   - `BasicApp::COMMIT_VERSION` (Int32)
   - `BasicApp.carbon_version` (Carbon::Version struct with `<=>` comparison)

2. **Zero-Overhead Runtime**:
   Version constants are computed at compile time by the Crystal macro engine with zero runtime overhead or external binary dependencies at runtime.

3. **Automated Commit Bumping**:
   When used in a Git repository with `carbon init`, every commit made automatically increments the commit number in `shard.yml`.

## How to Run

```bash
cd examples/basic_app
shards install
crystal run src/app.cr
```

Output:
```text
=================================================
  Welcome to BasicApp powered by Carbon!
=================================================
  Application Version: 0.1.0
  Major Component:     0
  Minor Component:     1
  Commit Index:        0
  Object Version:      0.1.0
=================================================
```
