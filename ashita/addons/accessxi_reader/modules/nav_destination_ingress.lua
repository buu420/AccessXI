-- Measured entrance-to-destination component connectivity. This selects an
-- entrance; it never installs waypoints or certifies a live door as open.
local M = {};
local function point_key(zone, name, x, z, y)
    if not (tonumber(zone) and tonumber(x) and tonumber(z) and tonumber(y)) then return ''; end
    return ('%d\t%s\t%.3f\t%.3f\t%.3f'):format(zone, tostring(name or ''), x, z, y);
end
function M.load(path)
    local index = {};
    local file = io.open(path, 'r');
    if not file then return index; end
    local header;
    for line in file:lines() do
        if line ~= '' and line:sub(1,1) ~= '#' then
            local fields = {};
            for field in (line:gsub('\r$', '') .. '\t'):gmatch('([^\t]*)\t') do fields[#fields+1] = field; end
            if not header then header = fields;
            else
                local row = {};
                for i, name in ipairs(header) do row[name] = fields[i]; end
                local k = point_key(row.zone, row.target_name, row.tx, row.tz, row.ty);
                if k ~= '' then
                    index[k] = index[k] or {};
                    index[k][#index[k]+1] = row;
                end
            end
        end
    end
    file:close();
    return index;
end
function M.lookup(index, point)
    return index[point_key(point.zone, point.name, point.x, point.z, point.y)];
end
local function near(a, b) return tonumber(a) and tonumber(b) and math.abs(a-b) < .05; end
function M.matches(row, edge)
    return tonumber(row.edge_id) == tonumber(edge.id)
        and tonumber(row.zone) == tonumber(edge.to_zone)
        and tonumber(row.from_zone) == tonumber(edge.from_zone)
        and near(row.sx, edge.to_x) and near(row.sz, edge.to_z) and near(row.sy, edge.to_y);
end
function M.select(point, rows, ctx, preferred)
    if type(rows) ~= 'table' or type(ctx.incoming_edges) ~= 'function' then return nil; end
    local best, best_score;
    local entrances, negatives, positives, unknown = 0, 0, 0, 0;
    for _, edge in ipairs(ctx.incoming_edges(point.zone) or {}) do
        entrances = entrances + 1;
        local status;
        for _, row in ipairs(rows) do
            if M.matches(row, edge) then status = row.status; end
        end
        if status == 'mesh-no-path' then negatives = negatives + 1;
        elseif status == 'mesh-connected' then positives = positives + 1;
        else unknown = unknown + 1; end
        for _, row in ipairs(rows) do
            if row.status == 'mesh-connected' and M.matches(row, edge) then
                local path = ctx.zone_path(ctx.player_zone, point.zone, edge.id, preferred);
                -- In the target zone, remember the entrance for recovery even
                -- though no ordinary zone chain needs to be started yet.
                if tonumber(ctx.player_zone) == tonumber(point.zone) or (type(path) == 'table' and #path > 0) then
                    local final = type(path) == 'table' and path[#path];
                    if tonumber(ctx.player_zone) == tonumber(point.zone)
                        or (final and tonumber(final.id) == tonumber(edge.id)) then
                        local penalty = 0;
                        if type(preferred) == 'table' and #preferred > 0 then
                            penalty = 1000000;
                            for _, zone in ipairs(preferred) do
                                if tonumber(zone) == tonumber(edge.from_zone) then penalty = 0; end
                            end
                        end
                        local rank = type(ctx.edge_rank) == 'function' and ctx.edge_rank(edge) or 50;
                        local score = penalty + (tonumber(rank) or 50)*1000 + (type(path)=='table' and #path or 0)*10;
                        if not best_score or score < best_score or (score == best_score and edge.id < best.id) then
                            best, best_score = edge, score;
                        end
                    end
                end
            end
        end
    end
    if not best and tonumber(ctx.player_zone) ~= tonumber(point.zone) then
        if entrances > 0 and negatives == entrances then return nil, 'mesh-no-path'; end
        if positives > 0 and unknown == 0 then return nil, 'no-connected-chain'; end
    end
    return best;
end
if type(accessxi) == 'table' then
    accessxi.destination_ingress = M;
    local index;
    function accessxi.nav_destination_ingress(point)
        if not index then index = M.load(accessxi_paths.addon_path('data', 'ffxi-nav-destination-ingress.tsv')); end
        return M.lookup(index, point);
    end
end
return M;
