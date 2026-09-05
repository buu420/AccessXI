-- Automatic, bounded diagnostic evidence. No packets are interpreted here and
-- no navigation or objective state is changed. The original developer log stays intact.
local M = {};
local Writer = {}; Writer.__index = Writer;

local function size(path)
    local f = io.open(path, 'rb'); if not f then return 0; end
    local length = f:seek('end') or 0; f:close(); return length;
end

local function text(value)
    return tostring(value):gsub('[\r\n\t]', ' '):gsub('"', "'");
end

local function describe(value, seen, depth)
    if type(value) == 'string' then return '"' .. text(value):sub(1, 2048) .. '"'; end
    if type(value) ~= 'table' then return text(value); end
    if seen[value] then return '<cycle>'; end
    if depth >= 6 then return '<table>'; end
    seen[value] = true;
    local keys, parts = {}, {};
    for key, item in pairs(value) do
        if (type(key) == 'string' or type(key) == 'number')
            and type(item) ~= 'function' and type(item) ~= 'userdata' then
            keys[#keys + 1] = key;
        end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b); end);
    for i, key in ipairs(keys) do
        if i > 64 then parts[#parts + 1] = '<more>'; break; end
        parts[#parts + 1] = text(key) .. '=' .. describe(value[key], seen, depth + 1);
    end
    seen[value] = nil;
    return '{' .. table.concat(parts, ',') .. '}';
end

function M.new(options)
    options = options or {};
    local self = setmetatable({}, Writer);
    self.path = assert(options.path);
    self.previous = self.path .. '.previous';
    self.version = text(options.version or 'development');
    self.limit = math.max(1024, tonumber(options.max_bytes) or 8 * 1024 * 1024);
    self.clock = options.clock or os.time;
    self.context = options.context or function() return {}; end;
    self.bytes = size(self.path);
    self.last_snapshot = -math.huge;
    self.started = false;
    return self;
end

function Writer:_append(event)
    local line = os.date('%Y-%m-%d %H:%M:%S') .. ' ' .. tostring(event):gsub('[\r\n]', ' ') .. '\n';
    -- A bad provider cannot turn a single event into an unbounded allocation on disk.
    local bound = math.min(32768, math.floor(self.limit / 2));
    if #line > bound then line = line:sub(1, bound - 15) .. ' <truncated>\n'; end
    if self.bytes + #line > self.limit then
        if size(self.previous) > 0 then
            local ok, err = os.remove(self.previous); if not ok then return false, err; end
        end
        local ok, err = os.rename(self.path, self.previous);
        if not ok then return false, err; end
        self.bytes = 0;
    end
    local header = '';
    if self.bytes == 0 then
        header = os.date('%Y-%m-%d %H:%M:%S') .. ' support segment schema=1 release="'
            .. self.version .. '"\n';
    end
    local f, err = io.open(self.path, 'ab'); if not f then return false, err; end
    local wrote, write_err = f:write(header, line);
    local closed, close_err = f:close();
    if not wrote or not closed then return false, write_err or close_err; end
    self.bytes = self.bytes + #header + #line;
    return true;
end

function Writer:snapshot(reason)
    local ok, context = pcall(self.context);
    local detail = ok and describe(context, {}, 0) or ('snapshot unavailable: ' .. text(context));
    local written, err = self:_append('support context reason=' .. text(reason) .. ' ' .. detail);
    if written then self.last_snapshot = self.clock(); end
    return written, err;
end

function Writer:record(event)
    if self.busy then return true; end
    self.busy = true;
    local ok, result, err = pcall(function()
        if not self.started then
            local wrote, why = self:_append('support session schema=1 release="' .. self.version .. '"');
            if not wrote then return false, why; end
            self.started = true;
        end
        if self.clock() - self.last_snapshot >= 30
            or tostring(event):find('^mission packet ')
            or tostring(event):find('^quest packet ') then
            local wrote, why = self:snapshot('automatic'); if not wrote then return false, why; end
        end
        return self:_append(event);
    end);
    self.busy = false;
    if not ok then return false, result; end
    return result, err;
end

function Writer:export(path)
    -- Fixed in-game output; reject our own source names even on case-insensitive Windows.
    local normalized = tostring(path or ''):gsub('/', '\\'):lower();
    if normalized == '' or normalized == self.path:gsub('/', '\\'):lower()
        or normalized == self.previous:gsub('/', '\\'):lower() then
        return false, 'report path must differ from the support log';
    end
    local captured, capture_err = self:snapshot('report');
    if not captured then return false, capture_err; end
    local output, err = io.open(path, 'wb'); if not output then return false, err; end
    local function copy(source, label, optional)
        local input, open_err, code = io.open(source, 'rb');
        if not input then
            if optional and code == 2 then return true; end -- no previous segment yet
            return false, open_err;
        end
        local wrote, why = output:write('\n--- ' .. label .. ' ---\n');
        if not wrote then input:close(); return false, why; end
        local remaining = self.limit;
        while remaining > 0 do
            local block, read_err = input:read(math.min(65536, remaining));
            if read_err then input:close(); return false, read_err; end
            if not block then break; end
            wrote, why = output:write(block);
            if not wrote then input:close(); return false, why; end
            remaining = remaining - #block;
        end
        input:close(); return true;
    end
    local ok, why = copy(self.previous, 'retained previous segment', true);
    if ok then ok, why = copy(self.path, 'current segment'); end
    local closed, close_err = output:close();
    if not ok or not closed then return false, why or close_err; end
    return true;
end

-- Read already-observed state only: collecting evidence must not advance a
-- guide cursor, query hidden server state, or start a route.
function M.context(a)
    local function point(p)
        local out = {};
        for _, key in ipairs({'zone', 'name', 'x', 'z', 'y', 'heading', 'kind', 'source',
            'objective_native_key', 'objective_guide_step_id', 'objective_action_id',
            'route_context_label', 'entity_server_id', 'status'}) do
            out[key] = type(p) == 'table' and p[key] or nil;
        end
        return out;
    end
    local index = tonumber(a.nav_route_point_index) or 1;
    local points = a.nav_route_points or {};
    local promy = a.nav_promyvion_state or {};
    return {
        identity = a.mission_quest_nav_identity, session = a.objective_session_epoch,
        mission = {packet=a.mission_packet_main, source=a.mission_packet_source,
            identity=a.mission_packet_identity, session=a.mission_packet_session_epoch,
            ahturghan=a.mission_packet_ahturghan, recent=a.nav_objective_recent_mission_key},
        quest = {packets=a.quest_packet_logs, source=a.quest_packet_source,
            identity=a.quest_packet_identity, session=a.quest_packet_session_epoch},
        selection = point((a.nav_menu_items or {})[tonumber(a.nav_menu_index) or 1]),
        route = {active=a.nav_active, generation=a.nav_route_ownership_generation,
            player=point(a.nav_current_position), destination=point(a.nav_destination),
            index=index, count=#points, waypoint=point(points[index]), next=point(points[index+1]),
            reject=a.nav_route_last_reject_reason, menu_open=a.nav_menu_open},
        promyvion = {phase=promy.phase, island=promy.island, target_island=promy.target_island,
            next_island=promy.next_island,
            record=type(promy.transition)=='table' and promy.transition.record_id or nil},
    };
end

return M;
