# Reasonait Extensions

Standard and example extensions for [Reasonait](https://github.com/jeppejohansen/reasonait).

This repository is source-first. Extension authors edit `extension.roc`; Reasonait owns the generated Roc app wrapper, Roc platform, Zig bridge, and WASM ABI glue.

## Structure

Each extension lives in its own directory:

```text
extensions/<name>/
|-- extension.roc
`-- README.md
```

`extension.roc` is the source artifact authors edit. `README.md` is optional, but recommended for any extension that exposes tools or user-visible behavior.

Release builds produce one WASM module per extension:

```text
dist/<name>.wasm
```

That means `extensions/context-bank/extension.roc` becomes `context-bank.wasm`, `extensions/write-guard/extension.roc` becomes `write-guard.wasm`, and so on.

## Requirements

Best path for users and extension authors:

```sh
reasonait version
```

A Reasonait release includes the private toolchains needed for extension builds on supported platforms. Authors should not need to install Roc, Zig, or the Reasonait Roc platform by hand.

Source-checkout fallback for Reasonait development:

```sh
cd /path/to/reasonait
go build -o /tmp/reasonait-current .

cd /path/to/reasonait-extensions
REASONAIT=/tmp/reasonait-current ./scripts/build-all.sh
```

## Using Extensions

End users should install release assets, not build from source. A release contains:

```text
<extension>.wasm
manifest.toml
SHA256SUMS
```

The intended install shape is that Reasonait downloads a selected `.wasm` asset, verifies it, and registers it under a local alias. Until that installer flow is implemented, the release assets are still the canonical user-facing build output.

Source checkouts are for authoring, reviewing, and local development.

## Build

Build every extension into `dist/`:

```sh
./scripts/build-all.sh
```

Use a custom Reasonait command:

```sh
REASONAIT="/path/to/reasonait" ./scripts/build-all.sh
```

Build one extension:

```sh
reasonait extension build ./extensions/hello ./dist/hello.wasm
```

## Test

Run Reasonait's extension load/build checks for every extension:

```sh
./scripts/test-all.sh
```

## CI and Releases

CI checks out both this repository and `jeppejohansen/reasonait`, builds a local Reasonait release bundle, and runs `scripts/test-all.sh` through that bundled binary. This keeps the test path aligned with the user-facing binary instead of relying on locally installed Roc or Zig.

Tagged releases build every extension and upload:

- one `<name>.wasm` file per extension
- `manifest.toml`
- `SHA256SUMS`

The release workflow intentionally does not commit generated files back to the repository.

## Repository Policy

Commit extension source and docs:

```text
extensions/<name>/extension.roc
extensions/<name>/README.md
```

Do not commit generated files:

```text
extensions/<name>/.reasonait/
extensions/<name>/dist/
dist/*.wasm
```

When adding an extension, add a new `extensions/<name>/` directory and a matching `[[extensions]]` entry in `manifest.toml`.

## Extensions

- `agent-monitor`: mode panel for live agent-loop state
- `compaction`: explicit conversation compaction tool
- `context-bank`: context storage and recall support
- `critical-assessor`: nudges the agent toward verification after work phases
- `extra-tools`: experimental helper tools such as glob, web fetch, and evidence storage
- `hello`: minimal example extension
- `output-repair`: nudges text-form tool calls back into native tool calls
- `quality-monitor`: observes quality signals across turns
- `skill-inject`: injects concise tool-use guidance
- `small-model-harness`: stricter workflow guidance for small local models
- `smart-compaction`: compaction guidance for context pressure
- `thinking-budget`: model-parameter and prompting guidance for thinking budget
- `write-guard`: guarded write tool that prefers edits for existing files
