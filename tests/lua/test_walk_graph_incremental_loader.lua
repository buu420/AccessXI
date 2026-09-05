-- Incremental AXWG loader behavior.
-- Run from the AccessXI repository root under LuaJIT.

package.path = './tests/lua/?.lua;./tools/navbuild/lua/?.lua;' .. package.path;

local fixture = require('axwg_v2_fixture');
local walk_graph = require('walk_graph');
local bit = require('bit');

local function instrument_open(path, maximum_read)
    local real_open = io.open;
    local reads, closed, reached_eof = {}, false, false;

    io.open = function(open_path, mode)
        local file, open_error = real_open(open_path, mode);
        if (file == nil or open_path ~= path or mode ~= 'rb') then
            return file, open_error;
        end
        local wrapper, known_size = {};
        function wrapper:seek(whence, offset)
            local position, seek_error = file:seek(whence, offset);
            if (whence == 'end' and position ~= nil) then known_size = position; end
            return position, seek_error;
        end
        function wrapper:read(amount)
            assert(type(amount) == 'number',
                'incremental loader requested an unbounded file read');
            assert(amount > 0 and amount <= maximum_read,
                ('incremental loader requested %s bytes, cap is %d'):format(
                    tostring(amount), maximum_read));
            reads[#reads + 1] = amount;
            local chunk = file:read(amount);
            if (chunk ~= nil and known_size ~= nil and file:seek() >= known_size) then
                reached_eof = true;
            end
            return chunk;
        end
        function wrapper:close()
            closed = true;
            return file:close();
        end
        return wrapper;
    end;

    return {
        restore = function() io.open = real_open; end,
        reads = reads,
        closed = function() return closed; end,
        reached_eof = function() return reached_eof; end,
    };
end

local function stepped_clock()
    local now = 0;
    return function()
        now = now + 0.001;
        return now;
    end;
end

local function finish(loader, budget_ms)
    local status, graph, reason = 'pending';
    local calls = 0;
    repeat
        calls = calls + 1;
        assert(calls < 10000, 'incremental loader did not terminate');
        status, graph, reason = walk_graph.step_load(loader, budget_ms);
    until status ~= 'pending';
    return status, graph, reason, calls;
end

local path = os.tmpname();
fixture.write(path);

-- Removing bounded numeric reads, or doing all validation in the final read frame,
-- makes this test fail. It exercises the real file/FFI loader and substitutes only
-- a clock so each public step gets one deterministic bounded operation.
local observed = instrument_open(path, 17);
local loader, begin_error = walk_graph.begin_load(path, 102, nil, {
    read_chunk_size = 17,
    crc_chunk_size = 17,
    validation_batch_size = 1,
    clock = stepped_clock(),
});
observed.restore();
assert(loader ~= nil, begin_error);

local pending_after_read = false;
local status, graph, reason, calls;
repeat
    status, graph, reason = walk_graph.step_load(loader, 0.5);
    calls = (calls or 0) + 1;
    if (status == 'pending' and observed.reached_eof()) then
        pending_after_read = true;
    end
    assert(calls < 10000, 'incremental loader did not terminate');
until status ~= 'pending';

assert(status == 'ready' and graph ~= nil, tostring(reason));
assert(graph.version == 2 and graph.zone_id == 102,
    'incremental loader returned the wrong graph');
assert(#observed.reads > 1,
    'incremental loader materialized the fixture in one read');
assert(pending_after_read,
    'incremental loader performed all validation in the final read frame');
assert(observed.closed(), 'incremental loader left its file handle open');

local repeated_status, repeated_graph, repeated_reason = walk_graph.step_load(loader, 0.5);
assert(repeated_status == 'ready' and repeated_graph == graph and repeated_reason == nil,
    'ready incremental loader was not terminal and idempotent');

print(('incremental AXWG load ready in %d bounded steps'):format(calls));

-- A caller switching modes or zones must be able to cancel without leaking the open file.
local canceled_observed = instrument_open(path, 17);
local canceled_loader = assert(walk_graph.begin_load(path, 102, nil, {
    read_chunk_size = 17,
    clock = stepped_clock(),
}));
canceled_observed.restore();
local first_status = walk_graph.step_load(canceled_loader, 0.5);
assert(first_status == 'pending', 'small first load slice unexpectedly completed');
assert(walk_graph.cancel_load(canceled_loader) == true,
    'incremental loader cancellation was not accepted');
assert(canceled_observed.closed(), 'canceled incremental loader leaked its file handle');
local canceled_status, canceled_graph, canceled_reason = walk_graph.step_load(
    canceled_loader, 0.5);
assert(canceled_status == 'failed' and canceled_graph == nil
        and tostring(canceled_reason):find('canceled', 1, true) ~= nil,
    'canceled incremental loader did not remain terminally failed');

print('incremental AXWG cancellation closes and stays terminal');

-- M.load remains source-compatible, but it must use numeric bounded reads too.
local synchronous_observed = instrument_open(path, 262144);
local synchronous_graph, synchronous_error = walk_graph.load(path, 102);
synchronous_observed.restore();
assert(synchronous_graph ~= nil, synchronous_error);
assert(#synchronous_observed.reads > 0 and synchronous_observed.closed(),
    'synchronous compatibility loader bypassed bounded file ownership');

-- Malformed content must fail through the same incremental path, without returning
-- a partially initialized Graph.
local corrupted_path = os.tmpname();
fixture.write(corrupted_path, nil, nil, function(context)
    local index = context.file_size - 1;
    context.bytes[index] = bit.bxor(context.bytes[index], 1);
end);
local corrupted_loader = assert(walk_graph.begin_load(corrupted_path, 102, nil, {
    read_chunk_size = 31,
    crc_chunk_size = 19,
    validation_batch_size = 1,
    clock = stepped_clock(),
}));
local failed_status, failed_graph, failed_reason = finish(corrupted_loader, 0.5);
assert(failed_status == 'failed' and failed_graph == nil
        and tostring(failed_reason):find('CRC mismatch', 1, true) ~= nil,
    'incremental loader did not fail closed on corrupt payload bytes: '
        .. tostring(failed_reason));

os.remove(corrupted_path);
os.remove(path);

print('incremental AXWG loader behavior ok');
