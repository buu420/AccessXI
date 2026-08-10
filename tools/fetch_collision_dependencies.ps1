[CmdletBinding()]
param(
    [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'

$dependencies = @(
    [pscustomobject]@{
        Name = 'recastnavigation'
        Url = 'https://github.com/recastnavigation/recastnavigation.git'
        Commit = '9f4ce64458dfae86e1239c525ddc219c4e9e06f1'
    },
    [pscustomobject]@{
        Name = 'bullet3'
        Url = 'https://github.com/bulletphysics/bullet3.git'
        Commit = '63c4d67e337017f9d8b298c900e9aabdb69296e7'
    }
)

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$Failure
    )

    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Failure (git exit $LASTEXITCODE)"
    }
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$repo = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $repo 'CMakeLists.txt') -PathType Leaf)) {
    throw "AccessXI repository root is invalid: $repo"
}

$externalRoot = Join-Path $repo 'external'
New-Item -ItemType Directory -Force -Path $externalRoot | Out-Null
$externalCanonical = [System.IO.Path]::GetFullPath($externalRoot).TrimEnd('\')
if (-not $externalCanonical.StartsWith($repo + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "External dependency directory escapes the repository: $externalCanonical"
}

foreach ($dependency in $dependencies) {
    $destination = Join-Path $externalCanonical $dependency.Name
    $destinationCanonical = [System.IO.Path]::GetFullPath($destination).TrimEnd('\')
    $created = $false
    if (-not $destinationCanonical.StartsWith($externalCanonical + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Dependency path escapes the external directory: $destinationCanonical"
    }

    if (-not (Test-Path -LiteralPath $destinationCanonical -PathType Container)) {
        Invoke-Git -Arguments @(
            'clone',
            '--filter=blob:none',
            '--no-checkout',
            $dependency.Url,
            $destinationCanonical
        ) -Failure "Could not clone $($dependency.Name)"
        $created = $true
    }

    if (-not (Test-Path -LiteralPath (Join-Path $destinationCanonical '.git'))) {
        throw "Dependency is not a Git checkout: $destinationCanonical"
    }

    if (-not $created) {
        $checkoutEntries = @(Get-ChildItem -LiteralPath $destinationCanonical -Force |
            Where-Object { $_.Name -ne '.git' })
        $created = $checkoutEntries.Count -eq 0
    }

    if (-not $created) {
        $dirty = @(& git -C $destinationCanonical status --porcelain)
        if ($LASTEXITCODE -ne 0) {
            throw "Could not inspect $($dependency.Name)"
        }
        if ($dirty.Count -ne 0) {
            throw "Dependency checkout is dirty and will not be replaced: $destinationCanonical"
        }
    }

    Invoke-Git -Arguments @(
        '-C', $destinationCanonical,
        'fetch', '--depth', '1', 'origin', $dependency.Commit
    ) -Failure "Could not fetch pinned $($dependency.Name) commit"
    Invoke-Git -Arguments @(
        '-C', $destinationCanonical,
        'checkout', '--detach', $dependency.Commit
    ) -Failure "Could not check out pinned $($dependency.Name) commit"

    $actual = (& git -C $destinationCanonical rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -ne $dependency.Commit) {
        throw "Pinned $($dependency.Name) revision mismatch. Expected $($dependency.Commit), got $actual"
    }

    Write-Output ("{0}`t{1}`t{2}" -f $dependency.Name, $actual, $destinationCanonical)
}
