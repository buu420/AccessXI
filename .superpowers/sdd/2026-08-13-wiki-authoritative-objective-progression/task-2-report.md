# Task 2 RED contract report

## Baseline

Before editing, both focused wrappers passed:

```text
mission and quest guide tests passed
mission and quest navigation tests passed
mission and quest reader I-handler integration tests passed
mission and quest reader integrity tests passed
mission and quest reader runtime pin test passed
```

## Changed files

- `tools/lua_tests/test_mission_quest_navigation.lua`
- `.superpowers/sdd/2026-08-13-wiki-authoritative-objective-progression/task-2-report.md`

The navigation harness now establishes coherent local mission and quest state,
then sends exact start/finish lifecycle evidence for Arnau and Cid without
calling `nav_mission_quest_remember_arrival`.  It requires one advancement
notification per accepted lifecycle and rejects a replayed finish.

## Confirmed RED

The existing production reducer failed only at the intended behavior boundary:

```text
Task 2 wiki-authoritative route-less progression REDs:
- route-less mission 0x032/0x034 start was not accepted for the current exact Arnau step
- route-less mission matching 0x05B finish did not advance the current wiki cursor
- route-less mission interaction did not emit exactly one progression notification
- route-less quest 0x032/0x034 start was not accepted for the current exact Cid step
- route-less quest matching 0x05B finish did not advance the current wiki cursor
- route-less quest interaction did not emit exactly one progression notification
```

The failure is an aggregate assertion after the real
`nav_mission_quest_observe_event_packet` seam has processed both packet phases;
it is not a Lua load or fixture error.  The replay expectations already stay
green under current production because no pending route-owned interaction was
created.

## Harness verification

- The reader runtime integration wrapper remains green.
- `git diff --check -- tools/lua_tests/test_mission_quest_navigation.lua` is clean.
- The navigation wrapper is intentionally RED only at the aggregate Task 2
  assertion above.

## APIs/behavior required from Task 3

`nav_mission_quest_observe_event_packet` must derive a unique current material
step from coherent local identity, World, session, objective key, exact target
server ID, and zone when no route arrival is pending.  It must arm only a
matching start, complete only its matching finish, persist/advance once, emit
one progression notification, and reject replayed finishes.

## Commit

Pending: commit after final syntax verification.
