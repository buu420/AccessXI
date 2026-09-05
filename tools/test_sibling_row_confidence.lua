-- THE ROUTER MUST NOT WALK YOU TO A ROW THE CATALOGUE CALLS BAD.
--
-- Live 2026-08-28, La Theine Plateau. "Shattered Telepoint" has three rows:
--
--   (340.0,-60.0,19.104)  proven   lsb-npc-list-all
--   (337.9,-60.2,19.104)  proven   the player's own walked survey mark
--   (334.0,-56.6,24.055)  BAD      live-screenshot-lathine-telepoint-20260628
--
-- FFXI's y is inverted, so 24.055 is the LOWER ground -- underneath the stairs
-- the telepoint stands on top of. The log caught the planner aiming there:
--
--   nav walk graph retrying sibling row destination="Shattered Telepoint"
--     mode="budget" -> (334.0,-56.6,24.1)
--
-- and the player: "your beacons try to either lead me through the bottom which
-- it can't do".
--
-- The catalogue has said that row is bad since 2026-08-27. Exactly ONE place in
-- the addon acted on it -- the static browse filter at nav_collect_menu_items --
-- which the mission and quest categories return before ever reaching. The
-- router never looked at confidence at all.
--
-- Drives the REAL accessxi.nav_walk_graph_sibling_row lifted from the deployed
-- reader, against the REAL shipped catalogue rows.
--
--   luajit tools/test_sibling_row_confidence.lua
--
-- Exit code 1 on any failed claim.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;
_G.accessxi = {};
_G.T = function (t)
    t = t or {};
    t.len = function (s) return #s end;
    t.append = function (s, v) s[#s + 1] = v end;
    return t;
end
_G.nav_clean_field = function (v) return (tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', '')); end
local logged = {};
_G.log_line = function (text) logged[#logged + 1] = tostring(text or ''); end

local reader = io.open(ADDON .. '/accessxi_reader.lua'):read('*a');
local function lift(header)
    local from = reader:find(header, 1, true);
    if (from == nil) then return nil; end
    local to = reader:find('\nend\n', from, true);
    if (to == nil) then return nil; end
    return reader:sub(from, to + 4);
end

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1; print('  ok   ' .. what);
    else failed = failed + 1; print('  FAIL ' .. what); end
end

local src = lift('function accessxi.nav_walk_graph_sibling_row(destination, allow_bad)');
claim(src ~= nil, 'the sibling-row retry is in the deployed reader');
if (src == nil) then
    print(('sibling row confidence: %d passed, %d failed'):format(passed, failed));
    os.exit(1);
end
assert(load(src, 'sibling'))();

-- Real catalogue rows for the name, out of BOTH files that feed nav_points.
local function load_rows(path, want_zone, want_name)
    local out = {};
    local f = io.open(path, 'r');
    if (f == nil) then return out; end
    for line in f:lines() do
        if (line ~= '' and line:sub(1, 1) ~= '#') then
            local c = {};
            for field in (line .. '\t'):gmatch('([^\t]*)\t') do c[#c + 1] = field; end
            if ((tonumber(c[1]) or 0) == want_zone
                and tostring(c[2]):lower() == want_name:lower()) then
                out[#out + 1] = {
                    zone = tonumber(c[1]), name = c[2],
                    x = tonumber(c[3]) or 0, z = tonumber(c[4]) or 0, y = tonumber(c[5]) or 0,
                    kind = c[6] or '', source = c[7] or '', confidence = c[8] or '',
                };
            end
        end
    end
    f:close();
    return out;
end

local rows = load_rows(ADDON .. '/data/ffxi-nav-destinations.tsv', 102, 'Shattered Telepoint');
for _, r in ipairs(load_rows(ADDON .. '/data/ffxi-nav-recorded-marks.tsv', 102, 'Shattered Telepoint')) do
    rows[#rows + 1] = r;
end
claim(#rows == 3, 'the shipped data holds three Shattered Telepoint rows, got ' .. #rows);

local bad_count = 0;
for _, r in ipairs(rows) do
    if (tostring(r.confidence):lower() == 'bad') then bad_count = bad_count + 1; end
end
claim(bad_count == 1, 'exactly one of them is marked bad, got ' .. bad_count);

-- ---------------------------------------------------------------------------
-- Walk the retry chain the way the router does: start on the first row and ask
-- for siblings until it runs out.
-- ---------------------------------------------------------------------------
accessxi.nav_points = rows;
accessxi.nav_walk_graph_tried_group = nil;
accessxi.nav_walk_graph_tried_rows = nil;

local start = { zone = 102, name = 'Shattered Telepoint', x = 340.0, z = -60.0, y = 19.104 };
local order = {};
local current = start;
for _ = 1, 5 do
    local nxt = accessxi.nav_walk_graph_sibling_row(current);
    if (nxt == nil) then break; end
    order[#order + 1] = nxt;
    current = nxt;
end

-- Only the GOOD row. A bad row must not be handed back by default, because the
-- caller reaches the stairs approach ONLY when this returns nil -- and the
-- approach is a correct route to the right place, while a bad row is one the
-- catalogue already knows is wrong. Returning it walked the player to the
-- bottom of the stairs and announced arrival.
claim(#order == 1, 'only the other GOOD row is offered by default, got ' .. #order);

local function is_bad(row)
    for _, r in ipairs(rows) do
        if (math.abs(r.x - row.x) < 0.01 and math.abs(r.y - row.y) < 0.01) then
            return tostring(r.confidence):lower() == 'bad';
        end
    end
    return false;
end

if (#order >= 1) then
    claim(not is_bad(order[1]),
        ('the FIRST sibling tried is not the bad row, got (%.1f,%.1f,%.1f)'):format(
            order[1].x, order[1].z, order[1].y));
end
for _, row in ipairs(order) do
    claim(not is_bad(row), 'no bad row is offered without being asked for');
end

-- ...but asked for explicitly, it is still there. "Never nothing" holds; it
-- just stops outranking a route that works.
accessxi.nav_walk_graph_tried_group = nil;
accessxi.nav_walk_graph_tried_rows = nil;
local explicit = accessxi.nav_walk_graph_sibling_row(start, true);
claim(explicit ~= nil and is_bad(explicit),
    'the bad row is still available when the caller explicitly asks');

-- And the caller asks in the right order: good rows, then the proven approach,
-- then a bad row. Getting these the wrong way round is the whole defect.
local reader_src = reader;
local approach_at = reader_src:find('sibling = accessxi.nav_walk_graph_proven_approach(player, destination);', 1, true);
local allow_bad_at = reader_src:find('sibling = accessxi.nav_walk_graph_sibling_row(destination, true);', 1, true);
claim(approach_at ~= nil, 'the caller tries the proven approach');
claim(allow_bad_at ~= nil, 'and can still fall back to a bad row');
claim(approach_at ~= nil and allow_bad_at ~= nil and approach_at < allow_bad_at,
    'and the approach is tried BEFORE any bad row');

-- The bad row is the one under the stairs. y is inverted, so it is the LOWER
-- ground; the two good rows sit together on the platform above it.
if (#order >= 1) then
    claim(math.abs(order[1].y - 19.104) < 0.01,
        ('the first sibling is on the upper platform, y=%.3f'):format(order[1].y));
end

-- ---------------------------------------------------------------------------
-- NEVER NOTHING. A bad row that is the only row is still offered -- a
-- destination that is absent is worse than one that is poor.
-- ---------------------------------------------------------------------------
local only_bad = nil;
for _, r in ipairs(rows) do
    if (tostring(r.confidence):lower() == 'bad') then only_bad = r; end
end
accessxi.nav_points = { only_bad };
accessxi.nav_walk_graph_tried_group = nil;
accessxi.nav_walk_graph_tried_rows = nil;
local lone = accessxi.nav_walk_graph_sibling_row({
    zone = 102, name = 'Shattered Telepoint', x = 999.0, z = 999.0, y = 999.0,
}, true);
claim(lone ~= nil, 'a bad row that is the only sibling is still offered when asked for');
claim(#logged > 0 and logged[#logged]:find('falling back to a bad row', 1, true) ~= nil,
    'and the fallback says so in the log');

print(('sibling row confidence: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);
