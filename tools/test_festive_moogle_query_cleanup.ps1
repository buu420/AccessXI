$ErrorActionPreference = 'Stop'

$modulePath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\menus\festive_moogle.lua'
$luaPath = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'

if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Festive Moogle module not found: $modulePath"
}
if (-not (Test-Path -LiteralPath $luaPath)) {
    throw "Lua 5.1 runtime not found: $luaPath"
}

$script = @"
local module_path = [[$modulePath]]

function T(init)
    init = init or {}
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

local data = dofile(module_path)

local function clean(label)
    label = accessxi.plain_native_menu_label(label or '')
    if label == '' then
        return ''
    end

    for _, pattern in ipairs(data.query_label_tail_patterns or {}) do
        label = label:gsub(pattern, '')
    end
    label = label:gsub('%s+', ' '):trim()

    for _, row in ipairs(data.query_contains_labels or {}) do
        local contains = tostring(row ~= nil and row.contains or '')
        local clean_label = tostring(row ~= nil and row.label or '')
        if contains ~= '' and clean_label ~= '' and label:contains(contains, true) then
            return clean_label
        end
    end

    for raw, clean_label in pairs(data.query_exact_labels or {}) do
        if label:eq(tostring(raw or ''), true) then
            return tostring(clean_label or label)
        end
    end

    for _, row in ipairs(data.query_dynamic_labels or {}) do
        local pattern = tostring(row ~= nil and row.pattern or '')
        local kind = tostring(row ~= nil and row.kind or ''):lower()
        local capture = pattern ~= '' and label:match(pattern) or nil
        if capture ~= nil then
            capture = accessxi.survival_guide_text(capture)
            if kind == 'cipher-alter-ego' and capture ~= '' then
                return ("Cipher of %s's alter ego"):format(capture)
            elseif kind == 'none' then
                return 'None'
            end
        end
    end

    return label
end

local cases = {
    { 'Nothing Items Macrame', 'Nothing' },
    { 'Items Malatrix Shard', 'Items' },
    { 'I.a-', 'Items' },
    { 'You Know It Poet Alter', 'You know it' },
    { 'No Not Tot Alter Ego', 'No, not totally' },
    { 'Cipher Of August Alter', "Cipher of August's alter ego" },
    { 'Cipher Of Areuhat Alter', "Cipher of Areuhat's alter ego" },
    { 'Cipher Of Uka Alter Ego', "Cipher of Uka's alter ego" },
    { 'Cipher Of Star Sibyl Alter', "Cipher of Star Sibyl's alter ego" },
    { 'Cipher Of Shantotto', "Cipher of Shantotto's alter ego" },
    { 'Mellidopt Wing Alter', 'Mellidopt Wing' },
    { 'Lebondopt Wing Ter', 'Lebondopt Wing' },
    { 'None Of Kuyin Alter Ego', 'None' },
    { 'None Dopt Wing', 'None' },
    { 'Previous Page Ogle Alter', 'Previous Page' },
}

for _, case in ipairs(cases) do
    local actual = clean(case[1])
    if actual ~= case[2] then
        error(('expected %q -> %q, got %q'):format(case[1], case[2], actual))
    end
end
"@

$tmp = Join-Path $env:TEMP ('accessxi-festive-moogle-query-cleanup-{0}.lua' -f ([guid]::NewGuid().ToString('N')))
try {
    Set-Content -LiteralPath $tmp -Value $script -Encoding ASCII
    & $luaPath $tmp
    if ($LASTEXITCODE -ne 0) {
        throw "Lua test failed with exit code $LASTEXITCODE"
    }
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

Write-Host 'festive moogle query cleanup regression ok'
