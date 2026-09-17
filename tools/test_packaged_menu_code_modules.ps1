param([string]$RepoRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$source = [IO.File]::ReadAllText((Join-Path $RepoRoot 'tools\package_accessxi_installer.ps1'))
$start = $source.IndexOf('function Assert-PackagedModuleReferences {')
$end = $source.IndexOf('$moduleReferenceCount = Assert-PackagedModuleReferences', $start)
if ($start -lt 0 -or $end -lt 0) { throw 'Cannot locate production module gate' }
. ([scriptblock]::Create($source.Substring($start, $end - $start)))

$fixture = Join-Path $RepoRoot ('logs\package-menu-gate-' + [guid]::NewGuid().ToString('N'))
foreach ($directory in @('modules\menus', 'data', 'third_party\FFXI-NavMesh-Builder', 'third_party\xiNavmeshes')) {
    New-Item -ItemType Directory -Path (Join-Path $fixture $directory) -Force | Out-Null
}
[IO.File]::WriteAllText((Join-Path $fixture 'accessxi_reader.lua'), "accessxi.load_menu_code_module('treasure_pool', {})")
$failure = ''
try { Assert-PackagedModuleReferences -PayloadAddonRoot $fixture | Out-Null } catch { $failure = $_.Exception.Message }
if (-not $failure.Contains('modules\menus\treasure_pool.lua')) {
    throw "The release gate must identify the missing menu code module; actual failure: $failure"
}
foreach ($file in @('modules\menus\treasure_pool.lua', 'data\ffxi-objective-step-targets.tsv',
    'data\ffxi-nav-destination-ingress.tsv', 'third_party\FFXI-NavMesh-Builder\FFXINAV.dll',
    'third_party\xiNavmeshes\fixture.nav')) {
    [IO.File]::WriteAllText((Join-Path $fixture $file), 'fixture')
}
if ((Assert-PackagedModuleReferences -PayloadAddonRoot $fixture) -ne 1) {
    throw 'Expected the present menu code module to be counted and accepted'
}
'ok: production package gate rejects missing menu code modules and accepts present modules.'
