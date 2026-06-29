param(
    [string]$Win32TypesPath = 'C:\Users\buu42\Ashita\addons\libs\win32types.lua'
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

Assert-True (Test-Path -LiteralPath $Win32TypesPath) "Missing Ashita win32types.lua: $Win32TypesPath"
$source = Get-Content -LiteralPath $Win32TypesPath -Raw

Assert-True ($source -notmatch 'typedef\s+const\s+IID\s*&\s*REFIID') 'win32types.lua must not use C++ reference typedefs inside LuaJIT ffi.cdef.'
Assert-True ($source -notmatch 'typedef\s+const\s+GUID\s*&\s*REFGUID') 'win32types.lua must not use C++ reference typedefs inside LuaJIT ffi.cdef.'
Assert-True ($source -match 'typedef\s+const\s+IID\s*\*\s*REFIID') 'win32types.lua must expose REFIID as a C pointer typedef for LuaJIT ffi.cdef.'
Assert-True ($source -match 'typedef\s+const\s+GUID\s*\*\s*REFGUID') 'win32types.lua must expose REFGUID as a C pointer typedef for LuaJIT ffi.cdef.'

'ok: Ashita win32types ffi definitions are C-compatible.'
