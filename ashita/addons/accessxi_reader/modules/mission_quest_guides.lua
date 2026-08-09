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

local function source_instruction(source, order)
    order = tonumber(order) or 0;
    if (type(source) ~= 'table' or type(source.steps) ~= 'table' or order <= 0) then
        return '';
    end
    local step = source.steps[order];
    return clean(type(step) == 'table' and step.instruction or '');
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
    local source_modules = type(entry.source_modules) == 'table' and entry.source_modules or {};
    local sources = {};
    local source_count = 0;
    for _, site in ipairs({ 'bg', 'ffxiclopedia' }) do
        local source_module_name = clean(source_modules[site]);
        if (source_module_name ~= '') then
            local source_module, source_error = self:load_module(source_module_name);
            local source = type(source_module) == 'table' and source_module[native_key] or nil;
            if (type(source) ~= 'table') then
                local reason = ('%s source chunk unavailable for %s: %s'):format(
                    site,
                    native_key,
                    clean(source_error));
                self.resolution_cache[native_key] = { available = false, reason = reason };
                return nil, reason;
            end
            sources[site] = source;
            source_count = source_count + 1;
        end
    end
    if (source_count == 0) then
        local reason = ('No source-backed guide is available for %s.'):format(native_key);
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

    local steps = {};
    for _, pair in ipairs(reconciliation.steps) do
        local orders = type(pair.source_orders) == 'table' and pair.source_orders or {};
        local bg_instruction = source_instruction(sources.bg, orders[1]);
        local ffxiclopedia_instruction = source_instruction(sources.ffxiclopedia, orders[2]);
        if (bg_instruction == '' and ffxiclopedia_instruction == '') then
            local reason = ('Reconciled step %s has no source instruction.'):format(
                clean(pair.stable_step_id));
            self.resolution_cache[native_key] = { available = false, reason = reason };
            return nil, reason;
        end
        steps[#steps + 1] = {
            stable_step_id = clean(pair.stable_step_id),
            order = tonumber(pair.order) or (#steps + 1),
            comparison = clean(pair.comparison),
            conflicting_fields = type(pair.conflicting_fields) == 'table'
                and pair.conflicting_fields or {},
            action = clean(pair.action),
            route_ready = pair.route_ready == true,
            navigation_target = copy_table(pair.navigation_target),
            bg_instruction = bg_instruction,
            ffxiclopedia_instruction = ffxiclopedia_instruction,
            primary_instruction = bg_instruction ~= '' and bg_instruction or ffxiclopedia_instruction,
        };
    end
    if (#steps == 0) then
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
    if (step == nil or (step.comparison == 'conflict' and step.route_ready ~= true)
        or type(self.route_resolver) ~= 'function') then
        return nil;
    end
    local ok, descriptor = pcall(
        self.route_resolver,
        self.selected_native_key,
        step.stable_step_id,
        step);
    if (not ok or type(descriptor) ~= 'table' or descriptor.verified ~= true) then
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
        instruction = 'Sources disagree.';
        if (step.bg_instruction ~= '') then
            instruction = instruction .. ' BG Wiki: ' .. step.bg_instruction;
        end
        if (step.ffxiclopedia_instruction ~= '') then
            instruction = instruction .. ' FFXIclopedia: ' .. step.ffxiclopedia_instruction;
        end
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
