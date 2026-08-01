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
local menu_title = 'Fhelm Jobeizat'

function T(init)
    init = init or {}
    function init:append(value)
        table.insert(self, value)
    end
    function init:concat(separator)
        return table.concat(self, separator or '')
    end
    function init:len()
        return #self
    end
    return init
end

function string.trim(self)
    return tostring(self or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

function string.contains(self, needle, ignore_case)
    self = tostring(self or '')
    needle = tostring(needle or '')
    if ignore_case then
        return self:lower():find(needle:lower(), 1, true) ~= nil
    end
    return self:find(needle, 1, true) ~= nil
end

function string.eq(self, other, ignore_case)
    self = tostring(self or '')
    other = tostring(other or '')
    if ignore_case then
        return self:lower() == other:lower()
    end
    return self == other
end

function string.fmt(self, ...)
    return string.format(self, ...)
end

accessxi = {}
function accessxi.survival_guide_text(text)
    return tostring(text or ''):gsub('%s+', ' '):trim()
end
function accessxi.plain_native_menu_label(label)
    label = accessxi.survival_guide_text(label or '')
    if label == '' or label:match('^[%p%s]+$') then
        return ''
    end
    return label
end
function accessxi.plain_native_menu_help(help)
    return accessxi.survival_guide_text(help or '')
end
function accessxi.sentence_fragment(text)
    text = accessxi.survival_guide_text(text or '')
    if text == '' then
        return ''
    end
    if text:match('[%.%!%?]$') then
        return text
    end
    return text .. '.'
end
function accessxi.escape_probe_log_text(text)
    return tostring(text or '')
end
function accessxi.is_probe_pointer(ptr)
    return tonumber(ptr) ~= nil and tonumber(ptr) ~= 0
end
function accessxi.table_count(value)
    local count = 0
    for _ in pairs(value or {}) do
        count = count + 1
    end
    return count
end
function accessxi.resource_path(_, name)
    return tostring(name or '')
end

local resources = {
    ['items.lua'] = {
        [16385] = { id = 16385, en = 'Cesti', enl = 'cesti', category = 'Weapon', jobs = 527334, level = 1, races = 510, skill = 1, slots = 1 },
        [16391] = { id = 16391, en = 'Brass Knuckles', enl = 'brass knuckles', category = 'Weapon', jobs = 525286, level = 9, races = 510, skill = 1, slots = 1 },
        [16465] = { id = 16465, en = 'Bronze Knife', enl = 'bronze knife', category = 'Weapon', jobs = 949698, level = 1, races = 510, skill = 2, slots = 3 },
        [16530] = { id = 16530, en = 'Xiphos', enl = 'xiphos', category = 'Weapon', jobs = 4419554, level = 7, races = 510, skill = 3, slots = 3 },
        [16624] = { id = 16624, en = 'Xiphos +1', enl = 'xiphos +1', category = 'Weapon', jobs = 4419554, level = 7, races = 510, skill = 3, slots = 3 },
        [12415] = { id = 12415, en = 'Shell Shield', enl = 'shell shield', category = 'Armor', jobs = 4770, level = 7, races = 510, slots = 2 },
        [30000] = { id = 30000, en = 'Test Blade', enl = 'test blade', category = 'Weapon', jobs = 8388606, level = 99, races = 510, skill = 3, slots = 3, superior_level = 5, item_level = 119 },
    },
    ['item_descriptions.lua'] = {
        [16385] = { id = 16385, en = 'DMG:+1 Delay:+48 Accuracy+3' },
        [16391] = { id = 16391, en = 'DMG:+4 Delay:+96 Accuracy+2' },
        [16465] = { id = 16465, en = 'DMG:4 Delay:195' },
        [16530] = { id = 16530, en = 'DMG:8 Delay:228' },
        [16624] = { id = 16624, en = 'DMG:9 Delay:222' },
        [12415] = { id = 12415, en = 'DEF:2 VIT+1 AGI-2 ' .. string.char(0xEE, 0x80, 0x85) .. '+2' },
        [30000] = { id = 30000, en = 'DMG:200 Delay:240' },
    },
}

function accessxi.load_module_file_table(path, _, default)
    return resources[tostring(path or '')] or default
end
function accessxi.survival_guide_query_child_state_for_obj(_)
    return 1, 0, 0x00000000, 0x1000, 17
end
function accessxi.native_query_label_for_selection(_, _, _, _)
    return selected_label, 'next+000:order'
end
function accessxi.native_menu_index(_)
    return 0
end
function accessxi.native_query_items_for_child(_, _, _)
    return T{}, 'empty'
end

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
    tick = function() return 0 end,
}

dofile(module_path)

function accessxi.generic_query_direct_label_for_child(_, _, _)
    return '', '', '', '', 0
end

local brass_help = select(1, accessxi.generic_query_resource_help_for_label('Brass Knuckles'))
local brass_expected = 'Hand-to-Hand. All Races. DMG:+4 Delay:+96 Accuracy+2. Level 9. WAR, MNK, RDM, THF, PLD, DRK, BST, DNC.'
if brass_help ~= brass_expected then
    error('full visible Brass Knuckles panel was not preserved: ' .. tostring(brass_help))
end

local knife_help = select(1, accessxi.generic_query_resource_help_for_label('Bronze Knife'))
local knife_expected = 'Dagger. All Races. DMG:4 Delay:195. Level 1. WAR, THF, PLD, DRK, BRD, RNG, SAM, NIN, DRG, COR, PUP, DNC.'
if knife_help ~= knife_expected then
    error('full visible Bronze Knife panel was not preserved: ' .. tostring(knife_help))
end

local item_level_help = select(1, accessxi.generic_query_resource_help_for_label('Test Blade'))
local item_level_expected = 'Sword. All Races. DMG:200 Delay:240. Level 99. All Jobs. Superior 5. Item level 119.'
if item_level_help ~= item_level_expected then
    error('item-level equipment did not preserve the full visible panel: ' .. tostring(item_level_help))
end

local shell_help = select(1, accessxi.generic_query_resource_help_for_label('Shell Shield'))
local shell_expected = 'Sub. All Races. DEF:2 VIT+1 AGI-2 Water resistance +2. Level 7. WAR, RDM, PLD, BST, SAM.'
if shell_help ~= shell_expected then
    error('element icon was not translated into its visible stat: ' .. tostring(shell_help))
end

selected_label = 'Cesti Primer'
menu_title = 'Fhelm Jobeizat'
local speech = accessxi.generic_query_menu_speech('menu    query', menu_title, 0x2000)
if speech ~= 'Fhelm Jobeizat. Cesti. Hand-to-Hand. All Races. DMG:+1 Delay:+48 Accuracy+3. Level 1. WAR, MNK, RDM, THF, PLD, DRK, BST, RNG, DNC.' then
    error('contaminated Cesti row was not repaired from the exact item resource: ' .. tostring(speech))
end

selected_label = 'Xiphos Tale Chapter'
speech = accessxi.generic_query_menu_speech('menu    query', menu_title, 0x2000)
if speech ~= 'Fhelm Jobeizat. Xiphos. Sword. All Races. DMG:8 Delay:228. Level 7. WAR, RDM, THF, PLD, DRK, BST, BRD, RNG, NIN, DRG, BLU, COR, RUN.' then
    error('contaminated Xiphos row was not repaired from the exact item resource: ' .. tostring(speech))
end

selected_label = 'Cesti Primer'
menu_title = 'Treasure Casket'
speech = accessxi.generic_query_menu_speech('menu    query', menu_title, 0x2000)
if speech ~= 'Treasure Casket. Cesti Primer.' then
    error('Sparks-only label repair leaked into an unrelated query menu: ' .. tostring(speech))
end
"@

$tmp = Join-Path $env:TEMP ('accessxi-generic-query-sparks-details-{0}.lua' -f ([guid]::NewGuid().ToString('N')))
try {
    Set-Content -LiteralPath $tmp -Value $script -Encoding ASCII
    & $luaPath $tmp
    if ($LASTEXITCODE -ne 0) {
        throw "Lua test failed with exit code $LASTEXITCODE"
    }
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

Write-Host 'generic query Sparks item details regression ok'
