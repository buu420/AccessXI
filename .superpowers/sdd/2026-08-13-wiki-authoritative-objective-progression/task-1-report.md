# Task 1 report — coherent parser and flat-progression schema slice

## Scope and commit

This report covers the coherent Python parser/reconciliation/generator slice only. The final refreshed-corpus and generated-shard rebuild was explicitly deferred by the parent task, so this commit does not stage generated runtime/data artifacts, the full-corpus test, design/plan documents, or Task 2 Lua tests.

Included paths:

- `tools/objective_guides/cli.py`
- `tools/objective_guides/generate_lua.py`
- `tools/objective_guides/objective_destinations.py`
- `tools/objective_guides/reconcile.py`
- `tools/objective_guides/wikitext.py`
- `tools/test_objective_guides.py`
- `.superpowers/sdd/2026-08-13-wiki-authoritative-objective-progression/task-1-report.md`

Commit SHA: this report is part of the scoped commit identified in the parent handoff.

## Research boundary

- Web research checked current BG Wiki examples containing explicit counted obtain steps, including `The Seamstress` (`Obtain 3 Sheepskins`) and current Gather assignment walkthroughs.
- Local Ghidra 12.0.4 was invoked successfully and the existing `ffxi_mission_menu_native_trace.txt` was inspected. It continues to support the established boundary: native state can identify active objectives, but does not provide a universal authoritative intra-objective walkthrough. The progression facts therefore remain revision-pinned wiki facts rather than inferred native stages.

## Behavioral RED

Pre-production command:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest -v `
  tools.test_objective_guides.WikitextParserTests.test_uncounted_fight_and_obtain_actions_use_single_count_semantics `
  tools.test_objective_guides.WikitextParserTests.test_counted_obtain_uses_canonical_link_target_and_rejects_zero_count `
  tools.test_objective_guides.WikitextParserTests.test_composite_fight_obtain_uses_explicit_completion_count_unless_fight_is_counted `
  tools.test_objective_guides.GeneratedArtifactTests.test_runtime_emission_uses_compact_lazy_progression_shards
```

Exit code: `1`.

Observed output:

```text
Ran 4 tests in 0.147s
FAILED (failures=4)

uncounted fight: got (1, 'credited-defeat', False), expected (1, 'single', False)
counted plural link: got target 'Copper Rings', expected 'Copper Ring'
composite completion count: got count 1/credited-defeat, expected 3/inventory-gain
runtime shard: progression_schema_version was absent and the old join-table schema was emitted
```

Follow-up review RED command:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest -v `
  tools.test_objective_guides.WikitextParserTests.test_counted_obtain_uses_canonical_link_target_and_rejects_zero_count `
  tools.test_objective_guides.WikitextParserTests.test_explicit_one_fight_and_obtain_actions_still_use_single_count_mode `
  tools.test_objective_guides.GeneratedArtifactTests.test_progression_payload_is_flat_authoritative_self_pinned_and_revision_sensitive
```

Exit code: `1`.

Observed output:

```text
Ran 3 tests in 0.062s
FAILED (failures=2, errors=1)

Item/ItemIcon target: got '', expected 'Copper Ring'
explicit count one: got 'credited-defeat', expected 'single'
flat payload: progression_objective_payload did not exist
```

Self-review fail-closed RED:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest -v tools.test_objective_guides.GeneratedArtifactTests.test_progression_payload_is_flat_authoritative_self_pinned_and_revision_sensitive
```

Exit code: `1`.

Observed output:

```text
Ran 1 test in 0.002s
FAILED (failures=1)
GenerationError not raised for a material claim whose declared BG and FFXIclopedia source-span pins did not resolve
```

## GREEN implementation

- Uncounted and explicit-one fight/obtain actions normalize to `required_count=1`, `count_mode=single`.
- Explicit counts greater than one use `credited-defeat` for fights and `inventory-gain` for obtains.
- Explicit zero normalizes safely to one and is not emitted as an explicit counted action.
- Counted plural links, `Item`, and `ItemIcon` templates retain the canonical link/item target.
- Composite fight/obtain actions retain the completion-side obtain count unless an explicit fight count governs, in both textual directions and conflicting-count cases.
- Every material objective action is emitted once in one ordered `progression_actions` array with `step_id`, `action_id`, ordering, exact authoritative matcher facts, count/result semantics, per-field source authority, revision pins, and inline exact catalogue facts.
- BG supplies each nonempty field; FFXIclopedia supplies only a missing field. Non-authoritative evidence remains in the JSON review artifacts.
- One canonical Python payload is both SHA-256 revision input and Lua serialization input. Matcher, catalogue, order, count, provenance, native key, shard name, schema, and authority are revision-pinned.
- Index rows and shards carry schema/module/native/revision/authority self-pins. Missing declared material source spans fail generation.
- Runtime shards no longer require claims/ledger/candidate joins or full source/reconciliation action tables.

Focused GREEN command:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest -v `
  tools.test_objective_guides.WikitextParserTests.test_uncounted_fight_and_obtain_actions_use_single_count_semantics `
  tools.test_objective_guides.WikitextParserTests.test_counted_obtain_uses_canonical_link_target_and_rejects_zero_count `
  tools.test_objective_guides.WikitextParserTests.test_explicit_one_fight_and_obtain_actions_still_use_single_count_mode `
  tools.test_objective_guides.WikitextParserTests.test_composite_fight_obtain_uses_explicit_completion_count_unless_fight_is_counted `
  tools.test_objective_guides.GeneratedArtifactTests.test_progression_payload_is_flat_authoritative_self_pinned_and_revision_sensitive `
  tools.test_objective_guides.GeneratedArtifactTests.test_runtime_emission_uses_compact_lazy_progression_shards
```

Exit code: `0`.

```text
Ran 6 tests in 0.158s
OK
```

## Verification

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_guides
```

Exit code: `0`.

```text
Ran 183 tests in 2.784s
OK
```

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_route_evidence
```

Exit code: `0`.

```text
Ran 72 tests in 11.719s
OK
```

A temporary fixture build was loaded directly with the checked-in Lua 5.1 executable:

```text
Lua 5.1 loaded 2 generated progression shards successfully.
```

Scoped `git diff --check` exit code: `0`.

## Corpus counts and deferred rebuild

The checked-in baseline and inherited working refresh both contain `3,889` revisioned source pages. The native manifest remains exactly `1,844` objectives: `706` missions and `1,138` quests across `26` kind/context pairs.

Baseline status counts at `HEAD`:

```text
automatic-stage 1
guide 918
source-conflict 575
source-missing 38
verified-navigation 312
```

Inherited working-refresh status counts before the final rebuild:

```text
automatic-stage 1
guide 837
source-conflict 668
source-missing 38
verified-navigation 300
```

The required final refresh command is recorded verbatim but was not rerun in this slice:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m tools.objective_guides.cli all --repo-root . --ffxi-root 'C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI' --refresh
```

The required second offline byte-equality build command is likewise deferred with the final corpus slice:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m tools.objective_guides.cli all --repo-root . --ffxi-root 'C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI' --offline
```

No corpus byte-equality or final generated-artifact hashes are claimed here because running either command would mutate the explicitly deferred generated corpus. Determinism of the generator on controlled fixtures is covered by the 183-test suite.

## Deferred artifacts and concerns

Deferred, unstaged paths include all refreshed/generated `ashita/addons/accessxi_reader/modules/mission_quest_*` files, `ashita/addons/accessxi_reader/data/mission-quest-route-manifest.tsv`, generated `data/mission-quest-guides/*` artifacts, `tools/test_wiki_authoritative_objective_corpus.py`, the design/plan documents, all three modified Task 2 Lua test files, and `build-collision-mhaura-repro/`.

Concern: the final corpus/shard slice must run the refresh plus two deterministic builds, verify all 1,844 index mappings and generated shard self-pins, measure the checked-in runtime footprint/cache regression, update affected integrity hashes, and only then stage the generated artifacts.

## Stable-review fix round 1/5

The stable review of `3d97593` identified four generator authority/fail-closed defects. The fix round stayed inside the Python generator, catalogue resolver, focused tests, report, and progress ledger; it did not rebuild or stage the generated corpus and did not touch Task 2 Lua tests.

### Behavioral RED

Command:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest -v `
  tools.test_objective_guides.ObjectiveActionResolutionTests.test_catalogue_resolution_applies_source_authority_per_matcher_field `
  tools.test_objective_guides.GeneratedArtifactTests.test_progression_count_triple_uses_explicit_field_authority `
  tools.test_objective_guides.GeneratedArtifactTests.test_progression_instruction_uses_each_authoritative_action_clause `
  tools.test_objective_guides.GeneratedArtifactTests.test_progression_payload_fails_closed_on_incomplete_material_pin_graph
```

Exit code: `1`.

```text
Ran 4 tests in 0.005s
FAILED (failures=6)

catalogue: split BG target/relationship plus FFXIclopedia kind/zone resolved unresolved
count: BG default 1/single/false overrode FFXIclopedia explicit 3/inventory-gain/true
instruction: every action emitted the enclosing BG SourceStep spoken text
pin graph: one-sided stale declaration, missing material ledger, and missing ledger pin raised no GenerationError
```

Each expectation is a hand-derived runtime payload or exact-candidate fact. The tests execute the real reconciliation, action resolver, and progression payload rather than inspecting source strings.

### GREEN implementation

- The count triple is selected atomically. Explicit BG wins, otherwise explicit FFXIclopedia fills an unexplicit BG default, otherwise the normal BG/nonempty fallback applies. All three count fields carry the selected source in `field_sources`.
- Every positive declared source-span order must resolve. Every material action must have a material ledger row, and that row must contain every exact expected source-span pin; additional reviewed fact pins remain valid.
- `instruction` now selects the material action span's `supporting_clause` per field authority. Multi-action steps receive distinct clauses and an FFXIclopedia-only action inside a paired step cannot inherit the BG step text.
- Catalogue target, target kind, relationship, and zone authority are selected independently. Exact game-data identity can therefore survive split source facts and a non-authoritative relationship conflict, while non-authoritative zones remain review evidence instead of being unioned into candidates.
- The obsolete unused `_reconciled_claim_lua` and `_progression_revision` nested-schema helpers were removed after confirming no callers.

Focused GREEN command: the same four-test command above.

Exit code: `0`.

```text
Ran 4 tests in 0.002s
OK
```

Focused regression command:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest -v `
  tools.test_objective_guides.ObjectiveActionResolutionTests.test_catalogue_resolution_applies_source_authority_per_matcher_field `
  tools.test_objective_guides.ObjectiveActionResolutionTests.test_pinned_orcish_pages_resolve_only_reviewed_gate_guards_and_east_west_camps `
  tools.test_objective_guides.GeneratedArtifactTests.test_progression_payload_is_flat_authoritative_self_pinned_and_revision_sensitive `
  tools.test_objective_guides.GeneratedArtifactTests.test_progression_count_triple_uses_explicit_field_authority `
  tools.test_objective_guides.GeneratedArtifactTests.test_progression_instruction_uses_each_authoritative_action_clause `
  tools.test_objective_guides.GeneratedArtifactTests.test_progression_payload_fails_closed_on_incomplete_material_pin_graph
```

```text
Ran 6 tests in 0.078s
OK
```

### Fix-round verification

The original 183-test suite now contains four new behavioral tests, so its fresh total is 187:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_guides
```

```text
Ran 187 tests in 2.793s
OK
```

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_route_evidence
```

```text
Ran 72 tests in 10.275s
OK
```

The first complete-suite pass correctly exposed one stale test fixture that bypassed the new ledger contract and one candidate-support regression that omitted an exact reviewed location-fact pin. The fixture now resolves a real ledger, and candidate support retains both per-field source spans and reviewed fact pins. The six-test focused regression command above proves both corrections.

Fix-round commit SHA is reported in the parent handoff because a file cannot contain the SHA of the commit that contains that same file.

## Stable-review fix round 2/5

The remaining reviewed-destination defect selected one whole BG span and required
that span alone to contain every destination field. A reviewed claim whose BG
span supplied the authoritative target/relationship and whose FFXIclopedia span
supplied the fallback kind/zone was therefore rejected even though its exact
catalogue point survived.

### Behavioral RED

Command:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest -v tools.test_objective_guides.ObjectiveDestinationTests.test_reviewed_destination_uses_field_authority_across_paired_source_spans
```

Exit code: `1`.

```text
test_reviewed_destination_uses_field_authority_across_paired_source_spans ... FAIL

Split-field reviewed destination was rejected: Reviewed objective destination source claim is conflicted or unsupported.

Ran 1 test in 0.002s
FAILED (failures=1)
```

This exercises the public reviewed-destination resolver with a pinned claim and
exact catalogue point. The BG action span independently supplies `target=Alpha`
and `relationship=talk-to`; the FFXIclopedia action span supplies
`target_kind=npc` and `zone_mentions=(East Ronfaure,)`. The expected source
claim and both source revisions are independently asserted.

### Minimal GREEN and fail-closed regression

`_select_source_claim()` now validates the paired source spans with the same
per-field BG-primary/FFXIclopedia-fallback selector used by automatic catalogue
semantics. It retains both original action spans as provenance. Target fallback
keeps the existing fail-closed boundary: if the authoritative span has no exact
`target` and exposes more than one distinct canonical typed mention, no mention
is accepted as the reviewed target.

Focused GREEN command (same single test as the RED):

```text
Ran 1 test in 0.001s
OK
```

The first complete objective-guide run then exposed the target-ambiguity guard
as a behavioral regression while the shared selector was being introduced:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_guides
```

```text
Ran 188 tests in 2.818s
FAILED (failures=4)
```

The four subtest failures belonged to the two existing canonical-ambiguity
tests: both `Mob A` and `Mob B` were incorrectly accepted from one span, and the
display-alias variant likewise stopped failing closed. After restoring the
target-only ambiguity guard, the new split-field test and both ambiguity tests
passed together:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest -v `
  tools.test_objective_guides.ObjectiveDestinationTests.test_reviewed_destination_uses_field_authority_across_paired_source_spans `
  tools.test_objective_guides.ObjectiveDestinationTests.test_destination_uses_only_exact_linked_target_from_selected_clause `
  tools.test_objective_guides.ObjectiveDestinationTests.test_paired_destination_uses_canonical_link_identity_not_display_aliases
```

```text
Ran 3 tests in 0.117s
OK
```

### Fix-round verification

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_guides
```

```text
Ran 188 tests in 2.830s
OK
```

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_objective_route_evidence
```

```text
Ran 72 tests in 9.056s
OK
```

No generated corpus artifact or Task 2 Lua test is part of this fix round.
