local data = {};

data.menu_categories = T{
    T{ key = 'all', label = 'All' },
    T{ key = 'mission', label = 'Missions' },
    T{ key = 'quest', label = 'Quests' },
    T{ key = 'area', label = 'Areas' },
    T{ key = 'npc', label = 'NPCs' },
    T{ key = 'object', label = 'Objects' },
    T{ key = 'enemy', label = 'Enemies' },
    T{ key = 'nm', label = 'NM Spawns' },
    T{ key = 'live-nm', label = 'Live NM' },
    T{ key = 'player', label = 'Players' },
};

data.mesh_names = T{
    [105] = 'Batallia_Downs.nav',
    [110] = 'Rolanberry_Fields.nav',
    [120] = 'Sauromugue_Champaign.nav',
    [126] = 'Qufim_Island.nav',
    [195] = 'The_Eldieme_Necropolis.nav',
    [230] = 'Southern_San_dOria.nav',
    [231] = 'Northern_San_dOria.nav',
    [232] = 'Port_San_dOria.nav',
    [243] = 'RuLude_Gardens.nav',
    [244] = 'Upper_Jeuno.nav',
    [245] = 'Lower_Jeuno.nav',
    [246] = 'Port_Jeuno.nav',
};

return data;
