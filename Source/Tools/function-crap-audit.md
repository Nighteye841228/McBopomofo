# Function CRAP audit

`audit-function-crap.py` reports new and modified functions relative to a Git
revision (default: `HEAD`) and exits with status 1 when any score exceeds 10.
It includes supported untracked source files. Explicit path arguments restrict
the audit; an explicit path with no changed hunks audits every function in it.

Install the parser in an isolated directory and run from the repository root:

```sh
/usr/bin/python3 -m pip install --target /tmp/mcbopomofo-crap-tools lizard==1.24.0
PYTHONPATH=/tmp/mcbopomofo-crap-tools /usr/bin/python3 Source/Tools/audit-function-crap.py
```

The calculation is `CC² × (1 − coverage)³ + CC`, where CC is Lizard's
cyclomatic complexity and coverage is the fraction of executable source lines
covered within the function's inclusive source range. Missing coverage is
conservatively zero, including functions with no executable lines in the
coverage export. Such results are upper bounds, explicitly identified by
`conservative_zero_coverage` in the JSON report. A function with CC 1 has an
upper bound of 2; CC 2 has an upper bound of 6. CC above 10 cannot pass even
with complete coverage.

For measured coverage, instrument the final source with LLVM coverage flags,
run the tests, merge their profiles, and export LCOV:

```sh
xcrun llvm-profdata merge -sparse /tmp/tests.profraw -o /tmp/tests.profdata
xcrun llvm-cov export /path/to/test-executable -instr-profile=/tmp/tests.profdata -format=lcov > /tmp/tests.lcov
PYTHONPATH=/tmp/mcbopomofo-crap-tools /usr/bin/python3 Source/Tools/audit-function-crap.py --lcov /tmp/tests.lcov
```

Clang instrumentation uses `-fprofile-instr-generate -fcoverage-mapping`;
Swift uses `-profile-generate -profile-coverage-mapping`. Regenerate profiles
after source changes. The audit does not validate profile freshness. Multiple
instrumented binaries must be supplied to LLVM's exporter using its `-object`
options so that the resulting LCOV file includes all audited production and
test sources.

Lizard is a source parser, not a compiler control-flow analysis. The audit
normalizes Swift `.set(...)` member names in memory because Lizard 1.24.0
otherwise misidentifies them as property accessors and loses function
boundaries. This replacement preserves line numbers and control flow.
Swift argument labels, optional expressions, and nested closures can still
affect its complexity model; review unusual output against the source.
Coverage is executable line coverage, not branch coverage, and does not prove
that every input combination was exercised. Unchanged legacy functions are
outside the default report; a passing changed-function audit does not claim
that the whole repository meets the threshold.
