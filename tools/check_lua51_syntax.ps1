param(
    [string] $Path = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua',
    [string] $LuaDll = 'C:\Users\buu42\ErionMUSHclient\MUSHclient\lua51.dll'
)

if ([Environment]::Is64BitProcess) {
    $wowPowerShell = "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe";
    if (Test-Path -LiteralPath $wowPowerShell) {
        & $wowPowerShell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Path $Path -LuaDll $LuaDll;
        exit $LASTEXITCODE;
    }
}

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Error "Lua file not found: $Path";
    exit 2;
}

if (-not (Test-Path -LiteralPath $LuaDll)) {
    Write-Error "Lua 5.1 DLL not found: $LuaDll";
    exit 2;
}

$escapedLuaDll = $LuaDll.Replace('\', '\\').Replace('"', '\"');
$code = @"
using System;
using System.Runtime.InteropServices;

public static class Lua51SyntaxCheck {
    [DllImport(@"$escapedLuaDll", CallingConvention=CallingConvention.Cdecl)]
    public static extern IntPtr luaL_newstate();

    [DllImport(@"$escapedLuaDll", CallingConvention=CallingConvention.Cdecl)]
    public static extern int luaL_loadfile(IntPtr L, string filename);

    [DllImport(@"$escapedLuaDll", CallingConvention=CallingConvention.Cdecl)]
    public static extern IntPtr lua_tolstring(IntPtr L, int idx, IntPtr len);

    [DllImport(@"$escapedLuaDll", CallingConvention=CallingConvention.Cdecl)]
    public static extern void lua_close(IntPtr L);
}
"@;

Add-Type -TypeDefinition $code;

$state = [Lua51SyntaxCheck]::luaL_newstate();
if ($state -eq [IntPtr]::Zero) {
    Write-Error 'luaL_newstate failed.';
    exit 2;
}

try {
    $result = [Lua51SyntaxCheck]::luaL_loadfile($state, $Path);
    if ($result -eq 0) {
        Write-Output "syntax ok: $Path";
        exit 0;
    }

    $messagePtr = [Lua51SyntaxCheck]::lua_tolstring($state, -1, [IntPtr]::Zero);
    $message = [Runtime.InteropServices.Marshal]::PtrToStringAnsi($messagePtr);
    Write-Error "syntax error rc=$result $message";
    exit 1;
}
finally {
    [Lua51SyntaxCheck]::lua_close($state);
}
