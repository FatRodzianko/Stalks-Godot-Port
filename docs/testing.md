# Testing

Framework: **GUT 9.7.1**, installed at `addons/gut/`.

Version matters here. GUT's own compatibility table maps **9.7.1 (the `godot_4_7`
branch) to Godot 4.7.x**, while its `main` branch targets 4.6.x — so "latest" is the
wrong thing to grab for this project. If Godot is ever upgraded, check that table
before upgrading GUT.

Do not install gdUnit4 alongside it. One framework only.

---

## Running the suite

From the project root, with `<godot>` being the console executable named in
`CLAUDE.md`:

```
<godot> --headless --path . -s res://addons/gut/gut_cmdln.gd
```

Configuration lives in `.gutconfig.json`, so no flags are needed. On a cold
checkout, import first — there is no `.godot/` cache yet:

```
<godot> --headless --path . --import
```

Useful ad-hoc flags:

| Flag | Effect |
|---|---|
| `-gtest=res://tests/unit/test_year_resolver.gd` | Run one file |
| `-gunit_test_name=test_split` | Run only tests whose name contains this |
| `-glog=2` | More verbose output |
| `-gexit` | Exit when finished (already the default via config) |

The editor also has a GUT panel at the bottom of the window once the plugin is
enabled, which it is in `project.godot`. Headless CLI runs do **not** require the
plugin to be enabled.

---

## Layout

```
tests/
  fixtures/        Shared helpers. NOT scanned for tests.
    stalks_fixture.gd          The ten real stalks, event sets, state builders
    fixed_price_model_stub.gd  Test double with a constant price delta
  unit/            Everything GUT runs. One file per unit under test.
    test_market_mood.gd
    test_random_range_price_model.gd
    test_event_pool.gd
    test_trade_rules.gd
    test_year_resolver.gd
```

`.gutconfig.json` points only at `tests/unit`, which is why fixtures can live
beside them without being mistaken for test scripts.

---

## Conventions

**Always seed the RNG.** Every test touching randomness takes its generator from
`StalksFixture.rng(seed)`. A test whose outcome depends on unseeded randomness is a
bug, not a test — it will eventually fail for no reason and be ignored.

**Statistical assertions are seeded too.** Checks like "the contrarian move fires
~10% of the time" run 60,000 seeded iterations with a generous tolerance. The point
is to catch a *wrong implementation* (50%, or 0%), not to validate Godot's RNG, so
the tolerance is deliberately loose while the seed keeps it stable.

**Use the stub to isolate a rule.** `FixedPriceModelStub` makes prices move by a
constant, so a split or bankruptcy test can set a price by hand and assert on one
behaviour instead of fighting the real random model.

**Pin ordering, not just outcomes.** Several rules only make sense as a sequence —
dividends paid on post-split share counts, a negative event preventing a split, an
event bankrupting a stalk the base move spared. Those tests exist specifically to
stop a future refactor quietly reordering the pipeline.

**Add a regression test for every rule bug found.** The original shipped with
several; the point of this suite is that the port does not.

---

## Current coverage

65 tests, ~11,600 asserts, about 2.4 seconds.

| File | Covers |
|---|---|
| `test_market_mood.gd` | 7/12 bull weighting, labels, degenerate weights |
| `test_random_range_price_model.gd` | Contrarian rate, inclusive range endpoints, softening thresholds, truncation direction, static stalks |
| `test_event_pool.gd` | Pool sizes 45/45, no repeats within a cycle, refill on exhaustion, bankrupt-target skipping without consuming |
| `test_trade_rules.gd` | Buy/sell validation and rejection reasons, max affordable, net worth with holdings and loans, ranking and tie-breaking |
| `test_year_resolver.gd` | Split rounding, threshold boundary, both bankruptcy passes, dividend sequencing, displayed yearly change, game length, determinism |

**Not yet covered:** loans (Phase 2), content validation (Phase 3), and anything
scene-dependent (Phase 4 onward). Scene behaviour will be tested through GUT's
scene-tree tests, not asserted from a script running outside the tree.
