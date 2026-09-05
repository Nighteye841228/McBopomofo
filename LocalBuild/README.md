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

## Install the current working copy

From the repository root:

```sh
./install.sh
```

The installer builds the latest source, checks the bundle, prepares a verified
copy, and backs up the installed version before replacing it. It installs into
`~/Library/Input Methods/McBopomofo.app` without sudo. Backups are kept in unique
subdirectories of `~/McBopomofo Backups`. Failed replacement restores the previous
bundle; cleanup also restores a moved backup if an interruption leaves the
destination missing. Log out and back in after installation.

Use `./install.sh --check` to build and validate without installing, or
`./install.sh --skip-build` to install an existing checked build. The latter still
runs the bundle self-check and signature verification. `./install.sh --help`
shows the available options. The installed app retains the local build's OpenCC
and character-info fallbacks described above.

Installer replacement and rollback checks use temporary directories and do not
register an input method or stop running applications:

```sh
python3 LocalBuild/test-install.py
```

## Mixed-input regression tests

Run the Swift Testing suites against the production Swift and Objective-C++
implementation, with a Swift 6 Command Line Tools installation that includes
the Testing framework, CMake, and Python 3.9 or later:

```sh
python3 LocalBuild/test.py
```

The runner builds its own dependencies and engine under
`Artifacts/MixedInputTests`, uses repository dictionary data, and runs with a
separate test bundle identifier. It neither installs an input method nor uses
the input method's preference domain. OpenCC and character-info lookup use the
same local fallbacks as the development build; this does not replace full
Xcode or IMKit application testing.

After the first build, `--skip-dependencies` reuses the runner's Swift dependency
modules. Rebuild them after changing the installed Swift toolchain. `--filter`
accepts a Swift Testing name filter. For comparison against the original
KeyHandler in HEAD (expected to fail the new regression cases):

```sh
python3 LocalBuild/test.py --skip-dependencies --baseline --filter englishPhraseBeforeChinese
```

A successful run replaces `coverage.profraw`, `coverage.profdata`, and
`coverage.lcov` in the test output directory. Run the normal suite again after
a baseline comparison before auditing coverage. Test source copies preserve
line numbers, and the export maps their paths back to `McBopomofoTests`.

For the changed-function CRAP audit, install Lizard as documented in
[function-crap-audit.md](../Source/Tools/function-crap-audit.md), then run:

```sh
PYTHONPATH=/tmp/mcbopomofo-crap-tools /usr/bin/python3 Source/Tools/audit-function-crap.py \
  --lcov Artifacts/MixedInputTests/coverage.lcov \
  > Artifacts/MixedInputTests/crap-report.json
```
