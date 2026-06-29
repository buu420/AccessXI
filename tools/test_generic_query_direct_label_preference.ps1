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
function accessxi.is_probe_pointer(ptr)
    return tonumber(ptr) ~= nil and tonumber(ptr) ~= 0
end
function accessxi.survival_guide_query_child_state_for_obj(_)
    return 3, 0, 0x00000002, 0x1000, 13
end
function accessxi.native_query_label_for_selection(_, _, _, _)
    return 'Equ Lv Up To', 'next+000:order'
end
function accessxi.native_menu_index(_)
    return 0
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
    return 'Equ.', 'next+000:direct+010', '', ''
end

local speech = accessxi.generic_query_menu_speech('menu    query', 'Rolandienne', 0x2000)
if speech == 'Rolandienne. Equ.' then
    error('short direct label Equ. overrode the fuller native list label')
end
if speech ~= 'Rolandienne. Equipment level 1 through 9.' then
    error('expected fuller native equipment category label, got: ' .. tostring(speech))
end
"@

$tmp = Join-Path $env:TEMP ('accessxi-generic-query-direct-label-{0}.lua' -f ([guid]::NewGuid().ToString('N')))
try {
    Set-Content -LiteralPath $tmp -Value $script -Encoding ASCII
    & $luaPath $tmp
    if ($LASTEXITCODE -ne 0) {
        throw "Lua test failed with exit code $LASTEXITCODE"
    }
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

Write-Host 'generic query direct label preference regression ok'
