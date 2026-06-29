$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$source = Get-Content -LiteralPath $addonPath -Raw

function Assert-AddonPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($source -notmatch $Pattern) {
        throw "Missing playermo native command-menu contract: $Name"
    }
}

function Assert-AddonNotPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($source -match $Pattern) {
        throw "Forbidden playermo command-menu contract: $Name"
    }
}

Assert-AddonPattern 'function\s+accessxi\.playermo_target_state_context' 'target state context helper'
Assert-AddonPattern 'function\s+accessxi\.playermo_native_help_entry' 'target-window native help helper'
Assert-AddonPattern '(?s)function\s+accessxi\.playermo_native_help_entry.*?GetWindowHelpTitle.*?GetWindowHelpString' 'native help/title pointers are read from the target manager'
Assert-AddonPattern 'state playermo native-help-row' 'log line for accepted target-window native command text'
Assert-AddonPattern 'reason="dynamic-target-without-native-label"' 'dynamic targets refuse guessed labels when native text is unavailable'
Assert-AddonPattern 'targetKind="%s"' 'playermo logs include state-backed target kind'
Assert-AddonPattern 'function\s+accessxi\.playermo_label_looks_safe' 'playermo-specific label safety helper'
Assert-AddonPattern "lower_label:match\('\^menu%s'\)" 'playermo rejects menu-internal labels'
Assert-AddonPattern "label:match\('\^,%a,%a\$'\)" 'playermo rejects comma-separated single-letter native artifacts before DAT fallback'
Assert-AddonPattern 'function\s+accessxi\.playermo_command_pointer_probe' 'selected command pointer dereference probe'
Assert-AddonPattern 'function\s+accessxi\.playermo_command_pointer_field_probe' 'compact selected command pointer field probe'
Assert-AddonPattern 'function\s+accessxi\.playermo_probe_words' 'compact selected command object word probe'
Assert-AddonPattern 'function\s+accessxi\.playermo_dynamic_command_id' 'live dynamic command id reader'
Assert-AddonPattern 'child\s+\+\s+0x1A\s+\+\s+\(selected\s+\*\s+2\)' 'dynamic command id is read from child command word list'
Assert-AddonPattern 'function\s+accessxi\.load_auto_translates_resource' 'auto-translate resource loader for command labels missing from DAT string tables'
Assert-AddonPattern "accessxi\.resource_path\('windower',\s*'auto_translates\.lua'\)" 'auto-translate labels are loaded through portable resource path discovery'
Assert-AddonPattern 'function\s+accessxi\.auto_translate_label' 'auto-translate label helper'
Assert-AddonPattern 'function\s+accessxi\.playermo_command_id_dat_entry' 'DAT-backed command id mapper'
Assert-AddonPattern 'function\s+accessxi\.playermo_command_context_label' 'native command context label helper'
Assert-AddonPattern "(?s)function\s+accessxi\.playermo_command_context_label.*?trust magic.*?return 'Trust Magic'" 'Trust magic native help sets Trust Magic context'
Assert-AddonPattern "(?s)function\s+accessxi\.playermo_command_context_label.*?release an alter ego.*?return 'Release'" 'Release native help sets Release context'
Assert-AddonPattern "(?s)function\s+accessxi\.native_known_menu_speech.*?if\s*\(title\s*==\s*''\s+and\s+not\s+menu_name:eq\('menu    playermo',\s*true\)\)\s*then\s*return\s+nil" 'empty-title playermo menus still reach the live playermo reader'
Assert-AddonPattern '\[1\]\s*=\s*\{\s*label_dat\s*=\s*''ROM\\\\165\\\\74\.DAT'',\s*label_row\s*=\s*112,\s*help_dat\s*=\s*''ROM\\\\165\\\\75\.DAT'',\s*help_row\s*=\s*31' 'command id 1 maps to DAT-backed Attack'
Assert-AddonPattern '\[18\]\s*=\s*\{\s*label_auto_translate\s*=\s*2111,\s*help_dat\s*=\s*''ROM\\\\165\\\\75\.DAT'',\s*help_row\s*=\s*37' 'combat command id 18 maps to resource-backed Switch Target with DAT-backed help'
Assert-AddonPattern '\[8\]\s*=\s*\{\s*label_dat\s*=\s*''ROM\\\\165\\\\74\.DAT'',\s*label_row\s*=\s*114,\s*help_dat\s*=\s*''ROM\\\\165\\\\75\.DAT'',\s*help_row\s*=\s*25' 'command id 8 maps to DAT-backed Magic'
Assert-AddonPattern '\[7\]\s*=\s*\{\s*label_dat\s*=\s*''ROM\\\\165\\\\74\.DAT'',\s*label_row\s*=\s*115,\s*help_dat\s*=\s*''ROM\\\\165\\\\75\.DAT'',\s*help_row\s*=\s*24' 'command id 7 maps to DAT-backed Abilities'
Assert-AddonPattern '\[25\]\s*=\s*\{\s*help_dat\s*=\s*''ROM\\\\165\\\\75\.DAT'',\s*help_row\s*=\s*718' 'command id 25 uses DAT-backed Trust magic help without invented label'
Assert-AddonPattern '\[26\]\s*=\s*\{\s*help_dat\s*=\s*''ROM\\\\165\\\\75\.DAT'',\s*help_row\s*=\s*719' 'command id 26 uses DAT-backed Release help without invented label'
Assert-AddonPattern '\[9\]\s*=\s*\{\s*label_dat\s*=\s*''ROM\\\\165\\\\74\.DAT'',\s*label_row\s*=\s*113,\s*help_dat\s*=\s*''ROM\\\\165\\\\75\.DAT'',\s*help_row\s*=\s*26' 'command id 9 maps to DAT-backed Items'
Assert-AddonPattern '\[3\]\s*=\s*\{\s*label_auto_translate\s*=\s*2101,\s*help_dat\s*=\s*''ROM\\\\165\\\\75\.DAT'',\s*help_row\s*=\s*32' 'combat command id 3 maps to resource-backed Disengage with DAT-backed help'
Assert-AddonPattern '\[11\]\s*=\s*\{\s*label_dat\s*=\s*''ROM\\\\165\\\\74\.DAT'',\s*label_row\s*=\s*122,\s*help_dat\s*=\s*''ROM\\\\165\\\\75\.DAT'',\s*help_row\s*=\s*30' 'command id 11 maps to DAT-backed Check'
Assert-AddonPattern '(?s)function\s+accessxi\.playermo_command_id_dat_entry.*?spec\.label_auto_translate.*?accessxi\.auto_translate_label' 'command id mapper resolves auto-translate labels before help-only fallback'
Assert-AddonPattern '(?s)function\s+accessxi\.playermo_command_menu_dat_entry.*?\[4\]\s*=\s*\{\s*help_dat\s*=\s*''ROM\\\\165\\\\75\.DAT'',\s*help_row\s*=\s*718' 'self command row 4 uses DAT-backed Trust magic help without invented label'
Assert-AddonPattern '(?s)function\s+accessxi\.playermo_command_menu_dat_entry.*?if\s*\(label\s*==\s*''''\s*and\s*help\s*==\s*''''\)\s*then' 'self command fallback accepts help-only DAT rows'
Assert-AddonPattern 'state playermo dynamic-command-row' 'log line for accepted dynamic command id rows'
Assert-AddonPattern 'native-playermo-dynamic-command' 'speech key for dynamic command id rows'
Assert-AddonPattern 'state playermo dynamic-visible-probe' 'dynamic target row probe before quiet return'
Assert-AddonPattern 'objDwords="%s"' 'dynamic target probe logs menu object dwords'
Assert-AddonPattern 'childDwords="%s"' 'dynamic target probe logs child/control object dwords'
Assert-AddonPattern 'objWords="%s"' 'dynamic target probe logs menu object words'
Assert-AddonPattern 'childWords="%s"' 'dynamic target probe logs child/control object words'
Assert-AddonPattern 'objPlus8=0x%08X' 'dynamic target probe logs object child pointer candidate'
Assert-AddonPattern 'childCommandWord=%d' 'dynamic target probe logs child command word candidate'
Assert-AddonPattern 'childVisibleCountWord=%d' 'dynamic target probe logs child visible count word candidate'
Assert-AddonPattern 'rowDwords="%s"' 'dynamic target probe logs selected row dwords'
Assert-AddonPattern 'rowStrings="%s"' 'dynamic target probe logs selected row inline strings'
Assert-AddonPattern 'rowRuns="%s"' 'dynamic target probe logs selected row text runs'
Assert-AddonPattern 'rowDescDwords="%s"' 'dynamic target probe logs selected row descriptor dwords'
Assert-AddonPattern 'rowDescStrings="%s"' 'dynamic target probe logs selected row descriptor inline strings'
Assert-AddonPattern 'rowDescRuns="%s"' 'dynamic target probe logs selected row descriptor text runs'
Assert-AddonPattern 'shapeDwords="%s"' 'dynamic target probe logs native ank shape dwords'
Assert-AddonPattern 'shapeStrings="%s"' 'dynamic target probe logs native ank shape inline strings'
Assert-AddonPattern 'commandDwords="%s"' 'quiet dynamic target logs command dwords'
Assert-AddonPattern 'commandStrings="%s"' 'quiet dynamic target logs command inline strings'
Assert-AddonPattern 'commandPointers="%s"' 'quiet dynamic target logs selected command pointer details'
Assert-AddonPattern 'commandPtr0="%s"' 'quiet dynamic target logs command pointer field 0 without truncating later fields'
Assert-AddonPattern 'commandPtr4="%s"' 'quiet dynamic target logs command pointer field 4 without truncating later fields'
Assert-AddonPattern 'commandPtr8="%s"' 'quiet dynamic target logs command pointer field 8 without truncating later fields'
Assert-AddonPattern 'entryDwords="%s"' 'quiet dynamic target logs selected entry dwords'
Assert-AddonNotPattern 'function\s+accessxi\.playermo_native_command_help_entry' 'disproven selected-command native help pointer helper'
Assert-AddonNotPattern 'function\s+accessxi\.playermo_command_label_from_help' 'disproven native help-to-DAT label mapper'
Assert-AddonNotPattern 'state playermo native-command-help-row' 'accepted selected-command help speech from wrong command bank'
Assert-AddonNotPattern 'native-playermo-command-help' 'speech key for wrong selected-command help text'
Assert-AddonNotPattern 'C:\\\\Users\\\\buu42\\\\windower\\\\res\\\\auto_translates\.lua' 'hardcoded local auto-translate path'
Assert-AddonNotPattern "label\s*=\s*'Trust'" 'literal Trust label in the playermo fixed DAT fallback'
Assert-AddonNotPattern "label\s*=\s*'Switch Target'" 'literal Switch Target label in the playermo dynamic command mapper'
Assert-AddonNotPattern "label\s*=\s*'Disengage'" 'literal Disengage label in the playermo dynamic command mapper'
Assert-AddonNotPattern '(?s)function\s+accessxi\.playermo_command_menu_dat_entry.*?return\s+nil,\s*''empty-label''' 'self command fallback rejects help-only DAT rows'

$speechStart = $source.IndexOf('function accessxi.playermo_menu_speech')
if ($speechStart -lt 0) {
    throw 'Missing playermo_menu_speech function'
}
$speechEnd = $source.IndexOf("`nend`r`n`r`naccessxi.inspect_equipment_slot_names", $speechStart)
if ($speechEnd -lt 0) {
    $speechEnd = $source.Length
}
$speechBody = $source.Substring($speechStart, $speechEnd - $speechStart)

$nativeHelpIndex = $speechBody.IndexOf('accessxi.playermo_native_help_entry')
$nativeQueryIndex = $speechBody.IndexOf('accessxi.native_query_label_for_selection')
$dynamicCommandIndex = $speechBody.IndexOf('accessxi.playermo_dynamic_command_id')
$commandFallbackIndex = $speechBody.IndexOf('accessxi.playermo_command_menu_dat_entry')
$dynamicProbeIndex = $speechBody.IndexOf('state playermo dynamic-visible-probe')
$dynamicQuietIndex = $speechBody.IndexOf('reason="dynamic-target-without-native-label"')
if ($nativeHelpIndex -lt 0) {
    throw 'playermo_menu_speech does not call playermo_native_help_entry'
}
if ($nativeQueryIndex -lt 0) {
    throw 'playermo_menu_speech does not call native_query_label_for_selection'
}
if ($dynamicCommandIndex -lt 0) {
    throw 'playermo_menu_speech does not call playermo_dynamic_command_id'
}
if ($commandFallbackIndex -lt 0) {
    throw 'playermo_menu_speech does not call playermo_command_menu_dat_entry'
}
if ($dynamicProbeIndex -lt 0) {
    throw 'playermo_menu_speech does not log dynamic-visible-probe before quieting dynamic targets'
}
if ($dynamicQuietIndex -lt 0) {
    throw 'playermo_menu_speech does not have the dynamic target quiet block'
}
if ($nativeHelpIndex -gt $nativeQueryIndex) {
    throw 'playermo native help must run before generic native row query'
}
if ($nativeQueryIndex -gt $dynamicProbeIndex) {
    throw 'playermo generic native row query must run before dynamic target row probe'
}
if ($nativeQueryIndex -gt $dynamicCommandIndex) {
    throw 'playermo generic native row query must run before dynamic command id mapper'
}
if ($dynamicCommandIndex -gt $dynamicProbeIndex) {
    throw 'playermo dynamic command id mapper must run before dynamic target row probe'
}
if ($dynamicProbeIndex -gt $dynamicQuietIndex) {
    throw 'playermo dynamic target row probe must run before the quiet block'
}
if ($nativeQueryIndex -gt $commandFallbackIndex) {
    throw 'playermo generic native row query must run before DAT fallback'
}
if ($speechBody -notmatch 'local\s+spoken_command\s*=\s*command_label\s*~=\s*''''\s*and\s*command_label\s*or\s*command_help') {
    throw 'playermo self command fallback does not preserve help-only speech text'
}
if ($speechBody -notmatch 'local\s+command_context\s*=\s*accessxi\.playermo_command_context_label\(command_label,\s*command_help\)') {
    throw 'playermo self command fallback does not derive a semantic command context from native help'
}
if ($speechBody -notmatch 'last_playermo_command_label\s*=\s*command_context') {
    throw 'playermo self command fallback does not hand off the context label to follow-up windows'
}
if ($speechBody -notmatch 'local\s+derived_command_label\s*=\s*''''') {
    throw 'playermo command speech does not keep a derived label slot for help-only native rows'
}
if ($speechBody -match 'local\s+speech_parts\s*=\s*T\{\s*''Commands'',\s*command_label\s*\}') {
    throw 'playermo self command fallback still forces a blank label into speech'
}

Write-Host 'playermo native command-menu static checks ok'
