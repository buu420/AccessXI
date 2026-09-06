# Nation-mission destination and ingress audit

**Date:** 2026-09-05 (revision 4 — final)
**Worktree:** `C:\Users\buu42\.codex\worktrees\AccessXI\nation-mission-routes` at `5396c39`
**Source read:** the worktree tree, via `ACCESSXI_ADDON=<worktree>/ashita/addons/accessxi_reader`
**Tools owned here:** `tools/audit_nation_mission_routes.lua`, `tools/test_nation_ingress_coverage.lua`
**Scope of this document:** inventory, case export, one regression. No runtime, data, deployment or packaging edits were made from here. Ships as **v2026.09.05.1**, built and published by Codex.

## Revision history — what was wrong before

**Rev 1** implied the mission step chose between the two `Gate: Magical Gizmo`
points. It did not. It also inherited the walkthrough's material filter and so
silently dropped the very step it was built to find.

**Rev 2** fixed enumeration but then counted **971 `note` steps** as actionable
steps that "refused" with reason `unknown` — 971 fictional gaps stacked on top of
the real ones.

**Rev 3** classified by the step's **verb**. A `note` whose compact action happens
to name an NPC is still a note; the resolver declines it by design. `examine` and
`travel` can never land in that bucket, so no real gap is hidden. Candidate export
deliberately stays **wider** than classification: scoping it to `actionable` cost
259 candidates the moment the buckets changed, which is how that mistake was caught.

**Rev 4 (this one)** records the final shipped figures and the design decision that
resolved the one open concern.

## What actually happened in the report

```
mission:Windurst:1:step-017 [examine]  (entity-less)
    East Sarutabaruta(116) -> Inner Horutoto Ruins(192)
    target = "Inner Horutoto Ruins entrance from East Sarutabaruta"
    source = zone-travel
```

The step resolved to a **generic zone entrance**, not to a gate. In the live report
the player stood in West Sarutabaruta, so the same zone-travel target selected the
**West** mouth; the player then tried both gate points manually.

Root cause of the empty target: both source pages say "Gate: Magical Gizmo", the
reconciler set `comparison = conflict` on `target_identity`, and `entities` came out
empty. The name survived only on the compact progression action.

**Closest-point disambiguation would not have fixed this.** Native probing shows
**both** zone-192 gates connect from East, so distance cannot pick between them. The
fix is the mission identity binding (`_5c5` = `object:v1:192:17563876`) on step-017,
with step-009 bound to the actual J-7 Lily Tower entrance. Where an exact reviewed
identity is missing, the resolver still **refuses** the ambiguous-name fallback
rather than guessing.

## Final inventory (three nations)

Source: `logs/nation-route-investigation/audit-final.log`.

| Measure | Count |
|---|---|
| Steps walked | 2386 |
| Instruction (names nowhere) | 518 |
| Instruction-only with positional mention (note/wait/select) | 1158 |
| **Actionable positional steps** | **710** |
| — refused | 123 |
| — zone-level substitute (`source='zone-travel'`) | 166 |
| — precise target | **421** |
| Precise steps entering a zone | 304 |
| Precise targets on `untested` catalogue rows | 420 of 421 |

**Export:** 750 candidates → 4166 rows. Reading every compact action rather than
only the lowest `action_order` added 47 candidates / 418 rows that no other source
names.

### The 111 "lost" precise targets — resolved

Mid-audit, an in-flight resolver revision moved precise targets 421 → 310 and
introduced 97 new `no-zone-chain` refusals. I flagged that rather than assume it was
intended. **The concern was valid and the final implementation reverses it: precise
is back to 421.** The reason it was wrong to drop them is the distinction below.

## The deliberate distinction: mesh-no-path is a provider limit, not an unreachable place

`mesh-no-path` means *this navmesh could not connect that entrance to that point*.
It does **not** mean a player cannot get there. Collision terrain the mesh omits,
routes players actually walk, scripted doors, NPC-driven exits and transports all
live outside the mesh — this project has already been bitten by treating a missing
provider as geometry (a zone with no DAT collision once read as "unreachable" while
its navmesh sat loaded).

So a target whose every measured entrance is negative is a **gap in the evidence**,
not a proven dead end. Discarding those targets would have deleted 111 real
destinations and told the player nothing — and for this mod, withholding information
is the failure mode that matters most.

The shipped behaviour:

- **All-negative targets are retained**, not dropped.
- Their approach is marked **unverified** in `choice_note` and in resolver metadata,
  and the warning is **spoken and logged at route start** — the player is told the
  approach is unproven rather than silently routed or silently refused.
- **Positive measured entrances always win when reachable**, so a proven mouth is
  never passed over for an unverified one.
- Final walking validation still **refuses invalid native results**; the retention
  relaxes the evidence bar for offering a route, not the safety bar for walking one.
- Re-entry supports **3 crossings** to recover from a wrong Horutoto component. Every
  walking leg must validate, across both synchronous and asynchronous hooks;
  `zonesearch:*` legs are excluded so the final mission target is preserved.

`tools/test_mission_destination_ingress.lua` (Codex's) asserts this distinction —
**17 claims passed**.

## Native evidence and independent consistency

| | |
|---|---|
| Native table | **4166 pairs across 75 zones** |
| — mesh-connected | 1980 |
| — mesh-no-path | 2173 |
| — unknown | 13 |
| Independent consistency (`tools/test_nation_ingress_coverage.lua`) | **551 passed, 0 failed** |
| — identical under LuaJIT and stock Lua 5.1 | yes |
| Candidates absent from the table | **1** |

The hard claim that regression makes: if any entrance into a target's zone is
recorded `mesh-connected` for that target, `nav_destination_ingress.select` must not
select an entrance recorded `mesh-no-path`. That is the Horutoto failure shape stated
as a property. Included and genuinely executed (not skipped): the Windurst 1 gate
`(420, -30.375, -1.660)` approached from West Sarutabaruta selects a mesh-connected
entrance.

**The one remaining uncovered candidate:** `Star Sibyl`, zone 238,
`npc:v1:238:17752265` — most likely an artefact of this harness's synthetic walk
rather than a shipped destination. It **remains unverified** and is recorded here
rather than rounded away.

## Artifact vs assumption

**Measured:** 4166 pairs of native geometry across 75 zones; every point with a
positive entrance provably prefers it.

**Not measured, and not claimed:**

- **2173 mesh-no-path pairs are not proof of unreachability** — see the distinction
  above. Targets resting only on those are offered with an explicit unverified
  warning, never presented as confirmed.
- **13 unknown pairs** stay unknown.
- **420 of 421 precise targets rest on `untested` catalogue rows.**
- **1 candidate (Star Sibyl, zone 238) is unprobed.**
- **No mission was played.** Nothing in this document is live verification.

## Fixed / no-fix limits

**Fixed across revisions:** step enumeration (compact actions now consulted, all of
them, not just the lowest `action_order`); zone-name resolution against the zone-line
graph (`ctx.zone_ids_for_name` returns empty for zones the catalogue never names as a
destination — that swallowed every gate row on the first export); zone-substitute
classified on `source`/`entity_choice_stage` rather than name shape; note steps no
longer counted as refusals; the 111 dropped precise targets restored with honest
unverified marking.

**Not fixed, by design or by ownership:**

1. Physical reachability is not probed by the two tools in this document; the export
   exists precisely because they cannot convict.
2. Duplicate-name *selection* is not simulated here — it rests on catalogue contents
   plus Codex's native run and the reviewed identity bindings.
3. The audit's candidate count (750) and the regression's (687) differ: the audit
   advances its simulated walk only on precise targets and falls back to the player's
   zone; the regression advances on `targets[1]`. Both are reported; neither is
   authoritative over the other.
4. The simulated walk diverges from a live player after any refusal, so all counts
   are population sizes, not per-step verdicts.
5. Wrong-component recovery, the runtime modules, the data regeneration and the
   release build are Codex's; nothing in that path was edited from here.
