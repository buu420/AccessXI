param(
    [string]$AddonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotContains {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )
    if ($Text -match $Pattern) {
        throw $Message
    }
}

Assert-True (Test-Path -LiteralPath $AddonPath) "Missing AccessXI reader addon: $AddonPath"
$source = Get-Content -LiteralPath $AddonPath -Raw
$roeModulePath = Join-Path (Split-Path -Path $AddonPath -Parent) 'modules\menus\records_of_eminence.lua'
Assert-True (Test-Path -LiteralPath $roeModulePath) "Missing Records of Eminence module: $roeModulePath"
$roeModuleSource = Get-Content -LiteralPath $roeModulePath -Raw

Assert-Contains $source 'local function load_step' 'AccessXI load callback must have a protected load_step helper.'
Assert-Contains $source "load_step\('nav-load-points',\s*nav_load_points\)" 'nav_load_points must run through protected load_step so a nav init error cannot abort speech/log startup.'
Assert-Contains $source "log_line\('load begin'\)" 'AccessXI load callback must log before risky startup work so failed loads leave evidence.'
Assert-Contains $source "log_line\(\('load step failed name=%s error=`"%s`"'\)" 'Protected load steps must log their own failure name and error.'
Assert-Contains $source 'function accessxi\.run_load_startup\(reason\)' 'AccessXI startup must be factored into an idempotent function.'
Assert-Contains $source 'accessxi\.run_load_startup\(''load-event''\)' 'Ashita load event must call the shared AccessXI startup function.'
Assert-Contains $source 'accessxi\.run_load_startup\(''top-level''\)' 'AccessXI must run the shared startup once from top-level as a fallback when the load event is not delivered.'
Assert-Contains $source 'accessxi\.load_startup_ran == true' 'AccessXI shared startup must be idempotent so load-event and top-level fallback cannot double initialize.'
Assert-Contains $source "accessxi_paths\.resolved_addon_root\s*=\s*function" 'AccessXI must resolve addon root through a helper that can reject blank addon.path values.'
Assert-Contains $source "accessxi_paths\.addon_root\s*=\s*accessxi_paths\.resolved_addon_root\(\)" 'AccessXI addon root must fall back to raw addon metadata when addon.path is blank.'
Assert-Contains $source "accessxi_paths\.ffxi_root_has_core_dat\s*=\s*function" 'AccessXI must validate a reported FFXI root before using it for DAT-backed menus.'
Assert-Contains $source "accessxi_paths\.default_ffxi_root_candidates\s*=\s*function" 'AccessXI must keep a portable fallback search for FFXI installs when Ashita reports a stale root.'
Assert-Contains $source "os\.getenv\('ACCESSXI_FFXI_ROOT'\)" 'AccessXI must allow an environment override for nonstandard FFXI installs.'
Assert-Contains $source "os\.getenv\('ProgramFiles\(x86\)'\)" 'AccessXI fallback install search must derive standard roots from the local machine environment.'
Assert-Contains $source "'PlayOnline', 'SquareEnix', 'FINAL FANTASY XI'" 'AccessXI must still search the PlayOnline install tree without hard-coding an absolute drive path.'
Assert-NotContains $source '(?i)c:\\users\\[a-z0-9._-]+\\' 'AccessXI reader source must not embed a user-profile absolute path.'
Assert-NotContains $source '(?i)c:\\\\users\\\\[a-z0-9._-]+\\\\' 'AccessXI reader source must not embed a Lua-escaped user-profile absolute path.'
Assert-True ($source.IndexOf('C:\Program Files', [StringComparison]::OrdinalIgnoreCase) -lt 0) 'AccessXI reader source must not hard-code a Program Files absolute path.'
Assert-True ($source.IndexOf('C:\\Program Files', [StringComparison]::OrdinalIgnoreCase) -lt 0) 'AccessXI reader source must not hard-code a Lua-escaped Program Files absolute path.'
Assert-Contains $source "accessxi_paths\.ffxi_root_has_core_dat\(normalized\)" 'AccessXI must reject reported FFXI roots that do not contain the expected DAT files.'
Assert-Contains $source "accessxi_paths\.addon_path\('modules'" 'AccessXI module table loader must use the resolved addon root, not raw addon.path.'
Assert-Contains $source "accessxi_paths\.addon_path\('modules',\s*'menus'" 'AccessXI menu module loader must use the resolved addon root, not raw addon.path.'
$loadCallback = [regex]::Match($source, "ashita\.events\.register\('load', 'load_cb', function \(\)(?<body>[\s\S]*?)\r?\nend\);")
Assert-True $loadCallback.Success 'Could not locate the AccessXI load callback body.'
if ($loadCallback.Groups['body'].Value -match '(?m)^\s*nav_load_points\(\);') {
    throw 'load_cb must not call nav_load_points directly; it must be protected by load_step.'
}

$tableLoaderBlock = [regex]::Match($source, "function accessxi\.load_module_file_table[\s\S]*?^end\s*$", [System.Text.RegularExpressions.RegexOptions]::Multiline)
Assert-True $tableLoaderBlock.Success 'Could not locate AccessXI table module loader block.'
Assert-Contains $tableLoaderBlock.Groups[0].Value 'env\.accessxi\s*=\s*accessxi' 'AccessXI table module loader must expose the local accessxi table to split-out menu data modules.'
Assert-Contains $tableLoaderBlock.Groups[0].Value 'setfenv\(chunk,\s*env\)' 'AccessXI table module loader must run split-out data modules in an environment that includes accessxi helpers.'
if ($tableLoaderBlock.Groups[0].Value -match 'loadfile\(path\)\(\)') {
    throw 'AccessXI table modules must not execute in the default global environment; split-out quest data needs the local accessxi helper table.'
}

$loaderBlock = [regex]::Match($source, "function accessxi\.load_module_table[\s\S]*?function accessxi\.load_code_module")
Assert-True $loaderBlock.Success 'Could not locate AccessXI module loader block.'
if ($loaderBlock.Groups[0].Value -match 'addon\.path\s*\.\.') {
    throw 'AccessXI module loaders must not build module paths from raw addon.path; use accessxi_paths.addon_path so blank addon.path does not break moved installs.'
}

$objectiveListBlock = [regex]::Match($source, "function accessxi\.records_of_eminence_objective_list_speech[\s\S]*?^end\s*$", [System.Text.RegularExpressions.RegexOptions]::Multiline)
Assert-True $objectiveListBlock.Success 'Could not locate Records of Eminence objective-list speech block.'
Assert-Contains $source 'function accessxi\.records_of_eminence_objective_list_native_row' 'RoE objective-list speech must recover native row labels when the live visible category shape differs from static data.'
Assert-Contains $source 'function accessxi\.records_of_eminence_objective_list_row_from_slot' 'RoE objective-list speech must recover parent categories from live native slot IDs, not selected row position.'
Assert-Contains $source '0xF210' 'RoE objective-list parent category recovery must be anchored to the live native category slot IDs.'
Assert-Contains $source 'native_query_label_for_selection\(child,\s*selected,\s*visible_count,\s*''roe-objective-list''' 'RoE objective-list native recovery must use the existing native selected-row scanner before falling silent.'
Assert-Contains $objectiveListBlock.Groups[0].Value 'quests_menu_runtime_slot\(child,\s*raw\)' 'RoE objective-list speech must inspect the current runtime slot before returning silence.'
Assert-Contains $objectiveListBlock.Groups[0].Value 'records_of_eminence_objective_catalog_speech\(' 'RoE objective-list speech must use current native objective IDs for catalog-backed objective rows.'
Assert-Contains $objectiveListBlock.Groups[0].Value 'records_of_eminence_objective_list_row_from_slot\(' 'RoE objective-list speech must use live native category slot IDs for parent category rows.'
Assert-Contains $objectiveListBlock.Groups[0].Value 'records_of_eminence_objective_list_native_row\(entry' 'RoE objective-list shape mismatch must try the selected native row label before returning silence.'
Assert-Contains $objectiveListBlock.Groups[0].Value 'row\.category_index' 'RoE objective-list native recovery must preserve the matched category index for downstream category speech.'
Assert-NotContains $objectiveListBlock.Groups[0].Value 'raw_category_index' 'RoE objective-list speech must not label dynamic category menus from raw row indices.'
Assert-NotContains $objectiveListBlock.Groups[0].Value 'all_rows\[raw_category_index\]' 'RoE objective-list speech must not map dynamic category menus through static row tables.'
Assert-NotContains $objectiveListBlock.Groups[0].Value 'row\s*=\s*rows\[selected\]' 'RoE objective-list speech must not label dynamic category menus from selected visible row tables.'
Assert-NotContains $roeModuleSource "\[10\]\s*=\s*\{[^\r\n]*optional\s*=\s*true" 'RoE objective-list data must not treat Vana''versary as hidden when raw=9 selects category 10.'
Assert-Contains $roeModuleSource "\[11\]\s*=\s*\{[^\r\n]*label\s*=\s*'Other'[^\r\n]*optional\s*=\s*true" 'RoE objective-list data must treat Other as optional for the current ten-row live menu fallback.'
Assert-Contains $roeModuleSource 'data\.objective_list_optional_category_indices\s*=\s*T\{\s*11,\s*12\s*\}' 'RoE objective-list optional category indices must allow the current ten-row live menu fallback without shifting Vana''versary.'
Assert-NotContains $source 'function accessxi\.records_of_eminence_objective_category_resource_row' 'RoE objective-category table resolver must be removed; dynamic category menus require native text or silence.'
$objectiveCategorySpeechBlock = [regex]::Match($source, "function accessxi\.records_of_eminence_objective_category_speech[\s\S]*?function accessxi\.records_of_eminence_objective_list_native_row", [System.Text.RegularExpressions.RegexOptions]::Multiline)
Assert-True $objectiveCategorySpeechBlock.Success 'Could not locate Records of Eminence objective-category speech block.'
Assert-NotContains $objectiveCategorySpeechBlock.Groups[0].Value 'records_of_eminence_objective_category_resource_row' 'RoE objective-category speech must not read labels from static category tables.'
Assert-NotContains $objectiveCategorySpeechBlock.Groups[0].Value 'objective-category-resource-row' 'RoE objective-category speech must not announce table-backed category labels.'
Assert-Contains $source 'function accessxi\.records_of_eminence_objective_category_row_from_slot' 'RoE objective-category speech must recover submenu labels from live native slot IDs.'
Assert-Contains $source 'ROM\\\\307\\\\24\.DAT' 'RoE objective-category labels must be sourced from the installed DAT category table, not user-specific hard-coded paths.'
Assert-Contains $source 'slot_id\s*-\s*0xF200' 'RoE objective-category DAT lookup must derive the category record from the live native 0xF2xx slot ID.'
Assert-Contains $source '0x0C00' 'RoE objective-category DAT lookup must use the native category record stride.'
Assert-Contains $source '0x280' 'RoE objective-category DAT lookup must use the native category title offset.'
Assert-Contains $objectiveCategorySpeechBlock.Groups[0].Value 'records_of_eminence_objective_category_row_from_slot\(slot_id' 'RoE objective-category speech must try the live slot-ID DAT label before returning silence.'
Assert-NotContains $objectiveCategorySpeechBlock.Groups[0].Value 'rows\[selected\]' 'RoE objective-category speech must not label dynamic submenu rows from selected row position.'
Assert-NotContains $source 'function accessxi\.records_of_eminence_objective_category_native_descriptor_row' 'RoE objective-category descriptor pointers are probe-only; they must not be promoted to speech.'
Assert-NotContains $objectiveCategorySpeechBlock.Groups[0].Value 'records_of_eminence_objective_category_native_descriptor_row\(' 'RoE objective-category speech must not announce descriptor pointer labels such as evitem or framesus-1.'
Assert-NotContains $objectiveCategorySpeechBlock.Groups[0].Value 'objective-category-descriptor-row' 'RoE objective-category speech must not log descriptor-backed rows as spoken category rows.'
Assert-Contains $source 'function accessxi\.records_of_eminence_objective_category_descriptor_text_probe' 'RoE objective-category probes must include descriptor pointer text candidates when native text is unavailable.'
$categoryLabelAllowedBlock = [regex]::Match($source, "function accessxi\.records_of_eminence_objective_category_label_allowed[\s\S]*?^end\s*$", [System.Text.RegularExpressions.RegexOptions]::Multiline)
Assert-True $categoryLabelAllowedBlock.Success 'Could not locate Records of Eminence objective-category label filter block.'
Assert-Contains $categoryLabelAllowedBlock.Groups[0].Value "lower:match\('\^menu%s\+'\)" 'RoE objective-category descriptor speech must reject internal menu object names such as "menu quest -1".'
Assert-Contains $categoryLabelAllowedBlock.Groups[0].Value "lower:match\('\^quest%s\*%-\?%d\+\$'\)" 'RoE objective-category descriptor speech must reject normalized internal quest menu names such as "quest -1".'
Assert-Contains $categoryLabelAllowedBlock.Groups[0].Value "lower == 'ro'" 'RoE objective-category descriptor speech must reject low-information RoE pointer fragments.'
Assert-Contains $objectiveCategorySpeechBlock.Groups[0].Value 'objective-category-missing' 'RoE objective-category speech must leave a targeted probe when native text is unavailable.'
Assert-Contains $source 'slotId=0x%04X' 'RoE objective-category block probe logs must include the live native submenu id.'

'ok: AccessXI reader load path is hardened.'
