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

## Final authoritative corpus rebuild and reboot recovery

The official two-site refresh was attempted first. BG Wiki returned its explicit
`Retry-After: 1200` rate limit before the transactional publisher could replace
any checked-in artifact. The last complete same-day BG Wiki and FFXIclopedia
snapshots were therefore retained and both final corpus generations used the
documented `--offline` path. No partial network result was published.

The completed pre-reboot hard gate was:

```powershell
tools\.objective-guides-venv\Scripts\python.exe -m unittest tools.test_wiki_authoritative_objective_corpus -v
```

```text
Ran 4 tests in 628.764s
OK
```

Those four tests validate the checked-in provenance/authority graph, every
generated self-pinned flat shard, the compact-footprint boundary, and two
consecutive offline generations with byte-identical artifacts.

The final exact corpus accounting is:

```text
native objectives                         1,844
missions                                    706
quests                                    1,138
source-backed objectives                  1,806
structural source-missing rows               38
typed action claims                      22,829
typed material actions                   22,479
typed nonmaterial actions                   350
explicit context-only ledger rows        16,898
total action-resolution ledger rows      39,727
exact destination-review candidates       1,803
```

The 38 source-missing native records stay non-routable and are classified only
as 7 native sentinels, 16 chapter indexes, 7 native placeholders, and 8 absent
wiki sources. No placeholder walkthrough was invented.

The generated Lua footprint is:

```text
source shards                  19,407,941 bytes (51 files)
reconciliation shards          19,240,256 bytes (26 files)
guide index                     1,292,715 bytes (1 file)
presentation subtotal          39,940,912 bytes
progression shards             32,122,900 bytes (26 files)
runtime corpus total           72,063,812 bytes (104 files)
```

The reboot did not leave a partial output. A fresh post-reboot hash pass over
all 118 corpus artifacts reproduced this exact canonical hash-map serialization:

```text
sha256("<relative-posix-path>\t<lowercase-file-sha256>\n" for sorted paths)
5920b4073c1fb86c7f96f6bca90e92fb83bc106ea71338a5a12c4f38b5f153c5
```

The canonical JSON serialization of the same map is independently
`43cd707fe34e04dd0d5818783c7da2432c6fb3571899d4f0228b651ae34a6c45`.
The runtime manifest bytes hash to
`0b5965660348e15f129bfc3e4d790f456011ae745932dc14db11bb98b9bd1315`,
and the reader contains exactly that one reviewed pin. All seven manifest source
children match their SHA-256 rows; the runtime module row is present and pins
`e598b49ccc73ced21bbd1ba23826c350a758f89522a26b2b6b4016034a0bb317`.

Fresh post-reboot focused verification:

```text
tools.test_objective_guides             Ran 197 tests in 3.221s — OK
tools.test_objective_route_evidence      Ran 73 tests in 8.792s — OK
Lua 5.1 generated-module execution      104/104 tables loaded
reader objective-integrity harness      passed
AccessXI SHA-256 behavior harness        passed
reader plus four route modules syntax    loaded by Lua 5.1
manifest source-child verification       7/7 hashes plus exact reader pin
```

Only the single generated manifest-pin line in `accessxi_reader.lua` belongs to
Task 1. The uncommitted production `mission_quest_guides.lua`, Task 2 harnesses,
navigation work, and `build-collision-mhaura-repro/` remain outside this commit.

### Clean-export line-ending regression

A post-commit clean `git archive` comparison found that the byte-pinned
`route-evidence-v2.jsonl` was the only one of the 118 artifacts exported with
different bytes: Git converted its 35 LF line endings to CRLF because JSONL had
no explicit repository EOL policy. The working generator output and staged blob
were both the approved LF bytes, but a clean Windows export would begin the next
offline determinism test from different bytes.

The focused regression executes a real `git archive --worktree-attributes` and
compares the archived JSONL member byte-for-byte with the generated artifact.
Before the fix it failed with the archived file 35 bytes larger. The minimal
repository fix adds `*.jsonl text eol=lf`, matching the existing JSON, TSV, and
Lua deterministic-artifact rules. The same focused test then passed. The corpus
artifact digest remains exactly `5920b4073c1fb86c7f96f6bca90e92fb83bc106ea71338a5a12c4f38b5f153c5`.

## Final progression-safety rebuild

The release corpus was rebuilt from the complete same-day pinned BG Wiki and
FFXIclopedia cache after the fail-closed player-instruction, branch, count,
typed-domain, and acquisition-owner fixes. The final corpus contains 1,844
native objectives (1,806 source-backed and 38 structurally source-missing),
31,124 reconciled steps, 22,951 typed claims, 12,069 material actions, 10,882
nonmaterial claims, 16,777 context-only rows, 39,728 total ledger rows, and
1,506 exact destination candidates. Material BG spans own progression fields;
when BG is present only as nonmaterial context, the material FFXIclopedia span
owns them. That bounded fallback class is pinned at 467 actions across 350
objectives and 445 steps, with no BG-owned progression field in those rows.

Generated runtime size is now 19,398,289 bytes of source shards, 19,170,586
bytes of reconciliation shards, 1,292,173 bytes of index, and 17,656,166 bytes
of compact progression shards. The presentation subtotal is 39,861,048 bytes
and the combined runtime corpus is 57,517,214 bytes. The route manifest remains
`0b5965660348e15f129bfc3e4d790f456011ae745932dc14db11bb98b9bd1315`.

Final acceptance evidence:

```text
objective parser/generator suite                 225 tests — OK
frozen obligation ledger                         47 admit / 12 reject — OK
frozen direct-imperative ledgers                  80 + 56 identities — OK
independent high/strict semantic suspect sets     0 / 0 — OK
deep index, shard, provenance, and ownership gate 1 test in 98.273s — OK
offline determinism rebuild                       118 artifacts, 0 changed — OK
generated Lua 5.1 execution                       104/104 tables loaded — OK
git diff --check                                  clean
```

The final clean-archive artifact map for Task 1 commit `cf3067d` contains all
118 expected paths, including the unchanged reader pin. Its canonical digests
are `6006f5c8c46d56c66285a91d10f6b28c656b006b257ab3ecccaaa48499eae95c`
for sorted tab-separated path/hash rows and
`bb8354962192c95398dc4d843312600a9fc236c5d65e9dd61729c8b44e050f1f`
for canonical JSON. These were recomputed directly from `git archive
--worktree-attributes cf3067d`. The byte-identical rebuild's earlier combined-
worktree digest included the concurrent Task 4 reader hunk, which Task 1
correctly excluded from its commit; that combined-tree value is not the Task 1
release digest. Eight exact obtain instructions still contain a redundant
spoken item name produced by renderer composition; their typed completion
semantics are correct and their stable IDs are pinned as a documented speech-
only follow-up so no ninth row can regress silently. No additional parser
rebuild is part of this release.
