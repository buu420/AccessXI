$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$addonPath = Join-Path $repoRoot 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$categoriesPath = Join-Path $repoRoot 'ashita\addons\accessxi_reader\modules\menus\chat_log.lua'
$source = Get-Content -LiteralPath $addonPath -Raw
$categories = Get-Content -LiteralPath $categoriesPath -Raw

function Assert-Match {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotMatch {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Text -match $Pattern) {
        throw $Message
    }
}

$expectedChannelModes = @(
    @{ Mode = 1;   Label = 'Say';         Category = 'say' },
    @{ Mode = 9;   Label = 'Say';         Category = 'say' },
    @{ Mode = 2;   Label = 'Shout';       Category = 'shout' },
    @{ Mode = 10;  Label = 'Shout';       Category = 'shout' },
    @{ Mode = 3;   Label = 'Yell';        Category = 'yell' },
    @{ Mode = 11;  Label = 'Yell';        Category = 'yell' },
    @{ Mode = 4;   Label = 'Tell';        Category = 'tell' },
    @{ Mode = 12;  Label = 'Tell';        Category = 'tell' },
    @{ Mode = 5;   Label = 'Party';       Category = 'party' },
    @{ Mode = 13;  Label = 'Party';       Category = 'party' },
    @{ Mode = 6;   Label = 'Linkshell';   Category = 'linkshell' },
    @{ Mode = 14;  Label = 'Linkshell';   Category = 'linkshell' },
    @{ Mode = 7;   Label = 'Emote';       Category = 'emote' },
    @{ Mode = 15;  Label = 'Emote';       Category = 'emote' },
    @{ Mode = 211; Label = 'Unity';       Category = 'unity' },
    @{ Mode = 212; Label = 'Unity';       Category = 'unity' },
    @{ Mode = 213; Label = 'Linkshell 2'; Category = 'linkshell2' },
    @{ Mode = 214; Label = 'Linkshell 2'; Category = 'linkshell2' },
    @{ Mode = 219; Label = 'Assist J';    Category = 'assistj' },
    @{ Mode = 220; Label = 'Assist J';    Category = 'assistj' },
    @{ Mode = 221; Label = 'Assist E';    Category = 'assiste' },
    @{ Mode = 222; Label = 'Assist E';    Category = 'assiste' }
)

foreach ($expected in $expectedChannelModes) {
    $pattern = ('\[{0}\]\s*=\s*T\{{\s*label\s*=\s*''{1}'',\s*category\s*=\s*''{2}''\s*\}}' -f `
        $expected.Mode,
        [regex]::Escape($expected.Label),
        [regex]::Escape($expected.Category))
    Assert-Match `
        -Text $source `
        -Pattern $pattern `
        -Message ("Rendered text mode {0} should map to {1}/{2}." -f $expected.Mode, $expected.Label, $expected.Category)
}

foreach ($expected in @(
    @{ Mode = 17;  Label = 'Message'; Category = 'message' },
    @{ Mode = 36;  Label = 'Combat';  Category = 'combat' },
    @{ Mode = 37;  Label = 'Combat';  Category = 'combat' },
    @{ Mode = 38;  Label = 'Combat';  Category = 'combat' },
    @{ Mode = 50;  Label = 'Combat';  Category = 'combat' },
    @{ Mode = 121; Label = 'System';  Category = 'system' },
    @{ Mode = 142; Label = 'NPC';     Category = 'npc' },
    @{ Mode = 200; Label = 'System';  Category = 'system' }
)) {
    $pattern = ('\[{0}\]\s*=\s*T\{{\s*label\s*=\s*''{1}'',\s*category\s*=\s*''{2}''\s*\}}' -f `
        $expected.Mode,
        [regex]::Escape($expected.Label),
        [regex]::Escape($expected.Category))
    Assert-Match `
        -Text $source `
        -Pattern $pattern `
        -Message ("Known rendered text mode {0} should map to {1}/{2}." -f $expected.Mode, $expected.Label, $expected.Category)
}

$categoryStart = $source.IndexOf('accessxi.chat_reader_category_key = function')
$categoryEnd = $source.IndexOf("`naccessxi.chat_reader_category = function", $categoryStart)
if ($categoryStart -lt 0 -or $categoryEnd -lt 0) {
    throw 'Could not locate chat reader category classifier.'
}
$categoryBody = $source.Substring($categoryStart, $categoryEnd - $categoryStart)

Assert-Match `
    -Text $categoryBody `
    -Pattern 'chat_mode_metadata\[mid\]' `
    -Message 'Chat categories should come from the canonical rendered-mode metadata table.'
Assert-NotMatch `
    -Text $categoryBody `
    -Pattern "text:find|Apururu|mid\s*==\s*0|mid\s*==\s*122|mid\s*==\s*123" `
    -Message 'Chat categories must not be guessed from message text or the obsolete sequential/combat mapping.'

Assert-Match `
    -Text $source `
    -Pattern "chat_entry_speech\(entries\[index\],\s*tostring\(category\.key or 'all'\)\s*==\s*'all'\)" `
    -Message 'The All view should announce a channel tag, while a selected channel should not repeat its own category label.'
Assert-Match `
    -Text $source `
    -Pattern "(?s)chat_entry_speech\s*=\s*function\s*\(entry,\s*include_label\).*?include_label\s*==\s*false.*?return\s+text" `
    -Message 'Selected chat categories should pass through the complete native line without a duplicate synthetic label.'

Assert-Match `
    -Text $source `
    -Pattern "chat_history_path\s*=\s*accessxi_paths\.addon_path\('logs',\s*'ffxi-chat-history-v2\.tsv'\)" `
    -Message 'Corrected native-only history should use a new cache path so the legacy file remains preserved.'
Assert-Match `
    -Text $source `
    -Pattern "chat_history_legacy_path\s*=\s*accessxi_paths\.addon_path\('logs',\s*'ffxi-chat-history\.tsv'\)" `
    -Message 'The old chat history should remain available for a conservative one-time migration.'
Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.chat_history_legacy_entry_reliable' `
    -Message 'Legacy history migration should explicitly reject ambiguous entries.'
Assert-Match `
    -Text $source `
    -Pattern '(?s)chat_history_legacy_entry_reliable.*?mid\s*==\s*0\s+or\s+mid\s*==\s*1.*?return\s+false' `
    -Message 'Legacy modes 0 and 1 are ambiguous with injected addon output and must not be assigned native categories.'
Assert-Match `
    -Text $source `
    -Pattern "chat_history_path\s*\.\.\s*'\.tmp'" `
    -Message 'V2 history rewrites should be staged in a sibling temporary file.'
Assert-Match `
    -Text $source `
    -Pattern 'MoveFileExW\([^\)]*0x00000009' `
    -Message 'Validated V2 history should atomically replace the destination with write-through enabled.'
Assert-Match `
    -Text $source `
    -Pattern 'chat_history_preserve_invalid_cache' `
    -Message 'An invalid V2 cache should be preserved before legacy fallback replaces it.'

$historyEntryStart = $source.IndexOf('accessxi.chat_history_entry = function')
$historyEntryEnd = $source.IndexOf("`naccessxi.chat_history_rebuild_positions", $historyEntryStart)
if ($historyEntryStart -lt 0 -or $historyEntryEnd -lt 0) {
    throw 'Could not locate chat history entry constructor.'
}
$historyEntryBody = $source.Substring($historyEntryStart, $historyEntryEnd - $historyEntryStart)
Assert-Match `
    -Text $historyEntryBody `
    -Pattern 'label\s*=\s*accessxi\.chat_mode_label\(mode\)' `
    -Message 'Cached labels must be re-derived from the corrected native mode table.'
Assert-NotMatch `
    -Text $historyEntryBody `
    -Pattern "tostring\(label\s+or\s+''\)\s*~=" `
    -Message 'Legacy derived labels must never override the corrected native classifier.'

$textInStart = $source.IndexOf("ashita.events.register('text_in', 'accessxi_reader_text_in_cb'")
$textInEnd = $source.IndexOf("`nashita.events.register('packet_in'", $textInStart)
if ($textInStart -lt 0 -or $textInEnd -lt 0) {
    throw 'Could not locate AccessXI text_in callback.'
}
$textInBody = $source.Substring($textInStart, $textInEnd - $textInStart)
Assert-Match `
    -Text $textInBody `
    -Pattern 'tonumber\(e\.mode\)\s+or\s+tonumber\(e\.mode_modified\)' `
    -Message 'Native categorization should prefer the original rendered mode over an addon-modified mode.'
Assert-Match `
    -Text $textInBody `
    -Pattern 'e\.message\s+or\s+e\.message_modified' `
    -Message 'Native chat speech should preserve the original client-rendered punctuation.'
Assert-Match `
    -Text $textInBody `
    -Pattern 'e\.injected\s*==\s*true' `
    -Message 'Injected addon output must be excluded before native mode classification.'

$handleStart = $source.IndexOf('accessxi.chat_reader_native_log_open = function')
$pollEnd = $source.IndexOf("`naccessxi.chat_should_speak = function", $handleStart)
if ($handleStart -lt 0 -or $pollEnd -lt 0) {
    throw 'Could not locate chat reader key handling block.'
}
$keyBody = $source.Substring($handleStart, $pollEnd - $handleStart)

Assert-Match `
    -Text $keyBody `
    -Pattern '(?s)chat_reader_keys_armed\s*~=\s*true.*?return\s+true' `
    -Message 'A held chat-reader key should remain disarmed until physical release.'
Assert-NotMatch `
    -Text $keyBody `
    -Pattern 'last_key_tick|<\s*90' `
    -Message 'The old 90 ms held-key repeat path must be removed.'
Assert-Match `
    -Text $keyBody `
    -Pattern 'chat_reader_native_log_open\(\)' `
    -Message 'The custom history reader must yield when FFXI native chat-log menus are active.'
Assert-Match `
    -Text $keyBody `
    -Pattern '(?s)if\s*\(key\s*==\s*0\).*?chat_reader_last_key\s*=\s*0.*?chat_reader_keys_armed\s*=\s*true' `
    -Message 'The chat-reader key latch should re-arm only after every reader key is released.'
Assert-Match `
    -Text $keyBody `
    -Pattern '(?s)not\s+accessxi\.is_foreground_process\(\).*?or\s+is_chat_input_open\(\).*?or\s+accessxi\.chat_reader_native_log_open\(\).*?chat_reader_keys_armed\s*=\s*false' `
    -Message 'Suppressed reader keys should remain consumed until physical release.'

foreach ($expectedCategory in @(
    "T{ key = 'say', label = 'Say' }",
    "T{ key = 'tell', label = 'Tell' }",
    "T{ key = 'party', label = 'Party' }",
    "T{ key = 'linkshell', label = 'Linkshell' }",
    "T{ key = 'linkshell2', label = 'Linkshell 2' }",
    "T{ key = 'assistj', label = 'Assist J' }",
    "T{ key = 'assiste', label = 'Assist E' }",
    "T{ key = 'unity', label = 'Unity' }",
    "T{ key = 'emote', label = 'Emotes' }",
    "T{ key = 'message', label = 'Message' }",
    "T{ key = 'npc', label = 'NPC' }",
    "T{ key = 'shout', label = 'Shout' }",
    "T{ key = 'yell', label = 'Yell' }"
)) {
    if ($categories.IndexOf($expectedCategory) -lt 0) {
        throw "Chat category list is missing native category: $expectedCategory"
    }
}

$metadataStartForCategories = $source.IndexOf('accessxi.chat_mode_metadata = T{')
$metadataEndForCategories = $source.IndexOf("`n};", $metadataStartForCategories)
if ($metadataStartForCategories -lt 0 -or $metadataEndForCategories -lt 0) {
    throw 'Could not locate canonical chat-mode metadata table for category completeness check.'
}
$metadataForCategories = $source.Substring($metadataStartForCategories, $metadataEndForCategories - $metadataStartForCategories)
$declaredCategoryKeys = @{}
foreach ($match in [regex]::Matches($categories, "key\s*=\s*'([^']+)'")) {
    $declaredCategoryKeys[$match.Groups[1].Value] = $true
}
foreach ($match in [regex]::Matches($metadataForCategories, "category\s*=\s*'([^']+)'")) {
    $key = $match.Groups[1].Value
    if (-not $declaredCategoryKeys.ContainsKey($key)) {
        throw "Canonical chat-mode metadata returns an orphaned category not present in the menu: $key"
    }
}

Assert-NotMatch `
    -Text $categories `
    -Pattern "Shout and Yell" `
    -Message 'Shout and Yell are distinct native modes and must not share one category.'

$luaExe = Join-Path $repoRoot 'tools\lua51\lua5.1.exe'
if (-not (Test-Path -LiteralPath $luaExe)) {
    throw "Lua 5.1 test runtime not found: $luaExe"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('accessxi-chat-reader-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $keyHarnessPath = Join-Path $tempRoot 'key-harness.lua'
    $keyHarness = @"
local moves = 0
local category_moves = 0
local speeches = 0
local menu_name = ''
local foreground = true
local chat_open = false
local key_state = {}

accessxi = {
    chat_reader_last_key = 0,
    chat_reader_keys_armed = true,
    is_foreground_process = function () return foreground end,
    chat_reader_move = function (delta) moves = moves + delta; return 'line' end,
    chat_reader_switch_category = function (delta) category_moves = category_moves + delta; return 'category' end,
}
function is_chat_input_open() return chat_open end
function get_menu_name() return menu_name end
function speak() speeches = speeches + 1 end
function log_line() end
function string.fmt(self, ...) return string.format(self, ...) end
function string.eq(self, other, insensitive)
    if insensitive then return string.lower(self) == string.lower(other) end
    return self == other
end
bit = { band = function (value, mask) if mask == 0x8000 and value >= 0x8000 then return 0x8000 end return 0 end }
kernel32 = { GetAsyncKeyState = function (key) return key_state[key] or 0 end }

$keyBody

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
    end
end

key_state[0x21] = 0x8000
for _ = 1, 20 do accessxi.poll_chat_reader_hotkeys() end
equal(moves, -1, 'held Page Up must move exactly once')
equal(speeches, 1, 'held Page Up must speak exactly once')

key_state[0x21] = nil
accessxi.poll_chat_reader_hotkeys()
equal(accessxi.chat_reader_last_key, 0, 'release must clear the key latch')

key_state[0x21] = 0x8000
for _ = 1, 20 do accessxi.poll_chat_reader_hotkeys() end
equal(moves, -2, 'second physical Page Up press must move once more')
equal(speeches, 2, 'second physical Page Up press must speak once more')

key_state[0x21] = nil
accessxi.poll_chat_reader_hotkeys()
menu_name = 'menu    fulllog'
key_state[0x22] = 0x8000
for _ = 1, 20 do accessxi.poll_chat_reader_hotkeys() end
equal(moves, -2, 'custom reader must not move in a native chat-log menu')
equal(speeches, 2, 'custom reader must not speak in a native chat-log menu')

menu_name = ''
for _ = 1, 20 do accessxi.poll_chat_reader_hotkeys() end
equal(moves, -2, 'a key held while leaving native chat log must remain consumed')
equal(speeches, 2, 'a key held while leaving native chat log must remain silent')

key_state[0x22] = nil
accessxi.poll_chat_reader_hotkeys()
key_state[0x24] = 0x8000
for _ = 1, 20 do accessxi.poll_chat_reader_hotkeys() end
equal(category_moves, -1, 'held Home must change category exactly once')
equal(speeches, 3, 'held Home must speak exactly once')

-- No second action is allowed when a higher-priority key is tapped while the
-- original Page Up remains physically held.
key_state[0x24] = nil
accessxi.poll_chat_reader_hotkeys()
key_state[0x21] = 0x8000
accessxi.poll_chat_reader_hotkeys()
equal(moves, -3, 'fresh Page Up before overlapping-key test')
key_state[0x24] = 0x8000
accessxi.poll_chat_reader_hotkeys()
key_state[0x24] = nil
for _ = 1, 20 do accessxi.poll_chat_reader_hotkeys() end
equal(moves, -3, 'overlapping Home must not re-arm a still-held Page Up')

key_state[0x21] = nil
accessxi.poll_chat_reader_hotkeys()
foreach_menu = { 'menu    logwindo', 'menu    fulllog', 'menu    logwin2a' }
for _, name in ipairs(foreach_menu) do
    menu_name = name
    key_state[0x22] = 0x8000
    accessxi.poll_chat_reader_hotkeys()
    equal(moves, -3, 'native menu matcher must suppress ' .. name)
    key_state[0x22] = nil
    accessxi.poll_chat_reader_hotkeys()
end

menu_name = ''
foreground = false
key_state[0x23] = 0x8000
accessxi.poll_chat_reader_hotkeys()
foreground = true
for _ = 1, 20 do accessxi.poll_chat_reader_hotkeys() end
equal(category_moves, -1, 'a key held while focus returns must remain consumed')
key_state[0x23] = nil
accessxi.poll_chat_reader_hotkeys()
key_state[0x23] = 0x8000
accessxi.poll_chat_reader_hotkeys()
equal(category_moves, 0, 'End should act once after a real release and fresh press')

key_state[0x23] = nil
accessxi.poll_chat_reader_hotkeys()
chat_open = true
key_state[0x22] = 0x8000
accessxi.poll_chat_reader_hotkeys()
chat_open = false
for _ = 1, 20 do accessxi.poll_chat_reader_hotkeys() end
equal(moves, -3, 'a key held while chat input closes must remain consumed')
key_state[0x22] = nil
accessxi.poll_chat_reader_hotkeys()
key_state[0x22] = 0x8000
accessxi.poll_chat_reader_hotkeys()
equal(moves, -2, 'Page Down should act once after a real release and fresh press')
"@
    [System.IO.File]::WriteAllText($keyHarnessPath, $keyHarness, [System.Text.UTF8Encoding]::new($false))
    & $luaExe $keyHarnessPath
    if ($LASTEXITCODE -ne 0) {
        throw "Lua chat-reader key behavior test failed with exit code $LASTEXITCODE"
    }

    $metadataStart = $source.IndexOf('accessxi.chat_mode_metadata = T{')
    $metadataEnd = $source.IndexOf("`naccessxi.chat_reader_category = function", $metadataStart)
    if ($metadataStart -lt 0 -or $metadataEnd -lt 0) {
        throw 'Could not extract chat classifier/cache implementation for Lua behavior test.'
    }
    $metadataBody = $source.Substring($metadataStart, $metadataEnd - $metadataStart)
    $legacyPath = (Join-Path $tempRoot 'legacy.tsv').Replace('\', '/')
    $v2Path = (Join-Path $tempRoot 'v2.tsv').Replace('\', '/')
    $cacheHarnessPath = Join-Path $tempRoot 'cache-harness.lua'
    $cacheHarness = @"
local table_methods = {}
function table_methods:len() return #self end
function table_methods:append(value) table.insert(self, value); return self end
function table_methods:concat(separator) return table.concat(self, separator) end
function T(value) return setmetatable(value or {}, { __index = table_methods }) end
bit = { band = function (value, mask) if mask == 0xFF then return (tonumber(value) or 0) % 256 end return 0 end }
function tick() return 0 end
function log_state() end
function string.fmt(self, ...) return string.format(self, ...) end
function utf8_to_wide(text) return text end
kernel32 = {
    MoveFileExW = function (source, destination)
        os.remove(destination)
        local moved = os.rename(source, destination)
        return moved and 1 or 0
    end,
}

accessxi = {
    chat_history = T{},
    chat_history_max = 10000,
    chat_reader_positions = T{},
    chat_history_path = '$v2Path',
    chat_history_legacy_path = '$legacyPath',
    chat_history_cache_ready = false,
    chat_history_cache_load_handled = false,
    chat_history_cache_write_blocked = false,
    log_path = '',
    clean_incoming_text = function (text) return tostring(text or '') end,
    chat_history_escape = function (text) return tostring(text or '') end,
    chat_history_unescape = function (text) return tostring(text or '') end,
    escape_probe_log_text = function (text) return tostring(text or '') end,
    load_menu_module_table = function () return T{ categories = T{} } end,
}

$metadataBody

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
    end
end

local legacy = assert(io.open(accessxi.chat_history_legacy_path, 'w'))
legacy:write('1\tShout\t[Addons] generated output\n')
legacy:write('2\tTell\tZaltar : native shout\n')
legacy:write('4\tLinkshell\t>>Longrodvonhugen : native tell\n')
legacy:write('121\tCombat\tBasic system message\n')
legacy:close()

local loaded = accessxi.chat_history_load_cache()
equal(loaded, 3, 'legacy migration must drop ambiguous injected mode 1')
equal(accessxi.chat_history:len(), 3, 'legacy migration row count')
equal(accessxi.chat_history[1].label, 'Shout', 'legacy mode 2 label must be re-derived')
equal(accessxi.chat_history[1].category, 'shout', 'legacy mode 2 category')
equal(accessxi.chat_history[2].label, 'Tell', 'legacy mode 4 label must be re-derived')
equal(accessxi.chat_history[2].category, 'tell', 'legacy mode 4 category')
equal(accessxi.chat_history[3].label, 'System', 'legacy mode 121 stale Combat label must be ignored')
equal(accessxi.chat_history[3].category, 'system', 'legacy mode 121 category')

local v2 = assert(io.open(accessxi.chat_history_path, 'r'))
local v2_text = v2:read('*a')
v2:close()
if not v2_text:find('^#accessxi%-chat%-history%-v2%-native%-only\n') then
    error('v2 cache header missing')
end
if v2_text:find('\tTell\t', 1, true) or v2_text:find('\tCombat\t', 1, true) then
    error('v2 cache must not persist derived labels')
end

accessxi.chat_history = T{}
accessxi.chat_reader_positions = T{}
accessxi.chat_history_cache_ready = false
local reloaded = accessxi.chat_history_load_cache()
equal(reloaded, 3, 'v2 cache round trip row count')
equal(accessxi.chat_history[1].category, 'shout', 'v2 cache round trip category')
equal(accessxi.chat_history[3].label, 'System', 'v2 cache round trip label')

local corrupt = assert(io.open(accessxi.chat_history_path, 'w'))
corrupt:write('partial cache without a valid header\n')
corrupt:close()
accessxi.chat_history = T{}
accessxi.chat_reader_positions = T{}
accessxi.chat_history_cache_ready = false
accessxi.chat_history_cache_load_handled = false
local recovered = accessxi.chat_history_load_cache()
equal(recovered, 3, 'invalid v2 must fall back to preserved legacy history')
equal(accessxi.chat_history[1].category, 'shout', 'invalid v2 fallback category')
local invalid_copy = io.open(accessxi.chat_history_path .. '.invalid', 'r')
if invalid_copy == nil then error('invalid v2 cache was not preserved') end
invalid_copy:close()
local recovered_v2 = assert(io.open(accessxi.chat_history_path, 'r'))
local recovered_header = recovered_v2:read('*l')
recovered_v2:close()
equal(recovered_header, '#accessxi-chat-history-v2-native-only', 'legacy fallback must publish a validated v2 cache')
"@
    [System.IO.File]::WriteAllText($cacheHarnessPath, $cacheHarness, [System.Text.UTF8Encoding]::new($false))
    & $luaExe $cacheHarnessPath
    if ($LASTEXITCODE -ne 0) {
        throw "Lua chat cache migration test failed with exit code $LASTEXITCODE"
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'chat reader native mode and key checks ok'
