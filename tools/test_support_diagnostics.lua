-- Exercise the production writer against real files, including rollover and errors.
local root = assert(arg[1], 'pass the addon root');
local base = os.tmpname(); os.remove(base);
local path = base .. '-support.log';
local report = base .. '-report.log';
local function read(p)
    local f = io.open(p, 'rb'); if not f then return ''; end
    local s = f:read('*a'); f:close(); return s;
end
local function contains(s, part) return s:find(part, 1, true) ~= nil; end
local function clean()
    for _, p in ipairs({path, path .. '.previous', report, report .. '.tmp'}) do os.remove(p); end
end
clean();
local now, zone = 100, 16;
local module = assert(loadfile(root .. '/modules/support_diagnostics.lua'))();
local observed = {mission_packet_main={cop=101}, mission_packet_source='packet_in_056',
    mission_quest_nav_identity='tester:1', objective_session_epoch=7,
    nav_current_position={zone=16,x=10,z=20,y=0}, nav_route_points={{zone=16,x=30,z=40,y=0}},
    nav_route_point_index=1, nav_active=true,
    quest_packet_logs={['sandoria-current']={words={2147483648,2}, source='packet_in_055'}},
    nav_promyvion_state={phase='waiting-for-stream', island='floor-2',
        transition={record_id='16:forward:08'}}};
local context = module.context(observed);
assert(context.mission.packet.cop == 101 and context.mission.source == 'packet_in_056');
assert(context.identity == 'tester:1' and context.session == 7);
assert(context.route.player.zone == 16 and context.route.waypoint.x == 30);
assert(context.promyvion.record == '16:forward:08', 'capture the actual selected platform record');
assert(observed.nav_active == true and observed.nav_route_point_index == 1, 'snapshot changed routing');
local log = module.new({path=path, version='2026.09.05', max_bytes=2048,
    clock=function() return now; end,
    context=function() return {zone=zone, mission={cop=101, source='packet_in_056'},
        promyvion={phase='waiting-for-stream'}}; end});
assert(log:record('packet 0x056 mission changed'));
assert(contains(read(path), 'release="2026.09.05"'));
assert(contains(read(path), 'packet 0x056 mission changed'));
assert(contains(read(path), 'packet_in_056'));
assert(contains(read(path), 'waiting-for-stream'));
zone=18; now=131;
assert(log:record('nav route stalled player=(1,2,3)'));
assert(contains(read(path), 'zone=18'));
assert(log:record('speech output result="prism backend=NVDA output=0" text="Enter the Memory Stream."'));
assert(contains(read(path), 'Enter the Memory Stream.'));
for i=1,30 do assert(log:record('nav sample=' .. i .. ' ' .. string.rep('x', 95))); end
assert(#read(path) <= 2048, 'current log exceeded its bound');
assert(#read(path .. '.previous') > 0 and #read(path .. '.previous') <= 2048);
zone=20;
assert(log:export(report));
local exported=read(report);
assert(contains(exported, 'zone=20'), 'export needs a fresh context');
assert(contains(exported, 'nav sample=30'));
assert(contains(exported, 'retained previous segment'));
assert(contains(exported, 'current segment'));
assert(#exported <= 4400, 'export must stay bounded');
assert(not log:export(path), 'export cannot overwrite its source');
assert(not log:export(path .. '.previous'), 'export cannot overwrite retained evidence');
assert(not log:export(base .. '/missing/report.log'), 'unwritable report must fail');
local broken=module.new({path=base .. '/missing/support.log',version='test'});
assert(not broken:record('unwritable'), 'writer must report a failed open');
local cycle={}; cycle.self=cycle;
local cyclic=module.new({path=path,version='test',context=function() return cycle; end});
assert(cyclic:record('cycle survived'));
assert(contains(read(path), '<cycle>'));
assert(cyclic:record(string.rep('z', 100000)));
local faulty=module.new({path=path,version='test',context=function() error('context unavailable'); end});
assert(faulty:record('event survives snapshot failure'));
assert(contains(read(path), 'event survives snapshot failure'));
assert(contains(read(path), 'snapshot unavailable'));
local real_context=module.new({path=path,version='test',context=function() return module.context(observed); end});
assert(real_context:record('quest snapshot'));
assert(contains(read(path), '2147483648'), 'quest snapshot must retain the observed bit words');
local real_open = io.open;
io.open = function(p, mode)
    if p == path and mode == 'rb' then return nil, 'permission denied', 13; end
    return real_open(p, mode);
end;
local denied, denied_error = real_context:export(report);
io.open = real_open;
assert(not denied and contains(tostring(denied_error), 'permission'), 'unreadable evidence cannot report success');
io.open = function(p, mode)
    if p == path and mode == 'rb' then
        return {read=function() return nil, 'I/O error'; end, close=function() return true; end};
    end
    return real_open(p, mode);
end;
local failed_read, read_error = real_context:export(report);
io.open = real_open;
assert(not failed_read and contains(tostring(read_error), 'I/O'), 'failed read cannot become EOF');
clean();
print('support diagnostics: writer and observed context checks passed');
