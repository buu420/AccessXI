local data = {};

-- Quests overview rows. The live menu supplies selected/count; these rows only
-- provide text for a resolved row. Use ROM offsets where the client exposes the
-- string plainly; otherwise keep the DAT row evidence explicit.
data.main_resource_path = accessxi.ffxi_path('ROM\\97\\40.DAT');
data.main_categories = T{
    [1] = { label = 'Current', offset = 0x000658 },
    [2] = { label = 'Completed', offset = 0x000661 },
    [3] = {
        label = 'Current',
        prefix = 'Records of Eminence',
        offset = 0x000658,
        prefix_path = accessxi.ffxi_path('ROM\\168\\25.DAT'),
        prefix_offset = 0x008B24,
    },
    [4] = { label = 'Objective List', evidence = 'dat:ROM/165/77.DAT#110', context = 'records-of-eminence-objective-list' },
    [5] = { label = "Vana'Bout", evidence = 'dat:ROM/165/77.DAT#520' },
    [6] = { label = 'Sparks', evidence = 'dat:ROM/165/77.DAT#120' },
    [7] = { label = 'Deeds', evidence = 'dat:ROM/165/77.DAT#122' },
};

data.quest_log_resources = T{
    sandoria = {
        label = "San d'Oria",
        path = accessxi.ffxi_path('ROM\\176\\60.DAT'),
    },
    bastok = {
        label = 'Bastok',
        path = accessxi.ffxi_path('ROM\\176\\61.DAT'),
    },
    windurst = {
        label = 'Windurst',
        path = accessxi.ffxi_path('ROM\\176\\62.DAT'),
    },
    jeuno = {
        label = 'Jeuno',
        path = accessxi.ffxi_path('ROM\\176\\63.DAT'),
    },
    other_areas = {
        label = 'Other Areas',
        path = accessxi.ffxi_path('ROM\\176\\64.DAT'),
    },
    outlands = {
        label = 'Outlands',
        path = accessxi.ffxi_path('ROM\\176\\65.DAT'),
    },
    aht_urhgan = {
        label = 'Aht Urhgan',
        path = accessxi.ffxi_path('ROM\\176\\66.DAT'),
    },
    crystal_war = {
        label = 'Crystal War',
        path = accessxi.ffxi_path('ROM\\196\\6.DAT'),
    },
    abyssea = {
        label = 'Abyssea',
        path = accessxi.ffxi_path('ROM\\242\\64.DAT'),
    },
    adoulin = {
        label = 'Adoulin',
        path = accessxi.ffxi_path('ROM\\293\\69.DAT'),
    },
    coalition = {
        label = 'Coalition',
        path = accessxi.ffxi_path('ROM\\293\\70.DAT'),
    },
};

data.quest_log_order = T{
    'sandoria',
    'bastok',
    'windurst',
    'jeuno',
    'other_areas',
    'outlands',
    'aht_urhgan',
    'crystal_war',
    'abyssea',
    'adoulin',
    'coalition',
};

data.quest_log_ports = T{
    sandoria = { current = 0x0050, completed = 0x0090 },
    bastok = { current = 0x0058, completed = 0x0098 },
    windurst = { current = 0x0060, completed = 0x00A0 },
    jeuno = { current = 0x0068, completed = 0x00A8 },
    other_areas = { current = 0x0070, completed = 0x00B0 },
    outlands = { current = 0x0078, completed = 0x00B8 },
    aht_urhgan = { current = 0x0080, completed = 0x00C0 },
    crystal_war = { current = 0x0088, completed = 0x00C8 },
    abyssea = { current = 0x00E0, completed = 0x00E8 },
    adoulin = { current = 0x00F0, completed = 0x00F8 },
    coalition = { current = 0x0100, completed = 0x0108 },
};

data.quest_rom_title_slot_offsets = T{
    { title_offset = 0x00007C, id_offset = 0x00005C, stride = 0x280 },
};

return data;
