local module_path = assert(arg[1], 'Expected key-items dynamic rows module path.')
local chunk, load_error = loadfile(module_path)
assert(chunk ~= nil, load_error)

local dynamic = chunk()
assert(type(dynamic) == 'table', 'Expected dynamic key-items module table.')
assert(type(dynamic.build_owned_rows) == 'function', 'Expected build_owned_rows function.')
assert(type(dynamic.resolve_selected_row) == 'function', 'Expected resolve_selected_row function.')
assert(type(dynamic.build_category_rows) == 'function', 'Expected native-data category row builder.')
assert(type(dynamic.classify_native_view) == 'function', 'Expected native evitem view classifier.')

assert(dynamic.classify_native_view(1) == 'categories', 'Expected native evitem state 1 to identify category headers.')
assert(dynamic.classify_native_view(2) == 'items', 'Expected native evitem state 2 to identify key-item rows.')
assert(dynamic.classify_native_view(0) == nil, 'Expected an inactive evitem state to stay silent.')
assert(dynamic.classify_native_view(3) == nil, 'Expected a transitional evitem state to stay silent.')

local category_resource = {
    [1] = { en = 'temporary one', category = 'Temporary Key Items' },
    [2] = { en = 'permanent one', category = 'Permanent Key Items' },
    [3] = { en = 'map one', category = 'Magical Maps' },
}
local category_order = {
    [1] = 10,
    [2] = 30,
    [3] = 20,
}
local category_rows = dynamic.build_category_rows(category_resource, category_order)
assert(#category_rows == 3, 'Expected categories to be derived from current native resources, not a fixed count.')
assert(category_rows[1].label == 'Temporary Key Items', 'Expected category order to follow native DAT order.')
assert(category_rows[2].label == 'Magical Maps', 'Expected the second native-data category.')
assert(category_rows[3].label == 'Permanent Key Items', 'Expected the third native-data category.')

category_resource[4] = { en = 'future one', category = 'Future Key Items' }
category_order[4] = 40
local grown_category_rows = dynamic.build_category_rows(category_resource, category_order)
assert(#grown_category_rows == 4, 'Expected a newly added native category to appear without changing code.')
assert(grown_category_rows[4].label == 'Future Key Items', 'Expected the new native-data category in DAT order.')

local resource = {
    [8] = { en = 'airship pass', category = 'Permanent Key Items' },
    [5000] = { en = 'future permanent token', category = 'Permanent Key Items' },
}
local details = {
    [3361] = { name = 'cipher bracelet' },
}
local order = {
    [8] = 1635,
    [3361] = 2020,
    [5000] = 2021,
}
local category_overrides = {
    [3361] = 'Permanent Key Items',
}

local rows, unresolved = dynamic.build_owned_rows(
    { 8, 3361 },
    resource,
    details,
    order,
    category_overrides,
    'Permanent Key Items')
assert(#rows == 2, 'Expected two packet-owned permanent identities.')
assert(#unresolved == 0, 'Expected every owned identity to resolve.')
assert(rows[1].id == 8 and rows[1].label == 'airship pass', 'Expected DAT order to place airship pass first.')
assert(rows[2].id == 3361 and rows[2].label == 'cipher bracelet', 'Expected DAT fallback to resolve cipher bracelet.')

local selected, mode = dynamic.resolve_selected_row(rows, 1, unresolved)
assert(selected ~= nil and selected.id == 3361, 'Expected live absolute selection to resolve cipher bracelet.')
assert(mode == 'packet-owned+dat-order+identity-complete', 'Expected identity-complete resolver mode.')

local grown_rows, grown_unresolved = dynamic.build_owned_rows(
    { 8, 3361, 5000 },
    resource,
    details,
    order,
    category_overrides,
    'Permanent Key Items')
assert(#grown_rows == 3, 'Expected the list to grow from the live owned-ID set without a fixed total.')
assert(#grown_unresolved == 0, 'Expected the grown owned-ID set to remain fully resolved.')
local grown_selected = dynamic.resolve_selected_row(grown_rows, 2, grown_unresolved)
assert(grown_selected ~= nil and grown_selected.id == 5000, 'Expected the newly owned identity at its DAT position.')

local unsafe_rows, unsafe_unresolved = dynamic.build_owned_rows(
    { 8, 3361, 6000 },
    resource,
    details,
    order,
    category_overrides,
    'Permanent Key Items')
assert(#unsafe_unresolved == 1 and unsafe_unresolved[1].id == 6000, 'Expected an unrecognized owned ID to remain unresolved.')
local unsafe_selected, unsafe_mode = dynamic.resolve_selected_row(unsafe_rows, 0, unsafe_unresolved)
assert(unsafe_selected == nil, 'Expected silence when any owned identity could shift the selected row.')
assert(unsafe_mode == 'unresolved-owned-identity', 'Expected explicit unresolved-identity safety mode.')

print('Dynamic permanent key-items behavior checks passed')
