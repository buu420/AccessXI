$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$nativeMenusPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\menus\native_menus.lua'

if (-not (Test-Path -LiteralPath $addonPath)) {
    throw "Addon not found: $addonPath"
}
if (-not (Test-Path -LiteralPath $nativeMenusPath)) {
    throw "Native menu module not found: $nativeMenusPath"
}

$source = Get-Content -LiteralPath $addonPath -Raw
$nativeMenus = Get-Content -LiteralPath $nativeMenusPath -Raw

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

Assert-Match `
    -Text $nativeMenus `
    -Pattern 'character_creation_family_menus\s*=\s*T\{' `
    -Message 'Character creation should declare the exact chmk menu family.'

foreach ($menu in @('chmkrace', 'chmkface', 'chmkhair', 'chmksize', 'chmkjobs', 'chmkname', 'chmkserv', 'chmktown', 'chmkpass', 'worldsel')) {
    Assert-Match `
        -Text $nativeMenus `
        -Pattern ("menu    {0}" -f $menu) `
        -Message ("Character creation family should include menu    {0}." -f $menu)
}

Assert-Match `
    -Text $nativeMenus `
    -Pattern 'character_creation_menu_resources\s*=\s*T\{' `
    -Message 'Character creation should keep DAT-backed row resources in native_menus.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "(?s)race\s*=\s*T\{\s*title\s*=\s*'Race'.*?label_dat\s*=\s*'ROM\\\\171\\\\5\.DAT'" `
    -Message 'The race picker should use the title-era DAT race labels from ROM\171\5.DAT.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "(?s)face\s*=\s*T\{\s*title\s*=\s*'Face'.*?label_template_dat\s*=\s*'ROM\\\\171\\\\6\.DAT'.*?label_template_row\s*=\s*5.*?count\s*=\s*8" `
    -Message 'The face picker should use the DAT label template Face %c from ROM\171\6.DAT:5.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "(?s)hair\s*=\s*T\{\s*title\s*=\s*'Hair'.*?label_template_dat\s*=\s*'ROM\\\\171\\\\6\.DAT'.*?label_template_row\s*=\s*6.*?count\s*=\s*2" `
    -Message 'The hair picker should use the DAT label template Hair %s from ROM\171\6.DAT:6.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "(?s)size\s*=\s*T\{\s*title\s*=\s*'Size'.*?label_template_dat\s*=\s*'ROM\\\\171\\\\6\.DAT'.*?label_template_row\s*=\s*7.*?count\s*=\s*3" `
    -Message 'The size picker should use the DAT label template Size %s from ROM\171\6.DAT:7.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "(?s)job\s*=\s*T\{\s*title\s*=\s*'Initial job'.*?label_dat\s*=\s*'ROM\\\\165\\\\86\.DAT'.*?count\s*=\s*6" `
    -Message 'The initial job picker should use the DAT job labels from ROM\165\86.DAT.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "(?s)name\s*=\s*T\{\s*title\s*=\s*''.*?label_dat\s*=\s*'ROM\\\\165\\\\69\.DAT'.*?label_row\s*=\s*4.*?label_kind\s*=\s*'prompt'" `
    -Message 'The character-name window should speak the DAT-backed name-entry prompt from ROM\165\69.DAT:4.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "(?s)worldpass\s*=\s*T\{\s*title\s*=\s*''.*?label_dat\s*=\s*'ROM\\\\97\\\\36\.DAT'.*?label_row\s*=\s*113.*?label_kind\s*=\s*'prompt'" `
    -Message 'The Gold World Pass text field should speak the DAT-backed window prompt from ROM\97\36.DAT:113.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "(?s)nation\s*=\s*T\{\s*title\s*=\s*'Starting country'.*?prompt_dat\s*=\s*'ROM\\\\97\\\\36\.DAT'.*?prompt_row\s*=\s*114.*?\[1\]\s*=\s*\{[^}]*title_row\s*=\s*29[^}]*body_row\s*=\s*30[^}]*\}.*?\[2\]\s*=\s*\{[^}]*title_row\s*=\s*40[^}]*body_row\s*=\s*41[^}]*\}.*?\[3\]\s*=\s*\{[^}]*title_row\s*=\s*51[^}]*body_row\s*=\s*52[^}]*\}" `
    -Message 'The starting-country picker should use DAT-backed title/body rows from ROM\97\36.DAT with one-based native row indices.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "(?s)character_creation_confirmation_resource\s*=\s*T\{.*?register_dat\s*=\s*'ROM\\\\97\\\\36\.DAT'.*?register_row\s*=\s*175.*?begin_dat\s*=\s*'ROM\\\\97\\\\36\.DAT'.*?begin_row\s*=\s*176.*?yes_dat\s*=\s*'ROM\\\\97\\\\37\.DAT'.*?yes_row\s*=\s*106.*?no_dat\s*=\s*'ROM\\\\97\\\\37\.DAT'.*?no_row\s*=\s*107" `
    -Message 'The character registration confirmation should use DAT-backed prompt and yes/no rows.'

Assert-NotMatch `
    -Text $nativeMenus `
    -Pattern "(?s)worldpass\s*=\s*T\{.*?label_dat\s*=\s*'ROM\\\\165\\\\71\.DAT'.*?label_row\s*=\s*111" `
    -Message 'The character-creation password field must not use the plain World Pass prompt from ROM\165\71.DAT:111.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "(?s)character_creation_error_dialog_resources\s*=\s*T\{.*?name_unavailable\s*=\s*T\{.*?error_dat\s*=\s*'ROM\\\\97\\\\35\.DAT'.*?error_row\s*=\s*1.*?error_code\s*=\s*3313.*?message_dat\s*=\s*'ROM\\\\97\\\\35\.DAT'.*?message_row\s*=\s*39.*?message_kind\s*=\s*'prompt'" `
    -Message 'Character creation should have a DAT-backed FFXI-3313 name-unavailable OK dialog resource.'

foreach ($case in @(
    @{ Index = 0; Row = 11; Label = 'Hair A' },
    @{ Index = 1; Row = 12; Label = 'Hair B' }
)) {
    Assert-Match `
        -Text $nativeMenus `
        -Pattern ("(?s)\[{0}\]\s*=\s*\{{\s*value_dat\s*=\s*'ROM\\\\171\\\\6\.DAT',\s*value_row\s*=\s*{1}\s*\}}" -f $case.Index, $case.Row) `
        -Message ("Hair index {0} should use DAT row {1} for {2}." -f $case.Index, $case.Row, $case.Label)
}

foreach ($case in @(
    @{ Index = 0; Row = 8; Label = 'Size S' },
    @{ Index = 1; Row = 9; Label = 'Size M' },
    @{ Index = 2; Row = 10; Label = 'Size L' }
)) {
    Assert-Match `
        -Text $nativeMenus `
        -Pattern ("(?s)\[{0}\]\s*=\s*\{{\s*value_dat\s*=\s*'ROM\\\\171\\\\6\.DAT',\s*value_row\s*=\s*{1}\s*\}}" -f $case.Index, $case.Row) `
        -Message ("Size index {0} should use DAT row {1} for {2}." -f $case.Index, $case.Row, $case.Label)
}

foreach ($case in @(
    @{ Index = 0; Row = 1; Label = 'Warrior' },
    @{ Index = 1; Row = 2; Label = 'Monk' },
    @{ Index = 2; Row = 3; Label = 'White Mage' },
    @{ Index = 3; Row = 4; Label = 'Black Mage' },
    @{ Index = 4; Row = 5; Label = 'Red Mage' },
    @{ Index = 5; Row = 6; Label = 'Thief' }
)) {
    Assert-Match `
        -Text $nativeMenus `
        -Pattern ("(?s)\[{0}\]\s*=\s*\{{\s*label_row\s*=\s*{1}\s*\}}" -f $case.Index, $case.Row) `
        -Message ("Initial job index {0} should map only to DAT row {1} for {2}." -f $case.Index, $case.Row, $case.Label)
}

foreach ($case in @(
    @{ Index = 0; Row = 0; Label = 'Hume Male' },
    @{ Index = 1; Row = 1; Label = 'Hume Female' },
    @{ Index = 2; Row = 2; Label = 'Elvaan Male' },
    @{ Index = 3; Row = 3; Label = 'Elvaan Female' },
    @{ Index = 4; Row = 4; Label = 'Tarutaru Male' },
    @{ Index = 5; Row = 5; Label = 'Tarutaru Female' },
    @{ Index = 6; Row = 6; Label = 'Mithra Female' },
    @{ Index = 7; Row = 7; Label = 'Galka Male' }
)) {
    Assert-Match `
        -Text $nativeMenus `
        -Pattern ("(?s)\[{0}\]\s*=\s*\{{\s*label_row\s*=\s*{1}\s*\}}" -f $case.Index, $case.Row) `
        -Message ("Race index {0} should map only to DAT row {1} for {2}." -f $case.Index, $case.Row, $case.Label)
}

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.is_character_creation_menu_name\s*\(' `
    -Message 'Addon should identify character creation menus through a dedicated family helper.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_menu_kind\s*\(' `
    -Message 'Addon should map chmk menu names to small resource kinds.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.is_character_creation_text_input_menu_name\s*\(menu_name\).*?menu    chmkname.*?menu    chmkpass" `
    -Message 'Character creation text fields should be identified explicitly so stale display text is not treated as native input.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_menu_selected\s*\(' `
    -Message 'Addon should have a dedicated native selected-row reader for character creation.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)if\s*\(kind\s*==\s*'name'\s+or\s+kind\s*==\s*'worldpass'\).*?%s-window-resource.*?return\s+0,\s*1,\s*state" `
    -Message 'Character creation text-entry windows should map to their single DAT prompts without relying on an unproven row signal.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.plain_native_menu_prompt\s*\(' `
    -Message 'Long DAT prompts should use a dedicated prompt sanitizer instead of the short row-label filter.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_long_prompt_text\s*\(' `
    -Message 'The starting-country description should use a narrow long-text sanitizer instead of the short prompt filter.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_dat_long_text\s*\(' `
    -Message 'The starting-country description should read long DAT rows without truncating or inventing text.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)text_kind\s*==\s*'prompt'.*?plain_native_menu_prompt" `
    -Message 'DAT row lookup should support prompt text for the character-name window.'

Assert-Match `
    -Text $source `
    -Pattern 'chat_input_speech_hold_until' `
    -Message 'The character-name prompt should briefly protect itself from chat-input just-opened speech.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_text_input_prompt_speech\s*\(' `
    -Message 'Character creation text-entry windows should have a native prompt speaker for the chat-input-open edge.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_ok_dialog_speech\s*\(' `
    -Message 'Character creation OK dialogs should have a dedicated native error-dialog reader.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_clean_name\s*\(' `
    -Message 'Character creation should sanitize native/input character names before speaking them in confirmation.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.remember_character_creation_name_from_input\s*\(' `
    -Message 'Character creation should remember the native typed name for the final registration confirmation.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_confirmation_native_name\s*\(' `
    -Message 'The registration confirmation should try a guarded native Register "Name" prompt scan so reloads do not lose the name.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_confirmation_selected_from_obj\s*\(' `
    -Message 'The registration confirmation should read the proven native Yes/No cursor from the live menu object.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_confirmation_probe\s*\(' `
    -Message 'The final character confirmation should have a narrow native selection probe for the Yes/No highlight.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_confirmation_speech\s*\(' `
    -Message 'The final character registration confirmation should have a dedicated DAT-backed yes/no reader.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_confirmation_prompt_text\s*\(' `
    -Message 'The character registration confirmation should preserve the DAT Register "%s" template quotes before substituting the native name.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_confirmation_dat_template_text\s*\(' `
    -Message 'The character registration confirmation should load the Register "%s" template as raw DAT text before quote-preserving cleanup.'

Assert-NotMatch `
    -Text $source `
    -Pattern 'register_template\s*=\s*accessxi\.plain_native_menu_prompt\(register_template' `
    -Message 'The Register "%s" DAT template must not go through the generic prompt cleaner because it strips the closing quote.'

Assert-Match `
    -Text $source `
    -Pattern ([regex]::Escape('Register%s+"([A-Za-z][A-Za-z]+)"')) `
    -Message 'The native confirmation name scan should be gated to the Register "Name" marker.'

$confirmSelectStart = $source.IndexOf('function accessxi.character_creation_confirmation_selected_from_obj')
if ($confirmSelectStart -lt 0) {
    throw 'Missing character_creation_confirmation_selected_from_obj helper.'
}
$confirmSelectEnd = $source.IndexOf("`nfunction accessxi.character_creation_confirmation_probe", $confirmSelectStart)
if ($confirmSelectEnd -lt 0) {
    throw 'Could not locate end of character_creation_confirmation_selected_from_obj helper.'
}
$confirmSelectBody = $source.Substring($confirmSelectStart, $confirmSelectEnd - $confirmSelectStart)

Assert-Match `
    -Text $confirmSelectBody `
    -Pattern 'read_i32\s*\(\s*obj\s*\+\s*0x4C\s*\)' `
    -Message 'The final confirmation cursor should use the live obj+0x4C field that changed when Yes/No moved.'

Assert-Match `
    -Text $confirmSelectBody `
    -Pattern "(?s)raw\s*==\s*1.*?return\s+0,\s*raw,\s*'native-one-4c-confirm'" `
    -Message 'The final confirmation should map native one-based 4C value 1 to the DAT-backed Yes row.'

Assert-Match `
    -Text $confirmSelectBody `
    -Pattern "(?s)raw\s*==\s*2.*?return\s+1,\s*raw,\s*'native-one-4c-confirm'" `
    -Message 'The final confirmation should map native one-based 4C value 2 to the DAT-backed No row.'

Assert-Match `
    -Text $confirmSelectBody `
    -Pattern 'fallback\s*==\s*0\s+or\s+fallback\s*==\s*1' `
    -Message 'The final confirmation should only use IwYesNoMenu.m_select as a guarded Yes/No fallback.'

Assert-Match `
    -Text $source `
    -Pattern 'character_creation_confirmation_probe\(menu_name,\s*obj,\s*selected' `
    -Message 'The character confirmation reader should log native selection evidence while the dialog is open.'

$confirmSpeechStart = $source.IndexOf('function accessxi.character_creation_confirmation_speech')
if ($confirmSpeechStart -lt 0) {
    throw 'Missing character_creation_confirmation_speech helper.'
}
$confirmSpeechEnd = $source.IndexOf("`nfunction accessxi.character_creation_text_input_prompt_speech", $confirmSpeechStart)
if ($confirmSpeechEnd -lt 0) {
    throw 'Could not locate end of character_creation_confirmation_speech helper.'
}
$confirmSpeechBody = $source.Substring($confirmSpeechStart, $confirmSpeechEnd - $confirmSpeechStart)

Assert-Match `
    -Text $confirmSpeechBody `
    -Pattern 'character_creation_confirmation_selected_from_obj\(obj,\s*fallback_selected\)' `
    -Message 'The final confirmation speech should use the proven obj+0x4C cursor before stale IwYesNoMenu.m_select.'

Assert-Match `
    -Text $confirmSpeechBody `
    -Pattern 'character_creation_confirmation_dat_template_text\(tostring\(spec\.register_dat\s+or\s+''''\),\s*tonumber\(spec\.register_row\)' `
    -Message 'The final confirmation speech should load Register "%s" through the quote-preserving raw DAT helper.'

Assert-NotMatch `
    -Text $confirmSpeechBody `
    -Pattern "register_template\s*=\s*accessxi\.dat_index_row_text\(.*?'prompt'\)" `
    -Message 'The final confirmation speech must not use the shared prompt DAT loader for Register "%s" because it strips the closing quote.'

Assert-Match `
    -Text $confirmSpeechBody `
    -Pattern "(?s)register_template:find\('%s',\s*1,\s*true\).*?name\s*==\s*''.*?reason=""missing-name"".*?return\s+nil" `
    -Message 'The final confirmation should stay silent while the native Register "%s" name is not available, instead of speaking a dangling begin-play fragment.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_ok_dialog_native_text\s*\(' `
    -Message 'Character creation OK dialogs should read the live native text buffer when it exposes an FFXI/POL error message.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)character_creation_ok_dialog_native_text\s*\(obj\).*?character_creation_ok_dialog_error_code\s*\(obj\)" `
    -Message 'The OK-dialog reader should prefer the live native error text before falling back to error-code mapping.'

Assert-Match `
    -Text $source `
    -Pattern 'FFXI%-%d%d%d%d.*POL%-%d%d%d%d' `
    -Message 'The live OK-dialog text reader should be gated to explicit FFXI/POL error markers.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)character_creation_ok_dialog_error_code\s*\(obj\).*?character_creation_error_dialog_entry\(error_code\)" `
    -Message 'The name-unavailable OK dialog should be gated by the native FFXI error code before speaking a mapped DAT row.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_ok_dialog_yesno_error_code\s*\(' `
    -Message 'Character creation OK dialogs should also check the native IwYesNoMenu error-code field.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.character_creation_ok_dialog_error_code\s*\(obj\).*?character_creation_ok_dialog_yesno_error_code" `
    -Message 'The OK-dialog error-code reader should fall back to the native IwYesNoMenu error-code field.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_ok_dialog_missing_error_probe\s*\(' `
    -Message 'Character creation OK dialogs without a native error code should emit a one-shot native probe instead of guessed speech.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)reason=""missing-error-code"".*?character_creation_ok_dialog_missing_error_probe" `
    -Message 'The missing-error-code path should trigger the character-creation OK native probe.'

Assert-Match `
    -Text $source `
    -Pattern 'accessxi\.dump_current_menu\s*=\s*dump_current_menu' `
    -Message 'The shared native menu dump helper should be callable from early character-creation dialog code.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.character_creation_error_dialog_entry\s*\(error_code\).*?spec\.error_code.*?message_dat.*?message_row" `
    -Message 'Character creation error dialogs should map native error codes to explicit DAT message rows.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)name:eq\('menu    ok'.*?character_creation_ok_dialog_speech" `
    -Message 'The menu    ok dialog should dispatch through the guarded character-creation OK dialog reader.'

Assert-Match `
    -Text $source `
    -Pattern 'state character-creation text-input-edge' `
    -Message 'Character creation text-input edges should log live menu evidence instead of relying on key timing.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)just_opened.*?accessxi\.is_character_creation_text_input_menu_name\(menu_name\).*?character_creation_text_input_prompt_speech" `
    -Message 'Character creation text-field prompts should speak when native chat input opens on any known text-input menu.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)accessxi\.is_character_creation_text_input_menu_name\(menu_name\).*?accessxi\.remember_character_creation_name_from_input\(menu_name,\s*state\.raw" `
    -Message 'Character creation name input should update the cached confirmation name from the real input text.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)local\s+input_key\s*=\s*\('%d:%s:%d'\):fmt\(state\.status.*?accessxi\.remember_chat_input_state\(state,\s*input_key\)" `
    -Message 'After the character-creation text prompt, chat input should remember the real input key so it does not echo a stray caret character.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)input_context\s*=\s*'Chat input\.';.*?state\.spoken.*?input_context\s*=\s*\('Chat input\. %s'\):fmt.*?sentence_fragment\(input_context\)" `
    -Message 'The character-creation text prompt should include Chat input and any existing text without changing the remembered edit state.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)raw\s*==\s*''\s+and\s+accessxi\.is_character_creation_text_input_menu_name\(get_menu_name\(\)\).*?spoken\s*=\s*''" `
    -Message 'Character creation input fields should ignore display-only text when the native raw input is blank.'

Assert-Match `
    -Text $source `
    -Pattern "'name-input-closed'" `
    -Message 'The character-name menu path should stay quiet when the text input is closed.'

Assert-Match `
    -Text $source `
    -Pattern "'text-input-closed'" `
    -Message 'Other character-creation text fields should stay quiet through the normal menu path while their input is closed.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_race_selected_from_state\s*\(' `
    -Message 'Race creation should have a dedicated cursor proof helper.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_face_selected_from_state\s*\(' `
    -Message 'Face creation should have a dedicated cursor proof helper.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_hair_selected_from_state\s*\(' `
    -Message 'Hair creation should have a dedicated cursor proof helper.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_size_selected_from_state\s*\(' `
    -Message 'Size creation should have a dedicated cursor proof helper.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_job_selected_from_state\s*\(' `
    -Message 'Initial job creation should have a dedicated cursor proof helper.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_nation_selected_from_state\s*\(' `
    -Message 'Starting-country selection should have a dedicated cursor proof helper.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_nation_menu_entry\s*\(' `
    -Message 'Starting-country speech should use a dedicated DAT-backed title/body row reader.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_template_value\s*\(' `
    -Message 'Character creation should allow short native template values like 1, A, and B without using full label filtering.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_dat_value_text\s*\(' `
    -Message 'Character creation should resolve short DAT-backed template values without full label filtering.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_format_template_label\s*\(' `
    -Message 'Character creation should format native DAT templates instead of hardcoding generated labels.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.log_character_creation_menu_probe\s*\(' `
    -Message 'Character creation should log a narrow native probe while its cursor signal is unknown.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_menu_speech\s*\(' `
    -Message 'Addon should dispatch character creation through a dedicated speech handler.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)menu_name:eq\('menu    worldsel',\s*true\).*?return\s+'world'" `
    -Message 'The world-selection screen should be mapped as a dynamic character-creation world menu.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_menu_entry\s*\(' `
    -Message 'World selection should have a dedicated dynamic native-row reader.'

$worldEntryStart = $source.IndexOf('function accessxi.character_creation_world_menu_entry')
if ($worldEntryStart -lt 0) {
    throw 'Missing character_creation_world_menu_entry helper.'
}
$worldEntryEnd = $source.IndexOf("`nfunction accessxi.log_character_creation_menu_probe", $worldEntryStart)
if ($worldEntryEnd -lt 0) {
    throw 'Could not locate end of character_creation_world_menu_entry helper.'
}
$worldEntryBody = $source.Substring($worldEntryStart, $worldEntryEnd - $worldEntryStart)

Assert-NotMatch `
    -Text $worldEntryBody `
    -Pattern 'magic_rendered_row_text|rendered-entry' `
    -Message 'World selection must not use the magic rendered-row fallback; it produced false-positive labels like NTA.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_name_resource\s*\(' `
    -Message 'World selection should load server names from the DAT index as an allowlist.'

Assert-Match `
    -Text $source `
    -Pattern 'ROM\\\\333\\\\34\.DAT' `
    -Message 'World selection should use the DAT-backed server-name table, not screenshot-derived labels.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_dat_match\s*\(' `
    -Message 'World selection should validate candidate row text against the DAT server-name allowlist.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_packet_rows_at\s*\(' `
    -Message 'World selection should parse native lobby world-list packet rows before using any row order.'

Assert-Match `
    -Text $source `
    -Pattern '0x46465849' `
    -Message 'World selection packet parsing should require the IXFF lobby packet terminator.'

Assert-Match `
    -Text $source `
    -Pattern '0x23' `
    -Message 'World selection packet parsing should require the native lobby world-list command id.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.arm_character_creation_world_packet_trace\s*\(' `
    -Message 'World selection should arm a bounded packet trace while the native row source is unknown.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.trace_character_creation_world_packet\s*\(' `
    -Message 'World selection should trace title/lobby packets before accepting a row source.'

Assert-Match `
    -Text $source `
    -Pattern 'state character-creation world-packet-trace dir=' `
    -Message 'World selection packet tracing should emit bounded diagnostic evidence.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)accessxi\.trace_character_creation_world_packet\(e,\s*'in'\).*?accessxi\.capture_character_creation_world_packet\(e\)" `
    -Message 'Incoming packet tracing should run before the current world-list packet capture.'

Assert-Match `
    -Text $source `
    -Pattern "accessxi\.trace_character_creation_world_packet\(e,\s*'out'\)" `
    -Message 'Outgoing lobby packet tracing should be available while the world list source is unknown.'

Assert-Match `
    -Text $source `
    -Pattern "accessxi\.arm_character_creation_world_packet_trace\('worldsel-transition'" `
    -Message 'Opening the world-selection menu should arm the bounded packet trace.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_scan_memory_for_packet_list\s*\(' `
    -Message 'World selection should have a one-shot native memory scan for the lobby world list.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_scan_memory_for_record_list\s*\(' `
    -Message 'World selection should scan for DAT-validated native id/name world records when the packet wrapper is not resident.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_record_sequence_from_hit\s*\(' `
    -Message 'World selection should build row order from contiguous native world records, not a hardcoded server list.'

Assert-Match `
    -Text $source `
    -Pattern 'state character-creation world-list-record-scan' `
    -Message 'World selection should log focused native id/name record scan evidence.'

Assert-NotMatch `
    -Text $source `
    -Pattern "character_creation_world_store_packet_rows\(rows,\s*'memory-(records|ixff)'" `
    -Message 'World selection must not speak detached memory-scanned world tables as live row order.'

Assert-Match `
    -Text $source `
    -Pattern 'detached-memory-source' `
    -Message 'World selection should reject stale detached memory world-list caches before speaking.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_packet_label\s*\(' `
    -Message 'World selection should resolve selected labels from a DAT-validated native world-list cache.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.log_character_creation_world_name_source_probe\s*\(' `
    -Message 'World selection should log the native world-name source pointer while the row source is being proven.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_name_hit_summary\s*\(' `
    -Message 'World selection should be able to log DAT-validated world-name hits near live native row roots.'

Assert-Match `
    -Text $source `
    -Pattern 'worldHits="%s"' `
    -Message 'World-name source probing should include DAT-validated hits from live pointer roots.'

Assert-Match `
    -Text $source `
    -Pattern 'hitRecords="%s"' `
    -Message 'World-name source probing should include native id/name records for DAT-validated hits.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_direct_record_hits\s*\(' `
    -Message 'World selection should have a focused direct native id/name record scanner.'

Assert-Match `
    -Text $source `
    -Pattern 'state character-creation world-child0c-record menu=' `
    -Message 'World selection should emit one-line DAT-validated child0C record probes to avoid clipped summaries.'

Assert-Match `
    -Text $source `
    -Pattern 'log_character_creation_world_child0c_record_probe\(\s*menu_name,\s*child0c,' `
    -Message 'World selection should log child0C record evidence from the live missing-row probe.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_record_ref_summary\s*\(' `
    -Message 'World selection should be able to scan row objects for pointers into native world records.'

Assert-Match `
    -Text $source `
    -Pattern 'state character-creation world-record-ref menu=' `
    -Message 'World selection should log whether the selected row/descriptor is bound to a native world record.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_id_array_summary\s*\(' `
    -Message 'World selection should probe for native DAT world-id arrays before accepting row order.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_record_pointer_array_summary\s*\(' `
    -Message 'World selection should probe for native pointers into DAT world records before accepting row order.'

Assert-Match `
    -Text $source `
    -Pattern 'state character-creation world-rowmap menu=' `
    -Message 'World selection should emit focused row-map evidence while the source is unknown.'

Assert-Match `
    -Text $source `
    -Pattern 'ids:len\(\) >= min_rows and unique_count == ids:len\(\)' `
    -Message 'World selection id-array probes should reject duplicate/partial byte runs before treating them as row maps.'

Assert-Match `
    -Text $source `
    -Pattern 'refs:len\(\) >= min_rows and unique_count == refs:len\(\)' `
    -Message 'World selection pointer-array probes should reject duplicate/partial native record runs.'

Assert-Match `
    -Text $source `
    -Pattern 'log_character_creation_world_row_map_probe\(\s*menu_name,\s*obj,\s*child04,\s*entry,\s*child0c,' `
    -Message 'World selection missing-row probe should include row-map diagnostics from live roots.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.log_character_creation_world_lobby_probe\s*\(' `
    -Message 'World selection should probe lobby/select pointer chains before accepting any guessed world order.'

Assert-Match `
    -Text $source `
    -Pattern 'state character-creation world-lobby-probe menu=' `
    -Message 'World selection should emit lobby/select chain evidence while the resident world-list source is unknown.'

Assert-Match `
    -Text $source `
    -Pattern 'log_character_creation_world_lobby_probe\(\s*menu_name,\s*obj,\s*child0c,' `
    -Message 'World selection missing-row probe should include lobby/select chain diagnostics from live roots.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_direct_record_window_summary\s*\(' `
    -Message 'World selection should test child0C records for full unique native windows before considering them ordered rows.'

Assert-Match `
    -Text $source `
    -Pattern 'state character-creation world-record-window menu=' `
    -Message 'World selection should log whether DAT-validated child0C records form a full native row window.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.log_character_creation_world_select_detail_probe\s*\(' `
    -Message 'World selection should have focused select/lobby object details while the dynamic row source is unknown.'

Assert-Match `
    -Text $source `
    -Pattern 'state character-creation world-select-detail-hit menu=' `
    -Message 'World selection should log individual DAT-validated hits from select/lobby object roots without clipped summaries.'

Assert-Match `
    -Text $source `
    -Pattern 'log_character_creation_world_select_detail_probe\(\s*menu_name,\s*obj,\s*child0c,' `
    -Message 'World selection missing-row probe should include detailed select/lobby object diagnostics.'

Assert-Match `
    -Text $source `
    -Pattern 'log_character_creation_world_record_ref_probe\(\s*menu_name,\s*child0c,\s*entry,\s*desc0c,\s*record,' `
    -Message 'World selection should emit selected-row record-reference evidence from the missing-row probe.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_probe_raw_state\s*\(' `
    -Message 'World selection should log raw native state before accepting any guessed world order.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_record_window\s*\(' `
    -Message 'World selection should log the live record window around the selected row.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_compact_raw_state\s*\(' `
    -Message 'World selection should keep a compact raw-state line so clipped probes do not hide child fields.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_row_descriptor_base\s*\(' `
    -Message 'World selection should identify the row descriptor table base from the selected descriptor.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.log_character_creation_world_row_descriptor_probe\s*\(' `
    -Message 'World selection should be able to log per-row descriptor records while the native row source is unknown.'

Assert-Match `
    -Text $source `
    -Pattern 'state character-creation world-probe-raw menu=' `
    -Message 'World selection should emit a separate compact raw probe line.'

Assert-Match `
    -Text $source `
    -Pattern 'state character-creation world-rowdesc menu=' `
    -Message 'World selection should emit row descriptor probes separate from the summary line.'

Assert-Match `
    -Text $source `
    -Pattern 'state character-creation world-name-source menu=' `
    -Message 'World selection should emit a focused world-name source probe separate from the summary line.'

Assert-Match `
    -Text $source `
    -Pattern 'child0CD00="%s".*child0CD40="%s".*desc0CD00="%s".*rowWindow="%s"' `
    -Message 'World selection compact probe should expose child0C, descriptor, and row-window fields.'

Assert-Match `
    -Text $source `
    -Pattern 'worldRaw="%s".*recordWindow="%s"' `
    -Message 'World selection diagnostics should include raw child/descriptor bytes and the record window.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.character_creation_world_label_from_rows\s*\(rows,\s*selected,\s*expected_count\)' `
    -Message 'World selection should require enough DAT-backed row evidence before accepting a selected label.'

Assert-Match `
    -Text $source `
    -Pattern 'character_creation_world_rows_proof_count' `
    -Message 'World selection should count DAT-backed live rows before speaking a selected row.'

Assert-Match `
    -Text $worldEntryBody `
    -Pattern 'character_creation_world_packet_label\(selected,\s*count\)' `
    -Message 'World selection should try the native world-list packet cache before render-row fallbacks.'

Assert-Match `
    -Text $worldEntryBody `
    -Pattern 'character_creation_world_native_row_candidates\(obj,\s*state,\s*max_rows\)' `
    -Message 'World selection should scan live native row roots beyond the generic survival-guide child path.'

Assert-Match `
    -Text $source `
    -Pattern 'accessxi\.character_creation_world_menu_entry\(menu_name,\s*obj,\s*state\)' `
    -Message 'Character creation speech should try the dynamic world-row reader before static resources.'

Assert-NotMatch `
    -Text $nativeMenus `
    -Pattern "Asura|Bahamut|Fenrir|Quetzalcoatl|Ragnarok|Cerberus|Carbuncle|Bismarck|Lakshmi|Shiva" `
    -Message 'World selection must not add a hardcoded server-name resource list.'

$selectedStart = $source.IndexOf('function accessxi.character_creation_menu_selected')
if ($selectedStart -lt 0) {
    throw 'Missing character_creation_menu_selected helper.'
}
$selectedEnd = $source.IndexOf("`nfunction accessxi.character_creation_menu_entry", $selectedStart)
if ($selectedEnd -lt 0) {
    throw 'Could not locate end of character_creation_menu_selected helper.'
}
$selectedBody = $source.Substring($selectedStart, $selectedEnd - $selectedStart)

Assert-Match `
    -Text $selectedBody `
    -Pattern 'accessxi\.survival_guide_query_child_state_for_obj\(obj\)' `
    -Message 'Character creation should log child query state as evidence.'

Assert-Match `
    -Text $selectedBody `
    -Pattern 'reason\s*=\s*''unproven-row-signal''' `
    -Message 'Character creation must stay silent when no native row signal has been proven.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.character_creation_world_native_row_candidates\s*\(.*?accessxi\.survival_guide_native_row_candidates\(obj,\s*true" `
    -Message 'World selection should read visible native row candidates, not a fixed row table.'

$worldCursorStart = $source.IndexOf('function accessxi.character_creation_world_selected_from_state')
if ($worldCursorStart -lt 0) {
    throw 'Missing character_creation_world_selected_from_state helper.'
}
$worldCursorEnd = $source.IndexOf("`nfunction accessxi.character_creation_template_value", $worldCursorStart)
if ($worldCursorEnd -lt 0) {
    throw 'Could not locate end of character_creation_world_selected_from_state helper.'
}
$worldCursorBody = $source.Substring($worldCursorStart, $worldCursorEnd - $worldCursorStart)

Assert-Match `
    -Text $worldCursorBody `
    -Pattern "kind\s*~=\s*'world'" `
    -Message 'The world cursor proof should be scoped to the world-selection screen.'

Assert-Match `
    -Text $worldCursorBody `
    -Pattern 'expected_y\s*=\s*field4c\s*>\s*0\s+and\s+\(0x05\s*\+\s*\(\(field4c\s*-\s*1\)\s*\*\s*0x10\)\)' `
    -Message 'World selection should use the observed native row origin 0x05, not the earlier 0x06 character-creation picker origin.'

Assert-Match `
    -Text $worldCursorBody `
    -Pattern 'return\s+field4c,\s*''native-one-4c-record-y-world''' `
    -Message 'World selection should keep the one-based native row index for dynamic native row lookup.'

Assert-Match `
    -Text $selectedBody `
    -Pattern 'accessxi\.character_creation_race_selected_from_state\(kind,\s*state\)' `
    -Message 'Character creation selected helper should use the race-specific proven cursor helper.'

Assert-Match `
    -Text $selectedBody `
    -Pattern 'accessxi\.character_creation_face_selected_from_state\(kind,\s*state\)' `
    -Message 'Character creation selected helper should use the face-specific proven cursor helper.'

Assert-Match `
    -Text $selectedBody `
    -Pattern 'accessxi\.character_creation_hair_selected_from_state\(kind,\s*state\)' `
    -Message 'Character creation selected helper should use the hair-specific proven cursor helper.'

Assert-Match `
    -Text $selectedBody `
    -Pattern 'accessxi\.character_creation_size_selected_from_state\(kind,\s*state\)' `
    -Message 'Character creation selected helper should use the size-specific proven cursor helper.'

Assert-Match `
    -Text $selectedBody `
    -Pattern 'accessxi\.character_creation_job_selected_from_state\(kind,\s*state\)' `
    -Message 'Character creation selected helper should use the initial-job-specific proven cursor helper.'

Assert-Match `
    -Text $selectedBody `
    -Pattern 'accessxi\.character_creation_nation_selected_from_state\(kind,\s*state\)' `
    -Message 'Character creation selected helper should use the starting-country-specific proven cursor helper.'

Assert-NotMatch `
    -Text $selectedBody `
    -Pattern 'selected\s*=\s*read_current_native_menu_index\(0x4C\)' `
    -Message 'Character creation must not assume obj+0x4C is the cursor before live evidence proves it.'

$raceCursorStart = $source.IndexOf('function accessxi.character_creation_race_selected_from_state')
if ($raceCursorStart -lt 0) {
    throw 'Missing character_creation_race_selected_from_state helper.'
}
$raceCursorEnd = $source.IndexOf("`nfunction accessxi.character_creation_menu_entry", $raceCursorStart)
if ($raceCursorEnd -lt 0) {
    throw 'Could not locate end of character_creation_race_selected_from_state helper.'
}
$raceCursorBody = $source.Substring($raceCursorStart, $raceCursorEnd - $raceCursorStart)

Assert-Match `
    -Text $raceCursorBody `
    -Pattern "kind\s*~=\s*'race'" `
    -Message 'The proven 4C cursor should be scoped to the race picker only.'

Assert-Match `
    -Text $raceCursorBody `
    -Pattern 'state\.field4c' `
    -Message 'Race cursor proof should use the live obj+0x4C field captured by the probe.'

Assert-Match `
    -Text $raceCursorBody `
    -Pattern 'field4c\s*<\s*1\s+or\s+field4c\s*>\s*8' `
    -Message 'Race cursor proof should require the observed one-based 1..8 range.'

Assert-Match `
    -Text $raceCursorBody `
    -Pattern 'expected_y\s*=\s*0x06\s*\+\s*\(\(field4c\s*-\s*1\)\s*\*\s*0x10\)' `
    -Message 'Race cursor proof should corroborate 4C with the selected descriptor y-position.'

Assert-Match `
    -Text $raceCursorBody `
    -Pattern 'record_y\s*==\s*expected_y' `
    -Message 'Race cursor proof should only accept 4C when descriptor y-position agrees.'

Assert-Match `
    -Text $raceCursorBody `
    -Pattern 'return\s+field4c\s*-\s*1,\s*''native-one-4c-record-y''' `
    -Message 'Race cursor proof should convert native one-based 4C to zero-based DAT row index.'

$faceCursorStart = $source.IndexOf('function accessxi.character_creation_face_selected_from_state')
if ($faceCursorStart -lt 0) {
    throw 'Missing character_creation_face_selected_from_state helper.'
}
$faceCursorEnd = $source.IndexOf("`nfunction accessxi.character_creation_format_template_label", $faceCursorStart)
if ($faceCursorEnd -lt 0) {
    throw 'Could not locate end of character_creation_face_selected_from_state helper.'
}
$faceCursorBody = $source.Substring($faceCursorStart, $faceCursorEnd - $faceCursorStart)

Assert-Match `
    -Text $faceCursorBody `
    -Pattern "kind\s*~=\s*'face'" `
    -Message 'The proven 4C cursor should be scoped to the face picker.'

Assert-Match `
    -Text $faceCursorBody `
    -Pattern 'field4c\s*<\s*1\s+or\s+field4c\s*>\s*8' `
    -Message 'Face cursor proof should require the observed one-based 1..8 range.'

Assert-Match `
    -Text $faceCursorBody `
    -Pattern 'expected_y\s*=\s*0x06\s*\+\s*\(\(field4c\s*-\s*1\)\s*\*\s*0x10\)' `
    -Message 'Face cursor proof should corroborate 4C with the selected descriptor y-position.'

Assert-Match `
    -Text $faceCursorBody `
    -Pattern 'return\s+field4c\s*-\s*1,\s*''native-one-4c-record-y-face''' `
    -Message 'Face cursor proof should convert native one-based 4C to zero-based template value.'

$hairCursorStart = $source.IndexOf('function accessxi.character_creation_hair_selected_from_state')
if ($hairCursorStart -lt 0) {
    throw 'Missing character_creation_hair_selected_from_state helper.'
}
$hairCursorEnd = $source.IndexOf("`nfunction accessxi.character_creation_format_template_label", $hairCursorStart)
if ($hairCursorEnd -lt 0) {
    throw 'Could not locate end of character_creation_hair_selected_from_state helper.'
}
$hairCursorBody = $source.Substring($hairCursorStart, $hairCursorEnd - $hairCursorStart)

Assert-Match `
    -Text $hairCursorBody `
    -Pattern "kind\s*~=\s*'hair'" `
    -Message 'The proven 4C cursor should be scoped to the hair picker.'

Assert-Match `
    -Text $hairCursorBody `
    -Pattern 'field4c\s*<\s*1\s+or\s+field4c\s*>\s*2' `
    -Message 'Hair cursor proof should require the observed one-based 1..2 range.'

Assert-Match `
    -Text $hairCursorBody `
    -Pattern 'expected_y\s*=\s*0x06\s*\+\s*\(\(field4c\s*-\s*1\)\s*\*\s*0x10\)' `
    -Message 'Hair cursor proof should corroborate 4C with the selected descriptor y-position.'

Assert-Match `
    -Text $hairCursorBody `
    -Pattern 'return\s+field4c\s*-\s*1,\s*''native-one-4c-record-y-hair''' `
    -Message 'Hair cursor proof should convert native one-based 4C to zero-based DAT value row.'

$sizeCursorStart = $source.IndexOf('function accessxi.character_creation_size_selected_from_state')
if ($sizeCursorStart -lt 0) {
    throw 'Missing character_creation_size_selected_from_state helper.'
}
$sizeCursorEnd = $source.IndexOf("`nfunction accessxi.character_creation_format_template_label", $sizeCursorStart)
if ($sizeCursorEnd -lt 0) {
    throw 'Could not locate end of character_creation_size_selected_from_state helper.'
}
$sizeCursorBody = $source.Substring($sizeCursorStart, $sizeCursorEnd - $sizeCursorStart)

Assert-Match `
    -Text $sizeCursorBody `
    -Pattern "kind\s*~=\s*'size'" `
    -Message 'The proven 4C cursor should be scoped to the size picker.'

Assert-Match `
    -Text $sizeCursorBody `
    -Pattern 'field4c\s*<\s*1\s+or\s+field4c\s*>\s*3' `
    -Message 'Size cursor proof should require the observed one-based 1..3 range.'

Assert-Match `
    -Text $sizeCursorBody `
    -Pattern 'expected_y\s*=\s*0x06\s*\+\s*\(\(field4c\s*-\s*1\)\s*\*\s*0x10\)' `
    -Message 'Size cursor proof should corroborate 4C with the selected descriptor y-position.'

Assert-Match `
    -Text $sizeCursorBody `
    -Pattern 'return\s+field4c\s*-\s*1,\s*''native-one-4c-record-y-size''' `
    -Message 'Size cursor proof should convert native one-based 4C to zero-based DAT value row.'

$jobCursorStart = $source.IndexOf('function accessxi.character_creation_job_selected_from_state')
if ($jobCursorStart -lt 0) {
    throw 'Missing character_creation_job_selected_from_state helper.'
}
$jobCursorEnd = $source.IndexOf("`nfunction accessxi.character_creation_format_template_label", $jobCursorStart)
if ($jobCursorEnd -lt 0) {
    throw 'Could not locate end of character_creation_job_selected_from_state helper.'
}
$jobCursorBody = $source.Substring($jobCursorStart, $jobCursorEnd - $jobCursorStart)

Assert-Match `
    -Text $jobCursorBody `
    -Pattern "kind\s*~=\s*'job'" `
    -Message 'The proven 4C cursor should be scoped to the initial job picker.'

Assert-Match `
    -Text $jobCursorBody `
    -Pattern 'field4c\s*<\s*1\s+or\s+field4c\s*>\s*6' `
    -Message 'Initial job cursor proof should require the observed one-based 1..6 range.'

Assert-Match `
    -Text $jobCursorBody `
    -Pattern 'expected_y\s*=\s*0x06\s*\+\s*\(\(field4c\s*-\s*1\)\s*\*\s*0x10\)' `
    -Message 'Initial job cursor proof should corroborate 4C with the selected descriptor y-position.'

Assert-Match `
    -Text $jobCursorBody `
    -Pattern 'return\s+field4c\s*-\s*1,\s*''native-one-4c-record-y-job''' `
    -Message 'Initial job cursor proof should convert native one-based 4C to zero-based DAT row index.'

$nationCursorStart = $source.IndexOf('function accessxi.character_creation_nation_selected_from_state')
if ($nationCursorStart -lt 0) {
    throw 'Missing character_creation_nation_selected_from_state helper.'
}
$nationCursorEnd = $source.IndexOf("`nfunction accessxi.character_creation_world_selected_from_state", $nationCursorStart)
if ($nationCursorEnd -lt 0) {
    throw 'Could not locate end of character_creation_nation_selected_from_state helper.'
}
$nationCursorBody = $source.Substring($nationCursorStart, $nationCursorEnd - $nationCursorStart)

Assert-Match `
    -Text $nationCursorBody `
    -Pattern "kind\s*~=\s*'nation'" `
    -Message 'The proven 4C cursor should be scoped to the starting-country picker.'

Assert-Match `
    -Text $nationCursorBody `
    -Pattern 'field4c\s*<\s*1\s+or\s+field4c\s*>\s*3' `
    -Message 'Starting-country cursor proof should require the observed one-based 1..3 selectable range.'

Assert-Match `
    -Text $nationCursorBody `
    -Pattern 'expected_y\s*=\s*0x06\s*\+\s*\(\(field4c\s*-\s*1\)\s*\*\s*0x10\)' `
    -Message 'Starting-country cursor proof should corroborate 4C with the selected descriptor y-position.'

Assert-Match `
    -Text $nationCursorBody `
    -Pattern 'return\s+field4c,\s*''native-one-4c-record-y-nation''' `
    -Message 'Starting-country cursor proof should keep the native one-based index for the one-based DAT resource rows.'

$entryStart = $source.IndexOf('function accessxi.character_creation_menu_entry')
if ($entryStart -lt 0) {
    throw 'Missing character_creation_menu_entry helper.'
}
$entryEnd = $source.IndexOf("`nfunction accessxi.log_character_creation_menu_probe", $entryStart)
if ($entryEnd -lt 0) {
    throw 'Could not locate end of character_creation_menu_entry helper.'
}
$entryBody = $source.Substring($entryStart, $entryEnd - $entryStart)

Assert-Match `
    -Text $entryBody `
    -Pattern 'label_template_row' `
    -Message 'Character creation menu entry should support DAT-backed label templates.'

Assert-Match `
    -Text $entryBody `
    -Pattern 'accessxi\.dat_index_row_text\(dat_path,\s*label_template_row,\s*''label''\)' `
    -Message 'Character creation menu entry should load label templates through dat_index_row_text.'

Assert-Match `
    -Text $entryBody `
    -Pattern 'accessxi\.character_creation_format_template_label' `
    -Message 'Character creation menu entry should format DAT templates through a dedicated helper.'

Assert-Match `
    -Text $entryBody `
    -Pattern 'value_dat' `
    -Message 'Character creation menu entry should support DAT-backed template replacement values.'

$formatStart = $source.IndexOf('function accessxi.character_creation_format_template_label')
if ($formatStart -lt 0) {
    throw 'Missing character_creation_format_template_label helper.'
}
$formatEnd = $source.IndexOf("`nfunction accessxi.character_creation_menu_entry", $formatStart)
if ($formatEnd -lt 0) {
    throw 'Could not locate end of character_creation_format_template_label helper.'
}
$formatBody = $source.Substring($formatStart, $formatEnd - $formatStart)

Assert-NotMatch `
    -Text $formatBody `
    -Pattern 'value\s*=\s*tostring\(tonumber\(value\)' `
    -Message 'Character creation template formatting must accept DAT text values like A/B, not only numbers.'

Assert-NotMatch `
    -Text $formatBody `
    -Pattern 'value\s*=\s*accessxi\.plain_native_menu_label' `
    -Message 'Character creation template values must not use full label filtering because valid values can be one character.'

Assert-Match `
    -Text $formatBody `
    -Pattern 'accessxi\.character_creation_template_value\(value\)' `
    -Message 'Character creation template formatting should use the short-value cleaner for replacements.'

Assert-Match `
    -Text $entryBody `
    -Pattern 'accessxi\.character_creation_dat_value_text\(value_dat,\s*value_row\)' `
    -Message 'Character creation should read DAT-backed A/B template values with the short-value cleaner.'

Assert-Match `
    -Text $source `
    -Pattern 'state character-creation probe menu="%s"' `
    -Message 'Character creation probe should emit stable menu-tagged evidence lines.'

Assert-Match `
    -Text $source `
    -Pattern 'state character-creation quiet menu="%s" kind="%s" reason="%s"' `
    -Message 'Character creation should log why it is silent instead of inventing labels.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)accessxi\.is_character_creation_menu_name\(name\).*?accessxi\.character_creation_menu_speech\(name,\s*obj\)" `
    -Message 'Character creation menus should dispatch before the generic unknown-menu probe.'

$ptcStart = $source.IndexOf("if (name:eq('menu    ptc6yesn', true))")
if ($ptcStart -lt 0) {
    throw 'Missing final character confirmation menu dispatch.'
}
$ptcEnd = $source.IndexOf("`n    local equipment_storage_options_text", $ptcStart)
if ($ptcEnd -lt 0) {
    throw 'Could not locate end of final character confirmation dispatch.'
}
$ptcBody = $source.Substring($ptcStart, $ptcEnd - $ptcStart)

Assert-Match `
    -Text $ptcBody `
    -Pattern 'accessxi\.character_creation_confirmation_speech\(name,\s*obj\)' `
    -Message 'menu    ptc6yesn should dispatch through the DAT-backed character registration confirmation reader.'

Assert-NotMatch `
    -Text $ptcBody `
    -Pattern 'Confirm character' `
    -Message 'menu    ptc6yesn should not use the old generic Confirm character prompt.'

$speechStart = $source.IndexOf('function accessxi.character_creation_menu_speech')
if ($speechStart -lt 0) {
    throw 'Missing character_creation_menu_speech helper.'
}
$speechEnd = $source.IndexOf("`nfunction accessxi.title_lobby_menu_entry", $speechStart)
if ($speechEnd -lt 0) {
    throw 'Could not locate end of character_creation_menu_speech helper.'
}
$speechBody = $source.Substring($speechStart, $speechEnd - $speechStart)

Assert-Match `
    -Text $speechBody `
    -Pattern "(?s)kind\s*==\s*'nation'.*?character_creation_nation_menu_entry\(selected\)" `
    -Message 'Starting-country speech should dispatch through the nation title/body DAT reader before generic row labels.'

Assert-Match `
    -Text $speechBody `
    -Pattern 'state character-creation nation-native menu=' `
    -Message 'Starting-country speech should log a dedicated native evidence line.'

Write-Host 'character creation menu native/resource static checks ok'
