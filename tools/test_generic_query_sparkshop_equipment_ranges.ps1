$ErrorActionPreference = 'Stop'

$modulePath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\menus\generic_query.lua'
$luaPath = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'

if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Generic query module not found: $modulePath"
}
if (-not (Test-Path -LiteralPath $luaPath)) {
    throw "Lua 5.1 runtime not found: $luaPath"
}

$script = @"
local module_path = [[$modulePath]]
local selected_case = nil

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
    if label == '' then
        return ''
    end
    if label:match('^[%p%s]+$') then
        return ''
    end
    return label
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
function accessxi.escape_probe_log_text_wide(text)
    return tostring(text or '')
end
function accessxi.is_probe_pointer(ptr)
    return tonumber(ptr) ~= nil and tonumber(ptr) ~= 0
end
function accessxi.resource_path(_, name)
    return 'missing-' .. tostring(name or '')
end
function accessxi.load_module_file_table(_, _, default)
    return default
end
function accessxi.survival_guide_query_child_state_for_obj(_)
    local selected = tonumber(selected_case.selected) or 0
    local raw = tonumber(selected_case.raw) or 0
    return selected, selected - 3, raw, 0x1000, 13
end
function accessxi.native_query_label_for_selection(_, _, _, _)
    return selected_case.list_label or 'Equ Lv Up To', 'next+000:order'
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
    return selected_case.direct_label or 'Equ.', 'next+000:direct+010', '', '', 0x2000
end

local cases = {
    { selected = 3, raw = 0x00000002, expected = 'Equipment level 1 through 9.' },
    { selected = 4, raw = 0x00010003, expected = 'Equipment level 10 through 19.' },
    { selected = 5, raw = 0x00020004, expected = 'Equipment level 20 through 29.' },
    { selected = 6, raw = 0x00030005, expected = 'Equipment level 30 through 39.' },
    { selected = 7, raw = 0x00040006, expected = 'Equipment level 40 through 50.' },
    { selected = 8, raw = 0x00050007, expected = 'Equipment level 51 through 70.' },
    { selected = 9, raw = 0x00060008, expected = 'Equipment level 71 through 98.' },
    { selected = 10, raw = 0x00070009, expected = 'Equipment level 99.' },
}

local titles = { 'Rolandienne', 'Isakoth', 'Fhelm Jobeizat', 'Eternal Flame' }
for _, title in ipairs(titles) do
    selected_case = {
        selected = 1,
        raw = 0x00000000,
        list_label = 'Items Axe',
        direct_label = '',
    }
    local items_speech = accessxi.generic_query_menu_speech('menu    query', title, 0x2000)
    local items_expected = title .. '. Items.'
    if items_speech ~= items_expected then
        error(('%s malformed Items row expected %q, got %q'):format(title, items_expected, tostring(items_speech)))
    end

    for _, case in ipairs(cases) do
        selected_case = case
        local speech = accessxi.generic_query_menu_speech('menu    query', title, 0x2000)
        local expected = title .. '. ' .. case.expected
        if speech ~= expected then
            error(('%s selected %d expected %q, got %q'):format(title, case.selected, expected, tostring(speech)))
        end
    end
end

-- FFXI can leave GetWindowName blank on the first Sparks opening after a
-- process restart.  A proven Sparks target plus the exact 13-row menu must
-- still decode immediately, without requiring the player to close/reopen it.
accessxi.last_target_name = 'Fhelm Jobeizat'
selected_case = cases[1]
local cold_open_speech = accessxi.generic_query_menu_speech('menu    query', '', 0x2000)
if cold_open_speech ~= 'Fhelm Jobeizat. Equipment level 1 through 9.' then
    error(('cold first opening did not recover the Sparks title safely: %q'):format(tostring(cold_open_speech)))
end

-- The fallback must not turn an unrelated remembered target into a Sparks
-- menu merely because another query happens to have the same row count.
accessxi.last_target_name = 'Treasure Casket'
selected_case = cases[1]
local unrelated_speech = accessxi.generic_query_menu_speech('menu    query', '', 0x2000)
if unrelated_speech == 'Equipment level 1 through 9.'
    or unrelated_speech == 'Treasure Casket. Equipment level 1 through 9.' then
    error(('cold-open Sparks recovery leaked to an unrelated target: %q'):format(tostring(unrelated_speech)))
end
"@

$tmp = Join-Path $env:TEMP ('accessxi-generic-query-sparkshop-ranges-{0}.lua' -f ([guid]::NewGuid().ToString('N')))
try {
    Set-Content -LiteralPath $tmp -Value $script -Encoding ASCII
    & $luaPath $tmp
    if ($LASTEXITCODE -ne 0) {
        throw "Lua test failed with exit code $LASTEXITCODE"
    }
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

Write-Host 'generic query sparkshop equipment range regression ok'
