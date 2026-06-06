# Hello Extension

This is a real Roc-to-WASM extension for the Reasonait host.

Layout:

- [extension.roc](/Users/jeppe/Documents/projects/reasonait/extensions/hello/extension.roc) is the only author-facing source file
- [build.sh](/Users/jeppe/Documents/projects/reasonait/extensions/hello/build.sh) delegates to `reasonait extension build`

Build it with:

```bash
reasonait extension build ./extensions/hello
```

Then load it with:

```bash
reasonait extension run ./extensions/hello
```

Reasonait now owns the Roc prelude, the Roc platform, and the Zig bridge
centrally under [`extension/authoring/`](/Users/jeppe/Documents/projects/reasonait/extension/authoring).
Extension authors only edit `extension.roc`.

In the official release layout, `reasonait extension build` will prefer private
toolchains bundled beside the `reasonait` executable under `toolchains/`.

The test suite keeps the synthetic wasm fixture for fallback coverage, and also
builds this Roc extension end to end whenever the Roc/Zig toolchain is
available.
