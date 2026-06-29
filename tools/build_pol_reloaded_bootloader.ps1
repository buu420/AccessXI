param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI'
)

$ErrorActionPreference = 'Stop'

$vcVars32 = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars32.bat'
$source = Join-Path $RepoRoot 'tools\pol_asi_probe\pol_asi_probe.cpp'
$output = Join-Path $RepoRoot 'tools\pol_asi_probe\AccessXI.PolReloadedBootstrap.asi'

if (-not (Test-Path -LiteralPath $vcVars32)) {
    throw "Visual Studio x86 vcvars32.bat is missing: $vcVars32"
}
if (-not (Test-Path -LiteralPath $source)) {
    throw "AccessXI POL Reloaded bootloader source is missing: $source"
}

& cmd.exe /c "`"$vcVars32`" >nul && cl /nologo /LD /MT /O2 `"$source`" /Fe:`"$output`" /link /NOLOGO"
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Get-FileHash -LiteralPath $output -Algorithm SHA256
