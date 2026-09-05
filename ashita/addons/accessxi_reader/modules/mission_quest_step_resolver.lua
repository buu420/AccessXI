-- Mission/quest step resolver: turns one reconciled guide step into routable
-- catalogue targets, or into a NAMED refusal.
--
-- Why this exists (2026-08-21, The Davoi Report): the runtime only routed a
-- step that named BOTH a zone and a non-zone entity present in the catalogue.
-- "Make your way to Davoi" names only zones, so it was discarded; "Talk to
-- Zantaviat" carries its zone by implication from the step before it, so it
-- was discarded too. Across every progression module that threw away 1,887
-- travel-to-zone actions and 5,054 entity actions -- the data was there, the
-- gate was wrong. Rulings (sol, this thread): (a) travel-to-zone resolves
-- through the directed zone-line graph and completes on the zone change;
-- (b) an entity step with no zone inherits it from the nearest preceding
-- zone-changing step on the same ordered branch, never across an ambiguous
-- one, with a catalogue fallback only when the entity is unique across all
-- zones; (c) refusals say which of those failed.
--
-- Pure: everything it needs comes in through `ctx`, so the same code runs
-- under the addon and under an offline LuaJIT harness against the real
-- reconciled steps, the real catalogue and the real zone-line graph.

local M = {};

M.REASONS = {
    NO_ZONE_CHAIN = 'no-zone-chain',
    EXIT_SQUARE_UNRESOLVED = 'exit-square-unresolved',
    ZONE_CONTEXT_MISSING = 'zone-context-missing',
    ZONE_CONTEXT_AMBIGUOUS = 'zone-context-ambiguous',
    ENTITY_ABSENT = 'entity-absent',
    ENTITY_DUPLICATED = 'entity-duplicated',
    SOURCE_CONFLICT = 'source-conflict',
    ALREADY_IN_ZONE = 'already-in-zone',
    NO_DESTINATION = 'no-destination',
};

local function clean(value)
    value = tostring(value or '');
    return (value:gsub('^%s+', ''):gsub('%s+$', ''));
end

local function list_local(value)
    if (type(value) ~= 'table') then return {}; end
    local out = {};
    for _, item in ipairs(value) do out[#out + 1] = item; end
    return out;
end

-- 6,474 reconciled steps carry a map square the guide printed. Saying "this
-- step has no destination in the guide" over the top of one is the addon
-- deleting a line the wiki wrote -- and a square is precisely what a sighted
-- player would read off the page and walk to.
function M.no_destination_detail(step)
    local square = table.concat(list_local(type(step) == 'table' and step.grid_coordinates or nil), ', ');
    if (square ~= '') then
        return ('the guide gives only map square %s for this step'):format(square);
    end
    return 'this step has no destination in the guide';
end

local function list(value)
    if (type(value) ~= 'table') then
        return {};
    end
    local out = {};
    for _, item in ipairs(value) do
        out[#out + 1] = item;
    end
    return out;
end

local function set_count(set)
    local count = 0;
    for _ in pairs(set) do
        count = count + 1;
    end
    return count;
end

local function only_key(set)
    local found = nil;
    for key in pairs(set) do
        if (found ~= nil) then
            return nil;
        end
        found = key;
    end
    return found;
end

local ZONE_CHANGING_ACTIONS = {
    travel = true, enter = true, go = true, move = true, zone = true, ['travel-to'] = true,
};

-- Actions that put the player somewhere. A 'note' (a Survival Guide tip, a
-- "you can also..." aside) names zones without moving anyone, so it is never
-- zone context -- Davoi Report step-010 is a note about Jugner Forest sitting
-- between "travel to Davoi" and "talk to Zantaviat".
local POSITIONAL_ACTIONS = {
    talk = true, examine = true, trade = true, fight = true, use = true, farm = true,
    obtain = true, deliver = true, enter = true, travel = true,
};

function M.is_zone_changing_action(action)
    return ZONE_CHANGING_ACTIONS[clean(action):lower()] == true;
end

-- Closed registry of things a guide names that are not places: spells,
-- abilities, status effects, supplies, currencies and systems. Membership is
-- by exact lower-case name or a "(status)"-style suffix; nothing fuzzy.
local MODIFIER_TERMS = {};
for _, term in ipairs({
    'sneak', 'invisible', 'deodorize', 'circumspection', 'elemental seal', 'sleep', 'sleep ii', 'sleepga', 'sleepga ii',
    'silence', 'bind', 'gravity', 'stun', 'utsusemi', 'utsusemi: ichi', 'utsusemi: ni', 'reraise', 'reraise ii', 'reraise iii',
    'warp', 'warp ii', 'escape', 'tractor', 'raise', 'raise ii', 'raise iii', 'cure', 'protect', 'shell', 'haste', 'refresh',
    'regen', 'blink', 'stoneskin', 'aquaveil', 'flash', 'slow', 'paralyze', 'poison', 'dia', 'bio', 'lullaby', 'horde lullaby',
    'foe lullaby', 'sleepga ii', 'repose', 'retaliation', 'provoke', 'hide', 'flee', 'perfect dodge', 'invincible', 'mighty strikes',
    'silent oil', 'prism powder', 'sneak oil', 'reraise earring', 'instant reraise', 'instant warp', 'warp cudgel', 'warp scroll',
    'echo drops', 'poison potion', 'holy water', 'remedy', 'panacea', 'hi-potion', 'potion', 'ether', 'elixir', 'vile elixir',
    'icarus wing', 'dusty elixir', 'dusty ether', 'dusty potion',
    -- A JOB IS NOT A PLACE. The guide names jobs constantly and always as
    -- advice -- "Picking the lock will only work if Thief is your main job",
    -- "If you do not have a Thief who can pick locks, obtain a Bronze Key by
    -- defeating Fomors" -- yet they were classified as entities to route to,
    -- 149 times across the mission corpus, and refused as absent. No catalogue
    -- row is named after a job: checked all twenty-two against
    -- data/ffxi-nav-destinations.tsv, zero hits, so nothing real is lost by
    -- treating them as the advice they are.
    'war', 'mnk', 'whm', 'blm', 'rdm', 'thf', 'pld', 'drk', 'bst', 'brd', 'rng', 'sam',
    'nin', 'drg', 'smn', 'blu', 'cor', 'pup', 'dnc', 'sch', 'geo', 'run',
    'warrior', 'monk', 'white mage', 'black mage', 'red mage', 'thief', 'paladin', 'dark knight',
    'beastmaster', 'bard', 'ranger', 'samurai', 'ninja', 'dragoon', 'summoner', 'blue mage',
    'corsair', 'puppetmaster', 'dancer', 'scholar', 'geomancer', 'rune fencer',
    'main job', 'sub job', 'subjob', 'support job',
    'grounds of valor', 'fields of valor', 'fov', 'gov', 'records of eminence', 'roe', 'unity warp', 'unity concord', 'unity',
    'bayld', 'cruor', 'conquest points', 'cp', 'gil', 'experience points', 'exp', 'limit break', 'item level', 'aoe', 'key item',
    'allegiance', 'signet', 'sanction', 'sigil', 'ionis', 'dominion ops', 'voidwatch', 'abyssea', 'trust', 'trusts', 'trust magic',
    'mimeo jewel', 'martello', 'home point warp', 'survival guide warp', 'waypoint warp',
}) do MODIFIER_TERMS[term] = true; end

-- AN ITEM IS WHAT YOU COME AWAY WITH, NOT WHERE YOU GO.
--
-- Extraction lifts the reward into `entities` and loses the target. Verbatim
-- from the shipped corpus:
--
--   entities       = { "Drops of Amnio" }
--   bg_instruction = "Check the Fountain of Kings again, after the bodies
--                     disappear, for some key item Drops of Amnio."
--
-- The Fountain of Kings is the thing to walk to and it is nowhere in the
-- structured fields; the key item is, and we then refused the whole step
-- because no catalogue row is called "Drops of Amnio". Often BOTH are listed --
-- "Examine the Seed Afterglow on the First Floor (J-10) for the key item
-- Amicitia Stone" carries Seed Afterglow and Amicitia Stone together -- so
-- dropping the reward lets the real target through.
--
-- We do not guess which nouns are items. The guide labels them, in its own
-- words, immediately before the name: "key item X", "the item X". 446 of the
-- 5,833 entity references on material steps are labelled that way.
-- The same disease one layer up. "Check the Dreamrose to spawn Sabotender
-- Enamorado" lists the NM and loses the Dreamrose; "check the Heavy Stone Door
-- to spawn three Skeleton NMs" lists the skeletons and loses the door; "Upon
-- defeating Magma, it will drop 6 Frag Rocks" lists the drop. What appears is
-- never what you walk to, and the guide says which is which in its own words.
local ITEM_LABEL_PATTERNS = { 'key%s+items?%s+', 'items?%s+' };
local RESULT_LABEL_PATTERNS = {
    'to%s+spawn%s+', 'spawns?%s+', 'spawning%s+',
    'will%s+drop%s+', 'drops?%s+', 'dropped%s+by%s+',
    'to%s+receive%s+', 'to%s+obtain%s+', 'to%s+get%s+',
};

function M.is_result_item(step, label, ctx)
    label = clean(label);
    if (type(step) ~= 'table' or label == '') then
        return false;
    end
    -- Declared outright, no reading needed. Two places carry the declaration
    -- and they are NOT the same place: the reconciled step's own fields are
    -- empty across all 31,124 steps -- which is why testing them alone found
    -- nothing and made me think the rule was useless -- while the compact
    -- progression action for the same step id has them populated. sol caught
    -- that; the join is the guide's structured statement, with no reading at
    -- all, and it catches 109 references the prose label cannot see.
    for _, field in ipairs({ 'items', 'key_items', 'result_items' }) do
        for _, entry in ipairs(list(step[field])) do
            local name = clean(type(entry) == 'table'
                and (entry.name or entry.item or entry.key_item) or entry);
            if (name ~= '' and name:lower() == label:lower()) then
                return true;
            end
        end
    end
    if (type(ctx) == 'table' and type(ctx.declared_result_names) == 'function') then
        local declared = ctx.declared_result_names(clean(step.stable_step_id));
        -- Exact normalized equality only. target_kind is confirmation, never
        -- permission to reclassify every entity on the step (sol).
        if (type(declared) == 'table' and declared[label:lower()] == true) then
            return true;
        end
    end
    local prose = table.concat({
        clean(step.primary_instruction),
        clean(step.bg_instruction),
        clean(step.ffxiclopedia_instruction),
    }, ' '):lower();
    if (prose == '') then
        return false;
    end
    local needle = label:lower():gsub('[%^%$%(%)%%%.%[%]%*%+%-%?]', '%%%0');
    for _, patterns in ipairs({ ITEM_LABEL_PATTERNS, RESULT_LABEL_PATTERNS }) do
        for _, prefix in ipairs(patterns) do
            -- The label must sit immediately before the name, so "Bastokan Gate
            -- Guard" is never read as "item Guard".
            if (prose:find('%f[%a]' .. prefix .. needle .. '%f[%A]')) then
                return true;
            end
        end
    end
    return false;
end

function M.is_modifier_term(key)
    key = clean(key):lower();
    if (MODIFIER_TERMS[key]) then return true; end
    if (key:find('%(status%)$') or key:find('%(status effect%)$') or key:find('%(spell%)$') or key:find('%(ability%)$')) then
        return true;
    end
    return false;
end

-- Titles the wikis prefix to names the catalogue stores bare: "Prince Trion"
-- is catalogued as "Trion". Tried only after the exact name finds nothing,
-- only for a step that addresses a PERSON, only inside a context that already
-- exists (a zone or an approved nation group), and it never creates context.
-- "the" is an article, not a title, and belongs to canonical names.
local HONORIFICS = { 'prince ', 'princess ', 'king ', 'queen ', 'lord ', 'lady ', 'sir ', 'captain ', 'master ', 'elder ', 'chief ', 'doctor ', 'dr. ' };
local PERSON_ACTIONS = { talk = true, trade = true, deliver = true };

local function with_spoken_name(points, label)
    local out = {};
    for _, point in ipairs(points) do
        local copy = {};
        for k, v in pairs(point) do copy[k] = v; end
        copy.spoken_name = label;
        out[#out + 1] = copy;
    end
    return out;
end

function M.alias_keys(key)
    local out = {};
    for _, h in ipairs(HONORIFICS) do
        if (key:sub(1, #h) == h and #key > #h) then
            out[#out + 1] = key:sub(#h + 1);
        end
    end
    return out;
end

function M.points_for_entity_alias(ctx, key)
    for _, alias in ipairs(M.alias_keys(key)) do
        local points = list(ctx.points_for_entity(alias));
        if (#points > 0) then return points, alias; end
    end
    return {}, nil;
end

function M.points_for_zone_entity_alias(ctx, zone, key)
    for _, alias in ipairs(M.alias_keys(key)) do
        local points = list(ctx.points_for_zone_entity(zone, alias));
        if (#points > 0) then return points, alias; end
    end
    return {}, nil;
end

-- Zone names as the wikis write them vs. as the catalogue writes them: the
-- Crystal War era is "(S)" on both wikis and "[S]" in the zone tables.
function M.zone_ids_for_name(ctx, value)
    local ids = ctx.zone_ids_for_name(value);
    if (type(ids) == 'table') then
        return ids;
    end
    local text = clean(value);
    local alias = nil;
    if (text:find('%(S%)$')) then
        alias = text:gsub('%s*%(S%)$', ' [S]');
    elseif (text:find('%[S%]$')) then
        alias = text:gsub('%s*%[S%]$', ' (S)');
    end
    if (alias ~= nil and alias ~= text) then
        ids = ctx.zone_ids_for_name(alias);
        if (type(ids) == 'table') then
            return ids;
        end
    end
    return nil;
end

-- A bare nation name ("return to San d'Oria") is not a zone; it is that
-- nation's ordinary districts as a CHOICE (sol: never silently pick one;
-- palace-like zones only when named). ctx.nation_zones(name) -> list of ids.
local function nation_districts(ctx, value)
    if (ctx.nation_zones == nil) then
        return nil;
    end
    local ids = ctx.nation_zones(value);
    if (type(ids) == 'table' and #ids > 0) then
        return ids;
    end
    return nil;
end

-- Split a step's names into zone ids, nation district lists and non-zone
-- entity keys.
function M.classify_step(step, ctx)
    local zone_ids = {};
    local entity_keys = {};
    local zone_order = {};
    local nation_ids = {};
    local seen_nation = {};
    local function take_nation(ids)
        for _, id in ipairs(ids) do
            if (not seen_nation[id]) then
                seen_nation[id] = true;
                nation_ids[#nation_ids + 1] = id;
            end
        end
    end
    for _, value in ipairs(list(step.zones)) do
        local ids = M.zone_ids_for_name(ctx, value);
        if (type(ids) == 'table') then
            for id in pairs(ids) do
                if (not zone_ids[id]) then
                    zone_ids[id] = true;
                    zone_order[#zone_order + 1] = id;
                end
            end
        else
            local districts = nation_districts(ctx, value);
            if (districts ~= nil) then take_nation(districts); end
        end
    end
    -- How many things this step names that are NOT a landmark class. A
    -- landmark is only ever demoted when there is something else to go to.
    local non_landmark_targets = 0;
    for _, value in ipairs(M.step_entities_with_unnamed(step)) do
        local probe = clean(value):lower();
        if (probe ~= '' and M.zone_ids_for_name(ctx, value) == nil
            and probe:find('home point', 1, true) == nil
            and probe:find('survival guide', 1, true) == nil
            and probe:find('waypoint', 1, true) == nil
            and probe:find('telepoint', 1, true) == nil
            and probe:find('mog house', 1, true) == nil) then
            non_landmark_targets = non_landmark_targets + 1;
        end
    end
    for _, value in ipairs(M.step_entities_with_unnamed(step)) do
        local ids = M.zone_ids_for_name(ctx, value);
        if (type(ids) == 'table') then
            for id in pairs(ids) do
                if (not zone_ids[id]) then
                    zone_ids[id] = true;
                    zone_order[#zone_order + 1] = id;
                end
            end
        else
            local districts = nation_districts(ctx, value);
            if (districts ~= nil) then
                take_nation(districts);
            else
                local key = ctx.name_key(value);
                -- A reward is not a destination. Dropping it here means a step
                -- that also names its real target resolves to that target, and
                -- a step that names only the reward becomes instruction-only --
                -- where the guide's own sentence is spoken instead of a refusal
                -- claiming we could not find a place that was never a place.
                -- A reward that is ALSO a catalogued place stays a place.
                -- Checked across the corpus: exactly two entities are both a
                -- declared reward and a catalogue row, and one of them --
                -- "Be sure to collect the Survival Guide in Beaucedine Glacier
                -- (S)" -- is somewhere the player genuinely walks to. The
                -- catalogue is evidence; a label is only a description.
                local catalogued = key ~= '' and ctx.points_for_entity ~= nil
                    and #list(ctx.points_for_entity(key)) > 0;
                -- A landmark the guide only says something is NEAR is not a
                -- destination of its own. See entity_is_proximity_hint.
                local hint = M.entity_is_proximity_hint(step, value, non_landmark_targets);
                if (key ~= '' and not hint
                    and (catalogued or not M.is_result_item(step, value, ctx))) then
                    entity_keys[key] = value;
                end
            end
        end
    end
    return zone_ids, entity_keys, zone_order, nation_ids;
end

-- A LANDMARK YOU ARE TOLD SOMETHING IS NEAR IS NOT WHERE YOU ARE GOING.
--
-- "Examine the Undulating Confluence at (G-8) in Qufim Island. It's close to
-- the Qufim Home Point." The extractor took "Home Point" from that second
-- sentence and it became a second destination for the objective, so
-- At the Heavens' Door appeared TWICE in the list -- once pointing at the
-- Confluence and once at a Home Point. The player: "there should [not] be 2
-- heavens doors, I'm standing at the actual qufim island zone, the other one
-- took me to my mog house so it's obviously not right."
--
-- The same shape produced "Closest Survival Guide is Davoi" as a destination
-- for a step whose real business was three Seedspalls.
--
-- A proximity clause is the tell: close to, near, next to, beside, closest,
-- not far from. A landmark named only inside one of those is orientation, not
-- an errand. TWO GUARDS keep this from eating real targets: it only ever
-- demotes a known landmark CLASS, and only when the step names something else
-- to go to. "Speak to the Survival Guide" or a step whose sole entity is a
-- Home Point still resolves to it, because then it is the errand.
function M.entity_is_proximity_hint(step, value, other_targets)
    local name = clean(value);
    if (name == '' or (tonumber(other_targets) or 0) < 1) then
        return false;
    end
    local key = name:lower();
    local landmark = key:find('home point', 1, true) ~= nil
        or key:find('survival guide', 1, true) ~= nil
        or key:find('waypoint', 1, true) ~= nil
        or key:find('telepoint', 1, true) ~= nil
        or key:find('mog house', 1, true) ~= nil
        or key:find('runic portal', 1, true) ~= nil
        or key:find('conflux', 1, true) ~= nil;
    if (not landmark) then
        return false;
    end
    local prose = table.concat({
        clean(step.instruction), clean(step.primary_instruction),
        clean(step.bg_instruction), clean(step.ffxiclopedia_instruction),
    }, ' '):lower();
    if (prose == '') then
        return false;
    end
    -- Look at the sentence the landmark actually appears in, so a proximity
    -- clause elsewhere in a long step cannot condemn a genuine target.
    for sentence in prose:gmatch('[^%.]+') do
        if (sentence:find(key, 1, true) ~= nil) then
            if (sentence:find('close to', 1, true) or sentence:find('closest', 1, true)
                or sentence:find('near', 1, true) or sentence:find('next to', 1, true)
                or sentence:find('beside', 1, true) or sentence:find('not far', 1, true)) then
                return true;
            end
        end
    end
    return false;
end

-- THE UNNAMED TARGET THE SCRAPER DROPPED.
--
-- FFXI marks a great many interaction points with a literal "???" instead of a
-- name, and the guides write them into prose: "Trade the 3 Seedspalls to the???
-- at (G-6) in Qufim Island". Note the missing space. The corpus writes "the???"
-- 746 times against 271 correctly spaced, so the extractor -- splitting on word
-- boundaries -- swallowed the marker into the preceding word and kept only the
-- zone. Across the shipped modules 2,359 steps name a ??? in their instruction
-- and 1,887 of them, EIGHTY PERCENT, carry no ??? in their entities. Every one
-- of those refuses with "this step has no destination in the guide" while the
-- catalogue holds the object.
--
-- Live 2026-08-27 that was A Crystalline Prophecy mission 2: the player stood
-- in Qufim Island, where there is exactly ONE catalogued ???, and was told the
-- step had no destination.
--
-- Recovering the marker is safe because it is never a zone and never a reward;
-- it is only ever a thing you walk to. Where a zone holds several -- 154 zones
-- do, against 59 with exactly one -- the caller's existing duplicate handling
-- offers them as a choice, which is what a sighted player gets from the map.
-- Their grid references sit unused in step.grid_coordinates and are the right
-- way to narrow that later.
function M.step_entities_with_unnamed(step)
    local entities = list(step.entities);
    for _, value in ipairs(entities) do
        if (clean(value):find('???', 1, true) ~= nil) then
            return entities;
        end
    end
    local prose = table.concat({
        clean(step.instruction),
        clean(step.primary_instruction),
        clean(step.bg_instruction),
        clean(step.ffxiclopedia_instruction),
    }, ' ');
    if (prose:find('???', 1, true) == nil) then
        return entities;
    end
    local augmented = {};
    for _, value in ipairs(entities) do
        augmented[#augmented + 1] = value;
    end
    augmented[#augmented + 1] = '???';
    return augmented;
end

-- The zone a zone-changing step leads to: the progression's recorded
-- destination when there is one, else the FIRST listed zone name that
-- resolves to exactly one id (the wikis write the destination first:
-- "Make your way to Davoi. To reach Davoi, zone into Jugner Forest...").
function M.step_destination_zone(step, ctx)
    local recorded = tonumber(ctx.destination_zone_for_step ~= nil
        and ctx.destination_zone_for_step(clean(step.stable_step_id)) or 0) or 0;
    if (recorded > 0) then
        return recorded, false;
    end
    local names = list(step.zones);
    if (#names == 0) then
        names = list(step.entities);
    end
    for _, value in ipairs(names) do
        local ids = M.zone_ids_for_name(ctx, value);
        if (type(ids) == 'table') then
            local count = set_count(ids);
            if (count == 1) then
                return only_key(ids), false;
            elseif (count > 1) then
                return nil, true;   -- the first named zone is ambiguous
            end
        end
    end
    return nil, false;
end

-- (b) Zone context for a step with no explicit zone: the nearest preceding
-- zone-changing step's destination, or the nearest preceding step that
-- names exactly one zone. An ambiguous zone-changing step in between stops
-- the search -- we do not guess across it.
function M.inherit_zone(steps, index, ctx)
    for j = index - 1, 1, -1 do
        local prior = steps[j];
        if (type(prior) == 'table') then
            if (M.is_zone_changing_action(prior.action)) then
                local zone, ambiguous = M.step_destination_zone(prior, ctx);
                if (zone ~= nil) then
                    return zone, clean(prior.stable_step_id);
                end
                if (ambiguous) then
                    return nil, M.REASONS.ZONE_CONTEXT_AMBIGUOUS;
                end
                -- a travel step naming no resolvable zone is not context; keep looking
            elseif (POSITIONAL_ACTIONS[clean(prior.action):lower()]) then
                local zone_ids = M.classify_step(prior, ctx);
                local count = set_count(zone_ids);
                if (count == 1) then
                    return only_key(zone_ids), clean(prior.stable_step_id);
                elseif (count > 1) then
                    return nil, M.REASONS.ZONE_CONTEXT_AMBIGUOUS;
                end
            end
        end
    end
    return nil, M.REASONS.ZONE_CONTEXT_MISSING;
end

-- (a) The zone-line edge that carries a travel step into `dest_zone` from
-- where the player is. Exactly one reachable edge binds it; several
-- reachable edges with an exit square in the guide is a refusal (we have no
-- map-grid resolver yet, and the nearest entrance is not the guide's);
-- several without a square picks the best by confidence, chain length, id.
-- The zone ids this step's own words name, in guide order. "Make your way to
-- Davoi. To reach Davoi, zone into Jugner Forest from La Theine Plateau" is the
-- road the wiki is telling the player to walk; passing it to the router is what
-- keeps a blind player out of King Ranperre's Tomb (sol, ruling D).
function M.named_via_zones(step, ctx)
    if (type(step) == 'table'
        and clean(step.action):lower() == 'note') then
        return nil;
    end

    if (type(step) ~= 'table'
        or type(ctx.zone_id_for_name) ~= 'function') then
        return nil;
    end

    local zones, seen = {}, {};

    for _, name in ipairs(list(step.zones)) do
        local zone =
            tonumber(ctx.zone_id_for_name(name)) or 0;

        if (zone > 0 and not seen[zone]) then
            seen[zone] = true;
            zones[#zones + 1] = zone;
        end
    end

    return #zones > 0 and zones or nil;
end

local function entry_path_length(path)
    if (type(path) ~= 'table') then return 0; end

    if (type(path.len) == 'function') then
        return tonumber(path:len()) or 0;
    end

    return #path;
end

local function entry_edge_rank(ctx, edge)
    if (type(ctx.edge_rank) ~= 'function') then
        return 50;
    end

    local ok, rank = pcall(ctx.edge_rank, edge);
    return ok and (tonumber(rank) or 50) or 50;
end

local function legacy_entry_edge_candidates(
    player_zone,
    dest_zone,
    via,
    ctx)

    local candidates = {};

    if (type(ctx.incoming_edges) ~= 'function'
        or type(ctx.zone_path) ~= 'function') then
        return candidates;
    end

    for _, edge in ipairs(
        list(ctx.incoming_edges(dest_zone))) do
        local path = ctx.zone_path(
            player_zone,
            dest_zone,
            tonumber(edge.id) or 0,
            via);
        local length = entry_path_length(path);

        if (length > 0) then
            candidates[#candidates + 1] = {
                edge = edge,
                path_len = length,
            };
        end
    end

    return candidates;
end

local function choose_from_entry_candidates(
    candidates,
    step,
    ctx)

    local reachable = {};

    for _, candidate in ipairs(list(candidates)) do
        local edge =
            type(candidate) == 'table'
            and candidate.edge or nil;
        local path_len =
            tonumber(type(candidate) == 'table'
                and candidate.path_len or nil) or 0;

        if (type(edge) == 'table' and path_len > 0) then
            reachable[#reachable + 1] = {
                edge = edge,
                path_len = path_len,
                rank = entry_edge_rank(ctx, edge),
            };
        end
    end

    table.sort(reachable, function(left, right)
        if (left.rank ~= right.rank) then
            return left.rank < right.rank;
        end
        if (left.path_len ~= right.path_len) then
            return left.path_len < right.path_len;
        end
        return (tonumber(left.edge.id) or 0)
            < (tonumber(right.edge.id) or 0);
    end);

    if (#reachable == 0) then
        return {
            edge = nil,
            reason = M.REASONS.NO_ZONE_CHAIN,
            all_edges = nil,
        };
    end

    if (#reachable > 1
        and #list(type(step) == 'table'
            and step.grid_coordinates or nil) > 0) then
        local all = {};

        for _, candidate in ipairs(reachable) do
            all[#all + 1] = candidate.edge;
        end

        return {
            edge = reachable[1].edge,
            reason = M.REASONS.EXIT_SQUARE_UNRESOLVED,
            all_edges = all,
        };
    end

    return {
        edge = reachable[1].edge,
        reason = nil,
        all_edges = nil,
    };
end

-- A missing destination key means the provider did not answer and the legacy
-- oracle must run. An explicit empty bucket means it proved the destination
-- unreachable; restarting independent searches would discard that evidence.
function M.choose_entry_edges(
    destination_zones,
    step,
    ctx)

    local choices = {};
    local ordered, seen = {}, {};

    for _, value in ipairs(list(destination_zones)) do
        local zone = tonumber(value) or 0;

        if (zone > 0 and not seen[zone]) then
            seen[zone] = true;
            ordered[#ordered + 1] = zone;
        end
    end

    local player_zone = tonumber(ctx.player_zone) or 0;

    if (player_zone <= 0) then
        for _, zone in ipairs(ordered) do
            choices[zone] = {
                edge = nil,
                reason = M.REASONS.NO_ZONE_CHAIN,
                all_edges = nil,
            };
        end
        return choices;
    end

    local remote = {};

    for _, zone in ipairs(ordered) do
        if (zone == player_zone) then
            choices[zone] = {
                edge = nil,
                reason = M.REASONS.ALREADY_IN_ZONE,
                all_edges = nil,
            };
        else
            remote[#remote + 1] = zone;
        end
    end

    local via = M.named_via_zones(step, ctx);
    local batch = nil;

    -- AND NOTHING THE PLAYER IS OFFERED MAY DEPEND ON LUCK. When the guide
    -- gives an exit square we cannot bind to one entrance, EVERY reachable
    -- entrance is offered as a choice -- and that list is path-sensitive.
    -- Both the batch and the per-entrance search really answer "does the one
    -- shortest prefix we happened to find avoid the destination zone", and
    -- they find different equal-length prefixes. Measured over 1,194 real
    -- destinations from three player zones: the SELECTED entrance never
    -- differed, but the offered list differed 24 times, in both directions.
    -- Neither answer is the true one; the true question is whether ANY prefix
    -- avoids the destination. Until that is asked properly, a square keeps the
    -- search whose answer is already shipped.
    local square = #list(type(step) == 'table'
        and step.grid_coordinates or nil) > 0;

    -- Guide-road scoring is destination-specific. The plain BFS must not
    -- replace it; that would restore the King Ranperre's Tomb failure.
    if (via == nil
        and not square
        and #remote > 0
        and type(ctx.entry_edge_candidates) == 'function') then
        local ok, answer = pcall(
            ctx.entry_edge_candidates,
            player_zone,
            remote,
            nil);

        if (ok and type(answer) == 'table') then
            batch = answer;
        end
    end

    for _, zone in ipairs(remote) do
        local candidates = nil;

        if (batch ~= nil
            and type(batch[zone]) == 'table') then
            candidates = batch[zone];
        else
            candidates =
                legacy_entry_edge_candidates(
                    player_zone,
                    zone,
                    via,
                    ctx);
        end

        choices[zone] =
            choose_from_entry_candidates(
                candidates,
                step,
                ctx);
    end

    return choices;
end

function M.choose_entry_edge(dest_zone, step, ctx)
    dest_zone = tonumber(dest_zone) or 0;

    local choices =
        M.choose_entry_edges(
            { dest_zone },
            step,
            ctx);
    local choice = choices[dest_zone];

    if (type(choice) ~= 'table') then
        return nil, M.REASONS.NO_ZONE_CHAIN;
    end

    return choice.edge,
        choice.reason,
        choice.all_edges;
end
function M.zone_travel_target(dest_zone, edge, ctx)
    local zone_name = clean(ctx.zone_name(dest_zone));
    if (zone_name == '') then
        zone_name = ('zone %d'):format(dest_zone);
    end
    return {
        zone = dest_zone,
        zone_name = zone_name,
        name = zone_name .. ' entrance',
        x = tonumber(edge.to_x) or 0,
        z = tonumber(edge.to_z) or 0,
        y = tonumber(edge.to_y) or 0,
        kind = 'area',
        source = 'zone-travel',
        destination_id = ('zone-travel:%d:%s'):format(dest_zone, tostring(edge.id or 0)),
        raw_identity = ('zoneline:%s'):format(tostring(edge.id or 0)),
        canonical_edge_id = tonumber(edge.id) or 0,
        canonical_from_zone = tonumber(edge.from_zone) or 0,
        arrival_radius = 6.0,
    };
end

local function copy_point(point)
    local out = {};
    for key, value in pairs(type(point) == 'table' and point or {}) do
        out[key] = value;
    end
    return out;
end

local function combine_rows(left, right)
    local out = {};
    for _, point in ipairs(list(left)) do out[#out + 1] = point; end
    for _, point in ipairs(list(right)) do out[#out + 1] = point; end
    return out;
end

local function exact_number_key(value)
    local number = tonumber(value);
    if (number == nil) then return ''; end
    return ('%.17g'):format(number);
end

local function entity_name_key(ctx, value)
    if (type(ctx.name_key) == 'function') then
        return clean(ctx.name_key(value));
    end
    return clean(value):lower();
end

local function entity_kind(ctx, point)
    if (type(ctx.effective_kind) == 'function') then
        return clean(ctx.effective_kind(point)):lower();
    end
    return clean(type(point) == 'table' and point.kind or ''):lower();
end

local function physical_signature(point, ctx)
    return table.concat({
        tostring(tonumber(point.zone) or 0),
        entity_name_key(ctx, point.name),
        entity_kind(ctx, point),
        exact_number_key(point.x),
        exact_number_key(point.z),
        exact_number_key(point.y),
    }, '\31');
end

local function same_catalogue_identity(left, right)
    local left_raw = clean(left.raw_identity);
    local right_raw = clean(right.raw_identity);
    local left_destination = clean(left.destination_id);
    local right_destination = clean(right.destination_id);

    -- A conflicting nonempty identity must preserve two candidates even when
    -- another identifier happens to match.
    if (left_raw ~= '' and right_raw ~= ''
        and left_raw ~= right_raw) then
        return false;
    end
    if (left_destination ~= '' and right_destination ~= ''
        and left_destination ~= right_destination) then
        return false;
    end

    -- Zone, name, kind and exact coordinates already match. A row lacking an
    -- identity may merge into its richer counterpart.
    return true;
end

local function identity_score(point)
    local score = 0;
    if (clean(point.raw_identity) ~= '') then score = score + 8; end
    if (clean(point.destination_id) ~= '') then score = score + 4; end
    if (clean(point.spoken_name) ~= '') then score = score + 2; end
    if (clean(point.confidence) ~= '') then score = score + 1; end
    return score;
end

local function merge_exact_instance(left, right)
    local keep, other = left, right;
    if (identity_score(right) > identity_score(left)) then
        keep, other = right, left;
    end

    local out = copy_point(keep);
    for key, value in pairs(other) do
        if (out[key] == nil
            or (type(out[key]) == 'string'
                and clean(out[key]) == '')) then
            out[key] = value;
        end
    end
    return out;
end

local function entity_point_less(left, right, ctx)
    local left_zone = tonumber(left.zone) or 0;
    local right_zone = tonumber(right.zone) or 0;
    if (left_zone ~= right_zone) then return left_zone < right_zone; end

    local left_name = entity_name_key(ctx, left.name);
    local right_name = entity_name_key(ctx, right.name);
    if (left_name ~= right_name) then return left_name < right_name; end

    local left_kind = entity_kind(ctx, left);
    local right_kind = entity_kind(ctx, right);
    if (left_kind ~= right_kind) then return left_kind < right_kind; end

    for _, field in ipairs({ 'x', 'z', 'y' }) do
        local left_value = tonumber(left[field]) or 0;
        local right_value = tonumber(right[field]) or 0;
        if (left_value ~= right_value) then
            return left_value < right_value;
        end
    end

    local left_destination = clean(left.destination_id);
    local right_destination = clean(right.destination_id);
    if (left_destination ~= right_destination) then
        return left_destination < right_destination;
    end
    return clean(left.raw_identity) < clean(right.raw_identity);
end

function M.dedupe_entity_points(points, ctx)
    local out = {};
    local buckets = {};

    for _, point in ipairs(list(points)) do
        if (type(point) == 'table') then
            local signature = physical_signature(point, ctx);
            local bucket = buckets[signature];
            if (bucket == nil) then
                bucket = {};
                buckets[signature] = bucket;
            end

            local merged = false;
            for _, index in ipairs(bucket) do
                if (same_catalogue_identity(out[index], point)) then
                    out[index] = merge_exact_instance(out[index], point);
                    merged = true;
                    break;
                end
            end

            if (not merged) then
                out[#out + 1] = copy_point(point);
                bucket[#bucket + 1] = #out;
            end
        end
    end

    table.sort(out, function(left, right)
        return entity_point_less(left, right, ctx);
    end);
    return out;
end

function M.entity_labels(entity_keys)
    local labels = {};
    for _, label in pairs(
        type(entity_keys) == 'table' and entity_keys or {}) do
        labels[#labels + 1] = clean(label);
    end
    table.sort(labels);
    return labels;
end

-- Filtering precedes counting, deduplication and zone grouping. This is what
-- prevents the Nyzul enemy named Naja Salaheem from becoming a talk target.
function M.collect_entity_rows(entity_keys, action, ctx)
    local rows, absent, wrong_kind = {}, {}, {};
    local stats = {
        raw_count = 0,
        allowed_count = 0,
        filtered_count = 0,
    };

    local keys = {};
    for key in pairs(entity_keys) do keys[#keys + 1] = key; end
    table.sort(keys);

    for _, key in ipairs(keys) do
        local label = clean(entity_keys[key]);
        local points = list(ctx.points_for_entity(key));

        -- Numbered facilities such as Home Point #1 are physical instances of
        -- the guide's unnumbered “Home Point”, not absent entities.
        if (#points == 0
            and type(ctx.points_for_entity_base) == 'function') then
            points = list(ctx.points_for_entity_base(key));
        end

        stats.raw_count = stats.raw_count + #points;

        if (#points == 0) then
            absent[#absent + 1] = label;
        else
            local accepted = 0;
            for _, point in ipairs(points) do
                if (ctx.kind_allowed(
                    action, ctx.effective_kind(point))) then
                    rows[#rows + 1] = point;
                    accepted = accepted + 1;
                    stats.allowed_count =
                        stats.allowed_count + 1;
                else
                    stats.filtered_count =
                        stats.filtered_count + 1;
                end
            end
            if (accepted == 0) then
                wrong_kind[#wrong_kind + 1] = label;
            end
        end
    end

    table.sort(absent);
    table.sort(wrong_kind);
    return rows, absent, wrong_kind, stats;
end

function M.guide_instruction(step)
    for _, field in ipairs({
        'primary_instruction',
        'bg_instruction',
        'ffxiclopedia_instruction',
    }) do
        local value = clean(
            type(step) == 'table' and step[field] or '');
        if (value ~= '') then return value; end
    end
    return '';
end

function M.attach_guide_metadata(info, step)
    info = type(info) == 'table' and info or {};

    if (clean(info.instruction) == '') then
        info.instruction = M.guide_instruction(step);
    end
    info.primary_instruction = clean(
        type(step) == 'table'
            and step.primary_instruction or '');
    info.bg_instruction = clean(
        type(step) == 'table'
            and step.bg_instruction or '');
    info.ffxiclopedia_instruction = clean(
        type(step) == 'table'
            and step.ffxiclopedia_instruction or '');

    local square = table.concat(
        list(type(step) == 'table'
            and step.grid_coordinates or nil), ', ');
    if (square ~= '' and clean(info.unbound_square) == '') then
        info.unbound_square = square;
    end
    return info;
end

function M.new_resolution_info(step)
    return M.attach_guide_metadata({
        kind = 'none',
        reason = nil,
        detail = '',
    }, step);
end

-- A NOTE IS READ, NOT WALKED.
--
-- A note used to be resolved like any other step, which meant flattening its
-- `entities` against its `zones` and routing to the cross-product. On the real
-- corpus that produced 18,641 of the 30,317 targets -- 61 per cent of every
-- destination in the addon -- from sentences like "Cursed Axe - Melee damage
-- (Constant Mighty Strikes)" and "Resists /DRK Stun", whose names happen to
-- collide with catalogue rows. One note resolved to 167 places.
--
-- A single result from that method is luck, not evidence, so it is never a
-- binding however few candidates it yields (sol). A note routes only when the
-- guide carries an explicit one: a verified navigation_target, an exact
-- destination id, one zone paired with one entity from a single clause, or a
-- named area with scope='zone'. Otherwise the sentence is spoken and browsed
-- and nothing is offered to walk to -- which is what a note is.
local NOTE_ROUTE_RESOLUTION_FIELDS = {
    'partial',
    'ambiguity',
    'choice_stage',
    'choice_count',
    'choice_origin',
    'equivalent_choices',
    'unreachable_choices',
    'unreachable_zone_count',
    'narrowed_by',
    'unbound_square',
    'standing_in',
    'destination_zone',
    'candidate_count',
    'guide_zone_fallback',
};

local function note_route_failure(
    code,
    option,
    resolved)

    return {
        code = code,
        option = option,
        reason = type(resolved) == 'table'
            and resolved.reason or nil,
        detail = type(resolved) == 'table'
            and resolved.detail or nil,
        unreachable_choices =
            type(resolved) == 'table'
            and resolved.unreachable_choices or nil,
    };
end

local function copy_note_route_resolution_fields(
    destination,
    source)

    if (type(destination) ~= 'table'
        or type(source) ~= 'table') then
        return;
    end

    for _, field in ipairs(
        NOTE_ROUTE_RESOLUTION_FIELDS) do
        if (source[field] ~= nil) then
            destination[field] = source[field];
        end
    end
end

local function note_failure_label(failure)
    local option =
        type(failure) == 'table'
        and failure.option or nil;

    if (type(option) ~= 'table') then
        return 'Invalid note route';
    end

    if (clean(option.entity_name) ~= '') then
        return clean(option.entity_name);
    end
    if (clean(option.zone_name) ~= '') then
        return clean(option.zone_name);
    end
    if (clean(option.destination_id) ~= '') then
        return clean(option.destination_id);
    end

    return 'Invalid note route';
end

local function note_unreachable_choices(failures)
    local choices = {};

    for _, failure in ipairs(
        type(failures) == 'table'
            and failures or {}) do
        if (type(failure.unreachable_choices)
                == 'table'
            and #failure.unreachable_choices > 0) then
            for _, choice in ipairs(
                failure.unreachable_choices) do
                choices[#choices + 1] = choice;
            end
        else
            choices[#choices + 1] = {
                name = note_failure_label(failure),
                reason =
                    failure.reason or failure.code,
                detail = failure.detail,
                count = 1,
            };
        end
    end

    return choices;
end

function M.note_information(
    step,
    failures,
    option_count,
    invalid_count)

    local info = M.new_resolution_info(step);

    info.kind = 'note-information';
    info.reason = nil;
    info.detail = '';
    info.note_information = true;
    info.note_route_options =
        tonumber(option_count) or 0;
    info.note_route_invalid_options =
        tonumber(invalid_count) or 0;
    info.note_route_failures =
        type(failures) == 'table'
        and failures or {};

    return {}, info;
end

function M.explicit_note_route_options(step)
    local options = {};
    local invalid = {};
    local seen = {};
    local raw_options =
        type(step) == 'table'
        and step.note_route_options or nil;

    if (raw_options == nil) then
        return options, invalid;
    end

    if (type(raw_options) ~= 'table') then
        invalid[#invalid + 1] = {
            index = 0,
            code = 'invalid-note-route-options',
        };
        return options, invalid;
    end

    for option_index, raw in ipairs(raw_options) do
        local scope = clean(
            type(raw) == 'table'
            and raw.scope or ''):lower();
        local zone_name = clean(
            type(raw) == 'table'
            and raw.zone_name or '');
        local entity_name = clean(
            type(raw) == 'table'
            and raw.entity_name or '');
        local destination_id = clean(
            type(raw) == 'table'
            and raw.destination_id or '');
        local option = nil;

        if (scope == 'zone'
            and zone_name ~= ''
            and entity_name == ''
            and destination_id == '') then
            option = {
                scope = 'zone',
                zone_name = zone_name,
            };
        elseif (scope == 'entity'
            and destination_id ~= ''
            and zone_name == ''
            and entity_name == '') then
            option = {
                scope = 'entity',
                destination_id = destination_id,
            };
        elseif (scope == 'entity'
            and destination_id == ''
            and zone_name ~= ''
            and entity_name ~= '') then
            option = {
                scope = 'entity',
                zone_name = zone_name,
                entity_name = entity_name,
            };
        else
            invalid[#invalid + 1] = {
                index = option_index,
                code = 'invalid-note-route-option',
            };
        end

        if (option ~= nil) then
            local key = table.concat({
                option.scope,
                option.destination_id or '',
                option.zone_name or '',
                option.entity_name or '',
            }, '\t');

            if (not seen[key]) then
                seen[key] = true;
                options[#options + 1] = option;
            end
        end
    end

    return options, invalid;
end

function M.note_route_variants(step)
    local options, invalid =
        M.explicit_note_route_options(step);
    local variants = {};

    for _, option in ipairs(options) do
        variants[#variants + 1] = {
            option = option,
        };
    end

    return variants, invalid;
end

function M.note_source_mode(step)
    if (type(step) ~= 'table'
        or clean(step.action):lower() ~= 'note') then
        return 'ordinary';
    end

    if (clean(step.note_attach_to_step_id) ~= '') then
        return 'attachment';
    end

    if (step.navigation_target ~= nil) then
        return 'verified';
    end

    local options =
        M.explicit_note_route_options(step);

    if (#options > 0) then
        return 'explicit';
    end

    return 'information';
end

local function note_entity_step(note, option)
    return {
        action = 'note-route',
        target = option.entity_name or '',
        entities = option.entity_name ~= nil
            and { option.entity_name } or {},
        zones = option.zone_name ~= nil
            and { option.zone_name } or {},
        destination_zone_name =
            option.zone_name or '',
        catalogue = {},
        primary_instruction =
            M.guide_instruction(note),
    };
end

function M.resolve_note_route_variant(
    note,
    variant,
    ctx)

    local option =
        type(variant) == 'table'
        and variant.option or nil;

    if (type(option) ~= 'table'
        or type(ctx) ~= 'table') then
        return {}, nil, note_route_failure(
            'invalid-note-route-option',
            type(option) == 'table'
                and option or {},
            nil);
    end

    if (option.scope == 'zone') then
        local synthetic = {
            action = 'travel',
            destination_zone_name =
                option.zone_name,
            zones = { option.zone_name },
            primary_instruction =
                M.guide_instruction(note),
        };
        local targets, resolved =
            M.resolve_step(
                { synthetic },
                1,
                ctx);

        if (type(targets) == 'table'
            and #targets > 0) then
            return targets, resolved, nil;
        end

        return {}, resolved, note_route_failure(
            'note-zone-not-routeable',
            option,
            resolved);
    end

    if (option.destination_id ~= nil) then
        local point = nil;

        if (type(ctx.point_for_destination_id)
            == 'function') then
            local ok, value = pcall(
                ctx.point_for_destination_id,
                option.destination_id);

            if (ok
                and type(value) == 'table'
                and clean(value.destination_id)
                    == option.destination_id) then
                point = value;
            end
        end

        if (point == nil) then
            return {}, nil, note_route_failure(
                'note-destination-not-found',
                option,
                nil);
        end

        local targets, resolved =
            M.finalize_entity_candidates(
                note_entity_step(note, option),
                { point },
                ctx,
                {
                    base_kind = 'note-route',
                    narrowed_by =
                        'note-route-destination-id',
                });

        if (type(targets) == 'table'
            and #targets > 0) then
            return targets, resolved, nil;
        end

        return {}, resolved, note_route_failure(
            'note-destination-not-routeable',
            option,
            resolved);
    end

    local zone_ids =
        M.zone_ids_for_name(
            ctx,
            option.zone_name);

    -- M.zone_ids_for_name answers nil for a name that is not a zone at all,
    -- which is exactly what an annotation naming a place we do not have looks
    -- like. Not unique and not present are the same answer here: no binding.
    if (type(zone_ids) ~= 'table' or set_count(zone_ids) ~= 1) then
        return {}, nil, note_route_failure(
            'note-zone-not-unique',
            option,
            nil);
    end

    local zone_id = only_key(zone_ids);
    local key =
        entity_name_key(
            ctx,
            option.entity_name);
    local rows =
        type(ctx.points_for_zone_entity)
            == 'function'
        and ctx.points_for_zone_entity(
            zone_id,
            key)
        or {};
    local placeable = {};

    for _, point in ipairs(list(rows)) do
        local effective_kind =
            type(ctx.effective_kind) == 'function'
            and ctx.effective_kind(point)
            or clean(point.kind);

        if (type(ctx.kind_allowed) ~= 'function'
            or ctx.kind_allowed(
                'note-route',
                effective_kind)) then
            placeable[#placeable + 1] = point;
        end
    end

    placeable =
        M.dedupe_entity_points(
            placeable,
            ctx);

    if (#placeable == 0) then
        return {}, nil, note_route_failure(
            'note-entity-not-found',
            option,
            nil);
    end

    local targets, resolved =
        M.finalize_entity_candidates(
            note_entity_step(note, option),
            placeable,
            ctx,
            {
                base_kind = 'note-route',
                narrowed_by =
                    'note-route-zone-entity',
            });

    if (type(targets) == 'table'
        and #targets > 0) then
        return targets, resolved, nil;
    end

    return {}, resolved, note_route_failure(
        'note-entity-not-routeable',
        option,
        resolved);
end

function M.resolve_note_step(steps, index, ctx)
    local step =
        type(steps) == 'table'
        and steps[index] or nil;

    if (type(step) ~= 'table') then
        return M.note_information(
            {},
            {
                note_route_failure(
                    'invalid-note-step',
                    nil,
                    nil),
            },
            0,
            0);
    end

    local mode = M.note_source_mode(step);

    if (mode ~= 'explicit') then
        return M.note_information(
            step,
            {},
            0,
            0);
    end

    local variants, invalid =
        M.note_route_variants(step);
    local targets = {};
    local failures = {};
    local resolutions = {};
    local successful_options = 0;

    for _, item in ipairs(invalid) do
        failures[#failures + 1] = {
            code = item.code,
            index = item.index,
        };
    end

    for _, variant in ipairs(variants) do
        local option_targets,
            resolved,
            failure =
                M.resolve_note_route_variant(
                    step,
                    variant,
                    ctx);

        if (type(option_targets) == 'table'
            and #option_targets > 0) then
            successful_options =
                successful_options + 1;
            resolutions[#resolutions + 1] = {
                option = variant.option,
                info = resolved,
            };

            for _, target in ipairs(
                option_targets) do
                targets[#targets + 1] = target;
            end
        elseif (failure ~= nil) then
            failures[#failures + 1] =
                failure;
        end
    end

    targets =
        M.dedupe_entity_points(
            targets,
            ctx);

    if (#targets == 0) then
        return M.note_information(
            step,
            failures,
            #variants,
            #invalid);
    end

    local info = M.new_resolution_info(step);

    info.reason = nil;
    info.detail = '';
    info.note_route = true;
    info.note_information = nil;
    info.note_route_options = #variants;
    info.note_route_invalid_options =
        #invalid;
    info.note_route_successful_options =
        successful_options;
    info.note_route_resolutions =
        resolutions;
    info.note_route_failures =
        failures;

    if (#resolutions == 1) then
        copy_note_route_resolution_fields(
            info,
            resolutions[1].info);
    end

    local unreachable = {};

    for _, resolution in ipairs(resolutions) do
        for _, choice in ipairs(
            type(resolution.info) == 'table'
                and type(resolution.info.unreachable_choices)
                    == 'table'
                and resolution.info.unreachable_choices
                or {}) do
            unreachable[#unreachable + 1] =
                choice;
        end
    end

    for _, choice in ipairs(
        note_unreachable_choices(failures)) do
        unreachable[#unreachable + 1] =
            choice;
    end

    local inherited_kind =
        #resolutions == 1
        and clean(resolutions[1].info.kind)
        or '';
    local remaining_option_count =
        successful_options + #failures;
    local is_choice =
        #targets > 1
        or remaining_option_count > 1
        or #unreachable > 0
        or inherited_kind:find(
            'choice',
            1,
            true) ~= nil;

    if (is_choice) then
        local unreachable_count = 0;

        for _, choice in ipairs(unreachable) do
            unreachable_count =
                unreachable_count
                + (tonumber(choice.count) or 1);
        end

        info.kind = 'note-route-choice';

        if (remaining_option_count > 1) then
            info.choice_stage = 'note-option';
            info.choice_origin =
                'explicit-note-options';
        end

        info.choice_count = math.max(
            tonumber(info.choice_count) or 0,
            #targets + unreachable_count);
        info.candidate_count = #targets;
        info.unreachable_choices =
            unreachable;
    else
        info.kind = 'note-route';
    end

    return targets, info;
end

function M.note_attachments(steps)
    local id_count = {};
    local actionable = {};
    local result = {};

    for _, step in ipairs(
        type(steps) == 'table'
            and steps or {}) do
        local step_id =
            clean(step.stable_step_id);

        if (step_id ~= '') then
            id_count[step_id] =
                (id_count[step_id] or 0) + 1;

            if (clean(step.action):lower()
                ~= 'note') then
                actionable[step_id] = true;
            end
        end
    end

    for _, step in ipairs(
        type(steps) == 'table'
            and steps or {}) do
        if (clean(step.action):lower()
            == 'note') then
            local target_id =
                clean(step.note_attach_to_step_id);
            local sentence =
                M.guide_instruction(step);

            if (target_id ~= ''
                and sentence ~= ''
                and id_count[target_id] == 1
                and actionable[target_id] == true) then
                result[target_id] =
                    result[target_id] or {};

                local duplicate = false;

                for _, existing in ipairs(
                    result[target_id]) do
                    if (existing == sentence) then
                        duplicate = true;
                        break;
                    end
                end

                if (not duplicate) then
                    result[target_id][
                        #result[target_id] + 1] =
                            sentence;
                end
            end
        end
    end

    return result;
end

function M.point_with_attached_notes(
    point,
    notes)

    if (type(point) ~= 'table'
        or type(notes) ~= 'table'
        or #notes == 0) then
        return point;
    end

    local copy = {};

    for key, value in pairs(point) do
        copy[key] = value;
    end

    local suffix = {};

    for _, sentence in ipairs(notes) do
        suffix[#suffix + 1] =
            'Guide note: ' .. sentence;
    end

    local prior = clean(copy.choice_note);
    local added = table.concat(suffix, ' ');

    copy.choice_note =
        prior ~= ''
        and (prior .. ' ' .. added)
        or added;

    return copy;
end

function M.entity_authoritative_zones(
    step,
    ctx,
    guide_zone_ids,
    nation_ids)

    local recorded = tonumber(
        ctx.destination_zone_for_step ~= nil
            and ctx.destination_zone_for_step(
                clean(step.stable_step_id))
            or 0) or 0;

    if (recorded > 0) then
        return { [recorded] = true }, 'recorded-zone';
    end

    local zones = {};
    for zone in pairs(
        type(guide_zone_ids) == 'table'
            and guide_zone_ids or {}) do
        zone = tonumber(zone) or 0;
        if (zone > 0) then zones[zone] = true; end
    end
    for _, zone in ipairs(
        type(nation_ids) == 'table' and nation_ids or {}) do
        zone = tonumber(zone) or 0;
        if (zone > 0) then zones[zone] = true; end
    end

    if (next(zones) ~= nil) then
        return zones, 'guide-zone';
    end
    return nil, nil;
end

function M.entity_rows_in_zones(
    zone_ids,
    entity_keys,
    action,
    ctx)

    local rows = {};

    for zone in pairs(
        type(zone_ids) == 'table' and zone_ids or {}) do
        for key in pairs(entity_keys) do
            local points =
                list(ctx.points_for_zone_entity(zone, key));

            if (#points == 0 and PERSON_ACTIONS[action]) then
                local aliased =
                    M.points_for_zone_entity_alias(
                        ctx, zone, key);
                if (#aliased > 0) then
                    points = with_spoken_name(
                        aliased, entity_keys[key]);
                end
            end

            if (#points == 0
                and ctx.points_for_zone_base ~= nil) then
                points =
                    list(ctx.points_for_zone_base(zone, key));
            end

            for _, point in ipairs(points) do
                if (ctx.kind_allowed(
                    action, ctx.effective_kind(point))) then
                    rows[#rows + 1] = point;
                end
            end
        end
    end
    return rows;
end

local function readable_zone(ctx, zone)
    local name = clean(ctx.zone_name(zone));
    if (name ~= '') then return name; end
    return ('zone %d'):format(tonumber(zone) or 0);
end

local function append_choice_note(point, note)
    local out = copy_point(point);
    note = clean(note);
    if (note ~= '') then
        local existing = clean(out.choice_note);
        out.choice_note = existing ~= ''
            and (existing .. ' ' .. note) or note;
    end
    return out;
end

local function zone_count_for_points(points)
    local zones = {};
    for _, point in ipairs(points) do
        local zone = tonumber(point.zone) or 0;
        if (zone > 0) then zones[zone] = true; end
    end
    return set_count(zones), zones;
end

local function choice_label(opts, physical)
    local labels =
        type(opts.labels) == 'table' and opts.labels or {};
    if (#labels > 0) then
        return table.concat(labels, ' or ');
    end

    local point = physical[1] or {};
    local spoken = clean(point.spoken_name);
    return spoken ~= '' and spoken or clean(point.name);
end

local function unavailable_reason_text(entry)
    if (entry.reason
        == M.REASONS.EXIT_SQUARE_UNRESOLVED) then
        return 'the guide square is not tied to one entrance';
    elseif (entry.reason == M.REASONS.ALREADY_IN_ZONE) then
        return 'the player is already in that zone';
    end
    return 'no known route from here';
end

local function unavailable_text(unreachable)
    local parts = {};
    for _, entry in ipairs(unreachable) do
        parts[#parts + 1] =
            ('%s (%d; %s)'):format(
                clean(entry.name),
                tonumber(entry.count) or 0,
                unavailable_reason_text(entry));
    end
    return table.concat(parts, ', ');
end

-- Ordinary duplicate names use one finalizer. Authoritative guide evidence may
-- narrow the pool, but global ambiguity remains recorded. Without such
-- evidence, current-zone physical points are offered directly and each remote
-- zone contributes at most one staging choice.
function M.finalize_entity_candidates(
    step,
    rows,
    ctx,
    opts)

    opts = type(opts) == 'table' and opts or {};
    local physical = M.dedupe_entity_points(rows, ctx);
    local info = M.new_resolution_info(step);
    local base_kind = clean(opts.base_kind);
    if (base_kind == '') then
        base_kind = 'catalogue-unique';
    end

    local stats =
        type(opts.stats) == 'table' and opts.stats or {};
    local eligible =
        tonumber(stats.allowed_count) or #rows;
    if (eligible < #physical) then eligible = #rows; end

    local raw_count =
        tonumber(stats.raw_count) or eligible;
    if (raw_count < eligible) then raw_count = eligible; end

    local physical_zone_count =
        zone_count_for_points(physical);

    info.choice_origin = base_kind;
    info.raw_candidate_count = raw_count;
    info.action_eligible_candidate_count = eligible;
    info.action_filtered_count =
        tonumber(stats.filtered_count) or 0;
    info.physical_candidate_count = #physical;
    info.physical_candidate_zone_count =
        physical_zone_count;
    info.deduplicated_candidate_count =
        math.max(0, eligible - #physical);
    info.inherited_zone = opts.inherited_zone;
    info.inherited_from = opts.inherited_from;

    if (#physical == 0) then
        info.reason = M.REASONS.ENTITY_ABSENT;
        return {}, info;
    end

    local label = choice_label(opts, physical);
    if (#physical > 1) then
        info.ambiguity = M.REASONS.ENTITY_DUPLICATED;
    end

    local authoritative = opts.authoritative_zones;
    if (type(authoritative) == 'table'
        and next(authoritative) ~= nil) then
        local narrowed = {};

        for _, point in ipairs(physical) do
            if (authoritative[
                tonumber(point.zone) or 0]) then
                narrowed[#narrowed + 1] = point;
            end
        end

        if (#narrowed == 0) then
            info.reason = M.REASONS.ENTITY_ABSENT;
            info.detail =
                ('the recorded or guide zone has no action-compatible indexed location for %s')
                    :format(label);
            return {}, info;
        end

        local narrowed_zone_count, narrowed_zones =
            zone_count_for_points(narrowed);

        info.kind = #narrowed > 1
            and 'entity-choice' or base_kind;
        info.reason = nil;
        info.choice_stage = 'physical';
        info.narrowed_by = clean(opts.narrowed_by) ~= ''
            and clean(opts.narrowed_by) or 'guide-zone';
        info.narrowed_candidate_count = #narrowed;
        info.candidate_count = #narrowed;
        info.choice_count = #narrowed;

        if (narrowed_zone_count == 1) then
            info.destination_zone =
                only_key(narrowed_zones);
        end

        local zone_names = {};
        for zone in pairs(narrowed_zones) do
            zone_names[#zone_names + 1] =
                readable_zone(ctx, zone);
        end
        table.sort(zone_names);

        local notes = {};
        if (#physical > #narrowed) then
            notes[#notes + 1] =
                ('The guide context narrows %s to %d physical location%s in %s; the same name is indexed elsewhere.')
                    :format(
                        label,
                        #narrowed,
                        #narrowed == 1 and '' or 's',
                        table.concat(zone_names, ' or '));
        elseif (#narrowed > 1) then
            notes[#notes + 1] =
                ('%s has %d matching physical locations in the authoritative zone context; choose one.')
                    :format(label, #narrowed);
        end

        if (clean(info.unbound_square) ~= '') then
            notes[#notes + 1] =
                ('The guide gives square %s, but it is not linked to one indexed point.')
                    :format(info.unbound_square);
        end

        local note = table.concat(notes, ' ');
        local targets = {};
        for _, point in ipairs(narrowed) do
            local target =
                append_choice_note(point, note);
            target.entity_choice_stage = 'physical';
            targets[#targets + 1] = target;
        end
        return targets, info;
    end

    if (#physical == 1) then
        local target = copy_point(physical[1]);
        target.entity_choice_stage = 'physical';

        if (clean(info.unbound_square) ~= '') then
            target = append_choice_note(
                target,
                ('The guide gives square %s, but it is not linked to one indexed point.')
                    :format(info.unbound_square));
        end

        info.kind = base_kind;
        info.reason = nil;
        info.choice_stage = 'physical';
        info.candidate_count = 1;
        info.choice_count = 1;
        info.destination_zone =
            tonumber(target.zone) or nil;
        return { target }, info;
    end

    local by_zone, zone_ids = {}, {};
    for _, point in ipairs(physical) do
        local zone = tonumber(point.zone) or 0;
        if (zone > 0) then
            if (by_zone[zone] == nil) then
                by_zone[zone] = {};
                zone_ids[#zone_ids + 1] = zone;
            end
            by_zone[zone][#by_zone[zone] + 1] =
                point;
        end
    end
    table.sort(zone_ids);

    local player_zone = tonumber(ctx.player_zone) or 0;
    local targets, unreachable = {}, {};
    local physical_here, staged = 0, 0;

    -- ASK ONCE FOR ALL OF THEM. A duplicated name offers every zone it is
    -- indexed in, and reachability used to be asked one zone at a time, each
    -- asking again per entrance: 852 breadth-first searches on one objective.
    local entry_choices =
        M.choose_entry_edges(zone_ids, step, ctx);

    local common_note =
        ('%s has %d indexed physical locations in %d zones; no location was selected by name alone.')
            :format(
                label,
                #physical,
                physical_zone_count);

    if (clean(info.unbound_square) ~= '') then
        common_note = common_note
            .. (' The guide gives square %s, but it is not linked to one indexed point.')
                :format(info.unbound_square);
    end

    for _, zone in ipairs(zone_ids) do
        local bucket = by_zone[zone];

        if (zone == player_zone) then
            for _, point in ipairs(bucket) do
                local target =
                    append_choice_note(point, common_note);
                target.entity_choice_stage = 'physical';
                targets[#targets + 1] = target;
                physical_here = physical_here + 1;
            end
        else
            local choice = entry_choices[zone] or {};
            local edge, reason =
                choice.edge, choice.reason;

            if (edge ~= nil and reason == nil) then
                local target =
                    M.zone_travel_target(zone, edge, ctx);
                target.entity_choice_zone = true;
                target.entity_choice_stage = 'zone';
                target.entity_candidate_name = label;
                target.entity_candidate_count = #bucket;
                target.spoken_name = label;
                target.choice_note =
                    ('%s has %d indexed physical location%s in %s. This choice routes only to that zone; the physical target%s will be offered after zoning.')
                        :format(
                            label,
                            #bucket,
                            #bucket == 1 and '' or 's',
                            target.zone_name,
                            #bucket == 1 and '' or 's');
                targets[#targets + 1] = target;
                staged = staged + 1;
            else
                unreachable[#unreachable + 1] = {
                    zone = zone,
                    name = readable_zone(ctx, zone),
                    count = #bucket,
                    reason = reason
                        or M.REASONS.NO_ZONE_CHAIN,
                    entity_name = label,
                };
            end
        end
    end

    info.unreachable_choices = unreachable;
    info.unreachable_zone_count = #unreachable;
    info.candidate_count = #targets;
    info.choice_count = #targets;

    if (#targets == 0) then
        info.kind = 'none';
        info.reason = M.REASONS.NO_ZONE_CHAIN;
        info.choice_stage = 'unreachable';
        info.detail =
            ('%s has %d indexed physical locations in %d zones, but none can currently be routed from here: %s')
                :format(
                    label,
                    #physical,
                    physical_zone_count,
                    unavailable_text(unreachable));
        return {}, info;
    end

    if (staged > 0 or physical_zone_count > 1) then
        info.kind = 'entity-zone-choice';
    elseif (physical_here > 1) then
        info.kind = 'entity-choice';
    else
        info.kind = base_kind;
    end
    info.reason = nil;

    if (physical_here > 0 and staged > 0) then
        info.choice_stage = 'mixed';
    elseif (physical_here > 0) then
        info.choice_stage = 'physical';
    else
        info.choice_stage = 'zone';
    end

    info.detail = common_note;

    if (#unreachable > 0) then
        local missing = unavailable_text(unreachable);
        info.detail = info.detail
            .. (' Unavailable candidate zones: %s.')
                :format(missing);

        local note =
            ('%d other indexed place%s cannot currently be routed from here.')
                :format(
                    #unreachable,
                    #unreachable == 1 and '' or 's');

        for target_index, target in ipairs(targets) do
            targets[target_index] =
                append_choice_note(target, note);
        end
    end

    if (#targets == 1) then
        info.destination_zone =
            tonumber(targets[1].zone) or nil;
    end
    return targets, info;
end

-- A prior physical binding is stronger than a global name match. Several
-- bindings remain choices even for a definite name; equivalent_choices says
-- whether the guide expressly permits any of them.
function M.finalize_prior_candidates(
    step,
    prior,
    entity_keys,
    action,
    ctx)

    local eligible = {};
    for _, point in ipairs(list(prior)) do
        if (ctx.kind_allowed(
            action, ctx.effective_kind(point))) then
            eligible[#eligible + 1] = point;
        end
    end

    local physical =
        M.dedupe_entity_points(eligible, ctx);
    if (#physical == 0) then return nil, nil; end

    local info = M.new_resolution_info(step);
    info.inherited_from = 'prior-step';
    info.raw_candidate_count = #prior;
    info.action_eligible_candidate_count = #eligible;
    info.physical_candidate_count = #physical;
    info.physical_candidate_zone_count =
        zone_count_for_points(physical);
    info.deduplicated_candidate_count =
        math.max(0, #eligible - #physical);
    info.choice_stage = 'physical';

    if (#physical == 1) then
        local target = copy_point(physical[1]);
        target.entity_choice_stage = 'physical';

        info.kind = 'return-to-prior';
        info.reason = nil;
        info.inherited_zone =
            tonumber(target.zone) or nil;
        info.candidate_count = 1;
        info.choice_count = 1;
        return { target }, info;
    end

    local equivalent =
        M.indefinite_target(step, entity_keys);
    local labels = M.entity_labels(entity_keys);
    local label = #labels > 0
        and table.concat(labels, ' or ')
        or clean(physical[1].name);

    local note;
    if (equivalent) then
        note =
            ('The guide says any %s; these prior instances are equivalent choices.')
                :format(label);
    else
        note =
            ('Several prior physical bindings match %s; choose the intended one.')
                :format(label);
    end

    local targets = {};
    for _, point in ipairs(physical) do
        local target =
            append_choice_note(point, note);
        target.entity_choice_stage = 'physical';
        targets[#targets + 1] = target;
    end

    info.kind = 'return-to-prior-choice';
    info.reason = nil;
    info.equivalent_choices = equivalent;
    info.candidate_count = #targets;
    info.choice_count = #targets;

    if (not equivalent) then
        info.ambiguity = M.REASONS.ENTITY_DUPLICATED;
    end
    return targets, info;
end

-- The catalogue instances EARLIER steps of this mission bound for these
-- entities: each prior step naming the entity is resolved in its own context
-- (explicit zone, inherited zone, nation group) and the points it would have
-- routed to are collected. Depth-limited: a prior step never consults later
-- steps, so this cannot recurse into itself.
-- The zones THIS STEP's own words name, each resolving to exactly one id, in
-- the order the guide wrote them. A recorded destination for this step id wins
-- alone. A name the zone table maps to several ids is never a destination --
-- we do not pick one of them -- but it is still spoken. Nations are absent
-- here: a nation is a set of districts and the caller handles it.
function M.step_named_zones(step, ctx)
    local recorded = tonumber(ctx.destination_zone_for_step ~= nil
        and ctx.destination_zone_for_step(clean(step.stable_step_id)) or 0) or 0;
    if (recorded > 0) then
        return { recorded }, { clean(ctx.zone_name(recorded)) };
    end
    local names = list(step.zones);
    if (#names == 0) then names = list(step.entities); end
    local ids, seen, spoken = {}, {}, {};
    for _, value in ipairs(names) do
        local set = M.zone_ids_for_name(ctx, value);
        if (type(set) == 'table') then
            spoken[#spoken + 1] = clean(value);
            if (set_count(set) == 1) then
                local id = only_key(set);
                if (not seen[id]) then
                    seen[id] = true;
                    ids[#ids + 1] = id;
                end
            end
        end
    end
    return ids, spoken;
end

-- Actions a zone can answer. 'note' is deliberately absent: a note is
-- information, and standing in Giddeus does not satisfy "Yagudo Caulk dropped
-- from Yagudos in Giddeus."
local GUIDE_ZONE_ACTIONS = {
    talk = true, trade = true, fight = true, obtain = true, examine = true,
    use = true, travel = true, deliver = true, enter = true, farm = true,
};

-- THE GUIDE NAMED THE PLACE; WE COULD NOT PLACE THE THING INSIDE IT.
--
-- That is our gap, not the page's. Refusing the whole step threw away a zone
-- the guide wrote in plain words -- "Kill Goblins in Batallia Downs", "Go to
-- Gusgen Mines or Palborough Mines or Ifrit's Cauldron" -- because no
-- catalogue row is called "Goblins". Across the corpus that is 8,588 refusals,
-- 6,101 of them holding a zone at the moment they refused.
--
-- So carry the player to the place the guide named, and say, in the guide's own
-- words, that it does not say where inside. The promise stays exactly as large
-- as the guide's: info.partial = 'zone-only' forces the spoken caveat, and every
-- zone the guide listed is both offered and read out -- we never pick one.
function M.guide_zone_fallback(step, ctx, ids, spoken)
    local targets, player_zone = {}, tonumber(ctx.player_zone) or 0;
    local square = table.concat(list(step.grid_coordinates), ', ');
    local standing_in, last_reason = nil, nil;
    local several = #ids > 1;
    local entry_choices = M.choose_entry_edges(ids, step, ctx);

    -- ONE ENTRY PER NATION, AND NONE FOR THE NATION YOU ARE STANDING IN.
    --
    -- Live 2026-08-25, "Journey Abroad": the step names the NATIONS Bastok and
    -- Windurst, each of which expands to every city district, so the player was
    -- offered "Bastok Mines entrance", "Bastok Markets entrance" and "Windurst
    -- Waters entrance" and cycled between them -- while STANDING IN PORT
    -- BASTOK. They put it exactly right: "it should only have 1 entry for each
    -- nation anyways cause pretty sure you only have to go to 1 location in
    -- each nation."
    --
    -- The existing skip only dropped the one zone underfoot, and Port Bastok is
    -- not Bastok Mines. Nations are the unit the guide actually named, so they
    -- are the unit to offer -- and arriving anywhere in a nation is arriving in
    -- that nation.
    local nation_of = type(ctx.nation_of_zone) == 'function'
        and ctx.nation_of_zone or nil;
    local player_nation = nation_of ~= nil and clean(nation_of(player_zone)) or '';
    local nation_taken = {};

    for _, dest in ipairs(ids) do
        local dest_nation = nation_of ~= nil and clean(nation_of(dest)) or '';
        if (dest == player_zone
            or (dest_nation ~= '' and dest_nation == player_nation)) then
            standing_in = clean(ctx.zone_name(dest == player_zone and dest or player_zone));
        elseif (dest_nation ~= '' and nation_taken[dest_nation]) then
            -- Already offering a way into this nation; a second district is the
            -- same answer written twice.
        else
            local choice = entry_choices[dest] or {};
            local edge, reason = choice.edge, choice.reason;
            if (edge ~= nil) then
                local target = M.zone_travel_target(dest, edge, ctx);
                local note = square ~= ''
                    and ('The guide places this at square %s of %s, which is not mapped yet.'):format(square, target.zone_name)
                    or ('The guide does not say where in %s.'):format(target.zone_name);
                if (several) then
                    note = ('The guide names %d places for this step: %s. %s'):format(
                        #ids, table.concat(spoken, ', '), note);
                end
                target.choice_note = note;
                targets[#targets + 1] = target;
                if (dest_nation ~= '') then nation_taken[dest_nation] = true; end
            else
                last_reason = reason;
            end
        end
    end
    local info = { kind = 'none', reason = nil, detail = '' };
    if (#targets > 0) then
        info.kind = #targets > 1 and 'zone-travel-choice' or 'zone-travel';
        info.partial = 'zone-only';
        info.guide_zone_fallback = true;
        if (#targets == 1) then info.destination_zone = targets[1].zone; end
        return targets, info;
    end
    if (standing_in ~= nil) then
        info.reason = M.REASONS.ALREADY_IN_ZONE;
        info.detail = ('you are already in %s'):format(standing_in)
            .. (square ~= '' and ('; the guide places this at square %s, which is not mapped yet'):format(square) or '');
        return targets, info;
    end
    info.reason = last_reason or M.REASONS.NO_ZONE_CHAIN;
    info.detail = ('no known zone-line chain to %s from here'):format(table.concat(spoken, ' or '));
    return targets, info;
end

-- "A Gate Guard", not "Halver".
--
-- sol's return-to-prior rule binds an entity back to an earlier instance only
-- when exactly one was found, because a named person is one person and
-- reachability never establishes identity. That is right for "Return to
-- Halver". It is wrong for "Return to a Gate Guard": the indefinite article is
-- the guide saying ANY of them, and this same guide names all three a few steps
-- earlier -- "There are two in Southern San d'Oria, Ambrotien at (K-6) and
-- Endracion at (F-9). There is also a gate guard in Northern San d'Oria, Grilau
-- at (D-8)." Live 2026-08-22 the acceptance step routed to exactly those three
-- as a choice, and then step-015, "Return to a Gate Guard", was refused with
-- "Gate Guard is not in the Davoi catalogue".
--
-- So several instances is the ANSWER here, not an ambiguity. Offer all of them
-- and let the player pick; nothing is chosen for them.
function M.indefinite_target(step, entity_keys)
    local text = clean(type(step) == 'table' and step.primary_instruction or ''):lower();
    if (text == '') then return false; end
    for _, label in pairs(entity_keys) do
        local needle = clean(label):lower();
        if (needle ~= '') then
            -- Only the article immediately before the name counts, so
            -- "Bastokan Gate Guard" is never mistaken for "a Gate Guard".
            if (text:find('%f[%a]any%s+' .. needle:gsub('%W', '%%%0'))
                or text:find('%f[%a]a%s+' .. needle:gsub('%W', '%%%0'))) then
                return true;
            end
        end
    end
    return false;
end

-- A ROLE IS NOT A MISSING NPC.
--
-- "Gate Guard" is a job, not a name, so no catalogue row is called that and the
-- entity test called it absent 36 times across the corpus. But the guide states
-- plainly who fills it -- "There are two in Southern San d'Oria, Ambrotien at
-- (K-6) and Endracion at (F-9). There is also a gate guard in Northern San
-- d'Oria, Grilau at (D-8)" -- and those facts were reviewed and recorded. They
-- were then baked into ONE step's catalogue, mission:San d'Oria:1 step-001, so
-- every other step naming the role got nothing.
--
-- The role's own zones are the guide speaking, so they replace an inherited
-- zone rather than being filtered by it: live 2026-08-22 "Return to a Gate
-- Guard" -- the second-to-last step of The Davoi Report -- was refused with
-- "Gate Guard is not in the Davoi catalogue", Davoi having been inherited from
-- the step that sent the player there. Returning is the whole point of the step.
--
-- Every member is offered. Nothing is chosen for the player.
function M.role_targets(step, entity_keys, ctx)
    if (type(ctx.role_members) ~= 'function') then return nil; end
    for key, label in pairs(entity_keys) do
        local role = ctx.role_members(clean(key):lower());
        if (type(role) == 'table' and type(role.members) == 'table' and #role.members > 0) then
            local targets = {};
            for _, member in ipairs(role.members) do
                local point = ctx.point_for_destination_id ~= nil
                    and ctx.point_for_destination_id(clean(member.destination_id)) or nil;
                if (type(point) == 'table') then
                    targets[#targets + 1] = point;
                end
            end
            if (#targets > 0) then
                return targets, {
                    kind = #targets > 1 and 'role-choice' or 'role',
                    reason = nil,
                    role_name = clean(role.name) ~= '' and clean(role.name) or clean(label),
                    review_basis = clean(role.review_basis),
                };
            end
        end
    end
    return nil;
end

function M.prior_instances(
    steps,
    index,
    entity_keys,
    ctx)

    if (ctx._prior_depth ~= nil
        and ctx._prior_depth > 0) then
        return {};
    end

    local found = {};
    local inner = {};
    for key, value in pairs(ctx) do
        inner[key] = value;
    end
    inner._prior_depth = 1;

    for prior_index = index - 1, 1, -1 do
        local prior = steps[prior_index];
        if (type(prior) == 'table') then
            local names_entity = false;

            for _, value in ipairs(list(prior.entities)) do
                if (entity_keys[
                    ctx.name_key(value)] ~= nil) then
                    names_entity = true;
                end
            end

            if (names_entity) then
                local targets =
                    M.resolve_step(
                        steps, prior_index, inner);

                if (type(targets) == 'table'
                    and #targets > 0) then
                    for _, point in ipairs(targets) do
                        -- A prior zone-stage row is not evidence that the
                        -- physical entity at the other end was selected.
                        if (point.entity_choice_zone ~= true
                            and clean(point.source)
                                ~= 'zone-travel'
                            and (entity_keys[
                                ctx.name_key(point.name)] ~= nil
                                or (point.spoken_name ~= nil
                                    and entity_keys[
                                        ctx.name_key(
                                            point.spoken_name)]
                                        ~= nil))) then
                            found[#found + 1] = point;
                        end
                    end
                end
            end
        end
    end
    return found;
end
-- AN INHERITED ZONE IS ROUTE HISTORY, NOT EVIDENCE ABOUT THIS TARGET.
--
-- The old rule was that a zone carried from an earlier step, missing the
-- entity, is a source conflict no wider search may rescue. That is right when
-- all we have is a bag of names off the step's prose -- rescuing from those
-- sends the player to attack Arciela, who is an ally with enemy rows in three
-- zones, or to a Quadav standing in for Gentle Tiger.
--
-- It is wrong when the CURRENT step proves one target. The compact progression
-- action carries relationship = talk-to / trade-to / deliver-to /
-- examine-object / use-object with an exact target, joined on stable_step_id.
-- That is the guide saying who this step is about, and an inherited zone was
-- never evidence about them. Measured: 55 of 261 entity-absent mission steps
-- have such a target, 28 resolving outright and 27 as honest choices.
--
-- Everything else -- fight, protect, travel, advisory, reward, generic markers
-- like ??? and any name the guide made indefinite or that names a role -- gets
-- no automatic rescue (sol).
local DIRECT_PRIMARY_ACTION_BY_RELATIONSHIP = {
    ['talk-to'] = 'talk',
    ['trade-to'] = 'trade',
    ['deliver-to'] = 'deliver',
    ['examine-object'] = 'examine',
    ['use-object'] = 'use',
};

local GENERIC_PRIMARY_TARGETS = {
    ['???'] = true,
};

local function primary_is_generic_role(
    step,
    key,
    label,
    ctx)

    if (GENERIC_PRIMARY_TARGETS[key]) then
        return true;
    end

    local keys = { [key] = label };

    if (M.indefinite_target(step, keys)) then
        return true;
    end

    if (type(ctx.role_members) == 'function') then
        local ok, members =
            pcall(ctx.role_members, key);

        if (ok
                and type(members) == 'table'
                and next(members) ~= nil) then
            return true;
        end
    end

    return false;
end

-- Exact compact evidence only. The join is:
-- reconciled step.stable_step_id == compact action.step_id.
-- THE GUIDE NAMED THE TARGET AND WE THREW IT AWAY.
--
-- Live 2026-08-23, RoV 7 step-001 "Examine the Oaken Door at (K-8) in Norg to
-- Gilgamesh's room": the reconciled step carries
--
--   entities = { "Norg", "Rhapsody in White" }
--
-- a ZONE and the REWARD key item -- and classifies to zero entities and zero
-- zones, so every path above refuses with no-destination and the player is
-- told nothing at all. Meanwhile the compact progression action for the very
-- same step id says target = "Oaken Door", target_kind = "object",
-- objects = { "Oaken Door" }, zones = { "Norg" }, and Norg's catalogue holds
-- two rows under that name. The route existed the whole time.
--
-- This is the LAST chance, and it is deliberately narrow: it runs only when
-- the step classified to NOTHING. That is what makes reading the compact
-- action safe here -- current_step_primary_evidence requires the compact
-- target to also appear in the step's entities, because a target_kind is
-- confirmation and never permission to reclassify entities the step does
-- name. Where the step names none, there is nothing to reclassify.
--
-- It OFFERS, it does not choose (sol). Two doors carry this name and the
-- guide's square K-8 cannot separate them -- we have no per-zone map-grid
-- calibration, so K-8 stays spoken information and never becomes a silent
-- selector. Picking one and calling it the route is how the player spent
-- three minutes examining a door that never answered.
function M.resolve_compact_action_rescue(step, action, ctx)
    local step_id = clean(step.stable_step_id);
    if (step_id == '' or action == ''
        or type(ctx.primary_actions_for_step) ~= 'function'
        or type(ctx.kind_allowed) ~= 'function') then
        return nil, nil;
    end

    local ok, actions = pcall(ctx.primary_actions_for_step, step_id);
    if (not ok or type(actions) ~= 'table') then
        return nil, nil;
    end

    local entity_keys = {};
    local named = 0;
    for _, compact in ipairs(actions) do
        if (clean(compact.action):lower() == action) then
            local labels = { clean(compact.target) };
            for _, field in ipairs({ 'objects', 'npcs' }) do
                for _, entry in ipairs(list(compact[field])) do
                    labels[#labels + 1] = clean(entry);
                end
            end
            for _, label in ipairs(labels) do
                -- A reward is not a destination. The compact action is also
                -- where the result declaration lives, so this is the guide's
                -- own structured statement, not a reading of its prose.
                if (label ~= '' and not M.is_result_item(step, label, ctx)) then
                    local key = entity_name_key(ctx, label);
                    if (key ~= '' and entity_keys[key] == nil) then
                        entity_keys[key] = label;
                        named = named + 1;
                    end
                end
            end
        end
    end

    if (named == 0) then
        return nil, nil;
    end

    local rows, absent, wrong_kind, stats =
        M.collect_entity_rows(entity_keys, action, ctx);
    if (type(rows) ~= 'table' or #rows == 0) then
        return nil, nil;
    end

    local targets, info = M.finalize_entity_candidates(step, rows, ctx, {
        base_kind = 'compact-action-rescue',
        stats = stats,
        absent = absent,
        wrong_kind = wrong_kind,
    });

    if (type(targets) ~= 'table' or #targets == 0) then
        return nil, nil;
    end
    return targets, info;
end

function M.current_step_primary_evidence(
    step,
    entity_keys,
    action,
    ctx)

    local step_id = clean(step.stable_step_id);
    local direct = {};

    if (step_id ~= ''
            and type(ctx.primary_actions_for_step)
                == 'function') then
        local ok, actions = pcall(
            ctx.primary_actions_for_step,
            step_id);

        if (ok and type(actions) == 'table') then
            for _, compact in ipairs(actions) do
                local relationship =
                    clean(compact.relationship):lower();
                local compact_action =
                    clean(compact.action):lower();
                local expected =
                    DIRECT_PRIMARY_ACTION_BY_RELATIONSHIP[
                        relationship];
                local target =
                    clean(compact.target);
                local target_key =
                    entity_name_key(ctx, target);
                local target_kind =
                    clean(compact.target_kind):lower();

                if (expected == action
                        and compact_action == action
                        and target ~= ''
                        and target_key ~= ''
                        and entity_keys[target_key]
                            ~= nil
                        and target_kind ~= ''
                        and type(ctx.kind_allowed)
                            == 'function'
                        and ctx.kind_allowed(
                            action,
                            target_kind)
                        and not M.is_result_item(
                            step,
                            target,
                            ctx)
                        and not primary_is_generic_role(
                            step,
                            target_key,
                            entity_keys[target_key],
                            ctx)) then
                    direct[target_key] =
                        direct[target_key] or {
                            key = target_key,
                            label =
                                entity_keys[target_key],
                            relationship =
                                relationship,
                            source =
                                'compact-action',
                        };
                end
            end
        end
    end

    local direct_count = set_count(direct);

    if (direct_count == 1) then
        return {
            primary = direct[only_key(direct)],
        };
    end

    -- Zero or several direct targets proves no single primary.
    return nil;
end

function M.resolve_inherited_compact_primary(
    step,
    action,
    ctx,
    evidence,
    context_zone,
    context_from)

    if (type(evidence) ~= 'table'
            or evidence.binding ~= nil
            or type(evidence.primary)
                ~= 'table') then
        return nil, nil;
    end

    local primary = evidence.primary;
    local keys = {
        [primary.key] = primary.label,
    };

    local rows, _, _, stats =
        M.collect_entity_rows(
            keys,
            action,
            ctx);

    if (#rows == 0) then
        return nil, nil;
    end

    local inherited_present = false;

    for _, point in ipairs(rows) do
        if (tonumber(point.zone)
                == tonumber(context_zone)) then
            inherited_present = true;
            break;
        end
    end

    local targets, info =
        M.finalize_entity_candidates(
            step,
            rows,
            ctx,
            {
                base_kind = 'compact-target',
                inherited_zone = context_zone,
                inherited_from = context_from,
                labels = { primary.label },
                stats = stats,
            });

    info.primary_target_source =
        'compact-action';
    info.narrowed_by =
        clean(info.narrowed_by) ~= ''
            and info.narrowed_by
            or 'current-step-primary-target';
    info.inherited_context_conflict =
        not inherited_present;

    if (info.inherited_context_conflict) then
        info.overridden_inherited_zone =
            context_zone;
    end

    return targets, info;
end

-- A DISAGREEMENT IS NOT A REASON TO HIDE THE STEP.
--
-- 1,451 reconciled steps are flagged comparison = "conflict", and every single
-- one names exactly one conflicting field: `target_identity`. That is the
-- extractor noticing the two pages WORDED the target differently -- not the
-- pages disagreeing about where to go. Both guards refused the step outright:
-- source_route_rows skipped it and resolve_step returned SOURCE_CONFLICT. Live
-- 2026-08-23, The Davoi Report step-013 -- "Walk south until you reach a pond
-- at (J-8) ... click the ! to receive the key item Lost document", which both
-- pages say in different words -- told the player "No exact source-backed
-- route is available". 222 of the 377 material mission steps flagged this way
-- would route.
--
-- sol's contract, which this implements:
--   * resolve each page from ITS OWN entities and zones, never the merged
--     union, which can name a place neither page stated;
--   * same target from both -> one route, attributed to both;
--   * one page resolves -> that route, saying the other named no location;
--   * different targets -> source-labelled choices, nothing selected;
--   * anything a choice cannot express -> no route, both sentences spoken.
-- Choosing a route never advances progress.
local CONFLICT_SITES = { 'bg', 'ffxiclopedia' };
local CONFLICT_SITE_LABEL = {
    bg = 'BG-Wiki',
    ffxiclopedia = 'FFXIclopedia',
};

local function conflict_reading_step(step, reading, instruction)
    local out = {
        stable_step_id = clean(step.stable_step_id),
        order = step.order,
        -- The reconciled ACTION is agreed; only target identity is disputed.
        action = clean(step.action),
        entities = list(reading.entities),
        zones = list(reading.zones),
        grid_coordinates = list(reading.grid_coordinates),
        primary_instruction = clean(instruction),
        bg_instruction = clean(step.bg_instruction),
        ffxiclopedia_instruction = clean(step.ffxiclopedia_instruction),
        items = step.items,
        key_items = step.key_items,
        result_items = step.result_items,
    };
    return out;
end

local function conflict_target_signature(targets, ctx)
    local parts = {};
    for _, point in ipairs(list(targets)) do
        parts[#parts + 1] = physical_signature(point, ctx);
    end
    table.sort(parts);
    return table.concat(parts, '\30');
end

function M.resolve_source_conflict_step(steps, index, ctx)
    local step = steps[index];
    local info = M.new_resolution_info(step);
    info.ambiguity = 'source-conflict';

    local readings = nil;
    if (type(ctx.source_readings) == 'function') then
        local ok, value = pcall(ctx.source_readings, clean(step.stable_step_id));
        if (ok and type(value) == 'table') then readings = value; end
    end

    -- Without each page's own reading the union is unsafe, so the old refusal
    -- stands rather than guessing from merged fields (sol).
    if (type(readings) ~= 'table' or next(readings) == nil) then
        info.reason = M.REASONS.SOURCE_CONFLICT;
        info.detail = 'the sources disagree on this step';
        return {}, info;
    end

    local resolved_sites, empty_sites = {}, {};
    for _, site in ipairs(CONFLICT_SITES) do
        local reading = readings[site];
        if (type(reading) == 'table') then
            local instruction = site == 'bg'
                and clean(step.bg_instruction)
                or clean(step.ffxiclopedia_instruction);
            if (instruction == '') then instruction = clean(reading.instruction); end

            local scoped = {};
            for position, other in ipairs(steps) do scoped[position] = other; end
            scoped[index] = conflict_reading_step(step, reading, instruction);

            local targets, reading_info = M.resolve_step(scoped, index, ctx);
            if (type(targets) == 'table' and #targets > 0) then
                resolved_sites[#resolved_sites + 1] = {
                    site = site,
                    label = CONFLICT_SITE_LABEL[site] or site,
                    targets = targets,
                    info = reading_info,
                    signature = conflict_target_signature(targets, ctx),
                };
            else
                empty_sites[#empty_sites + 1] = CONFLICT_SITE_LABEL[site] or site;
            end
        end
    end

    if (#resolved_sites == 0) then
        -- Nothing either page named can be placed. Not a conflict refusal --
        -- say what we could not do, and the guide's own words still travel.
        info.reason = M.REASONS.ENTITY_ABSENT;
        info.detail = 'neither source names a place I can find for this step';
        return {}, info;
    end

    local square = table.concat(list(step.grid_coordinates), ', ');
    if (square == '') then
        for _, entry in ipairs(resolved_sites) do
            square = clean(entry.info.unbound_square);
            if (square ~= '') then break; end
        end
    end
    if (square ~= '' and clean(info.unbound_square) == '') then
        info.unbound_square = square;
    end

    local agreed = #resolved_sites > 1;
    for _, entry in ipairs(resolved_sites) do
        if (entry.signature ~= resolved_sites[1].signature) then agreed = false; end
    end

    if (#resolved_sites == 1 or agreed) then
        local chosen = resolved_sites[1];
        local targets = chosen.targets;
        for key, value in pairs(chosen.info) do
            if (info[key] == nil) then info[key] = value; end
        end
        info.kind = clean(chosen.info.kind);
        info.reason = nil;
        info.ambiguity = 'source-conflict';
        info.conflict_sources = agreed
            and table.concat({ CONFLICT_SITE_LABEL.bg, CONFLICT_SITE_LABEL.ffxiclopedia }, ' and ')
            or chosen.label;
        info.conflict_silent_sources = (not agreed) and table.concat(empty_sites, ', ') or '';
        info.requires_choice = #targets > 1;
        return targets, info;
    end

    -- The pages name different places. Offer both, labelled, and pick neither.
    local targets = {};
    local labels = {};
    for _, entry in ipairs(resolved_sites) do
        labels[#labels + 1] = entry.label;
        for _, point in ipairs(entry.targets) do
            local copy = {};
            for key, value in pairs(point) do copy[key] = value; end
            local note = ('%s names this place.'):format(entry.label);
            local prior = clean(copy.choice_note);
            copy.choice_note = prior ~= '' and (prior .. ' ' .. note) or note;
            copy.conflict_source = entry.site;
            targets[#targets + 1] = copy;
        end
    end
    targets = M.dedupe_entity_points(targets, ctx);

    info.kind = 'source-conflict-choice';
    info.reason = nil;
    info.requires_choice = true;
    info.choice_stage = 'source';
    info.choice_origin = 'source-conflict';
    info.choice_count = #targets;
    info.candidate_count = #targets;
    info.conflict_sources = table.concat(labels, ' and ');
    info.detail = ('%s describe different places for this step; choose one.')
        :format(table.concat(labels, ' and '));
    return targets, info;
end

function M.resolve_entity_step(
    steps,
    index,
    step,
    ctx,
    zone_ids,
    entity_keys,
    zone_order,
    nation_ids,
    action,
    info)

    local targets = {};
    info = type(info) == 'table'
        and info or M.new_resolution_info(step);

    local global_rows, absent, wrong_kind, candidate_stats =
        M.collect_entity_rows(entity_keys, action, ctx);
    local labels = M.entity_labels(entity_keys);

    local authoritative_zones, authoritative_basis =
        M.entity_authoritative_zones(
            step, ctx, zone_ids, nation_ids);

    -- A compact progression destination is stronger than an extracted list.
    if (authoritative_basis == 'recorded-zone') then
        zone_ids = {};
        for zone in pairs(authoritative_zones) do
            zone_ids[zone] = true;
        end
    end

    local context_zone = nil;
    local context_from = nil;

    if (next(zone_ids) == nil and #nation_ids > 0) then
        for _, id in ipairs(nation_ids) do
            zone_ids[id] = true;
        end

        if (type(ctx.default_zone_group) == 'table') then
            local evidence = false;
            local player_zone =
                tonumber(ctx.player_zone) or 0;

            for _, id in ipairs(ctx.default_zone_group) do
                if (zone_ids[id] or id == player_zone) then
                    evidence = true;
                end
            end

            if (evidence) then
                for _, id in ipairs(
                    ctx.default_zone_group) do
                    zone_ids[id] = true;
                end

                if (authoritative_basis
                    == 'guide-zone') then
                    for _, id in ipairs(
                        ctx.default_zone_group) do
                        authoritative_zones[id] = true;
                    end
                end
            end
        end
    end

    if (next(zone_ids) == nil) then
        local inherited, note =
            M.inherit_zone(steps, index, ctx);

        if (inherited ~= nil) then
            zone_ids = { [inherited] = true };
            context_zone = inherited;
            context_from = note;
        else
            info.reason = note;
        end
    end

    -- WHAT THE STEP NAMES IS NOT ALL THE SAME KIND OF THING.
    --
    -- A reconciled step's `entities` is the flattened wiki paragraph, so it
    -- holds the thing you act on, the places, and whatever the sentence
    -- mentions afterwards. mission:Chains of Promathia:3:step-009 -- Below the
    -- Arks -- carries
    --
    --   zones    = { Tahrongi Canyon, Konschtat Highlands, La Theine Plateau }
    --   entities = { crag, Tahrongi Canyon, Konschtat Highlands,
    --                La Theine Plateau, Shattered Telepoint,
    --                Hall of Transference, Large Apparatus }
    --
    -- Every one of those nouns was looked up in every zone, so the browse
    -- offered the player six "Large Apparatus" rows in the Hall of
    -- Transference -- a chamber you can only ARRIVE in, by examining the very
    -- telepoint the step is about. Live 2026-08-28 they heard ten rows for this
    -- one step: "I don't know if I just have to visit 1 of these, if so you can
    -- make it show just the places you need to visit."
    --
    -- The compact progression action already says which noun is the target of
    -- THIS action: examine-object -> Shattered Telepoint. "Hall of
    -- Transference" belongs to the step's other action (enter-through) and
    -- "Large Apparatus" to no action at all. So the separator is the action's
    -- own target, not the prose and not the zone list -- LandSandBoat confirms
    -- Hall of Transference and Leujaoam Sanctum are both real zones, so "is it
    -- a zone?" cannot tell them apart, while their action roles can (sol).
    --
    -- This evidence was already computed and already used to narrow -- but only
    -- when a zone had been INHERITED from a previous step. The identical
    -- reasoning holds wherever the step names its own zones, which is the case
    -- here, so the gate is on the geography rather than on the logic.
    --
    -- Still narrow only when the narrowed lookup actually finds something:
    -- #scoped > 0 below guards the return, so a step whose proven target
    -- resolves to nothing falls through to the paths it always used and cannot
    -- lose a destination it would otherwise have offered.
    local primary_evidence =
        M.current_step_primary_evidence(
            step,
            entity_keys,
            action,
            ctx);

    if (next(zone_ids) ~= nil) then
        local scoped_entity_keys =
            entity_keys;
        local scoped_global_rows =
            global_rows;
        local scoped_stats =
            candidate_stats;
        local scoped_labels =
            labels;

        -- Once the current step proves one target, an incidental noun in the
        -- same zones cannot answer first.
        if (type(primary_evidence)
                    == 'table'
                and type(primary_evidence.primary)
                    == 'table') then
            local primary =
                primary_evidence.primary;

            scoped_entity_keys = {
                [primary.key] = primary.label,
            };
            scoped_global_rows, _, _, scoped_stats =
                M.collect_entity_rows(
                    scoped_entity_keys,
                    action,
                    ctx);
            scoped_labels = {
                primary.label,
            };
        end

        local scoped =
            M.entity_rows_in_zones(
                zone_ids,
                scoped_entity_keys,
                action,
                ctx);

        if (#scoped > 0) then
            local narrowed_zones =
                authoritative_zones;
            local narrowed_by =
                authoritative_basis;
            local base_kind = 'explicit';

            if (context_zone ~= nil) then
                narrowed_zones = {
                    [context_zone] = true,
                };
                narrowed_by =
                    'inherited-guide-zone';
                base_kind = 'inherited';
            end

            local resolved, resolved_info =
                M.finalize_entity_candidates(
                    step,
                    combine_rows(
                        scoped_global_rows,
                        scoped),
                    ctx,
                    {
                        base_kind = base_kind,
                        authoritative_zones =
                            narrowed_zones,
                        narrowed_by =
                            narrowed_by,
                        inherited_zone =
                            context_zone,
                        inherited_from =
                            context_from,
                        labels = scoped_labels,
                        stats = scoped_stats,
                    });

            if (type(primary_evidence)
                        == 'table'
                    and type(primary_evidence.primary)
                        == 'table') then
                resolved_info.primary_target_source =
                    primary_evidence.primary.source;
            end

            return resolved, resolved_info;
        end
    end

    -- The mission's reviewed nation context may narrow a duplicate only when
    -- the player or the step supplies evidence for that nation.
    local group_evidence = false;
    if (type(ctx.default_zone_group) == 'table'
        and next(zone_ids) == nil) then
        local player_zone =
            tonumber(ctx.player_zone) or 0;

        for _, id in ipairs(ctx.default_zone_group) do
            if (id == player_zone) then
                group_evidence = true;
            end
        end
        if (#nation_ids > 0) then
            group_evidence = true;
        end
    end

    if (group_evidence) then
        local group = {};
        for _, id in ipairs(ctx.default_zone_group) do
            group[id] = true;
        end

        local group_zone = nil;
        local ambiguous = false;

        for key in pairs(entity_keys) do
            local points =
                list(ctx.points_for_entity(key));

            if (#points == 0
                and PERSON_ACTIONS[action]) then
                points =
                    M.points_for_entity_alias(ctx, key);
            end

            local zones = {};
            for _, point in ipairs(points) do
                if (ctx.kind_allowed(
                    action,
                    ctx.effective_kind(point))) then
                    local zone =
                        tonumber(point.zone) or 0;
                    if (group[zone]) then
                        zones[zone] = true;
                    end
                end
            end

            local count = set_count(zones);
            if (count == 1) then
                local zone = only_key(zones);
                if (group_zone ~= nil
                    and group_zone ~= zone) then
                    ambiguous = true;
                end
                group_zone = group_zone or zone;
            elseif (count > 1) then
                ambiguous = true;
            end
        end

        if (group_zone ~= nil and not ambiguous) then
            local scoped =
                M.entity_rows_in_zones(
                    { [group_zone] = true },
                    entity_keys,
                    action,
                    ctx);

            if (#scoped > 0) then
                return M.finalize_entity_candidates(
                    step,
                    combine_rows(global_rows, scoped),
                    ctx,
                    {
                        base_kind = 'nation-group',
                        authoritative_zones =
                            { [group_zone] = true },
                        narrowed_by = 'nation-group',
                        inherited_zone = group_zone,
                        inherited_from = 'nation-group',
                        labels = labels,
                        stats = candidate_stats,
                    });
            end
        end
    end

    if (next(zone_ids) ~= nil) then
        local resolution_entity_keys =
            entity_keys;

        if (context_zone ~= nil
                and type(primary_evidence)
                    == 'table'
                and type(primary_evidence.primary)
                    == 'table') then
            local primary =
                primary_evidence.primary;

            resolution_entity_keys = {
                [primary.key] = primary.label,
            };
        end

        if (context_zone ~= nil) then
            local prior =
                M.prior_instances(
                    steps,
                    index,
                    resolution_entity_keys,
                    ctx);
            local prior_targets, prior_info =
                M.finalize_prior_candidates(
                    step,
                    prior,
                    resolution_entity_keys,
                    action,
                    ctx);

            if (prior_targets ~= nil) then
                if (type(primary_evidence)
                        == 'table'
                        and type(primary_evidence.primary)
                            == 'table') then
                    prior_info.primary_target_source =
                        primary_evidence.primary.source;

                    local displaced = true;

                    for _, point in ipairs(
                            prior_targets) do
                        if (tonumber(point.zone)
                                == tonumber(
                                    context_zone)) then
                            displaced = false;
                        end
                    end

                    prior_info.inherited_context_conflict =
                        displaced;

                    if (displaced) then
                        prior_info
                            .overridden_inherited_zone =
                                context_zone;
                    end
                end

                return prior_targets, prior_info;
            end
        end

        do
            local role_targets, role_info =
                M.role_targets(
                    step,
                    resolution_entity_keys,
                    ctx);

            if (role_targets ~= nil) then
                return role_targets,
                    M.attach_guide_metadata(
                        role_info,
                        step);
            end
        end

        if (context_zone ~= nil
                and type(primary_evidence)
                    == 'table'
                and primary_evidence.binding
                    == nil) then
            local primary_targets, primary_info =
                M.resolve_inherited_compact_primary(
                    step,
                    action,
                    ctx,
                    primary_evidence,
                    context_zone,
                    context_from);

            if (primary_targets ~= nil) then
                return primary_targets,
                    primary_info;
            end
        end

        if (GUIDE_ZONE_ACTIONS[action]) then
            local named, spoken =
                M.step_named_zones(step, ctx);

            if (#named > 0) then
                local zone_targets, zone_info =
                    M.guide_zone_fallback(
                        step, ctx, named, spoken);
                return zone_targets,
                    M.attach_guide_metadata(
                        zone_info, step);
            elseif (#nation_ids > 0) then
                local districts = {};
                for _, id in ipairs(nation_ids) do
                    districts[#districts + 1] =
                        clean(ctx.zone_name(id));
                end

                local zone_targets, zone_info =
                    M.guide_zone_fallback(
                        step,
                        ctx,
                        nation_ids,
                        districts);
                return zone_targets,
                    M.attach_guide_metadata(
                        zone_info, step);
            end
        end

        -- An inherited zone that lacks the entity is a source conflict. A
        -- global name search must never silently replace the guide context.
        info.reason = M.REASONS.ENTITY_ABSENT;

        if (context_zone ~= nil) then
            info.detail =
                ('the guide does not say where %s is for this step')
                    :format(
                        table.concat(labels, ', '));
        else
            local zone_names = {};
            for zone in pairs(zone_ids) do
                zone_names[#zone_names + 1] =
                    readable_zone(ctx, zone);
            end
            table.sort(zone_names);

            info.detail =
                ('I have no indexed location for %s in %s')
                    :format(
                        table.concat(labels, ', '),
                        table.concat(
                            zone_names, ' or '));
        end
        return targets, info;
    end

    -- No authoritative context: expose candidates instead of converting
    -- duplicate names into a terminal refusal.
    if (#global_rows > 0) then
        return M.finalize_entity_candidates(
            step,
            global_rows,
            ctx,
            {
                base_kind = 'catalogue-unique',
                labels = labels,
                stats = candidate_stats,
            });
    end

    do
        local role_targets, role_info =
            M.role_targets(step, entity_keys, ctx);
        if (role_targets ~= nil) then
            return role_targets,
                M.attach_guide_metadata(
                    role_info, step);
        end
    end

    if (#absent > 0) then
        info.reason = M.REASONS.ENTITY_ABSENT;
        info.detail =
            ('I have no indexed location for %s')
                :format(table.concat(absent, ', '));
    elseif (#wrong_kind > 0) then
        info.reason = M.REASONS.NO_DESTINATION;
        info.detail =
            ('%s is not something a %s step can walk to')
                :format(
                    table.concat(wrong_kind, ', '),
                    action ~= ''
                        and action or 'guide');
    elseif (info.reason == nil) then
        info.reason = M.REASONS.NO_DESTINATION;
        info.detail = M.no_destination_detail(step);
    elseif (info.reason
        == M.REASONS.ZONE_CONTEXT_MISSING) then
        info.detail =
            ('the guide does not say which zone %s is in')
                :format(table.concat(labels, ', '));
    else
        info.detail =
            ('the zone for %s is ambiguous in the guide')
                :format(table.concat(labels, ', '));
    end

    return targets, info;
end

-- Resolve one step. Returns targets (possibly empty) and an info table:
--   info.kind   = 'explicit' | 'inherited' | 'catalogue-unique' | 'zone-travel' | 'none'
--   info.reason = one of M.REASONS when targets is empty
--   info.detail = human text for logs/speech
function M.resolve_step(steps, index, ctx)
    local step = steps[index];
    local targets = {};
    local info = M.new_resolution_info(step);
    if (type(step) ~= 'table') then
        info.reason = M.REASONS.NO_DESTINATION;
        return targets, info;
    end
    if (clean(step.comparison):lower() == 'conflict') then
        local conflicted, conflicted_info =
            M.resolve_source_conflict_step(steps, index, ctx);
        -- A DISAGREEMENT IS STILL NOT A REASON TO HIDE THE STEP.
        -- RoV 7 step-001 is flagged conflict on target_identity, yet BOTH
        -- pages name the same Oaken Door -- they differ only in what they say
        -- comes of it ("to Gilgamesh's room" against "a cutscene and the key
        -- item Rhapsody in White"). Reading each page alone finds no target on
        -- either, so the conflict path refuses, and the compact action that
        -- names the door outright is never consulted. Live 2026-08-23 that
        -- left the player with no route at all in Norg.
        if (type(conflicted) ~= 'table' or #conflicted == 0) then
            local rescued, rescued_info = M.resolve_compact_action_rescue(
                step, clean(step.action):lower(), ctx);
            if (rescued ~= nil) then
                return rescued, M.attach_guide_metadata(rescued_info, step);
            end
        end
        return conflicted, conflicted_info;
    end

    local action = clean(step.action):lower();

    if (action == 'note') then
        return M.resolve_note_step(
            steps,
            index,
            ctx);
    end

    -- A BINDING BEATS A GUESS. Where the guide never named the target, a
    -- reviewed row says which catalogued place it meant. Checked before any
    -- zone fallback, because "go to Bastok" is what this exists to replace.
    if (type(ctx.step_target_binding) == 'function') then
        local ok_bind, bound = pcall(ctx.step_target_binding, clean(step.stable_step_id));
        if (ok_bind and type(bound) == 'table' and clean(bound.target) ~= '') then
            local rows = list(ctx.points_for_entity(
                type(ctx.name_key) == 'function' and ctx.name_key(bound.target)
                    or clean(bound.target):lower()));
            local picked = {};
            for _, point in ipairs(rows) do
                if ((tonumber(point.zone) or 0) == (tonumber(bound.zone) or 0)) then
                    picked[#picked + 1] = point;
                end
            end
            if (#picked > 0) then
                local bound_targets, bound_info = M.finalize_entity_candidates(
                    step, picked, ctx, { base_kind = 'step-binding' });
                if (bound_targets ~= nil and #bound_targets > 0) then
                    return bound_targets, M.attach_guide_metadata(bound_info, step);
                end
            end
        end
    end

    local zone_ids,
        entity_keys,
        zone_order,
        nation_ids =
            M.classify_step(step, ctx);
    -- "Head to Xarcabard with Sneak up": Sneak is not a place. Only names in
    -- the closed spell/ability/status/supply registry are set aside as
    -- modifiers; an unknown absent name stays a real (absent) entity, because
    -- a thin catalogue gives the same signal as a modifier would (sol).
    local modifiers_removed = 0;
    local entities_before = 0;
    for key in pairs(entity_keys) do
        entities_before = entities_before + 1;
        if (M.is_modifier_term(key)) then
            entity_keys[key] = nil;
            modifiers_removed = modifiers_removed + 1;
        end
    end
    local has_entities = next(entity_keys) ~= nil;
    if (not has_entities and modifiers_removed > 0 and modifiers_removed == entities_before
        and next(zone_ids) == nil and #nation_ids == 0) then
        -- "Bring Silent Oil", "cast Sneak": supplies or spells only, nowhere
        -- to walk. An instruction, not a refusal.
        info.reason = M.REASONS.NO_DESTINATION;
        info.modifier_only = true;
        info.detail = 'only supplies or spells are named';
        return targets, info;
    end

    if (has_entities) then
        return M.resolve_entity_step(
            steps,
            index,
            step,
            ctx,
            zone_ids,
            entity_keys,
            zone_order,
            nation_ids,
            action,
            info);
    end

    -- No entities and only a nation named: one zone-travel target per
    -- reachable district, spoken as choices. The progression's recorded
    -- destination (a specific district) still wins through
    -- step_destination_zone when it exists.
    if (next(zone_ids) == nil and #nation_ids > 0) then
        local recorded = M.step_destination_zone(step, ctx);
        local districts = recorded ~= nil and { recorded } or nation_ids;
        local player_zone = tonumber(ctx.player_zone) or 0;
        local last_reason = nil;

        -- A NATION YOU ARE STANDING IN IS SATISFIED, NOT A DEAD END.
        --
        -- Live 2026-08-25, San d'Oria mission 6 "Journey Abroad" step-007: "Go
        -- to Bastok first and then to Windurst." Both nations are named, so
        -- `districts` holds every Bastok district AND every Windurst district.
        -- The player stood in Bastok Markets, the loop below matched the very
        -- first district equal to their zone, and RETURNED -- refusing the whole
        -- step with "you are already in Bastok Markets" and never once offering
        -- Windurst, which is the half they still had to do.
        --
        -- Arriving in Bastok answers Bastok. It says nothing about Windurst.
        -- So drop the nation underfoot and carry on with what is left; the
        -- original refusal still stands when NOTHING is left, which is the case
        -- that rule was written for.
        local nation_of = type(ctx.nation_of_zone) == 'function'
            and ctx.nation_of_zone or nil;
        local player_nation = nation_of ~= nil and clean(nation_of(player_zone)) or '';
        -- CORRECTED 2026-08-25: do NOT drop the nation underfoot. Standing in
        -- Bastok does not mean Bastok is FINISHED -- the player still had an NPC
        -- to talk to there, and hiding it pushed them toward Windurst with work
        -- outstanding. "Don't be trying to take me to windurst when I haven't
        -- even finished the steps here yet." A nation is listed until the step
        -- itself advances; arrival is not completion.
        --
        -- What the earlier loop must still not do is ABORT on the nation
        -- underfoot, refusing the whole step and hiding the other nation too.
        -- That is handled by the per-district check below, which now skips
        -- rather than returns.

        -- Standing in one of the districts answers the step outright, so it is
        -- checked before any searching is paid for (sol).
        -- IS THE WHOLE STEP ABOUT THE NATION UNDERFOOT?
        --
        -- If the guide names ONE nation and the player is standing in it, they
        -- have arrived and "you are already in X" is the right answer. If it
        -- names TWO -- "Go to Bastok first and then to Windurst" -- then being
        -- in Bastok says nothing about Windurst, and refusing the whole step
        -- hides the half still to do. Live 2026-08-25 that refused in Bastok
        -- Markets and never mentioned Windurst at all.
        --
        -- And the reverse mistake, made an hour later: DROPPING Bastok because
        -- they stood in it pushed them at Windurst while they still had an NPC
        -- to talk to in Bastok. "Don't be trying to take me to windurst when I
        -- haven't even finished the steps here yet." Arrival is not completion,
        -- so a nation stays listed until the step itself advances.
        local foreign_district = false;
        if (player_nation ~= '' and nation_of ~= nil) then
            for _, district in ipairs(districts) do
                if (clean(nation_of(district)) ~= player_nation) then
                    foreign_district = true;
                end
            end
        end
        for _, district in ipairs(districts) do
            if (district == player_zone and not foreign_district) then
        -- ARRIVING IN THE ZONE IS NOT DOING THE STEP.
        --
        -- Live 2026-08-24, The Davoi Report step-016: "Examine the Door: Papal
        -- Chambers, which is on the top floor of the Cathedral in Northern San
        -- d'Oria." The step's entities hold only the ZONE, so standing in it
        -- answered the step and it refused -- "you are already in Northern San
        -- d'Oria" -- while the door stood at (130.3, 122.3) and the player had
        -- no idea where to walk.
        --
        -- The guide's own compact action names it outright (claim-03: action
        -- examine, target "Door: Papal Chambers", objects { "Door: Papal
        -- Chambers" }). Being in the right zone is exactly when that target
        -- matters most, so ask for it before saying there is nowhere to go.
                local inside, inside_info = M.resolve_compact_action_rescue(
                    step, action, ctx);
                if (inside ~= nil) then
                    return inside, M.attach_guide_metadata(inside_info, step);
                end
                local square = table.concat(list(step.grid_coordinates), ', ');
                info.reason = M.REASONS.ALREADY_IN_ZONE;
                info.detail = ('you are already in %s'):format(clean(ctx.zone_name(district)))
                    .. (square ~= '' and ('; the guide places this at square %s, which is not mapped yet'):format(square) or '');
                return {}, info;
            end
        end
        -- ONE WAY IN PER NATION. The guide named NATIONS, not districts, so
        -- offering four Windurst entrances is the same answer written four
        -- times -- and the player has to arrow past all of them. Windurst has
        -- four districts and Bastok three; without this a single step offers
        -- seven choices for what the guide describes as two places.
        local entry_choices = M.choose_entry_edges(districts, step, ctx);
        local district_nation_taken = {};
        for _, district in ipairs(districts) do
            local district_nation = nation_of ~= nil and clean(nation_of(district)) or '';
            if (district_nation ~= '' and district_nation_taken[district_nation]) then
                -- Already offering a way into this nation.
            else
                local choice = entry_choices[district] or {};
                local edge, reason = choice.edge, choice.reason;
                if (edge ~= nil) then
                    targets[#targets + 1] = M.zone_travel_target(district, edge, ctx);
                    if (district_nation ~= '') then
                        district_nation_taken[district_nation] = true;
                    end
                else
                    last_reason = reason;
                end
            end
        end
        if (#targets > 0) then
            info.kind = #targets > 1 and 'zone-travel-choice' or 'zone-travel';
            info.reason = nil;
            return targets, info;
        end
        info.reason = last_reason or M.REASONS.NO_ZONE_CHAIN;
        info.detail = 'no known zone-line chain to any district from here';
        return targets, info;
    end

    -- No entities: a zone-travel step, or nothing to route. "Talk to the
    -- guards in Ru'Lude Gardens" written with only the zone is still "get to
    -- Ru'Lude Gardens"; any positional action with a zone and no entity is
    -- carried to that zone, where the instruction does the rest.
    if (next(zone_ids) ~= nil) then
        local dest_zone, ambiguous = M.step_destination_zone(step, ctx);
        if (dest_zone == nil) then
            dest_zone = (not ambiguous and #zone_order == 1) and zone_order[1] or nil;
        end
        if (dest_zone == nil) then
            info.reason = M.REASONS.ZONE_CONTEXT_AMBIGUOUS;
            info.detail = 'the guide names more than one destination zone';
            return targets, info;
        end
        local edge, reason, all_edges = M.choose_entry_edge(dest_zone, step, ctx);
        if (edge == nil) then
            if (reason == M.REASONS.ALREADY_IN_ZONE) then
    -- ARRIVING IN THE ZONE IS NOT DOING THE STEP.
    --
    -- Live 2026-08-24, The Davoi Report step-016: "Examine the Door: Papal
    -- Chambers, which is on the top floor of the Cathedral in Northern San
    -- d'Oria." The step's entities hold only the ZONE, so standing in it
    -- answered the step and it refused -- "you are already in Northern San
    -- d'Oria" -- while the door stood at (130.3, 122.3) and the player had
    -- no idea where to walk.
    --
    -- The guide's own compact action names it outright (claim-03: action
    -- examine, target "Door: Papal Chambers", objects { "Door: Papal
    -- Chambers" }). Being in the right zone is exactly when that target
    -- matters most, so ask for it before saying there is nowhere to go.
                local inside, inside_info = M.resolve_compact_action_rescue(
                    step, action, ctx);
                if (inside ~= nil) then
                    return inside, M.attach_guide_metadata(inside_info, step);
                end
            end
            info.reason = reason;
            local zone_name = clean(ctx.zone_name(dest_zone));
            if (reason == M.REASONS.ALREADY_IN_ZONE) then
                info.detail = ('you are already in %s'):format(zone_name);
            else
                info.detail = ('no known zone-line chain to %s from here'):format(zone_name);
            end
            return targets, info;
        end
        local square = table.concat(list(step.grid_coordinates), ', ');
        if (reason == M.REASONS.EXIT_SQUARE_UNRESOLVED and type(all_edges) == 'table' and #all_edges > 1) then
            -- Partial credit (sol): nothing is chosen for the player, but the
            -- guide's square is still unresolved. Each entrance names where it
            -- comes from, and the limitation is spoken with it.
            for _, e in ipairs(all_edges) do
                local target = M.zone_travel_target(dest_zone, e, ctx);
                local from_name = clean(ctx.zone_name(tonumber(e.from_zone) or 0));
                if (from_name ~= '') then
                    target.name = ('%s entrance from %s'):format(target.zone_name, from_name);
                end
                target.choice_note = ('The guide names square %s, which is not mapped yet; this is one of %d entrances.'):format(square, #all_edges);
                targets[#targets + 1] = target;
            end
            info.kind = 'zone-travel-choice';
            info.destination_zone = dest_zone;
            info.unbound_square = square;
            info.partial = 'unbound-square';
            info.reason = nil;
            return targets, info;
        end
        targets[1] = M.zone_travel_target(dest_zone, edge, ctx);
        info.kind = 'zone-travel';
        info.destination_zone = dest_zone;
        info.reason = nil;
        if (not M.is_zone_changing_action(action) and action ~= '') then
            -- "Examine ... in Northern San d'Oria (M-6)": the zone is reached,
            -- the interaction spot inside it is not resolved.
            info.partial = 'zone-only';
            targets[1].choice_note = square ~= ''
                and ('The guide places this at square %s of %s, which is not mapped yet.'):format(square, targets[1].zone_name)
                or ('The guide does not say where in %s.'):format(targets[1].zone_name);
        end
        return targets, info;
    end

    -- Everything above has refused. Before telling the player there is
    -- nowhere to go, ask the guide's own structured action what it named.
    local rescued, rescued_info = M.resolve_compact_action_rescue(step, action, ctx);
    if (rescued ~= nil) then
        return rescued, M.attach_guide_metadata(rescued_info, step);
    end

    info.reason = M.REASONS.NO_DESTINATION;
    info.detail = M.no_destination_detail(step);
    return targets, info;
end

-- Ruling 4 (sol), corrected after review: the progression cursor is the
-- single authority, and a routable TRAVEL step must not be reached by
-- skipping an acquisition the candidate EXPLICITLY depends on. Sequence is
-- not requiredness -- The Davoi Report lists Silent Oil and Prism Powder as
-- a precaution, and an earlier "obtain" with a material verb proved nothing.
-- The data carries no required/optional flag, so the only dependency this
-- honours is an explicit link: an item or key item the earlier action
-- obtains (items, key_items, result_items) that the candidate action itself
-- lists among its items or key items. Everything else never blocks.
-- `owned_fn(action)` answers from live inventory/key-item state and is
-- evidence of possession now, nothing more. Returns the blocking action.
local ACQUISITION_ACTIONS = { obtain = true, farm = true, trade = true, fight = true, use = true, examine = true };

local function requirement_names(action)
    local names = {};
    for _, field in ipairs({ 'items', 'key_items', 'result_items' }) do
        for _, entry in ipairs(list(action[field])) do
            local name = clean(type(entry) == 'table' and (entry.name or entry.item or entry.key_item) or entry):lower();
            if (name ~= '') then names[name] = true; end
        end
    end
    return names;
end

function M.blocking_prerequisite(actions, completed_order, candidate_step_id, owned_fn)
    completed_order = tonumber(completed_order) or 0;
    candidate_step_id = clean(candidate_step_id);
    local candidate = nil;
    for _, action in ipairs(list(actions)) do
        if (clean(action.step_id) == candidate_step_id) then
            candidate = action;
            break;
        end
    end
    if (candidate == nil) then
        return nil;
    end
    local candidate_order = tonumber(candidate.step_order) or 0;
    local needs = {};
    for _, field in ipairs({ 'items', 'key_items' }) do
        for _, entry in ipairs(list(candidate[field])) do
            local name = clean(type(entry) == 'table' and (entry.name or entry.item or entry.key_item) or entry):lower();
            if (name ~= '') then needs[name] = true; end
        end
    end
    if (next(needs) == nil) then
        return nil;   -- the candidate declares no requirement; nothing can block it
    end
    for _, action in ipairs(list(actions)) do
        local order = tonumber(action.step_order) or 0;
        if (order > completed_order and order < candidate_order
            and action.material ~= false
            and ACQUISITION_ACTIONS[clean(action.action):lower()]) then
            local provides = requirement_names(action);
            local linked = false;
            for name in pairs(needs) do
                if (provides[name]) then linked = true; break; end
            end
            if (linked and owned_fn(action) ~= true) then
                return action;
            end
        end
    end
    return nil;
end

function M.prerequisite_refusal(blocking, travel_step)
    local names = {};
    for _, entry in ipairs(list(blocking.items)) do
        names[#names + 1] = clean(type(entry) == 'table' and (entry.name or entry.item) or entry);
    end
    for _, entry in ipairs(list(blocking.key_items)) do
        names[#names + 1] = clean(type(entry) == 'table' and (entry.name or entry.key_item) or entry);
    end
    local what = #names > 0 and table.concat(names, ' and ') or 'the items it lists';
    local where = clean(type(travel_step) == 'table' and travel_step.primary_instruction or '');
    return {
        reason = 'prerequisite-pending',
        detail = ('the guide says to %s %s before %s'):format(
            clean(blocking.action):lower() ~= '' and clean(blocking.action):lower() or 'get',
            what,
            where ~= '' and where:lower():gsub('%.$', '') or 'travelling on'),
        blocking_step_id = clean(blocking.step_id),
    };
end

-- Speech for a refusal: concise, names the failure class, never the generic
-- sentence. IDs stay in the log.
-- What the guide says, attributed, as its own sentence.
--
-- "Guide:" marks it as the page speaking rather than the addon reporting live
-- state, which matters because a guide line can be stale while everything the
-- addon observes is current. Text is passed through unchanged apart from
-- terminal punctuation -- never paraphrased, never summarised, never merged
-- with our own words.
function M.guide_sentence(instruction)
    instruction = clean(instruction);
    if (instruction == '') then
        return '';
    end
    if (not instruction:find('[%.%?!]$')) then
        instruction = instruction .. '.';
    end
    return ('Guide: %s'):format(instruction);
end

-- A refusal downgrades the ROUTE. It must not downgrade the INFORMATION.
--
-- Live 2026-08-22 this said "No route for The Davoi Report: this step has no
-- destination in the guide. Press K for instructions." and stopped -- while
-- the step it was refusing read "Click on it to receive the key item Lost
-- document", and the guide had said where: near the platform on the small pond.
-- The player was told a route had failed and never told what the page said.
function M.refusal_speech(title, info, instruction)
    local detail = clean(type(info) == 'table' and info.detail or '');
    if (detail == '') then
        detail = 'this step has no destination in the guide';
    end
    if (clean(instruction) == '') then
        instruction = type(info) == 'table' and info.instruction or '';
    end
    local guide = M.guide_sentence(instruction);
    if (guide ~= '') then
        return ('No route for %s: %s. %s Press K for instructions.'):format(
            clean(title), detail, guide);
    end
    return ('No route for %s: %s. Press K for instructions.'):format(clean(title), detail);
end

if (type(accessxi) == 'table') then
    accessxi.mission_step_resolver = M;
end
return M;
