-- The real three-zone boundary metadata with controlled route-provider answers.
-- Native walking evidence for these legs is recorded in the investigation.
WALKTHROUGH_EMBED = true;
local h = dofile('tools/test_mission_step_resolver.lua');
local addon = assert(os.getenv('ACCESSXI_ADDON'));
local methods = {};
function methods:len() return #self; end
function methods:append(v) self[#self+1] = v; end
T = function(t) return setmetatable(t or {}, {__index=methods}); end;
string.fmt = string.format;
local by_id = {};
for _, edge in ipairs(h.edges) do by_id[tonumber(edge.id)] = edge; end
local chain = {by_id[1633891706], by_id[876032890], by_id[1631073146]};
assert(chain[1] and chain[2] and chain[3]);
local player = {zone=192, x=-200.937, z=61.118, y=-10};
local target = {zone=192, x=420, z=-30.375, y=-1.660, name='Gate: Magical Gizmo',
    objective_canonical_edge_id=1631073146};
local function edge_point(e, side) return {zone=e[side..'_zone'],x=e[side..'_x'],z=e[side..'_z'],y=e[side..'_y']}; end
local function same(a,b) return a.zone==b.zone and math.abs(a.x-b.x)<.01 and math.abs(a.z-b.z)<.01; end
local pairs_ = {{player, edge_point(chain[1],'from')},
    {edge_point(chain[1],'to'),edge_point(chain[2],'from')},
    {edge_point(chain[2],'to'),edge_point(chain[3],'from')},
    {edge_point(chain[3],'to'),target}};
local reject_leg, measured = nil, true;
accessxi = {
    nav_zoneline_out_edges = function(zone)
        local out=T{}; for _, e in ipairs(chain) do if e.from_zone==zone then out:append(e); end end; return out;
    end,
    nav_zoneline_path = function(from,to,id)
        if from==115 and to==192 and id==1631073146 then return T{chain[2],chain[3]}; end; return T{};
    end,
    nav_destination_ingress = function() return measured and {{edge_id=1631073146,status='mesh-connected'}} or {}; end,
    nav_zoneline_edge_rank = function() return 8; end,
    nav_graph_zone_name = function(z) return h.zone_names[z]; end,
    nav_copy_point = function(t) local r=T{}; for k,v in pairs(t) do r[k]=v; end; return r; end,
};
nav_compute_mesh_route = function(a,b)
    for i,p in ipairs(pairs_) do if same(a,p[1]) and same(b,p[2]) and reject_leg~=i then return T{a,b}; end end
    return T{b};
end;
nav_distance = function(a,b) return math.sqrt((a.x-b.x)^2+(a.z-b.z)^2+(a.y-b.y)^2); end;
nav_clean_field = function(s) return tostring(s or ''); end;
log_line = function() end;
dofile(addon .. '/modules/same_zone_reentry_navigation.lua');
local plan = assert(accessxi.nav_same_zone_reentry_find(player,target));
assert(#plan.edges==3 and plan.edges[3].id==1631073146);
for i=1,4 do reject_leg=i; assert(accessxi.nav_same_zone_reentry_find(player,target)==nil, 'unverified walking leg '..i); end
reject_leg=nil; measured=false; assert(accessxi.nav_same_zone_reentry_find(player,target)==nil);
measured=true; assert(accessxi.nav_same_zone_reentry_begin(player,target));
local current=player;
for i,edge in ipairs(chain) do
    local leg,state=accessxi.nav_same_zone_reentry_current_leg(current);
    assert(state=='leg' and leg.same_zone_reentry_edge_id==edge.id);
    assert(not accessxi.nav_same_zone_reentry_advance({zone=999}), 'wrong transition must not advance');
    assert(accessxi.nav_same_zone_reentry_advance(leg)); current=edge_point(edge,'to');
end
local _,state=accessxi.nav_same_zone_reentry_current_leg(current); assert(state=='complete');
print('Horutoto reentry: 3 crossings; every walking leg and transition guard passed');
