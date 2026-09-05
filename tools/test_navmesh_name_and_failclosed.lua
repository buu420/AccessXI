-- A MISSING MESH IS UNKNOWN, NOT A WALL -- AND THE MESH WAS THERE ALL ALONG.
--
-- Live 2026-08-29, Promyvion-Holla. The beacon refused every aim:
--
--   16 x 'nav pursuit aim BLOCKED ... falling through to sightline'
--    0 x 'nav pursuit CLAMPED'
--
-- Zero clamps is the fingerprint. The clamp bisects eight times back toward the
-- player, so a real obstruction almost always lets some short prefix through and
-- logs one. Sixteen refusals with no clamp is a test that never consulted
-- geometry at all.
--
-- Two causes, both fixed here.
--
-- 1. THE FILENAME. The client calls zone 16 "Promyvion - Holla", spaces either
--    side of the hyphen. nav_mesh_filename_from_zone_name collapsed that whole
--    run to one underscore and asked for Promyvion_Holla.nav. The file shipped
--    in third_party/xiNavmeshes is Promyvion-Holla.nav. The mesh was present and
--    unfindable. The shipped convention keeps a hyphen and underscores ordinary
--    spaces: Promyvion-Dem.nav, Abyssea-La_Theine.nav, Hall_of_Transference.nav.
--
-- 2. THE FAIL-CLOSED. With no mesh loaded, nav_mesh_probe_can_see returns a hard
--    false, so nav_leg_walkable refused every leg whatever its geometry. The
--    comment on nav_beacon_sightline_see already promised to return nil when the
--    mesh is unavailable "so callers leave the aim point alone rather than
--    clamping on bad information" -- but the path was dead, because
--    nav_mesh_probe_can_see is defined unconditionally so the type test always
--    passed. Absent data was being read as a wall, in every zone with no mesh.
--
--   luajit tools/test_navmesh_name_and_failclosed.lua
--
-- Exit code 1 on any failed claim.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;
_G.accessxi = {};
_G.nav_clean_field = function (v) return (tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', '')); end

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1; print('  ok   ' .. what);
    else failed = failed + 1; print('  FAIL ' .. what); end
end

local reader = io.open(ADDON .. '/accessxi_reader.lua'):read('*a');
local function lift(header)
    local from = reader:find(header, 1, true);
    if (from == nil) then return nil; end
    local to = reader:find('\nend\n', from, true);
    if (to == nil) then return nil; end
    return reader:sub(from, to + 4);
end

local src = lift('accessxi.nav_mesh_filename_from_zone_name = function (name)');
claim(src ~= nil, 'the mesh filename derivation is in the deployed reader');
if (src == nil) then
    print(('navmesh name and failclosed: %d passed, %d failed'):format(passed, failed));
    os.exit(1);
end
assert(load(src, 'meshname'))();

-- ---------------------------------------------------------------------------
-- 1. EVERY DERIVED NAME MUST BE A FILE THAT EXISTS. Zone names as the client's
--    own string table gives them; files as they are shipped.
-- ---------------------------------------------------------------------------
local CASES = {
    { 'Promyvion - Holla',   'Promyvion-Holla.nav'      },  -- the live failure
    { 'Promyvion - Dem',     'Promyvion-Dem.nav'        },
    { 'Promyvion - Mea',     'Promyvion-Mea.nav'        },
    { 'Promyvion - Vahzl',   'Promyvion-Vahzl.nav'      },
    { 'Abyssea - La Theine', 'Abyssea-La_Theine.nav'    },  -- hyphen AND spaces
    { 'Hall of Transference','Hall_of_Transference.nav' },  -- must not regress
    { 'La Theine Plateau',   'La_Theine_Plateau.nav'    },  -- must not regress
    { 'Spire of Holla',      'Spire_of_Holla.nav'       },
};
local found = 0;
for _, case in ipairs(CASES) do
    local derived = accessxi.nav_mesh_filename_from_zone_name(case[1]);
    claim(derived == case[2],
        ('"%s" derives %s'):format(case[1], case[2]) ..
        (derived == case[2] and '' or (', got ' .. tostring(derived))));
    local h = io.open(ADDON .. '/third_party/xiNavmeshes/' .. derived, 'rb');
    if (h ~= nil) then h:close(); found = found + 1; end
end
claim(found == #CASES,
    ('and all %d derived names are files that exist, got %d'):format(#CASES, found));

-- An apostrophe is still stripped, which is why Ru'Lude worked before.
claim(accessxi.nav_mesh_filename_from_zone_name("Ru'Lude Gardens") == 'RuLude_Gardens.nav',
    "an apostrophe is still removed, got " ..
    tostring(accessxi.nav_mesh_filename_from_zone_name("Ru'Lude Gardens")));
claim(accessxi.nav_mesh_filename_from_zone_name('') == '',
    'and an empty name derives nothing');

-- ---------------------------------------------------------------------------
-- 2. THE FAIL-CLOSED. With no mesh ready, the sightline source must be nil so
--    callers leave the aim alone -- never a false that reads as a wall.
-- ---------------------------------------------------------------------------
_G.T = function (t) return t or {}; end
dofile(ADDON .. '/modules/beacon_sightline.lua');
claim(type(accessxi.nav_beacon_sightline_see) == 'function', 'the sightline source loaded');

accessxi.nav_objective_native_can_see = function () return true; end
accessxi.nav_mesh_probe_can_see = function () return false; end

accessxi.nav_mesh_probe_ready = function () return false; end
claim(accessxi.nav_beacon_sightline_see() == nil,
    'with no mesh ready the sightline source is nil, so the aim is left alone');

accessxi.nav_mesh_probe_ready = function () return true; end
claim(type(accessxi.nav_beacon_sightline_see()) == 'function',
    'and with a mesh ready it answers as before');

-- The geometry half must still be able to refuse on its own, mesh or no mesh.
claim(accessxi.nav_leg_walkable(0, 24.0, 0, 1.0, 18.0, 0, nil) == false,
    'a 6 yalm climb over a 1 yalm run is still refused with no mesh consulted');
claim(accessxi.nav_leg_walkable(0, 24.0, 0, 5.0, 23.4, 0, nil) == true,
    'and an ordinary leg still passes');

print(('navmesh name and failclosed: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);
