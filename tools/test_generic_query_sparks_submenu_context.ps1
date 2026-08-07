$ErrorActionPreference = 'Stop'

$modulePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\ashita\addons\accessxi_reader\modules\menus\generic_query.lua'))
$luaPath = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'

if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Generic query module not found: $modulePath"
}
if (-not (Test-Path -LiteralPath $luaPath)) {
    throw "Lua 5.1 runtime not found: $luaPath"
}

$script = @"
local module_path = [[$modulePath]]
local selected_label = ''
local current_count = 13
local current_child = 0x1000
local current_tick = 1000

function T(init)
    init = init or {}
    function init:append(value) table.insert(self, value) end
    function init:concat(separator) return table.concat(self, separator or '') end
    function init:len() return #self end
    return init
end

function string.trim(self)
    return tostring(self or ''):gsub('^%s+', ''):gsub('%s+$', '')
end
function string.contains(self, needle, ignore_case)
    self = tostring(self or '')
    needle = tostring(needle or '')
    if ignore_case then return self:lower():find(needle:lower(), 1, true) ~= nil end
    return self:find(needle, 1, true) ~= nil
end
function string.eq(self, other, ignore_case)
    self = tostring(self or '')
    other = tostring(other or '')
    if ignore_case then return self:lower() == other:lower() end
    return self == other
end
function string.fmt(self, ...) return string.format(self, ...) end

accessxi = { last_target_name = 'Fhelm Jobeizat' }
function accessxi.survival_guide_text(text) return tostring(text or ''):gsub('%s+', ' '):trim() end
function accessxi.plain_native_menu_label(label)
    label = accessxi.survival_guide_text(label or '')
    if label == '' or label:match('^[%p%s]+$') then return '' end
    return label
end
function accessxi.plain_native_menu_help(help) return accessxi.survival_guide_text(help or '') end
function accessxi.sentence_fragment(text)
    text = accessxi.survival_guide_text(text or '')
    if text == '' then return '' end
    if text:match('[%.%!%?]$') then return text end
    return text .. '.'
end
function accessxi.escape_probe_log_text(text) return tostring(text or '') end
function accessxi.is_probe_pointer(ptr) return tonumber(ptr) ~= nil and tonumber(ptr) ~= 0 end
function accessxi.table_count(value)
    local count = 0
    for _ in pairs(value or {}) do count = count + 1 end
    return count
end
function accessxi.resource_path(_, name) return tostring(name or '') end

local resources = {
    ['items.lua'] = {
        [16385] = { id = 16385, en = 'Cesti', enl = 'cesti', category = 'Weapon', jobs = 527334, level = 1, races = 510, skill = 1, slots = 1 },
        [17160] = { id = 17160, en = 'Longbow', enl = 'longbow', category = 'Weapon', jobs = 6530, level = 5, races = 510, skill = 25, slots = 4 },
        [12992] = { id = 12992, en = 'Solea', enl = 'solea', category = 'Armor', jobs = 7703740, level = 8, races = 510, slots = 256 },
    },
    ['item_descriptions.lua'] = {
        [16385] = { id = 16385, en = 'DMG:+1 Delay:+48 Accuracy+3' },
        [17160] = { id = 17160, en = 'DMG:17 Delay:540' },
        [12992] = { id = 12992, en = 'DEF:2' },
    },
}

function accessxi.load_module_file_table(path, _, default) return resources[tostring(path or '')] or default end
function accessxi.survival_guide_query_child_state_for_obj(_)
    return 1, 0, 0x00000000, current_child, current_count
end
function accessxi.native_query_label_for_selection(_, _, _, _) return selected_label, 'next+000:order' end
function accessxi.native_menu_index(_) return 0 end
function accessxi.native_query_items_for_child(_, _, _) return T{}, 'empty' end

generic_query_context = {
    safe_call = function(fn, default)
        local ok, result = pcall(fn)
        if ok then return result end
        return default
    end,
    read_u8 = function(_) return nil end,
    read_u32 = function(_) return 0 end,
    read_probe_string = function(_) return '' end,
    read_current_native_menu_index = function(_) return 0 end,
    log_line = function(_) end,
    log_state = function(_) end,
    tick = function() return current_tick end,
}

dofile(module_path)

function accessxi.generic_query_direct_label_for_child(_, _, _)
    return '', '', '', '', 0
end

selected_label = 'Equ. Lv.1 - 9. (Up to 100000)'
local speech = accessxi.generic_query_menu_speech('menu    query', 'Fhelm Jobeizat', 0x2000)
if speech == nil then error('proven Sparks top menu did not seed a query session') end

current_count = 17
selected_label = 'Cesti Ur Home Point'
speech = accessxi.generic_query_menu_speech('menu    query', '', 0x2000)
local cesti_expected = 'Cesti. Hand-to-Hand. All Races. DMG:+1 Delay:+48 Accuracy+3. Level 1. WAR, MNK, RDM, THF, PLD, DRK, BST, RNG, DNC.'
if speech ~= cesti_expected then
    error('blank-title Sparks submenu did not repair Cesti: ' .. tostring(speech))
end

current_count = 18
selected_label = 'Longbow Tomes'
speech = accessxi.generic_query_menu_speech('menu    query', '', 0x2000)
local longbow_expected = 'Longbow. Archery. All Races. DMG:17 Delay:540. Level 5. WAR, PLD, DRK, RNG, SAM.'
if speech ~= longbow_expected then
    error('blank-title Sparks submenu did not repair Longbow: ' .. tostring(speech))
end

selected_label = 'Solea Gs Int'
speech = accessxi.generic_query_menu_speech('menu    query', '', 0x2000)
local solea_expected = 'Solea. Feet. All Races. DEF:2. Level 8. MNK, WHM, BLM, RDM, PLD, BRD, RNG, SMN, BLU, PUP, SCH, GEO, RUN.'
if speech ~= solea_expected then
    error('blank-title Sparks submenu did not repair Solea: ' .. tostring(speech))
end

current_child = 0x3000
selected_label = 'Longbow Tomes'
speech = accessxi.generic_query_menu_speech('menu    query', '', 0x2000)
if speech ~= 'Longbow Tomes.' then
    error('Sparks repair leaked to a different query child: ' .. tostring(speech))
end

current_child = 0x1000
accessxi.last_target_name = 'Treasure Casket'
speech = accessxi.generic_query_menu_speech('menu    query', '', 0x2000)
if speech ~= 'Longbow Tomes.' then
    error('Sparks repair leaked after the target changed: ' .. tostring(speech))
end
"@

$tmp = Join-Path $env:TEMP ('accessxi-generic-query-sparks-context-{0}.lua' -f ([guid]::NewGuid().ToString('N')))
try {
    Set-Content -LiteralPath $tmp -Value $script -Encoding ASCII
    & $luaPath $tmp
    if ($LASTEXITCODE -ne 0) {
        throw "Lua test failed with exit code $LASTEXITCODE"
    }
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

Write-Host 'generic query Sparks submenu context regression ok'
