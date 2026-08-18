# McBopomofo Local Build Without Xcode

This directory builds a macOS 14 or later Apple Silicon development bundle
with Command Line Tools. It is intended only for local mixed-input verification.

Run from the repository root:

```bash
zsh LocalBuild/build.sh
```

The output is `Artifacts/LocalBuild/McBopomofo.app`. The build uses ad-hoc code
signing and the production input-source identifiers. OpenCC conversion and system
character-information lookup use local fallbacks; Bopomofo input, mixed ASCII
segmentation, candidates, preferences, and personalization use the production
implementation.

The script does not install or replace an input method.
