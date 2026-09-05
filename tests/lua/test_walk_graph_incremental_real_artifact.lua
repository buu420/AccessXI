-- Incremental loading smoke test for the accepted La Theine AXWG v2 artifact.
-- Usage: luajit tests/lua/test_walk_graph_incremental_real_artifact.lua <file>

package.path = './tools/navbuild/lua/?.lua;' .. package.path;

local walk_graph = require('walk_graph');

local artifact = os.getenv('AXWG_V2_FILE') or arg[1];
assert(artifact ~= nil and artifact ~= '', 'AXWG_V2_FILE or argv[1] is required');

local loader, begin_error = walk_graph.begin_load(artifact, 102, 0x30BA83D1);
assert(loader ~= nil, begin_error);

local started = os.clock();
local maximum_slice_ms, pending_steps = 0, 0;
local status, graph, reason;
repeat
    local slice_started = os.clock();
    status, graph, reason = walk_graph.step_load(loader, 2);
    local slice_ms = (os.clock() - slice_started) * 1000;
    maximum_slice_ms = math.max(maximum_slice_ms, slice_ms);
    if (status == 'pending') then pending_steps = pending_steps + 1; end
until status ~= 'pending';

local total_ms = (os.clock() - started) * 1000;
assert(status == 'ready' and graph ~= nil, tostring(reason));
assert(graph.version == 2 and graph.zone_id == 102
        and graph.node_count == 228470
        and graph.edge_count == 523139
        and graph.portal_count == 262231,
    'incremental real-artifact load returned the wrong graph');
assert(pending_steps > 1,
    'real artifact completed without yielding across frames');
-- One unavoidable allocation or OS read can overrun the requested two milliseconds,
-- but no slice may approach the old whole-file/whole-validation freeze.
assert(maximum_slice_ms < 100,
    ('real-artifact loader froze one slice for %.1f ms'):format(maximum_slice_ms));

print(('incremental real artifact ready total=%.1fms max2ms=%.1fms pending=%d')
    :format(total_ms, maximum_slice_ms, pending_steps));
