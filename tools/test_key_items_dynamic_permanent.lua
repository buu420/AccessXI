local module_path = assert(arg[1], 'Expected key-items dynamic rows module path.')
local chunk, load_error = loadfile(module_path)
assert(chunk ~= nil, load_error)

local dynamic = chunk()
assert(type(dynamic) == 'table', 'Expected dynamic key-items module table.')
assert(type(dynamic.build_owned_rows) == 'function', 'Expected build_owned_rows function.')
assert(type(dynamic.resolve_selected_row) == 'function', 'Expected resolve_selected_row function.')

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
