# Task 2 report: typed objective actions and shared destinations

Status: DONE

## Scope delivered

- Added immutable, ordered `SourceActionSpan` records while preserving the legacy
  `SourceStep.action`, speech, entity, zone, item, and coordinate fields for generated-data
  compatibility.
- Added conservative typed parsing for action chains, exact authoritative zone mentions,
  direct unlinked interaction targets, literal `???` targets, temporal zones, battlefield
  entrances, material protection instructions, and required-state warnings.
- Reconciled action spans and individual target/zone/map/grid/item candidates with source
  ownership, alignment score, paired/unpaired reason, and partial agreement. Flattened
  compatibility bags are not used by the reviewed target or shared destination resolvers.
- Added one immutable `ReviewedObjectiveDestination` model for missions and quests. The
  generator temporarily reads existing `mission_destination_overrides`, but emits only
  `objective_destinations` in new reconciliation output.
- Preserved source revisions, source step IDs, immutable destination IDs, exact references
  and points, ingress/transport fields, eligibility, route-contract IDs, and instruction-only
  state in Lua and review output.
- Exported every reconciled step to `target-review.json` exactly once, including text-only
  notes, with typed claims and a provisional classification.
- Legacy free-text `route_evidence` is ignored and omitted. Compatibility destinations remain
  `catalogue` candidates with `route_ready=false`; Task 2 creates no new route start.

## TDD evidence

Baseline before test edits:

```text
tools\test_objective_guides.ps1
Ran 54 tests
OK
```

Primary RED after adding the Task 2 tests and before production edits:

```text
tools\test_objective_guides.ps1
ImportError: cannot import name 'SourceActionSpan' from 'tools.objective_guides.model'
Ran 1 test
FAILED (errors=1)
exit code 1
```

Additional focused RED checks caught and then guarded source-revision omission, mismatched
reviewed target points, missing typed `return to` actions, overlong Abandoned Mineshaft target
capture, and missing battlefield entrance semantics.

Final focused GREEN:

```text
tools\.objective-guides-venv\Scripts\python.exe -m unittest \
  tools.test_objective_guides.WikitextParserTests \
  tools.test_objective_guides.ReconciliationTests \
  tools.test_objective_guides.ObjectiveDestinationTests \
  tools.test_objective_guides.GeneratedArtifactTests -v
Ran 41 tests
OK
```

Final complete GREEN:

```text
tools\test_objective_guides.ps1
Ran 68 tests
OK
Objective guide tests passed
```

Additional verification:

```text
python -m py_compile <all six Task 2 Python files>
exit code 0

git diff --check
exit code 0
```

## Commit

Planned commit subject: `feat: preserve typed objective actions`

Base commit: `a194e673d76917317145cd8a2ca1e10242fafecc`

## Concerns and deferred work

- The complete source corpus was intentionally not regenerated. Task 6 owns refresh and full
  deterministic regeneration after the schema stabilizes.
- The parser is deliberately conservative. Names that cannot be typed from exact source syntax
  and exact current zone catalogue data remain source-owned unresolved claims rather than
  guessed NPC/object/enemy identities.
- A catalogue identity or exact point is not route proof. Task 3 owns action-class resolution,
  and Task 4 owns current hash-bound route/transition contracts and any eligibility promotion.
- No runtime Lua navigation behavior, live addon deployment, route start, Ghidra target claim,
  wiki refresh, or corpus artifact was changed in this task.
