$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$source = Get-Content -LiteralPath $addonPath -Raw

function Assert-AddonPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($source -notmatch $Pattern) {
        throw "Missing combat feedback contract: $Name"
    }
}

function Assert-AddonNotPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($source -match $Pattern) {
        throw "Forbidden combat feedback contract: $Name"
    }
}

Assert-AddonPattern 'function\s+accessxi\.combat_is_combat_mode' 'combat mode gate helper'
Assert-AddonPattern 'mid\s*==\s*121\s+or\s+mid\s*==\s*122\s+or\s+mid\s*==\s*123' 'combat feedback only handles native combat chat modes'
Assert-AddonPattern 'function\s+accessxi\.combat_player_name' 'player name comes from party memory'
Assert-AddonPattern '(?s)GetParty\(\).*?GetMemberName\(0\)' 'player name uses native party state'
Assert-AddonPattern 'function\s+accessxi\.combat_player_hp_summary' 'player HP summary helper'
Assert-AddonPattern 'GetMemberHP\(0\)' 'player current HP uses native party state'
Assert-AddonPattern '(?s)GetPlayer\(\).*?GetHPMax\(\)' 'player max HP uses native player state'
Assert-AddonPattern 'function\s+accessxi\.combat_target_name' 'target name helper'
Assert-AddonPattern '(?s)GetTarget\(\).*?GetWindowName\(\)' 'target name uses native target state'
Assert-AddonPattern 'function\s+accessxi\.combat_target_hp_summary' 'monster target HP summary helper'
Assert-AddonPattern 'GetWindowHPPercent\(\)' 'target HP percent uses native target state'
Assert-AddonPattern 'function\s+accessxi\.combat_damage_speech' 'combat damage speech formatter'
Assert-AddonPattern 'points of damage' 'combat damage speech parses plural native damage wording'
Assert-AddonPattern 'point of damage' 'combat damage speech parses singular native damage wording'
Assert-AddonPattern 'You deal %d+ damage' 'outgoing damage is summarized'
Assert-AddonPattern 'You take %d+ damage' 'incoming damage is summarized'
Assert-AddonPattern 'targetHp="%s"' 'combat feedback log includes target HP evidence'
Assert-AddonPattern 'playerHp="%s"' 'combat feedback log includes player HP evidence'
Assert-AddonPattern '(?s)accessxi\.handle_chat_text\s*=\s*function.*?accessxi\.combat_damage_speech\(entry\).*?accessxi\.chat_entry_speech\(entry\)' 'chat handler prefers combat feedback then falls back to normal chat speech'
Assert-AddonPattern 'function\s+accessxi\.combat_player_server_id' 'player server id helper for native action packets'
Assert-AddonPattern '(?s)GetPlayerEntity\(\).*?ServerId' 'player server id uses native entity state'
Assert-AddonPattern 'function\s+accessxi\.combat_action_parse' '0x028 action packet parser'
Assert-AddonPattern 'bitpos\s*=\s*8\s*\*\s*5' 'action parser skips packet header and work size'
Assert-AddonPattern 'packet_bits_le\(data,\s*bitpos,\s*width\)' 'action parser uses Ashita/Windower little-endian packed bit order'
Assert-AddonPattern 'action\.m_uID\s*=\s*read_bits\(32\)' 'action parser reads actor id through the little-endian bit reader'
Assert-AddonNotPattern 'packet_bits_be\(data,\s*bitpos' 'action parser must not use big-endian packet bits for 0x028 fields'
Assert-AddonPattern 'function\s+accessxi\.combat_action_result_is_damage' 'action result damage gate'
Assert-AddonPattern 'message\s*==\s*1\s+or\s+message\s*==\s*67' 'action packet speech only accepts basic hit and critical hit damage messages'
Assert-AddonPattern 'action\.cmd_no\s*~=\s*1' 'action packet speech is gated to basic attacks'
Assert-AddonPattern 'function\s+accessxi\.combat_action_packet_speech' 'action packet speech formatter'
Assert-AddonPattern 'function\s+accessxi\.queue_combat_action_feedback' 'action feedback queues a deferred HP read'
Assert-AddonPattern 'ready_tick\s*=\s*tick\(\)\s*\+\s*80' 'action feedback defers damage speech until after packet processing'
Assert-AddonPattern 'hp_ready_tick\s*=\s*tick\(\)\s*\+\s*650' 'target HP speech is delayed until the target window has updated'
Assert-AddonPattern 'target_percent_before' 'target HP feedback records the pre-hit percent to avoid stale repeat speech'
Assert-AddonPattern 'function\s+accessxi\.speak_combat_action_target_hp_feedback' 'target HP feedback is spoken separately after outgoing damage'
Assert-AddonPattern 'state combat action target hp feedback' 'target HP feedback logs its native delayed sample'
Assert-AddonPattern 'target hp skipped reason="unchanged"' 'unchanged target HP after damage is skipped instead of announcing stale health'
Assert-AddonPattern 'function\s+accessxi\.poll_combat_action_feedback' 'deferred action feedback poller'
Assert-AddonPattern 'poll_combat_action_feedback\(\)' 'present callback polls deferred action feedback'
Assert-AddonPattern 'function\s+accessxi\.capture_combat_action_packet' 'packet_in combat action handler'
Assert-AddonPattern 'tonumber\(e\.id\)\s*~=\s*0x028' 'combat action handler only processes 0x028 action packets'
Assert-AddonPattern 'e\.data_modified\s+or\s+e\.data\s+or\s+accessxi\.packet_event_string\(e,\s*''data_modified''' 'combat action handler uses modified/raw packet data fallback'
Assert-AddonPattern 'function\s+accessxi\.log_combat_action_diag' 'combat action handler has capped native packet diagnostic'
Assert-AddonPattern 'state combat action diag' 'combat action diagnostic logs native packet fields'
Assert-AddonPattern 'combat_action_diag_count\s*>=\s*32' 'combat action diagnostic is capped to avoid combat lag'
Assert-AddonPattern 'packet_hex_limit\(data,\s*48\)' 'combat action diagnostic includes limited packet hex evidence'
Assert-AddonPattern 'capture_combat_action_packet\(e\)' 'packet_in callback invokes combat action capture'
Assert-AddonPattern 'state combat action feedback' 'packet action feedback logs native evidence'

$combatStart = $source.IndexOf('function accessxi.combat_is_combat_mode')
if ($combatStart -lt 0) {
    throw 'Missing combat feedback function block'
}
$combatEnd = $source.IndexOf("accessxi.handle_chat_text = function", $combatStart)
if ($combatEnd -lt 0) {
    throw 'Missing handle_chat_text after combat feedback functions'
}
$combatBody = $source.Substring($combatStart, $combatEnd - $combatStart)

if ($combatBody -match 'GetAsyncKeyState|ocr|OCR') {
    throw 'Combat feedback must not use key monitoring or OCR'
}

Assert-AddonNotPattern 'combat_damage_speech\(entry\)\s*or\s*''''\s*;' 'combat feedback must fall back to normal speech, not silence all unmatched combat lines'

Write-Host 'combat feedback static checks ok'
