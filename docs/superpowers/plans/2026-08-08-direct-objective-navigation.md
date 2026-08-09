# Direct Objective Navigation Implementation Plan

1. Update focused Lua and integration assertions for flat category browsing, direct `I` routing, active-only quests, and live-state-backed available nation missions.
2. Capture and character-own the nation mission completion words from incoming `0x056` port `0x00D0`, and expose native nation/rank/rank-point state.
3. Reproduce the source-backed nation gate-guard availability predicate conservatively and attach exact current-nav gate-guard destinations.
4. Remove objective guide-view interception from the navigation hotkeys and route the selected mission or quest directly through the existing GPS path.
5. Run focused tests, Lua 5.1 syntax checks, broader addon regressions, and diff validation before deploying the changed addon files to the live Ashita installation.
