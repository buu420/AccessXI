local dynamic = {};

local function identity_label(entry, detail)
    if (type(entry) == 'table') then
        local label = tostring(entry.en or entry.english or entry.name or '');
        if (label ~= '') then
            return label;
        end
    end
    if (type(detail) == 'table') then
        return tostring(detail.en or detail.english or detail.name or '');
    end
    return '';
end

function dynamic.build_owned_rows(owned_ids, resource, details, order, category_overrides, requested_category)
    owned_ids = type(owned_ids) == 'table' and owned_ids or {};
    resource = type(resource) == 'table' and resource or {};
    details = type(details) == 'table' and details or {};
    order = type(order) == 'table' and order or {};
    category_overrides = type(category_overrides) == 'table' and category_overrides or {};
    requested_category = tostring(requested_category or '');

    local rows = {};
    local unresolved = {};
    for _, raw_id in ipairs(owned_ids) do
        local id = tonumber(raw_id) or -1;
        local entry = resource[id];
        local detail = details[id];
        local category = tostring(category_overrides[id]
            or (type(entry) == 'table' and entry.category)
            or '');
        local label = identity_label(entry, detail);
        local display_order = tonumber(order[id]);
        if (id < 0 or category == '' or label == '' or display_order == nil) then
            unresolved[#unresolved + 1] = {
                id = id,
                category = category,
                label = label,
                order = display_order,
            };
        elseif (category:lower() == requested_category:lower()) then
            rows[#rows + 1] = {
                id = id,
                category = category,
                label = label,
                order = display_order,
            };
        end
    end

    table.sort(rows, function (a, b)
        if (a.order == b.order) then
            return a.id < b.id;
        end
        return a.order < b.order;
    end);
    table.sort(unresolved, function (a, b)
        return a.id < b.id;
    end);
    return rows, unresolved;
end

function dynamic.resolve_selected_row(rows, zero_based_index, unresolved)
    rows = type(rows) == 'table' and rows or {};
    unresolved = type(unresolved) == 'table' and unresolved or {};
    if (#unresolved > 0) then
        return nil, 'unresolved-owned-identity';
    end
    local index = tonumber(zero_based_index);
    if (index == nil or index < 0 or index ~= math.floor(index)) then
        return nil, 'invalid-selection';
    end
    local row = rows[index + 1];
    if (type(row) ~= 'table') then
        return nil, 'selection-out-of-range';
    end
    return row, 'packet-owned+dat-order+identity-complete';
end

return dynamic;
