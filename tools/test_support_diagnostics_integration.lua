-- Load the actual reader hooks and command handler; only hardware speech and
-- the addon path are fixtures. The report is written through the real writer.
local root = assert(arg[1], 'pass the addon root');
local f = assert(io.open(root .. '/accessxi_reader.lua', 'rb'));
local source = f:read('*a'); f:close();
local base = os.tmpname(); os.remove(base);
local function path(name) return base .. '-' .. name; end
local function read(name)
    local input = assert(io.open(name, 'rb')); local data = input:read('*a'); input:close(); return data;
end
local function contains(data, needle) return data:find(needle, 1, true) ~= nil; end
string.fmt = string.format;
string.any = function(value, ...)
    for _, item in ipairs({...}) do if value == item then return true; end end
    return false;
end;
local diagnostics = assert(loadfile(root .. '/modules/support_diagnostics.lua'))();
local a = {log_path=path('legacy.log'), nav_route_points={},
    nav_promyvion_state={phase='waiting-for-jump',island='floor-2'}};
local env = setmetatable({accessxi=a, addon={version='2026.09.05'}, T=function(v) return v; end,
    accessxi_paths={addon_path=function(_, name) return path(name); end}}, {__index=_G});
local function load_between(first, last, suffix)
    local begin = assert(source:find(first, 1, true));
    local finish = assert(source:find(last, begin + #first, true));
    local chunk = assert(loadstring(source:sub(begin, finish - 1) .. (suffix or ''), 'production-support-seam'));
    setfenv(chunk, env); return chunk();
end
local log_line = load_between('local function log_line(text)', 'local function log_state(text)', '\nreturn log_line;');
env.log_line = log_line;
a.load_module_table = function(name) assert(name == 'support_diagnostics'); return diagnostics; end;
load_between("accessxi.support_diagnostics = accessxi.load_module_table('support_diagnostics'", "accessxi.load_code_module('speech_format');");
assert(a.support_log, 'logging must start automatically');
log_line('mission packet native-key=mission:cop:101');
assert(contains(read(a.log_path), 'mission packet native-key='));
assert(contains(read(path('ffxi-support.log')), 'mission packet native-key='));
local speech_calls, spoken, expected_cancel = 0, '', false;
a.speech_output_text = function(value) return tostring(value or ''); end;
a.speak_output = function(value, cancel)
    speech_calls=speech_calls+1; spoken=value; expected_cancel=cancel;
    return 'prism backend=test output=0';
end;
local speak = load_between('local function speak(text, cancel)', 'local function get_menu_obj(ptr, t)', '\nreturn speak;');
assert(speak('Enter the Memory Stream.', false) == 'prism backend=test output=0');
assert(speech_calls == 1 and expected_cancel == false);
assert(contains(read(path('ffxi-support.log')), 'phase="waiting-for-jump" island="floor-2"'));
assert(contains(read(path('ffxi-support.log')), 'Enter the Memory Stream.'));
local commands = assert(loadfile(root .. '/modules/debug_commands.lua'))();
assert(commands.handle({'/axi','report'}, {accessxi=a,speak=speak,log_line=log_line}));
assert(contains(spoken, 'Support report saved'));
assert(contains(read(a.support_report_path), 'mission packet native-key='));
assert(contains(read(a.support_report_path), 'support context reason=report'));
a.support_log.export = function() return false, 'disk full'; end;
assert(commands.handle({'/axi','report'}, {accessxi=a,speak=speak,log_line=log_line}));
assert(contains(spoken, 'could not be saved'));
for _, name in ipairs({'legacy.log','ffxi-support.log','ffxi-support.log.previous','AccessXI-support-report.log'}) do
    os.remove(path(name));
end
print('support diagnostics: automatic logger, speech, report and failure integration passed');
