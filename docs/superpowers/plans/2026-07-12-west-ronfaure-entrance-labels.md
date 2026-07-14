# West Ronfaure Entrance Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show both Northern San d'Oria exits distinctly by renaming the currently visible wrong-for-La-Theine destination to `Watchtower entrance` while preserving the hidden working exit as `West Ronfaure zone line`.

**Architecture:** This is a data-only correction. The three synchronized destination files receive the same single-row label change; the existing menu key then treats the two coordinates as distinct entries without routing-code changes.

**Tech Stack:** Tab-separated navigation data and PowerShell regression tests.

## Global Constraints

- Rename only `231\tWest Ronfaure zone line\t-238.702\t105.961\t-9.433` to `Watchtower entrance`.
- Keep `231\tWest Ronfaure zone line\t-252.158\t43.913\t1.663` unchanged and visible.
- Do not change coordinates, routing logic, graph topology, route overrides, or character-specific state.
- Keep source data, source-addon data, and live-addon data byte-identical.
- Do not initialize a git repository or create a commit.

---

### Task 1: Distinguish the two West Ronfaure entrances

**Files:**
- Create: `C:\Users\buu42\AccessXI\tools\test_nav_west_ronfaure_entrance_labels.ps1`
- Modify: `C:\Users\buu42\AccessXI\data\ffxi-nav-destinations.tsv:607-608`
- Modify: `C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\data\ffxi-nav-destinations.tsv:607-608`
- Modify: `C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-destinations.tsv:607-608`

**Interfaces:**
- Consumes: the existing nine-column `ffxi-nav-destinations.tsv` format.
- Produces: two distinct zone-231 area destinations named `West Ronfaure zone line` and `Watchtower entrance`.

- [ ] **Step 1: Write the failing regression test**

Create a PowerShell test that loads all three destination files, requires the exact working and watchtower rows, rejects the old duplicate label at the watchtower coordinate, and compares all three SHA-256 hashes:

```powershell
$ErrorActionPreference = 'Stop'

$paths = @(
    'C:\Users\buu42\AccessXI\data\ffxi-nav-destinations.tsv',
    'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\data\ffxi-nav-destinations.tsv',
    'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-destinations.tsv'
)

$working = "231`tWest Ronfaure zone line`t-252.158`t43.913`t1.663`tarea`tlsb-san-doria-zoneline`tgenerated`tsan-doria"
$watchtower = "231`tWatchtower entrance`t-238.702`t105.961`t-9.433`tarea`tlsb-san-doria-zoneline`tgenerated`tsan-doria"
$oldDuplicate = "231`tWest Ronfaure zone line`t-238.702`t105.961`t-9.433`tarea`tlsb-san-doria-zoneline`tgenerated`tsan-doria"

foreach ($path in $paths) {
    $text = Get-Content -LiteralPath $path -Raw
    if (-not $text.Contains($working)) { throw "Missing working West Ronfaure entrance in $path" }
    if (-not $text.Contains($watchtower)) { throw "Missing Watchtower entrance in $path" }
    if ($text.Contains($oldDuplicate)) { throw "Watchtower coordinate still has duplicate West Ronfaure label in $path" }
}

$hashes = $paths | ForEach-Object { (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash }
if (($hashes | Sort-Object -Unique).Count -ne 1) { throw 'Destination data copies are not synchronized.' }

Write-Host 'West Ronfaure entrance label checks ok'
```

- [ ] **Step 2: Run the test and confirm the current duplicate fails**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\buu42\AccessXI\tools\test_nav_west_ronfaure_entrance_labels.ps1'
```

Expected: FAIL with `Missing Watchtower entrance`.

- [ ] **Step 3: Apply the minimal synchronized label change**

In all three destination files, replace only:

```text
231\tWest Ronfaure zone line\t-238.702\t105.961\t-9.433\tarea\tlsb-san-doria-zoneline\tgenerated\tsan-doria
```

with:

```text
231\tWatchtower entrance\t-238.702\t105.961\t-9.433\tarea\tlsb-san-doria-zoneline\tgenerated\tsan-doria
```

- [ ] **Step 4: Run the focused test and existing navigation regressions**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\buu42\AccessXI\tools\test_nav_west_ronfaure_entrance_labels.ps1'
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\buu42\AccessXI\tools\test_nav_static_destination_preempts_live_duplicate.ps1'
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\buu42\AccessXI\tools\test_nav_zoneline_menu_visibility.ps1'
```

Expected:

```text
West Ronfaure entrance label checks ok
nav static destination duplicate suppression checks ok
nav zoneline menu visibility checks ok
```

- [ ] **Step 5: Verify final scope**

Confirm the three destination files have identical SHA-256 hashes and that no Lua, route override, graph, or installer file changed.
