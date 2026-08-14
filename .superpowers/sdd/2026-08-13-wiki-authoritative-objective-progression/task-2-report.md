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
- `tools/lua_tests/test_mission_quest_reader_runtime_integration.lua`
- `.superpowers/sdd/2026-08-13-wiki-authoritative-objective-progression/task-2-report.md`

The navigation harness now establishes coherent local mission and quest state,
then sends exact start/finish lifecycle evidence for Arnau and Cid without
calling `nav_mission_quest_remember_arrival`.  It requires one advancement
notification per accepted lifecycle and rejects a replayed finish.

The reader extraction harness also executes the real
`current_objective_session_epoch` function across identity loss and a
same-identity relogin.  It requires a new positive generation for the second
login.

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

The reader runtime harness independently reports this intended RED:

```text
same-identity relogin reused the prior objective session generation
```

## Harness verification

- Before the Task 2 edit, both focused wrappers were green.
- Lua 5.1 loads the changed navigation harness successfully.
- The navigation and reader wrappers are now intentionally RED only at the
  Task 2 assertions above; the reader RED occurs before the concurrent
  manifest-byte pin can run.
- `git diff --check` is clean for every Task 2 file.

## APIs/behavior required from Task 3

`nav_mission_quest_observe_event_packet` must derive a unique current material
step from coherent local identity, World, session, objective key, exact target
server ID, and zone when no route arrival is pending.  It must arm only a
matching start, complete only its matching finish, persist/advance once, emit
one progression notification, and reject replayed finishes.

`current_objective_session_epoch` must observe identity loss and issue a new
positive generation when the local character subsequently logs in, including
when their stable name/server identity is unchanged.

## Commit

`68a8ac1afef50b6fdcc36c151dd10ec28aca65b5` (`test: add route-less objective progression REDs`)
