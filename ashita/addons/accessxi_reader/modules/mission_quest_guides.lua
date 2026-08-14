local module = {};

local function clean(value)
    return tostring(value or ''):gsub('[\t\r\n]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '');
end

local function valid_identity(value)
    value = clean(value):lower();
    return value:match('^[a-z0-9_%-]+:%d+$') ~= nil;
end

local function valid_native_key(value)
    value = clean(value);
    return value:match('^mission:[^:]+:%d+$') ~= nil
        or value:match('^quest:[^:]+:%d+$') ~= nil;
end

local function copy_table(value)
    if (type(value) ~= 'table') then
        return nil;
    end
    local result = {};
    for key, item in pairs(value) do
        result[key] = item;
    end
    return result;
end

local function deep_copy(value, seen)
    if (type(value) ~= 'table') then
        return value;
    end
    seen = seen or {};
    if (seen[value] ~= nil) then
        return seen[value];
    end
    local result = {};
    seen[value] = result;
    for key, item in pairs(value) do
        result[deep_copy(key, seen)] = deep_copy(item, seen);
    end
    return result;
end

local function finite_number(value)
    value = tonumber(value);
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge;
end

local function positive_integer(value)
    value = tonumber(value);
    return value ~= nil and value >= 1 and value == math.floor(value);
end

local function exact_source_authority(value)
    return type(value) == 'table'
        and clean(value.primary) == 'bg'
        and clean(value.fallback) == 'ffxiclopedia';
end

local function exact_progression_schema(value)
    return tonumber(value) == 2 and tonumber(value) == math.floor(tonumber(value));
end

local function progression_action_less(left, right)
    local left_step = tonumber(left.step_order) or 0;
    local right_step = tonumber(right.step_order) or 0;
    if (left_step ~= right_step) then return left_step < right_step; end
    local left_action = tonumber(left.action_order) or 0;
    local right_action = tonumber(right.action_order) or 0;
    if (left_action ~= right_action) then return left_action < right_action; end
    return clean(left.action_id) < clean(right.action_id);
end

local function valid_catalogue_point(point)
    if (type(point) ~= 'table') then return false; end
    local coordinates = point.target_point;
    return clean(point.destination_id) ~= ''
        and positive_integer(point.zone_id)
        and clean(point.zone_name) ~= ''
        and clean(point.target_name) ~= ''
        and clean(point.target_kind) ~= ''
        and clean(point.target_key) ~= ''
        and clean(point.raw_identity) ~= ''
        and type(coordinates) == 'table'
        and #coordinates == 3
        and finite_number(coordinates[1])
        and finite_number(coordinates[2])
        and finite_number(coordinates[3]);
end

local function validate_progression_action(row)
    if (type(row) ~= 'table' or row.material ~= true
        or clean(row.step_id) == '' or not positive_integer(row.step_order)
        or clean(row.action_id) == '' or not positive_integer(row.action_order)
        or not positive_integer(row.order)
        or clean(row.action) == '' or clean(row.relationship) == ''
        or type(row.field_sources) ~= 'table'
        or type(row.source_revisions) ~= 'table'
        or type(row.source_action_span_ids) ~= 'table'
        or #row.source_action_span_ids == 0
        or type(row.catalogue) ~= 'table'
        or (clean(row.source_authority) ~= 'bg'
            and clean(row.source_authority) ~= 'ffxiclopedia')) then
        return nil, clean(row.relationship) == '' and 'relationship is unavailable'
            or 'action schema is invalid';
    end

    local target = clean(row.target);
    local target_key = clean(row.target_key);
    local instruction = clean(row.instruction);
    local instruction_source = clean(row.field_sources.instruction);
    local target_has_key_material = target:match('[%w]') ~= nil;
    if (target == '' and target_key ~= '')
        or (target_key == '' and target_has_key_material) then
        return nil, 'target key is unavailable';
    end
    if (target_key == '' and (instruction == ''
        or (instruction_source ~= 'bg' and instruction_source ~= 'ffxiclopedia'))) then
        return nil, 'target and authoritative instruction are unavailable';
    end

    local required_count = tonumber(row.required_count);
    if (required_count == nil or required_count < 1
        or required_count ~= math.floor(required_count)) then
        return nil, 'action count is invalid';
    end
    local count_mode = clean(row.count_mode);
    local action = clean(row.action):lower();
    local relationship = clean(row.relationship):lower();
    if (count_mode == 'single') then
        if (required_count ~= 1) then return nil, 'single action count is invalid'; end
    elseif (count_mode == 'credited-defeat') then
        if (action ~= 'fight' or relationship:find('defeat', 1, true) == nil
            or row.count_explicit ~= true or required_count <= 1) then
            return nil, 'credited-defeat count is incompatible with the action';
        end
    elseif (count_mode == 'inventory-gain') then
        if (action ~= 'obtain' or relationship:find('item', 1, true) == nil
            or relationship:find('key%-item') ~= nil
            or type(row.items) ~= 'table' or #row.items == 0
            or type(row.key_items) == 'table' and #row.key_items > 0
            or row.count_explicit ~= true or required_count <= 1) then
            return nil, 'inventory-gain count is incompatible with the action';
        end
    else
        return nil, 'action count mode is invalid';
    end

    local destination_name = clean(row.destination_zone_name);
    local destination_id = tonumber(row.destination_zone_id) or 0;
    if ((destination_name == '') ~= (destination_id <= 0)) then
        return nil, 'destination zone pair is invalid';
    end
    for _, point in ipairs(row.catalogue) do
        if (not valid_catalogue_point(point)) then
            return nil, 'catalogue destination is invalid';
        end
    end
    return true;
end

local function step_policy_text(step)
    local parts = {
        clean(type(step) == 'table' and step.primary_instruction or ''),
        clean(type(step) == 'table' and step.bg_instruction or ''),
        clean(type(step) == 'table' and step.ffxiclopedia_instruction or ''),
    };
    for _, field in ipairs({ 'entities', 'items', 'key_items' }) do
        for _, value in ipairs(type(step) == 'table' and type(step[field]) == 'table'
            and step[field] or {}) do
            parts[#parts + 1] = clean(type(value) == 'table'
                and (value.name or value.item or value.key_item) or value);
        end
    end
    return clean(table.concat(parts, ' ')):lower();
end

local function optional_shortcut_step(step, text)
    local action = clean(type(step) == 'table' and step.action or ''):lower();
    if (text:find('shortcut', 1, true) ~= nil
        or text:find('fastest', 1, true) ~= nil
        or text:find('faster route', 1, true) ~= nil) then
        return true;
    end
    return (action == 'travel' or action == 'use')
        and (text:find('warp', 1, true) ~= nil
            or text:find('teleport', 1, true) ~= nil
            or text:find('home point', 1, true) ~= nil
            or text:find('survival guide', 1, true) ~= nil
            or text:find('unity', 1, true) ~= nil);
end

local route_recommendation_items = {
    ['silent oil'] = 'Recommended: carry Silent Oil. Use it before entering areas with sound-detecting enemies to avoid aggro.',
    ['prism powder'] = 'Recommended: carry Prism Powder. Use it before entering areas with sight-detecting enemies to avoid aggro.',
};

local function route_recommendation(step, text)
    local advisory = text:find('precaution', 1, true) ~= nil
        or text:find('may want', 1, true) ~= nil
        or text:find('recommend', 1, true) ~= nil
        or text:find('suggest', 1, true) ~= nil
        or text:find('advisable', 1, true) ~= nil
        or text:find('should have', 1, true) ~= nil
        or text:find('be sure to have', 1, true) ~= nil
        or text:find('handy', 1, true) ~= nil
        or text:find('bring', 1, true) ~= nil
        or text:find('carry', 1, true) ~= nil
        or text:find('optional', 1, true) ~= nil
        or (text:find('silent oil', 1, true) ~= nil
            and (text:find('sneak', 1, true) ~= nil
                or text:find('sound', 1, true) ~= nil
                or text:find('aggro', 1, true) ~= nil))
        or (text:find('prism powder', 1, true) ~= nil
            and (text:find('invisible', 1, true) ~= nil
                or text:find('sight', 1, true) ~= nil
                or text:find('aggro', 1, true) ~= nil));
    if (not advisory) then return nil; end
    for item, instruction in pairs(route_recommendation_items) do
        if (text:find(item, 1, true) ~= nil) then
            return {
                item = item == 'silent oil' and 'Silent Oil' or 'Prism Powder',
                instruction = instruction,
                stable_step_id = clean(type(step) == 'table' and step.stable_step_id or ''),
                order = tonumber(type(step) == 'table' and step.order or nil) or 0,
            };
        end
    end
    return nil;
end

local function explicitly_optional_step(step, text)
    local action = clean(type(step) == 'table' and step.action or ''):lower();
    local optional = text:match('^optionally[%s,:%?%-]') ~= nil
        or text:match('^optional[%s:%?%-]') ~= nil
        or text:find('(optional', 1, true) ~= nil
        or text:find('non-essential', 1, true) ~= nil
        or text:find('extra dialogue', 1, true) ~= nil
        or text:find('additional dialogue', 1, true) ~= nil;
    local optional_map = action == 'obtain'
        and text:find('map of ', 1, true) ~= nil
        and optional;
    return optional or optional_map;
end

local function apply_step_policy(step)
    local text = step_policy_text(step);
    local recommendation = route_recommendation(step, text);
    if (recommendation ~= nil) then
        step.route_recommendation = true;
        step.optional_nonessential = true;
        step.recommendation_item = recommendation.item;
        step.recommendation_instruction = recommendation.instruction;
        return recommendation;
    end
    if (optional_shortcut_step(step, text)) then
        step.optional_shortcut = true;
        return nil;
    end
    if (explicitly_optional_step(step, text)) then
        step.optional_nonessential = true;
    end
    return nil;
end

local function array_value_count(values, expected)
    local count = 0;
    for _, value in ipairs(type(values) == 'table' and values or {}) do
        if (clean(value) == expected) then
            count = count + 1;
        end
    end
    return count;
end

local function source_spans_belong_to(candidate, ledger)
    local candidate_spans = type(candidate.source_action_span_ids) == 'table'
        and candidate.source_action_span_ids or {};
    local ledger_spans = type(ledger.source_action_span_ids) == 'table'
        and ledger.source_action_span_ids or {};
    if (#candidate_spans == 0 or #ledger_spans == 0) then
        return false;
    end
    local seen = {};
    for _, value in ipairs(candidate_spans) do
        local span_id = clean(value);
        if (span_id == '' or seen[span_id] or array_value_count(ledger_spans, span_id) ~= 1) then
            return false;
        end
        seen[span_id] = true;
    end
    return true;
end

local function unique_nonempty_values(values)
    if (type(values) ~= 'table' or #values == 0) then
        return false;
    end
    local seen = {};
    for _, value in ipairs(values) do
        local key = clean(value);
        if (key == '' or seen[key]) then
            return false;
        end
        seen[key] = true;
    end
    return true;
end

local function exact_claim_step(progression, action_id, action)
    local owner_step = nil;
    local owner_count = 0;
    local claim_steps = type(progression.claims) == 'table' and progression.claims
        or (type(progression.steps) == 'table' and progression.steps or {});
    for _, step in ipairs(claim_steps) do
        for _, claim in ipairs(type(step.typed_claims) == 'table' and step.typed_claims or {}) do
            if (clean(claim.stable_claim_id) == action_id) then
                owner_count = owner_count + 1;
                if (clean(claim.action) ~= action) then
                    return nil;
                end
                owner_step = step;
            end
        end
    end
    if (owner_count ~= 1 or type(owner_step) ~= 'table'
        or clean(owner_step.stable_step_id) == '') then
        return nil;
    end
    return owner_step;
end

local function reviewed_candidate_copy(progression, candidate)
    if (type(candidate) ~= 'table') then
        return nil;
    end
    local candidate_id = clean(candidate.candidate_id);
    local action_id = clean(candidate.action_id);
    local action = clean(candidate.action);
    local arrival_instruction = clean(candidate.arrival_instruction);
    if (candidate_id == '' or action_id == '' or action == '' or arrival_instruction == '') then
        return nil;
    end

    local owner = nil;
    local owner_count = 0;
    for _, ledger in ipairs(type(progression.action_resolution_ledger) == 'table'
        and progression.action_resolution_ledger or {}) do
        local occurrences = array_value_count(ledger.candidate_ids, candidate_id);
        if (occurrences > 0) then
            owner_count = owner_count + occurrences;
            owner = ledger;
        end
    end
    if (owner_count ~= 1 or clean(owner.action_id) ~= action_id
        or clean(owner.action) ~= action or not source_spans_belong_to(candidate, owner)) then
        return nil;
    end

    local guide_step = exact_claim_step(progression, action_id, action);
    if (guide_step == nil) then
        return nil;
    end

    local result = deep_copy(candidate);
    result.classification = 'catalogue-candidate';
    result.guide_step_id = clean(guide_step.stable_step_id);
    result.guide_step_order = tonumber(guide_step.order) or 0;
    -- This candidate-specific text is for speech only. Route authorization is
    -- owned by the separately validated runtime contract index.
    result.action_instruction = arrival_instruction;
    return result;
end

local function reviewed_instruction_copy(progression, ledger)
    if (type(ledger) ~= 'table'
        or clean(ledger.status) ~= 'instruction-only'
        or clean(ledger.reason) ~= 'complete-instruction'
        or ledger.material ~= true
        or ledger.route_ready == true
        or type(ledger.candidate_ids) ~= 'table'
        or #ledger.candidate_ids ~= 0
        or not unique_nonempty_values(ledger.source_action_span_ids)) then
        return nil;
    end
    local action_id = clean(ledger.action_id);
    local action = clean(ledger.action);
    local instruction = clean(ledger.instruction);
    if (action_id == '' or action == '' or instruction == '') then
        return nil;
    end
    local guide_step = exact_claim_step(progression, action_id, action);
    if (guide_step == nil or clean(guide_step.comparison):lower() == 'conflict') then
        return nil;
    end
    return {
        candidate_id = '',
        action_id = action_id,
        source_action_span_ids = deep_copy(ledger.source_action_span_ids),
        action = action,
        status = 'instruction-only',
        reason = 'complete-instruction',
        material = true,
        group_id = '',
        destination_id = '',
        guide_step_id = clean(guide_step.stable_step_id),
        guide_step_order = tonumber(guide_step.order) or 0,
        action_instruction = instruction,
        instruction_only = true,
        classification = 'instruction-only',
        route_ready = false,
    };
end

local function objective_destination_less(left, right)
    local left_order = tonumber(left.guide_step_order) or 0;
    local right_order = tonumber(right.guide_step_order) or 0;
    if (left_order ~= right_order) then
        return left_order < right_order;
    end
    for _, field in ipairs({ 'action_id', 'group_id', 'candidate_id' }) do
        local left_value = clean(left[field]);
        local right_value = clean(right[field]);
        if (left_value ~= right_value) then
            return left_value < right_value;
        end
    end
    return false;
end

local function source_instruction(source, order)
    order = tonumber(order) or 0;
    if (type(source) ~= 'table' or type(source.steps) ~= 'table' or order <= 0) then
        return '';
    end
    local step = source.steps[order];
    return clean(type(step) == 'table' and step.instruction or '');
end

local function source_step_values(source, order, field)
    order = tonumber(order) or 0;
    if (type(source) ~= 'table' or type(source.steps) ~= 'table'
        or order <= 0 or type(field) ~= 'string') then
        return {};
    end
    local step = source.steps[order];
    local values = type(step) == 'table' and step[field] or nil;
    return type(values) == 'table' and deep_copy(values) or {};
end

local function preferred_source_step_values(sources, orders, field)
    local bg_values = source_step_values(sources.bg, orders[1], field);
    if (#bg_values > 0) then
        return bg_values;
    end
    return source_step_values(sources.ffxiclopedia, orders[2], field);
end

local GuideState = {};
GuideState.__index = GuideState;

function GuideState:log(text)
    if (type(self.logger) == 'function') then
        pcall(self.logger, clean(text));
    end
end

function GuideState:identity()
    if (type(self.identity_provider) ~= 'function') then
        return '';
    end
    local ok, value = pcall(self.identity_provider);
    if (not ok) then
        return '';
    end
    value = clean(value):lower();
    return valid_identity(value) and value or '';
end

function GuideState:index_entry(native_key)
    native_key = clean(native_key);
    local entry = type(self.index) == 'table' and self.index[native_key] or nil;
    return type(entry) == 'table' and entry or nil;
end

function GuideState:load_module(name)
    name = clean(name);
    if (name == '') then
        return nil, 'module name unavailable';
    end
    local cached = self.module_cache[name];
    if (cached ~= nil) then
        if (cached == false) then
            return nil, self.module_errors[name] or 'module unavailable';
        end
        return cached;
    end
    if (type(self.module_loader) ~= 'function') then
        self.module_cache[name] = false;
        self.module_errors[name] = 'module loader unavailable';
        return nil, self.module_errors[name];
    end
    local ok, data = pcall(self.module_loader, name);
    if (not ok or type(data) ~= 'table') then
        self.module_cache[name] = false;
        self.module_errors[name] = clean(ok and 'module returned no table' or data);
        self:log(('objective guide module failed name="%s" reason="%s"'):format(
            name,
            self.module_errors[name]));
        return nil, self.module_errors[name];
    end
    self.module_cache[name] = data;
    return data;
end

local function trim_lru(cache, limit, protected_key)
    local entries = {};
    for key, value in pairs(cache) do
        entries[#entries + 1] = {
            key = key,
            last_used = tonumber(type(value) == 'table' and value.last_used or 0) or 0,
        };
    end
    table.sort(entries, function(left, right)
        if (left.last_used ~= right.last_used) then
            return left.last_used < right.last_used;
        end
        return tostring(left.key) < tostring(right.key);
    end);
    local remove_count = math.max(0, #entries - math.max(0, tonumber(limit) or 0));
    for _, entry in ipairs(entries) do
        if (remove_count <= 0) then break; end
        if (entry.key ~= protected_key) then
            cache[entry.key] = nil;
            remove_count = remove_count - 1;
        end
    end
end

function GuideState:touch_progression_module(module_name, envelope)
    self.progression_module_use_counter = self.progression_module_use_counter + 1;
    self.progression_module_cache[module_name] = envelope;
    self.progression_module_use[module_name] = {
        last_used = self.progression_module_use_counter,
    };
    trim_lru(self.progression_module_use, self.progression_module_cache_limit, module_name);
    local retained = {};
    for name in pairs(self.progression_module_use) do retained[name] = true; end
    for name in pairs(self.progression_module_cache) do
        if (not retained[name]) then self.progression_module_cache[name] = nil; end
    end
end

function GuideState:trim_progression_objectives(protected_key)
    trim_lru(self.progression_objective_cache, self.progression_cache_limit, protected_key);
end

function GuideState:progression_actions(native_key)
    native_key = clean(native_key);
    local entry = self:index_entry(native_key);
    if (entry == nil) then
        return nil, 'progression objective is absent from the native guide index';
    end
    if (not exact_source_authority(entry.source_authority)) then
        return nil, 'progression source authority is unavailable';
    end
    if (not exact_progression_schema(entry.progression_schema_version)) then
        return nil, 'progression index schema is unsupported';
    end
    local module_name = clean(entry.progression_module);
    local revision = clean(entry.progression_revision);
    if (module_name == '' or revision == '') then
        return nil, module_name == '' and 'progression module is unavailable'
            or 'progression revision is unavailable';
    end

    local cached = self.progression_objective_cache[native_key];
    if (type(cached) == 'table'
        and (clean(cached.module_name) ~= module_name
            or clean(cached.revision) ~= revision)) then
        self.progression_objective_cache[native_key] = nil;
        cached = nil;
    end
    if (type(cached) == 'table') then
        self.progression_use_counter = self.progression_use_counter + 1;
        cached.last_used = self.progression_use_counter;
        local cached_envelope = self.progression_module_cache[cached.module_name];
        if (type(cached_envelope) == 'table') then
            self:touch_progression_module(cached.module_name, cached_envelope);
        end
        return deep_copy(cached.actions);
    end

    local envelope = self.progression_module_cache[module_name];
    if (envelope == nil) then
        local ok, loaded = pcall(self.module_loader, module_name);
        if (not ok or type(loaded) ~= 'table') then
            return nil, ('progression module is unavailable: %s'):format(
                clean(ok and 'module returned no table' or loaded));
        end
        envelope = loaded;
    end
    self:touch_progression_module(module_name, envelope);
    if (not exact_progression_schema(envelope.schema_version)) then
        return nil, 'progression shard schema is unsupported';
    end
    if (clean(envelope.module_name) ~= module_name) then
        return nil, 'progression shard module self-pin is invalid';
    end
    if (not exact_source_authority(envelope.source_authority)) then
        return nil, 'progression shard source authority is invalid';
    end
    local objective = type(envelope.objectives) == 'table'
        and envelope.objectives[native_key] or nil;
    if (type(objective) ~= 'table') then
        return nil, 'progression objective is unavailable from the shard';
    end
    if (clean(objective.native_key) ~= native_key) then
        return nil, 'progression objective native self-pin is invalid';
    end
    if (clean(objective.progression_module) ~= module_name) then
        return nil, 'progression objective module self-pin is invalid';
    end
    if (not exact_progression_schema(objective.progression_schema_version)) then
        return nil, 'progression objective schema self-pin is invalid';
    end
    if (not exact_source_authority(objective.source_authority)) then
        return nil, 'progression objective source authority is invalid';
    end
    if (clean(objective.progression_revision) ~= revision) then
        return nil, 'progression objective revision self-pin is invalid';
    end

    local actions = {};
    local ids, global_orders, step_orders = {}, {}, {};
    for _, row in ipairs(type(objective.progression_actions) == 'table'
        and objective.progression_actions or {}) do
        local valid, reason = validate_progression_action(row);
        if (not valid) then return nil, reason; end
        local action_id = clean(row.action_id);
        local global_order = tonumber(row.order);
        local step_key = clean(row.step_id) .. '\t' .. tostring(tonumber(row.action_order));
        if (ids[action_id] or global_orders[global_order] or step_orders[step_key]) then
            return nil, 'duplicate progression action ID or order';
        end
        ids[action_id] = true;
        global_orders[global_order] = true;
        step_orders[step_key] = true;
        actions[#actions + 1] = deep_copy(row);
    end
    table.sort(actions, progression_action_less);
    for index, row in ipairs(actions) do
        if (tonumber(row.order) ~= index) then
            return nil, 'progression action order is not contiguous';
        end
    end

    self.progression_use_counter = self.progression_use_counter + 1;
    self.progression_objective_cache[native_key] = {
        actions = actions,
        module_name = module_name,
        revision = revision,
        last_used = self.progression_use_counter,
    };
    self:trim_progression_objectives(native_key);
    return deep_copy(actions);
end

function GuideState:retain_progression_keys(active_keys)
    active_keys = type(active_keys) == 'table' and active_keys or {};
    local retained, count = {}, 0;
    local active = {};
    for key, value in pairs(active_keys) do
        local native_key = type(key) == 'number' and clean(value) or clean(key);
        if (native_key ~= '' and type(self.progression_objective_cache[native_key]) == 'table') then
            active[#active + 1] = native_key;
        end
    end
    table.sort(active);
    for _, native_key in ipairs(active) do
        if (not retained[native_key] and count < self.progression_cache_limit) then
            retained[native_key] = true;
            count = count + 1;
        end
    end

    local extras = {};
    for native_key, cached in pairs(self.progression_objective_cache) do
        if (not retained[native_key]) then
            extras[#extras + 1] = {
                native_key = native_key,
                last_used = tonumber(cached.last_used) or 0,
            };
        end
    end
    table.sort(extras, function(left, right)
        if (left.last_used ~= right.last_used) then
            return left.last_used > right.last_used;
        end
        return left.native_key < right.native_key;
    end);
    for _, extra in ipairs(extras) do
        if (count >= self.progression_cache_limit) then break; end
        retained[extra.native_key] = true;
        count = count + 1;
    end
    for native_key in pairs(self.progression_objective_cache) do
        if (not retained[native_key]) then
            self.progression_objective_cache[native_key] = nil;
        end
    end
    -- Compact shards are extraction inputs, not live reducer state.  Dropping
    -- them here keeps the large module retention bounded independently of the
    -- small per-objective action cache.
    self.progression_module_cache = {};
    self.progression_module_use = {};
    return count;
end

function GuideState:resolve(native_key)
    native_key = clean(native_key);
    local cached = self.resolution_cache[native_key];
    if (cached ~= nil) then
        if (cached.available == true) then
            return cached;
        end
        return nil, cached.reason;
    end

    local entry = self:index_entry(native_key);
    if (entry == nil) then
        return nil, 'objective is absent from the native guide index';
    end
    local authority = type(entry.source_authority) == 'table' and entry.source_authority or {};
    if (clean(authority.primary) ~= 'bg' or clean(authority.fallback) ~= 'ffxiclopedia') then
        local reason = ('Objective source authority is unavailable for %s.'):format(native_key);
        self.resolution_cache[native_key] = { available = false, reason = reason };
        return nil, reason;
    end
    local reconciliation_name = clean(entry.reconcile_module);
    local reconciliation_module, reconciliation_error = self:load_module(reconciliation_name);
    local reconciliation = type(reconciliation_module) == 'table'
        and reconciliation_module[native_key] or nil;
    if (type(reconciliation) ~= 'table' or type(reconciliation.steps) ~= 'table') then
        local reason = ('Reconciliation chunk unavailable for %s: %s'):format(
            native_key,
            clean(reconciliation_error));
        self.resolution_cache[native_key] = { available = false, reason = reason };
        return nil, reason;
    end

    -- Compact generated guide shards carry source speech directly.  Keep this
    -- compatibility path only for legacy/custom indexes that predate them.
    local sources = {};
    local need_legacy_sources = false;
    for _, pair in ipairs(reconciliation.steps) do
        if (clean(pair.bg_instruction) == '' and clean(pair.ffxiclopedia_instruction) == '') then
            need_legacy_sources = true;
            break;
        end
    end
    if (need_legacy_sources) then
        local source_modules = type(entry.source_modules) == 'table' and entry.source_modules or {};
        for _, site in ipairs({ 'bg', 'ffxiclopedia' }) do
            local source_module_name = clean(source_modules[site]);
            if (source_module_name ~= '') then
                local source_module, source_error = self:load_module(source_module_name);
                local source = type(source_module) == 'table' and source_module[native_key] or nil;
                if (type(source) ~= 'table') then
                    local reason = ('%s source chunk unavailable for %s: %s'):format(
                        site, native_key, clean(source_error));
                    self.resolution_cache[native_key] = { available = false, reason = reason };
                    return nil, reason;
                end
                sources[site] = source;
            end
        end
    end

    local steps = {};
    local source_steps = {};
    local route_recommendations = {};
    for _, pair in ipairs(reconciliation.steps) do
        local orders = type(pair.source_orders) == 'table' and pair.source_orders or {};
        local bg_instruction = clean(pair.bg_instruction);
        local ffxiclopedia_instruction = clean(pair.ffxiclopedia_instruction);
        if (bg_instruction == '' and ffxiclopedia_instruction == '') then
            bg_instruction = source_instruction(sources.bg, orders[1]);
            ffxiclopedia_instruction = source_instruction(sources.ffxiclopedia, orders[2]);
        end
        if (bg_instruction == '' and ffxiclopedia_instruction == '') then
            local reason = ('Reconciled step %s has no source instruction.'):format(
                clean(pair.stable_step_id));
            self.resolution_cache[native_key] = { available = false, reason = reason };
            return nil, reason;
        end
        local step = {
            stable_step_id = clean(pair.stable_step_id),
            order = tonumber(pair.order) or (#source_steps + 1),
            comparison = clean(pair.comparison),
            conflicting_fields = type(pair.conflicting_fields) == 'table'
                and deep_copy(pair.conflicting_fields) or {},
            action = clean(pair.action),
            entities = type(pair.entities) == 'table' and deep_copy(pair.entities) or {},
            zones = type(pair.zones) == 'table' and deep_copy(pair.zones) or {},
            grid_coordinates = type(pair.grid_coordinates) == 'table'
                and deep_copy(pair.grid_coordinates) or {},
            items = type(pair.items) == 'table' and deep_copy(pair.items)
                or preferred_source_step_values(sources, orders, 'items'),
            key_items = type(pair.key_items) == 'table' and deep_copy(pair.key_items)
                or preferred_source_step_values(sources, orders, 'key_items'),
            field_sources = type(pair.field_sources) == 'table'
                and deep_copy(pair.field_sources) or {},
            route_ready = pair.route_ready == true,
            navigation_target = deep_copy(pair.navigation_target),
            bg_instruction = bg_instruction,
            ffxiclopedia_instruction = ffxiclopedia_instruction,
            primary_instruction = bg_instruction ~= '' and bg_instruction or ffxiclopedia_instruction,
        };
        local recommendation = apply_step_policy(step);
        source_steps[#source_steps + 1] = step;
        if (recommendation ~= nil) then
            route_recommendations[#route_recommendations + 1] = recommendation;
        elseif (step.optional_nonessential ~= true) then
            local visible = deep_copy(step);
            if (visible.optional_shortcut == true) then
                visible.primary_instruction = 'Shortcut. ' .. visible.primary_instruction;
            end
            steps[#steps + 1] = visible;
        end
    end
    -- Attach each preparation recommendation to one route segment instead of
    -- repeating it for every later objective.  Prefer the next source-backed
    -- routable destination; if the corpus has no exact destination yet, use
    -- the next material non-optional step as a conservative fallback.
    for _, recommendation in ipairs(route_recommendations) do
        local recommendation_order = tonumber(recommendation.order) or 0;
        local fallback_order = nil;
        for _, step in ipairs(source_steps) do
            local step_order = tonumber(step.order) or 0;
            local action = clean(step.action):lower();
            if (step_order > recommendation_order
                and action ~= '' and action ~= 'note'
                and step.optional_nonessential ~= true
                and step.route_recommendation ~= true
                and step.optional_shortcut ~= true) then
                fallback_order = fallback_order or step_order;
                if (step.route_ready == true) then
                    recommendation.route_order = step_order;
                    break;
                end
            end
        end
        recommendation.route_order = tonumber(recommendation.route_order)
            or fallback_order or recommendation_order;
    end
    if (#source_steps == 0) then
        local reason = ('No ordered walkthrough steps are available for %s.'):format(native_key);
        self.resolution_cache[native_key] = { available = false, reason = reason };
        return nil, reason;
    end

    local resolved = {
        available = true,
        native_key = native_key,
        title = clean(entry.title),
        status = clean(entry.status),
        sources = sources,
        reconciliation = reconciliation,
        steps = steps,
        source_steps = source_steps,
        route_recommendations = route_recommendations,
        progression_module = clean(entry.progression_module),
        source_authority = deep_copy(authority),
        progression_revision = clean(entry.progression_revision),
    };
    self.resolution_cache[native_key] = resolved;
    return resolved;
end

function GuideState:load_manual_steps()
    if (self.manual_loaded) then
        return;
    end
    self.manual_loaded = true;
    if (self.manual_path == '') then
        return;
    end
    local file = io.open(self.manual_path, 'r');
    if (file == nil) then
        return;
    end
    for line in file:lines() do
        local identity, native_key, index = tostring(line or ''):match('^([^\t]+)\t([^\t]+)\t(%d+)$');
        index = tonumber(index);
        identity = clean(identity):lower();
        native_key = clean(native_key);
        if (valid_identity(identity) and valid_native_key(native_key)
            and index ~= nil and index >= 1) then
            self.manual_steps[identity .. '\t' .. native_key] = index;
        end
    end
    file:close();
end

function GuideState:save_manual_step(native_key, index)
    local identity = self:identity();
    native_key = clean(native_key);
    index = tonumber(index) or 0;
    if (identity == '' or not valid_native_key(native_key) or index < 1) then
        return false;
    end
    self:load_manual_steps();
    local key = identity .. '\t' .. native_key;
    self.manual_steps[key] = index;
    if (self.manual_path == '') then
        return true;
    end
    local file = io.open(self.manual_path, 'a');
    if (file == nil) then
        self:log(('objective guide manual step write failed path="%s"'):format(self.manual_path));
        return false;
    end
    file:write(identity, '\t', native_key, '\t', tostring(index), '\n');
    file:close();
    return true;
end

function GuideState:is_open()
    return type(self.selected_objective) == 'table' and self.selected_native_key ~= '';
end

function GuideState:close(reason)
    local was_open = self:is_open();
    self.selected_objective = nil;
    self.selected_native_key = '';
    self.selected_index = 0;
    if (was_open) then
        self:log(('objective guide closed reason="%s"'):format(clean(reason)));
    end
    return was_open;
end

function GuideState:sync_identity()
    local current = self:identity();
    if (self.tracked_identity == '') then
        self.tracked_identity = current;
        return false;
    end
    if (current == self.tracked_identity) then
        return false;
    end
    self:close('character-changed');
    self.tracked_identity = current;
    if (type(self.on_character_change) == 'function') then
        pcall(self.on_character_change, current);
    end
    return true;
end

function GuideState:open(native_key, automatic_step_id)
    self:sync_identity();
    local identity = self:identity();
    if (identity == '') then
        return nil, 'Current character identity is unavailable.';
    end
    local objective, reason = self:resolve(native_key);
    if (objective == nil) then
        return nil, reason;
    end
    local selected = 0;
    automatic_step_id = clean(automatic_step_id);
    if (automatic_step_id ~= '') then
        for index, step in ipairs(objective.steps) do
            if (step.stable_step_id == automatic_step_id) then
                selected = index;
                break;
            end
        end
    end
    if (selected == 0) then
        self:load_manual_steps();
        local saved = tonumber(self.manual_steps[identity .. '\t' .. clean(native_key)]) or 0;
        if (saved >= 1 and saved <= #objective.steps) then
            selected = saved;
        end
    end
    if (selected == 0) then
        local default_step_id = clean(objective.reconciliation.default_step_id);
        if (default_step_id ~= '') then
            for index, step in ipairs(objective.steps) do
                if (step.stable_step_id == default_step_id) then
                    selected = index;
                    break;
                end
            end
        end
    end
    if (selected == 0) then
        selected = 1;
    end
    self.selected_native_key = clean(native_key);
    self.selected_objective = objective;
    self.selected_index = selected;
    return objective;
end

function GuideState:step_count()
    return self:is_open() and #self.selected_objective.steps or 0;
end

function GuideState:current_native_key()
    return self:is_open() and self.selected_native_key or '';
end

function GuideState:automatic_step_id(native_key, stage_key)
    local objective = self:resolve(native_key);
    if (objective == nil) then
        return '';
    end
    local stages = type(objective.reconciliation.automatic_stages) == 'table'
        and objective.reconciliation.automatic_stages or {};
    return clean(stages[clean(stage_key)]);
end

function GuideState:objective_destinations(native_key)
    self:sync_identity();
    local objective = self:resolve(native_key);
    local result = {};
    if (objective == nil) then
        return result;
    end
    local progression_name = clean(objective.progression_module);
    if (progression_name ~= '') then
        local actions = self:progression_actions(native_key);
        for _, action in ipairs(type(actions) == 'table' and actions or {}) do
            local catalogue = type(action.catalogue) == 'table' and action.catalogue or {};
            if (#catalogue == 0) then
                result[#result + 1] = {
                    candidate_id = '',
                    action_id = clean(action.action_id),
                    group_id = '', destination_id = '',
                    guide_step_id = clean(action.step_id),
                    guide_step_order = tonumber(action.step_order) or 0,
                    action_order = tonumber(action.action_order) or 0,
                    action = clean(action.action),
                    relationship = clean(action.relationship),
                    action_instruction = clean(action.instruction),
                    instruction_only = true,
                    classification = 'instruction-only',
                    status = 'instruction-only', reason = 'complete-instruction',
                    material = true, route_ready = false,
                    progression_revision = clean(objective.progression_revision),
                    source_authority = clean(action.source_authority),
                    field_sources = deep_copy(action.field_sources),
                };
            else
                for _, point in ipairs(catalogue) do
                    local destination_id = clean(point.destination_id);
                    result[#result + 1] = {
                        candidate_id = clean(point.candidate_id) ~= ''
                            and clean(point.candidate_id)
                            or clean(action.action_id) .. ':candidate:' .. destination_id,
                        action_id = clean(action.action_id),
                        group_id = clean(point.group_id),
                        destination_id = destination_id,
                        guide_step_id = clean(action.step_id),
                        guide_step_order = tonumber(action.step_order) or 0,
                        action_order = tonumber(action.action_order) or 0,
                        action = clean(action.action),
                        relationship = clean(action.relationship),
                        action_instruction = clean(point.arrival_instruction) ~= ''
                            and clean(point.arrival_instruction) or clean(action.instruction),
                        arrival_instruction = clean(point.arrival_instruction) ~= ''
                            and clean(point.arrival_instruction) or clean(action.instruction),
                        classification = 'catalogue-candidate',
                        material = true, route_ready = false,
                        zone = tonumber(point.zone_id) or 0,
                        zone_name = clean(point.zone_name),
                        target_name = clean(point.target_name),
                        target_kind = clean(point.target_kind),
                        target_key = clean(point.target_key),
                        target_point = deep_copy(point.target_point),
                        raw_identity = clean(point.raw_identity),
                        raw_spawn_ids = deep_copy(point.raw_spawn_ids),
                        cluster_policy_version = clean(point.cluster_policy_version),
                        transport_id = clean(point.transport_id),
                        battlefield_id = clean(point.battlefield_id),
                        metadata_class = clean(point.metadata_class),
                        items = deep_copy(action.items),
                        key_items = deep_copy(action.key_items),
                        enemies = deep_copy(action.enemies),
                        destination_zone_name = clean(action.destination_zone_name),
                        destination_zone_id = tonumber(action.destination_zone_id) or 0,
                        progression_revision = clean(objective.progression_revision),
                        source_authority = clean(action.source_authority),
                        field_sources = deep_copy(action.field_sources),
                    };
                end
            end
        end
        table.sort(result, objective_destination_less);
        return result;
    end
    local progression = objective.reconciliation;
    if (type(progression) ~= 'table') then
        return result;
    end
    if (type(progression.objective_destination_candidates) ~= 'table'
        and type(progression.mission_destinations) == 'table') then
        for _, destination in ipairs(progression.mission_destinations) do
            if (type(destination) == 'table') then
                result[#result + 1] = deep_copy(destination);
            end
        end
        return result;
    end
    for _, candidate in ipairs(type(progression.objective_destination_candidates) == 'table'
        and progression.objective_destination_candidates or {}) do
        local copied = reviewed_candidate_copy(progression, candidate);
        if (copied ~= nil) then
            result[#result + 1] = copied;
        end
    end
    for _, ledger in ipairs(type(progression.action_resolution_ledger) == 'table'
        and progression.action_resolution_ledger or {}) do
        local copied = reviewed_instruction_copy(progression, ledger);
        if (copied ~= nil) then
            result[#result + 1] = copied;
        end
    end
    table.sort(result, objective_destination_less);
    return result;
end

function GuideState:source_route_steps(native_key)
    self:sync_identity();
    local objective = self:resolve(native_key);
    local result = {};
    if (objective == nil or type(objective.source_steps) ~= 'table') then
        return result;
    end
    for _, step in ipairs(objective.source_steps) do
        if (type(step) == 'table') then
            result[#result + 1] = deep_copy(step);
        end
    end
    return result;
end

function GuideState:route_recommendations(native_key, through_order)
    self:sync_identity();
    local objective = self:resolve(native_key);
    local result = {};
    if (objective == nil or type(objective.route_recommendations) ~= 'table') then
        return result;
    end
    through_order = tonumber(through_order);
    for _, recommendation in ipairs(objective.route_recommendations) do
        if (type(recommendation) == 'table'
            and (through_order == nil
                or (tonumber(recommendation.route_order) or tonumber(recommendation.order) or 0)
                    == through_order)) then
            result[#result + 1] = deep_copy(recommendation);
        end
    end
    return result;
end

function GuideState:mission_destinations(native_key)
    return self:objective_destinations(native_key);
end

function GuideState:current_index()
    return self:is_open() and self.selected_index or 0;
end

function GuideState:current_step()
    if (not self:is_open()) then
        return nil;
    end
    return self.selected_objective.steps[self.selected_index];
end

function GuideState:route_descriptor()
    local step = self:current_step();
    if (step == nil or type(self.route_resolver) ~= 'function') then
        return nil;
    end
    local ok, descriptor = pcall(
        self.route_resolver,
        self.selected_native_key,
        step.stable_step_id,
        step);
    local wiki_ready = type(descriptor) == 'table'
        and clean(descriptor.mode) == 'wiki-ready'
        and descriptor.objective_wiki_route == true
        and descriptor.wiki_authoritative == true
        and descriptor.verified ~= true
        and tonumber(descriptor.zone) ~= nil and tonumber(descriptor.zone) > 0
        and clean(descriptor.name) ~= '' and clean(descriptor.kind) ~= ''
        and finite_number(descriptor.x) and finite_number(descriptor.z)
        and clean(descriptor.objective_route_contract_id) == '';
    if (not ok or type(descriptor) ~= 'table'
        or (descriptor.verified ~= true and not wiki_ready)) then
        return nil;
    end
    local result = copy_table(descriptor);
    result.guide_step_id = step.stable_step_id;
    result.objective_native_key = self.selected_native_key;
    return result;
end

function GuideState:step_speech()
    local step = self:current_step();
    if (step == nil) then
        return 'No objective step is selected.';
    end
    local prefix = ('Step %d of %d.'):format(self.selected_index, self:step_count());
    local evidence = '';
    local instruction = step.primary_instruction;
    if (step.comparison == 'conflict') then
        instruction = step.bg_instruction ~= '' and step.bg_instruction or step.ffxiclopedia_instruction;
        evidence = ' Source facts conflict.';
    elseif (step.comparison == 'corroborated') then
        evidence = ' Both guides corroborate this step.';
    elseif (step.comparison == 'compatible') then
        evidence = ' Both guides provide compatible guidance.';
    elseif (step.bg_instruction ~= '' and step.ffxiclopedia_instruction == '') then
        evidence = ' BG Wiki guide only.';
    elseif (step.ffxiclopedia_instruction ~= '' and step.bg_instruction == '') then
        evidence = ' FFXIclopedia guide only.';
    else
        evidence = ' Source-backed guidance.';
    end
    local navigation = self:route_descriptor() ~= nil
        and ' Navigation available.'
        or ' Navigation unavailable for this step.';
    return prefix .. ' ' .. instruction .. evidence .. navigation;
end

function GuideState:repeat_step()
    return self:step_speech();
end

function GuideState:move(delta)
    if (not self:is_open()) then
        return 'No objective step is selected.';
    end
    local count = self:step_count();
    delta = tonumber(delta) or 0;
    self.selected_index = ((self.selected_index - 1 + delta) % count) + 1;
    self:save_manual_step(self.selected_native_key, self.selected_index);
    return self:step_speech();
end

function module.new(options)
    options = type(options) == 'table' and options or {};
    local state = setmetatable({
        index = type(options.index) == 'table' and options.index or {},
        module_loader = options.module_loader,
        identity_provider = options.identity_provider,
        route_resolver = options.route_resolver,
        on_character_change = options.on_character_change,
        logger = options.logger,
        manual_path = clean(options.manual_path),
        module_cache = {},
        module_errors = {},
        progression_module_cache = {},
        progression_module_use = {},
        progression_module_use_counter = 0,
        progression_module_cache_limit = 64,
        progression_objective_cache = {},
        progression_use_counter = 0,
        progression_cache_limit = 64,
        resolution_cache = {},
        manual_steps = {},
        manual_loaded = false,
        tracked_identity = '',
        selected_native_key = '',
        selected_objective = nil,
        selected_index = 0,
    }, GuideState);
    state.tracked_identity = state:identity();
    return state;
end

return module;
