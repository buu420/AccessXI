-- A MID-STRING READ MUST NOT OUT-SCORE THE GAME'S OWN CHAIN.
--
-- Live 2026-08-28. The player opened a Survival Guide and instead of the
-- destination option heard "R5!d&." On the same guide, one row over, the log
-- caught the identical failure with a different pointer:
--
--   native query list ... mode=next+088 best=76
--     tries="+000 len=3 score=66 [1:None. | 2:        | 3:] ;
--            +088 len=3 score=76 [1:None. | 2:ersion  | 3:]"
--   state generic-query ... label="ersion" speech="ersion."
--   2026-08-28 18:21:02 ersion.
--
-- The offset scorer awards +10 for any non-empty label, so a pointer landing
-- part-way through some unrelated string beat the real chain, which had
-- honestly reported blanks. Two independent holes let it through:
--
--   1. native_query_label_fragment_penalty only caught a lower-to-upper
--      transition inside an all-alphabetic string ("aBc"). "ersion" is all
--      lower case and "R5!d&" is not all-alphabetic, so BOTH scored a zero
--      penalty.
--   2. The canonical-chain guard read `best_score < canonical + margin`.
--      Canonical 66, alternative 76, margin 10 -- and 76 < 76 is false, so the
--      garbage won on the boundary of the rule written to stop it.
--
-- Drives the REAL functions lifted from the deployed accessxi_reader.lua.
--
--   luajit tools/test_menu_label_garbage.lua
--
-- Exit code 1 on any failed claim.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;
_G.accessxi = {};
_G.T = function (t)
    t = t or {};
    t.len = function (s) return #s end;
    t.append = function (s, v) s[#s + 1] = v end;
    t.concat = function (s, sep) return table.concat(s, sep or '') end;
    return t;
end

-- Ashita's string extensions, which the deployed code assumes exist.
function string.trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')); end
function string.eq(a, b, ci)
    a, b = tostring(a or ''), tostring(b or '');
    if (ci) then return a:lower() == b:lower(); end
    return a == b;
end
function string.contains(a, b, ci)
    a, b = tostring(a or ''), tostring(b or '');
    if (ci) then a, b = a:lower(), b:lower(); end
    return a:find(b, 1, true) ~= nil;
end

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

for _, header in ipairs({
    'function accessxi.survival_guide_text(text)',
    'function accessxi.native_query_label_is_menu_structure(label)',
    'function accessxi.native_query_label_fragment_penalty(label)',
    'function accessxi.native_query_label_looks_real(label)',
    'function accessxi.native_query_score_items(items, expected_count)',
}) do
    local src = lift(header);
    claim(src ~= nil, 'lifted ' .. header:match('accessxi%.([%w_]+)'));
    if (src == nil) then
        print(('menu label garbage: %d passed, %d failed'):format(passed, failed));
        os.exit(1);
    end
    assert(load(src, header))();
end

local penalty = accessxi.native_query_label_fragment_penalty;
local looks_real = accessxi.native_query_label_looks_real;

-- ---------------------------------------------------------------------------
-- 1. THE TWO STRINGS THE PLAYER ACTUALLY HEARD.
-- ---------------------------------------------------------------------------
claim(penalty('ersion') > 0, 'a lower-case opening is penalised, got ' .. penalty('ersion'));
claim(penalty('R5!d&') > 0, '"R5!d&" is penalised, got ' .. penalty('R5!d&'));

-- ...but never silenced. A rejected label is silence, and for this player a
-- wrong word can at least be questioned while silence cannot.
claim(looks_real('ersion') == true, '"ersion" is still speakable rather than dropped to silence');
claim(penalty('ersion') < 90, 'and its penalty stays under the rejection threshold');

-- ---------------------------------------------------------------------------
-- 2. REAL OPTIONS MUST NOT BE PENALISED. Every one of these was read correctly
--    from this very menu system in the same session.
-- ---------------------------------------------------------------------------
local REAL = {
    'Nowhere.', 'La Theine Plateau.', 'Travel Using Tabs.', 'Not Just Yet.',
    'Other Mysteries', 'None.', 'Norvallen.', 'Zulkheim.',
    'Transportation Assistance', 'Home Point #2', "Ru'Lude Gardens",
    "Chateau d'Oraguille", 'Survival Guide', 'Battle Records',
};
for _, label in ipairs(REAL) do
    claim(penalty(label) == 0, ('a real option is not penalised: "%s" got %d'):format(label, penalty(label)));
end
for _, label in ipairs(REAL) do
    if (looks_real(label) ~= true) then
        claim(false, ('a real option stayed speakable: "%s"'):format(label));
    end
end
claim(true, 'and every real option is still speakable');

-- ---------------------------------------------------------------------------
-- 3. THE LIVE CONTEST, REPLAYED. Canonical honestly reports blanks; the
--    alternative reports one garbage string. Canonical must win.
-- ---------------------------------------------------------------------------
local function items(labels, indices)
    local out = T{};
    for i, label in ipairs(labels) do
        out:append({ label = label, index = indices[i] or 0 });
    end
    return out;
end

local canonical = accessxi.native_query_score_items(
    items({ 'None.', '', '' }, { 2049, 39043, 2817 }), 3);
local alternative = accessxi.native_query_score_items(
    items({ 'None.', 'ersion', '' }, { 2049, 39043, 2817 }), 3);

print(('       (canonical=%d alternative=%d)'):format(canonical, alternative));
claim(alternative < canonical + math.max(10, math.floor(canonical * 0.10)),
    'the garbage read no longer clears the canonical margin');

-- The same contest with a genuinely better read must STILL be able to win, or
-- the guard has simply frozen the canonical chain in place.
local genuine = accessxi.native_query_score_items(
    items({ 'None.', 'Transportation Assistance', 'Other Mysteries' }, { 1, 2, 3 }), 3);
claim(genuine > canonical + math.max(10, math.floor(canonical * 0.10)),
    'but a genuinely better read still beats it, got ' .. genuine .. ' vs ' .. canonical);

-- ---------------------------------------------------------------------------
-- 4. THE BOUNDARY. The guard is written "beaten, not merely edged"; a win by
--    EXACTLY the margin is the edge, and it used to be allowed through.
-- ---------------------------------------------------------------------------
local guard = reader:find('if (best_score <= canonical_score + margin) then', 1, true);
claim(guard ~= nil, 'a win by exactly the margin keeps the canonical chain');

-- AN UPGRADED ITEM IS NOT PUNCTUATION SOUP.
--
-- Live 2026-08-29: "when I open some of these treasure caskets, the items
-- literally are silent instead of speaking when I arrow over them." The
-- punctuation-soup clause added on 2026-08-27 to kill "R5!d&." also charged 60
-- to every short label containing a plus -- which is every upgraded item in the
-- game, and a Treasure Casket names its contents in exactly that form. The
-- penalty drove the correct offset chain negative, so it lost the contest to a
-- chain of blanks and the whole casket went silent, clean rows included.
--
--   19:58:54 state generic-query ... title="Treasure Casket" select=2 count=3
--            mode="next+020:missing" label="" help="" helpMode="" speech=""
--
-- "A Potion +3." read correctly on 2026-08-15, before the clause existed.
for _, name in ipairs({ 'An Ether +1.', 'A Potion +3.', 'A Wool Hat.',
                        'An Axe +1.', 'A Bronze Sword +1.' }) do
    claim(accessxi.native_query_label_fragment_penalty(name) == 0,
        ('"%s" is an item name, not soup, penalty=%d'):format(
            name, accessxi.native_query_label_fragment_penalty(name)));
    claim(accessxi.native_query_label_looks_real(name) == true,
        ('and it is still read as real'):format(name));
end

-- The soup this clause exists for is untouched. "R5!d&." is what the player
-- actually heard from a Survival Guide on 2026-08-29 before it was scored down.
for _, garbage in ipairs({ "R5!d&'", 'x?!&', '3:v1 x', 'erf%1a' }) do
    claim(accessxi.native_query_label_fragment_penalty(garbage) >= 60,
        ('"%s" is still penalised, got %d'):format(
            garbage, accessxi.native_query_label_fragment_penalty(garbage)));
end

-- And a plus in a LONG label was never in scope -- the clause only ever looked
-- at twelve characters or fewer, so nothing changes there either way.
claim(accessxi.native_query_label_fragment_penalty(
        'Travel Using 200 Gil. (408023 Gil) +1') < 60,
    'a long label carrying a plus is unaffected');

print(('menu label garbage: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);
