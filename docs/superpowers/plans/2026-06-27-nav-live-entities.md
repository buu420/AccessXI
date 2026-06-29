# Nav Live Entities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make navigation obstacle, enemy, and NM behavior use nearby live client entities instead of broad guesses.

**Architecture:** Add a small live entity snapshot layer inside the existing AccessXI Ashita addon nav section. Route obstacle avoidance, enemy warnings, and live nav categories will consume that snapshot, while static NM spawn destinations remain separate from live NM candidates.

**Tech Stack:** Ashita Lua 5.1 addon, PowerShell static guard tests, existing AccessXI Lua 5.1 syntax wrapper.

---

## File Structure

- Modify: `C:\Users\buu42\Ashita\addons\accessxi_reader\modules\navigation_data.lua`
  - Add a `Live NM` category while keeping `NM Spawns`.
- Modify: `C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua`
  - Add live entity snapshot helpers near `nav_entity_position`.
  - Route `nav_live_enemies`, nav menu live categories, dynamic obstacle avoidance, and progress watchdog wording through those helpers.
- Create: `C:\Users\buu42\AccessXI\tools\test_nav_live_entities.ps1`
  - Static guard for the behavior and wording changes.

## Task 1: Add Static Guards

**Files:**
- Create: `C:\Users\buu42\AccessXI\tools\test_nav_live_entities.ps1`

- [ ] **Step 1: Create the failing test**

Create a PowerShell static test that checks:

```powershell
$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$navigationDataPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\navigation_data.lua'
$source = Get-Content -LiteralPath $addonPath -Raw
$navigationData = Get-Content -LiteralPath $navigationDataPath -Raw

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw $Message }
}

function Assert-NotMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) { throw $Message }
}

Assert-Match -Text $navigationData -Pattern "key\s*=\s*'nm'.*?label\s*=\s*'NM Spawns'" -Message 'Static NM spawn category must remain.'
Assert-Match -Text $navigationData -Pattern "key\s*=\s*'live-nm'.*?label\s*=\s*'Live NM'" -Message 'Expected separate Live NM category.'

foreach ($fragment in @(
    'function accessxi.nav_live_entity_key(pos)',
    'function accessxi.nav_live_entity_valid(pos)',
    'function accessxi.nav_live_entity_snapshot(max_count, max_distance)',
    'function accessxi.nav_live_nm_names_for_zone(zone)',
    'function accessxi.nav_entity_is_live_nm_candidate(pos)',
    'function accessxi.nav_live_entities_for_category(category_key, max_distance)',
    'function accessxi.nav_recent_live_obstacle(now)'
)) {
    Assert-Match -Text $source -Pattern ([regex]::Escape($fragment)) -Message "Missing live entity helper: $fragment"
}

$segmentStart = $source.IndexOf('function accessxi.nav_segment_obstacle')
$segmentEnd = $source.IndexOf('function accessxi.nav_obstacle_avoidance_target', $segmentStart)
if ($segmentStart -lt 0 -or $segmentEnd -lt 0) { throw 'Could not locate nav_segment_obstacle block.' }
$segmentBody = $source.Substring($segmentStart, $segmentEnd - $segmentStart)
Assert-Match -Text $segmentBody -Pattern 'nav_live_entity_snapshot' -Message 'Dynamic obstacle detection must use live entity snapshot.'
Assert-Match -Text $segmentBody -Pattern 'nav_live_entity_valid' -Message 'Dynamic obstacle detection must validate live entities.'
Assert-NotMatch -Text $segmentBody -Pattern 'GetEntityMapSize\(\)' -Message 'Dynamic obstacle detection should not do broad raw entity scans directly.'

$progressStart = $source.IndexOf('function accessxi.nav_progress_watch')
$progressEnd = $source.IndexOf('function accessxi.poll_nav_beacon', $progressStart)
if ($progressStart -lt 0 -or $progressEnd -lt 0) { throw 'Could not locate nav_progress_watch block.' }
$progressBody = $source.Substring($progressStart, $progressEnd - $progressStart)
Assert-NotMatch -Text $progressBody -Pattern 'Possible obstacle' -Message 'No-progress watchdog must not claim possible obstacles without live proof.'
Assert-Match -Text $progressBody -Pattern 'No forward progress' -Message 'No-progress watchdog should use honest no-progress wording.'
Assert-Match -Text $progressBody -Pattern 'nav_recent_live_obstacle' -Message 'No-progress watchdog should check recent live obstacle evidence.'

$liveEnemiesStart = $source.IndexOf('function accessxi.nav_live_enemies')
$liveEnemiesEnd = $source.IndexOf('function accessxi.nav_live_category', $liveEnemiesStart)
if ($liveEnemiesStart -lt 0 -or $liveEnemiesEnd -lt 0) { throw 'Could not locate nav_live_enemies block.' }
$liveEnemiesBody = $source.Substring($liveEnemiesStart, $liveEnemiesEnd - $liveEnemiesStart)
Assert-Match -Text $liveEnemiesBody -Pattern 'nav_live_entities_for_category' -Message 'Enemy warning should share live category filtering.'

$liveCategoryStart = $source.IndexOf('function accessxi.nav_live_category')
$liveCategoryEnd = $source.IndexOf('function accessxi.nav_log_entity_candidates', $liveCategoryStart)
if ($liveCategoryStart -lt 0 -or $liveCategoryEnd -lt 0) { throw 'Could not locate nav_live_category block.' }
$liveCategoryBody = $source.Substring($liveCategoryStart, $liveCategoryEnd - $liveCategoryStart)
Assert-Match -Text $liveCategoryBody -Pattern "category_key == 'live-nm'" -Message 'Live NM category should refresh dynamically.'

$collectStart = $source.IndexOf('local function nav_collect_menu_items')
$collectEnd = $source.IndexOf('local function nav_refresh_search_results', $collectStart)
if ($collectStart -lt 0 -or $collectEnd -lt 0) { throw 'Could not locate nav_collect_menu_items block.' }
$collectBody = $source.Substring($collectStart, $collectEnd - $collectStart)
Assert-Match -Text $collectBody -Pattern 'nav_live_entities_for_category' -Message 'Navigation menu should use shared live entity category filtering.'
Assert-Match -Text $collectBody -Pattern "source = \('live-entity:%d:%d'" -Message 'Live menu entries should be visibly live entity sourced.'

Write-Host 'nav live entity checks ok'
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\buu42\AccessXI\tools\test_nav_live_entities.ps1"
```

Expected: failure on missing `Live NM` category or live entity helper fragments.

## Task 2: Add The Live Entity Snapshot Layer

**Files:**
- Modify: `C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua`

- [ ] **Step 1: Implement the snapshot helpers**

Add helpers near `nav_entity_position`:

```lua
function accessxi.nav_live_entity_key(pos)
    if (pos == nil) then
        return '';
    end
    return ('%d:%d:%d:%s'):fmt(
        tonumber(pos.zone) or 0,
        tonumber(pos.index) or -1,
        tonumber(pos.server_id) or 0,
        tostring(pos.name or ''):lower():gsub('%s+', ' '));
end

function accessxi.nav_live_entity_valid(pos)
    if (pos == nil or nav_clean_field(pos.name) == '') then
        return false;
    end
    if ((tonumber(pos.x) or 0) == 0 and (tonumber(pos.z) or 0) == 0) then
        return false;
    end
    local status = tonumber(pos.status) or -1;
    if (status == 2 or status == 3) then
        return false;
    end
    local zone = nav_zone_id();
    return zone <= 0 or (tonumber(pos.zone) or 0) == zone;
end

function accessxi.nav_live_entity_snapshot(max_count, max_distance)
    local nearby = nav_nearby(max_count or 80, max_distance or (tonumber(accessxi.nav_widescan_max_range) or 350));
    local results = {};
    if (nearby == nil) then
        return results;
    end
    local now = tick();
    if (type(accessxi.nav_live_entity_seen) ~= 'table') then
        accessxi.nav_live_entity_seen = T{};
    end
    for _, pos in ipairs(nearby) do
        if (accessxi.nav_live_entity_valid(pos)) then
            pos.live_kind = accessxi.nav_entity_kind(pos);
            pos.live_nm = accessxi.nav_entity_is_live_nm_candidate(pos);
            if (pos.live_nm == true) then
                pos.live_kind = 'live-nm';
            end
            local key = accessxi.nav_live_entity_key(pos);
            if (key ~= '') then
                accessxi.nav_live_entity_seen[key] = T{ tick = now, kind = pos.live_kind, name = pos.name, zone = pos.zone };
            end
            table.insert(results, pos);
        end
    end
    table.sort(results, function (a, b) return (a.distance or 999999) < (b.distance or 999999); end);
    return results;
end
```

- [ ] **Step 2: Add live category helpers**

Add:

```lua
function accessxi.nav_live_entities_for_category(category_key, max_distance)
    category_key = tostring(category_key or 'all');
    local entities = accessxi.nav_live_entity_snapshot(80, max_distance or (tonumber(accessxi.nav_widescan_max_range) or 350));
    local filtered = {};
    for _, pos in ipairs(entities) do
        local kind = tostring(pos.live_kind or accessxi.nav_entity_kind(pos));
        if (category_key == 'all'
            or category_key == kind
            or (category_key == 'enemy' and (kind == 'enemy' or kind == 'live-nm'))) then
            table.insert(filtered, pos);
        end
    end
    return filtered;
end

function accessxi.nav_live_enemies(max_distance)
    return accessxi.nav_live_entities_for_category('enemy', max_distance);
end
```

## Task 3: Separate Static NM Spawns From Live NM Candidates

**Files:**
- Modify: `C:\Users\buu42\Ashita\addons\accessxi_reader\modules\navigation_data.lua`
- Modify: `C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua`

- [ ] **Step 1: Add the category**

In `navigation_data.lua`, keep `NM Spawns` and add:

```lua
T{ key = 'live-nm', label = 'Live NM' },
```

- [ ] **Step 2: Implement NM name matching**

Add:

```lua
function accessxi.nav_live_nm_names_for_zone(zone)
    nav_load_points();
    local names = T{};
    zone = tonumber(zone) or nav_zone_id();
    for _, point in ipairs(accessxi.nav_points or T{}) do
        if ((tonumber(point.zone) or 0) == zone and accessxi.nav_point_effective_kind(point) == 'nm') then
            local name = nav_clean_field(point.name or ''):lower():gsub('%s+', ' ');
            if (name ~= '') then
                names[name] = true;
            end
        end
    end
    return names;
end

function accessxi.nav_entity_is_live_nm_candidate(pos)
    if (not accessxi.nav_entity_is_enemy(pos)) then
        return false;
    end
    local name = nav_clean_field(pos.name or ''):lower():gsub('%s+', ' ');
    if (name == '') then
        return false;
    end
    local names = accessxi.nav_live_nm_names_for_zone(pos.zone);
    return names[name] == true;
end
```

- [ ] **Step 3: Make live category refresh include live NM**

Update `nav_live_category` to include:

```lua
return category_key == 'all' or category_key == 'enemy' or category_key == 'player' or category_key == 'live-nm';
```

## Task 4: Use Live Snapshots In Menus And Obstacles

**Files:**
- Modify: `C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua`

- [ ] **Step 1: Update nav menu live entity insertion**

Replace the `nav_nearby` loop in `nav_collect_menu_items` with `nav_live_entities_for_category`, and mark live sources:

```lua
local live_distance = (category_key == 'enemy' or category_key == 'live-nm') and (tonumber(accessxi.nav_widescan_max_range) or 350) or 120;
if (nav_clean_field(search_query) ~= '') then
    live_distance = tonumber(accessxi.nav_widescan_max_range) or 350;
end
local nearby = accessxi.nav_live_entities_for_category(category_key, live_distance);
for _, entity_point in ipairs(nearby) do
    local entity_kind = tostring(entity_point.live_kind or accessxi.nav_entity_kind(entity_point));
    local point = T{
        zone = zone,
        name = entity_point.name,
        x = entity_point.x,
        z = entity_point.z,
        y = entity_point.y,
        kind = entity_kind,
        source = ('live-entity:%d:%d'):fmt(entity_point.index or -1, entity_point.server_id or 0),
        distance = entity_point.distance or 0,
    };
    local key = nav_point_key(point);
    if (accessxi.nav_point_matches_category(point, category_key) and accessxi.nav_point_matches_search(point, search_query) and not seen:contains(key)) then
        seen:append(key);
        table.insert(items, point);
    end
end
```

- [ ] **Step 2: Update dynamic obstacle detection**

In `nav_segment_obstacle`, replace the raw entity map scan with:

```lua
local candidates = accessxi.nav_live_entity_snapshot(80, scan_ahead + 8);
for _, pos in ipairs(candidates) do
    if ((tonumber(pos.index) or -1) ~= player_index and accessxi.nav_live_entity_valid(pos)) then
        local entity_type = tonumber(pos.type) or -1;
        if (entity_type ~= 0 and not accessxi.nav_entity_is_obvious_object(pos)) then
            -- keep the existing corridor math here
        end
    end
end
```

When a live obstacle is chosen, set:

```lua
accessxi.nav_last_live_obstacle_tick = now;
accessxi.nav_last_live_obstacle_name = name;
```

inside `nav_apply_dynamic_obstacle`.

- [ ] **Step 3: Add recent obstacle helper**

Add:

```lua
function accessxi.nav_recent_live_obstacle(now)
    now = tonumber(now) or tick();
    return (now - (tonumber(accessxi.nav_last_live_obstacle_tick) or 0)) <= 2500;
end
```

## Task 5: Make Progress Wording Honest

**Files:**
- Modify: `C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua`

- [ ] **Step 1: Change `nav_progress_watch` speech**

Replace the `Possible obstacle` text selection with:

```lua
local text = 'No forward progress.';
if (accessxi.nav_recent_live_obstacle(now)) then
    local obstacle_name = nav_clean_field(accessxi.nav_last_live_obstacle_name or '');
    if (obstacle_name ~= '') then
        text = ('Obstacle still nearby. %s.'):fmt(obstacle_name);
    else
        text = 'Obstacle still nearby.';
    end
elseif (wall ~= nil and wall <= 2.5) then
    text = ('No forward progress. Near wall. Clearance %.0f yalm.'):fmt(wall);
elseif (wall ~= nil) then
    text = ('No forward progress. Wall clearance %.0f yalms.'):fmt(wall);
else
    text = 'No forward progress. Try turning until the beacon moves off-center.';
end
```

Keep the existing route refresh behavior and evidence logging.

## Task 6: Validate

**Files:**
- Test: `C:\Users\buu42\AccessXI\tools\test_nav_live_entities.ps1`
- Test: `C:\Users\buu42\AccessXI\tools\test_nav_collision_detection.ps1`
- Test: `C:\Users\buu42\AccessXI\tools\test_nav_zoning_and_key_blocking.ps1`

- [ ] **Step 1: Run focused static tests**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\buu42\AccessXI\tools\test_nav_live_entities.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\buu42\AccessXI\tools\test_nav_collision_detection.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\buu42\AccessXI\tools\test_nav_zoning_and_key_blocking.ps1"
```

Expected: all report `ok`.

- [ ] **Step 2: Run Lua syntax validation**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\buu42\AccessXI\tools\check_lua51_syntax.ps1" -Path "C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua"
```

Expected: `syntax ok`.
