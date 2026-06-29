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

Assert-True (Test-Path -LiteralPath $AddonPath) "Missing AccessXI reader addon: $AddonPath"
$source = Get-Content -LiteralPath $AddonPath -Raw

$firstMetadata = [regex]::Match($source, '(?m)^addon\.name\s*=')
Assert-True $firstMetadata.Success 'Could not locate AccessXI addon metadata assignment.'

$prefix = $source.Substring(0, $firstMetadata.Index)
Assert-True ($prefix -match "rawget\(_G,\s*'addon'\)") 'AccessXI must tolerate Ashita exposing addon metadata as _G.addon.'
Assert-True ($prefix -match "rawget\(_G,\s*'_addon'\)") 'AccessXI must tolerate Ashita exposing addon metadata as _G._addon.'
Assert-True ($prefix -match "_G\.addon\s*=\s*addon") 'AccessXI must publish the resolved metadata table back to _G.addon for legacy code paths.'
Assert-True ($prefix -match "_G\._addon\s*=\s*addon") 'AccessXI must publish the resolved metadata table back to _G._addon for Ashita v4 metadata paths.'
Assert-True ($prefix -match "accessxi_boot_trace\('top-start'\)") 'AccessXI must log an early boot trace before risky top-level startup work.'
Assert-True ($source -match "(local\s+)?accessxi_win32types_ok,\s*accessxi_win32types_err\s*=\s*pcall\(require,\s*'win32types'\)") 'AccessXI must not abort addon load when Ashita win32types.lua fails to load.'
Assert-True ($source -match "win32types-failed") 'AccessXI must boot-trace win32types require failures so the next launch leaves evidence.'

'ok: AccessXI addon metadata compatibility is guarded.'
