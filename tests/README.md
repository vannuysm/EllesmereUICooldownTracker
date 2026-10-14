# Test suite

The addon remains Lua. Python/pytest organizes and reports the tests; Lupa executes
the real addon and codec on both Lua 5.1 and LuaJIT 2.1. Dependencies are managed by
`uv` and pinned in `uv.lock`. No Python application package is built or installed.

## Run

Install [uv](https://docs.astral.sh/uv/getting-started/installation/), then run from
the checkout:

```sh
uv sync --locked
uv run --locked pytest
uv run --locked pytest tests/unit
uv run --locked pytest tests/performance --performance-report=test-results/performance.json
```

`uv run pytest` also works and automatically synchronizes the environment. Use
`--locked` in CI or when verifying an existing lockfile. The harness requires
Python 3.14, which is also the default interpreter. Both Lua runtimes run automatically
for every Lua case, with their names visible in pytest parameter IDs.

Useful selections:

```sh
uv run --locked pytest tests/unit/profiles
uv run --locked pytest tests/unit/trackers/test_buffs.py
uv run --locked pytest -m regression
uv run --locked pytest -m performance
uv run --locked pytest -k unreadable
uv run --locked pytest --junitxml=test-results/all.xml
```

## Organization

Automated tests are split between `unit` and `performance`. Manual testing docs
live under `docs`, using the same feature categories as the automated tests.
Shared Python fixture/bridge files remain at the test root. Feature directories
keep test functions, Lua cases, and their fixtures together.

```text
tests/
  __init__.py
  conftest.py                       # runtime fixtures, markers, JSON reports
  lua_runtime.py                    # Lua bridge and named-case discovery
  README.md
  unit/
    profiles/
      test_codec.py                 # FCT1 syntax, round trips, resource guards
      test_validation.py            # schema, bounds, atomic failures, normalization
      test_application.py           # imports, saved profiles, storage references
      test_fixtures.py              # portable legacy payload contract
      *_cases.lua                   # existing assertions against real Lua code
      support.lua
      fixtures/                     # stable Hunter/Paladin FCT1 literals
    trackers/
      test_configuration.py         # controls, slash/profile entry points, positions
      test_cooldowns.py              # caches, events, visibility, native durations
      test_buffs.py                  # aura deltas, resets, synthetic timers, text
      test_reminders.py              # alternatives, ownership, ordering, uncertainty
      test_ranks.py                  # markers and combat deferral
      test_standalone.py             # operation without EllesmereUI
      *_cases.lua
      support.lua
    support/
      bootstrap.lua                 # load TOC and create a fresh mocked WoW boundary
      wow_mocks.lua                 # shared frames/events/queries/counters
  performance/
    profiles/
      conftest.py                    # codec-only runtime and measurement helper
      test_codec.py                 # large strings, malformed inputs, keys, depth
    trackers/
      test_collection.py            # deterministic collection budgets
      workloads.lua                 # warmed, representative game-state scenarios
  docs/
    trackers/
      IN_GAME.md                    # runtime responsibilities and client checks
      BUFF_STATE_VERIFICATION.md    # detailed buff-state regression procedures
```

The 98 profile regressions and 22 tracker/standalone cases each run independently
on both runtimes. Four additional fixture checks and 56 performance cases bring
the suite to 300 pytest cases. Each behavioral case receives a fresh namespace,
mock state, frame pool, event queue, and Lua VM. A failure never depends on which
case previously ran. Python test modules parametrize existing Lua assertions so
pytest can select, report, and rerun individual cases. The Lua bridge is test
support, not a second implementation of addon behavior.

Keep new regressions with the affected feature. Give each case a descriptive
behavioral name and make its setup self-contained. Avoid broad catch-all scripts,
duplicated mocks, tests of implementation details, and snapshots of developer
diagnostics. Truly shared fixtures belong in the root `conftest.py`; codec-only
performance fixtures stay within their feature directory.

## Fixtures and portability

The retained FCT1 files contain profile configuration and generic class names
only. Their [fixture notes](unit/profiles/fixtures/README.md) explain their scope.
They are checked for storage metadata and machine paths as part of the suite.
Lua source and fixture paths are resolved from the current checkout, not from
an installation directory or the shell's working directory.

No test requires ignored diagnostics, installed WoW data, previous Git revisions,
saved-variable exports, or an externally installed Lupa package. The older
one-off runners, duplicate mocks, historical measurement JSON, saved-variable
exporter, and before-review codec snapshots are not retained as suite inputs.
Generated environments, caches, JUnit reports, and performance reports are ignored
by Git and excluded from addon packaging; all source tests and fixtures are
versioned. The existing `.pkgmeta` exclusion for `/tests/` stays in place.

## Performance

Tracker workloads run 100 warmed iterations with eight cooldown spells, three
item-name matches in 60 occupied bag slots, six tracked buffs, eight self/ally
reminder entries, and twenty auras on each of five units. Burst workloads send
twenty events before flushing. Each scenario starts in a fresh runtime.

CI asserts deterministic API-call budgets: unchanged resolution does no extra
spell/bag queries, a targeted burst refreshes one spell, a player aura refresh
does not reread other units, and appearance/preview changes do not collect game
state. Codec workloads verify successful/error outcomes and known output before
recording measurements.

Elapsed times and Lua heap growth with GC stopped are observations, not CI
thresholds. Shared runners, JIT warmup, and allocator differences make fixed
wall-clock thresholds unreliable. JSON reports contain test IDs, runtime names,
input/output sizes, counts, elapsed time, and allocation proxies. They contain
no developer-machine paths or stored baseline snapshots. The proxy includes the
mock boundary and excludes WoW's native allocations and frame-time behavior.
The depth-12 encoding workload targets the encoder's maximum table depth; it
does not assert decoder round-trip behavior at that boundary because the decoder
also counts the scalar leaf. Ordinary codec round trips remain regression-tested.

## Pull-request CI

[`.github/workflows/tests.yml`](../.github/workflows/tests.yml) runs on pull requests,
pushes to `main`, and manual dispatch. Unit/regression jobs cover Windows and
Ubuntu using Python 3.14. A separate Ubuntu/Python 3.14 job runs performance
budgets and records measurements. Every job tests both Lua runtimes, installs with
`uv sync --locked`, and uploads JUnit results; the performance job also uploads
JSON. The workflow needs no repository secrets or Git history.

The setup follows the official [uv GitHub Actions guidance](https://docs.astral.sh/uv/guides/integration/github/).
Workflow files and lockfiles must be committed with the tests to activate PR
checks. Repository branch-protection settings determine whether those checks
are required for merging; no remote settings are changed by this work.

On Windows the harness disables Python's automatic fault handler during the pytest
session because [LuaJIT's handled Windows exception unwinding](https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_err.c)
otherwise produces false fatal-exception tracebacks. Normal assertions and process
failures still fail the run. Fault handling on other platforms is unchanged.

## In-game checks

Mocks cover readable values, simulated API failures, and fake secret values;
they cannot emulate protected frames, real secret-value restrictions, native
animation, or interactive widget behavior. Keep the
[in-game checklist](docs/trackers/IN_GAME.md) and
[buff-state checks](docs/trackers/BUFF_STATE_VERIFICATION.md) for supported-client
verification.
