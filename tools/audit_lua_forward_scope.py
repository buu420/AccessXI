"""Any name that is declared as a local in a file but READ AS A GLOBAL in that
same file's bytecode is a Lua 5.1 forward-scope bug: the reader sits above the
declaration, so it compiles to a global read and is nil at runtime.

This is the trap that made nav_objective_travel_destination_zones reach a nil
progression_revision, and that made declared_result_names and
nav_mission_quest_first_objective call a nil progression_actions.
"""
import io, os, re, subprocess, sys, glob

LUAJIT = r"C:\Users\buu42\AppData\Local\Programs\LuaJIT\bin\luajit.exe"
ADDON = os.environ.get('ACCESSXI_ADDON', r"C:\Users\buu42\Ashita\addons\accessxi_reader")

# Globals the addon legitimately reads (Ashita/Lua environment + addon table).
ALLOWED = {
    'accessxi', 'T', 'string', 'table', 'math', 'os', 'io', 'ipairs', 'pairs',
    'type', 'tostring', 'tonumber', 'pcall', 'select', 'next', 'error', 'assert',
    'setmetatable', 'getmetatable', 'rawget', 'rawset', 'require', 'unpack',
    'print', 'AshitaCore', 'addon', 'ashita', 'bit', 'ffi', 'jit', 'debug',
    'coroutine', 'log_line', 'arg', 'dofile', 'loadfile', 'load', 'loadstring',
    'collectgarbage', 'WALKTHROUGH_EMBED', 'gdi', 'imgui', 'd3d8',
}

# --modules restricts the audit to the mission/objective/navigation modules.
# accessxi_reader.lua carries two known instances of this bug in unrelated
# subsystems (clean_login_text, nav_zone_id); they are tracked separately and
# would otherwise hold this gate red for something it is not watching.
modules_only = '--modules' in sys.argv
targets = [] if modules_only else [os.path.join(ADDON, 'accessxi_reader.lua')]
targets += sorted(glob.glob(os.path.join(ADDON, 'modules', '*.lua')))

problems = 0
for path in targets:
    text = io.open(path, encoding='utf-8', errors='replace').read()
    locals_declared = set()
    for m in re.finditer(r'^\s*local\s+function\s+([A-Za-z_][A-Za-z0-9_]*)', text, re.M):
        locals_declared.add(m.group(1))
    for m in re.finditer(r'^\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*[=;]', text, re.M):
        locals_declared.add(m.group(1))
    if not locals_declared:
        continue

    try:
        done = subprocess.run([LUAJIT, '-bl', path], capture_output=True,
                              timeout=600)
        out = done.stdout.decode('utf-8', 'replace')
        if done.returncode != 0 or not out.strip():
            why = done.stderr.decode('utf-8', 'replace').strip().splitlines()
            print('%-46s DOES NOT COMPILE: %s' % (
                os.path.basename(path), why[-1] if why else 'no bytecode produced'))
            problems += 1
            continue
    except Exception as exc:
        print('%-46s COULD NOT BE AUDITED: %s' % (os.path.basename(path), exc))
        problems += 1
        continue

    read_as_global = set()
    for m in re.finditer(r'GGET\s+\d+\s+\d+\s+;\s+"([^"]+)"', out):
        read_as_global.add(m.group(1))

    clash = sorted((read_as_global & locals_declared) - ALLOWED)
    if clash:
        problems += len(clash)
        print('%-46s %s' % (os.path.basename(path), ', '.join(clash)))

print('')
print('files audited: %d' % len(targets))
print('forward-scope clashes (and uncompilable files): %d' % problems)
if problems == 0:
    print('OK: no local is read as a global above its own declaration')
sys.exit(1 if problems else 0)
