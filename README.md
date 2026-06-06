# Reasonait Extensions

Standard and example extensions for [Reasonait](https://github.com/jeppejohansen/reasonait).

This repository is source-first. Extension authors edit `extension.roc`; Reasonait owns the generated Roc app wrapper, Roc platform, Zig bridge, and WASM ABI glue.

## Requirements

Best path:

```sh
reasonait version
```

A Reasonait release should include the private toolchains needed for extension builds on supported platforms.

Source-checkout fallback:

```sh
REASONAIT="go run /path/to/reasonait" ./scripts/build-all.sh
```

## Build

Build every extension into `dist/`:

```sh
./scripts/build-all.sh
```

Use a custom Reasonait command:

```sh
REASONAIT="/path/to/reasonait" ./scripts/build-all.sh
REASONAIT="go run /path/to/reasonait" ./scripts/build-all.sh
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

Release assets should contain prebuilt `.wasm` modules for users who only want to install extensions.

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
