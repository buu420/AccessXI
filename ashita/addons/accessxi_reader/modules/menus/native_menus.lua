local data = {};

data.search_condition_family_menus = T{
    'menu    scsibori',
    'menu    searchma',
    'menu    searchjo',
    'menu    searchle',
    'menu    searchna',
    'menu    searchra',
    'menu    scname',
    'menu    scchar',
    'menu    scmlev',
    'menu    comgenre',
    'menu    sccompar',
    'menu    arealist',
};

data.linkshell_action_family_menus = T{
    'menu    link1',
    'menu    link2',
    'menu    link3',
    'menu    link4',
    'menu    link7',
    'menu    link8',
    'menu    link9',
    'menu    link10',
    'menu    link13',
};

data.config_family_menus = T{
    'menu    configwi',
    'menu    conf1win',
    'menu    conf2win',
    'menu    k1assign',
    'menu    k2assign',
    'menu    keylayou',
    'menu    cfilter',
    'menu    conftxtc',
    'menu    textcol1',
    'menu    textcol2',
    'menu    textcol3',
    'menu    confyn',
    'menu    conf11m',
    'menu    conf11l',
    'menu    conf11s',
    'menu    conf3win',
    'menu    conf7',
    'menu    fxfilter',
    'menu    conf4',
    'menu    conf5m',
    'menu    conf5win',
    'menu    conf5w1',
    'menu    conf5w2',
    'menu    conf6win',
    'menu    conf12wi',
    'menu    conf13wi',
};

data.character_creation_family_menus = T{
    'menu    chmkrace',
    'menu    chmkface',
    'menu    chmkhair',
    'menu    chmksize',
    'menu    chmkjobs',
    'menu    chmkname',
    'menu    chmkserv',
    'menu    chmktown',
    'menu    chmkpass',
    'menu    worldsel',
};

data.fixed_titles = T{
    { menus = T{ 'menu    statcom2' }, title = 'Status menu' },
    { menus = T{ 'menu    jobchang', 'menu    jobcselu' }, title = 'Change Jobs' },
    { menus = T{ 'menu    jbpcat' }, title = 'Job Points' },
    { menus = T{ 'menu    ut_menu' }, title = 'Unity' },
    { menus = T{ 'menu    merit1' }, title = 'Merit Points' },
    { menus = T{ 'menu    sortyn' }, title = 'Confirmation' },
    { menus = T{ 'menu    mgcmenu', 'menu    magselec' }, title = 'Magic list' },
    { menus = T{ 'menu    magic' }, title = 'Magic' },
    { menus = T{ 'menu    bluequip', 'menu    bluinven' }, title = 'Blue Magic' },
    { menus = T{ 'menu    abimenu', 'menu    abiselec' }, title = 'Abilities' },
    { menus = T{ 'menu    ability' }, title = 'Job Abilities' },
    { menus = T{ 'menu    chatctrl' }, title = 'Chat' },
    { menus = T{ 'menu    emote' }, title = 'Emote List' },
    { menus = T{ 'menu    mount' }, title = 'Mounts' },
    { menus = T{ 'menu    prty1' }, title = 'Party' },
    { menus = T{ 'menu    alarm' }, title = 'Alarm' },
    { menus = T{ 'menu    commenu' }, title = 'Communication' },
    { menus = T{ 'menu    flistmai' }, title = 'Friend List' },
    { menus = T{ 'menu    friend' }, title = 'Friend List' },
    { menus = T{ 'menu    prty5us' }, title = 'Party language' },
    { menus = T{ 'menu    myroom' }, title = 'Mog House' },
    { menus = T{ 'menu    mogcont' }, title = 'View House' },
    { menus = T{ 'menu    bazaar' }, title = 'Set Bazaar' },
    { menus = T{ 'menu    shopmain' }, title = 'Shop' },
    { menus = T{ 'menu    shopbuy' }, title = 'Shop' },
    { menus = T{ 'menu    shopsell' }, title = 'Set Bazaar' },
    { menus = T{ 'menu    itmsort2' }, title = 'Sort' },
    { menus = T{ 'menu    blusortw' }, title = 'Sort' },
    { menus = T{ 'menu    mgcsortw' }, title = 'Sort' },
    { menus = data.config_family_menus, title = 'Config' },
    { menus = T{ 'menu    mcrmenu' }, title = 'MacroPalette' },
    { menus = T{ 'menu    mcr1pall', 'menu    mcr2pall' }, title = 'Macro Palette' },
    { menus = T{ 'menu    mcres20' }, title = 'Equipment Sets' },
    { menus = T{ 'menu    mcrselec' }, title = 'Edit Macros' },
    { menus = T{ 'menu    mcrselop' }, title = 'Edit Macros' },
    { menus = T{ 'menu    mcr1edit', 'menu    mcr2edit', 'menu    mcr1edlo', 'menu    mcr2edlo' }, title = 'Edit Macro Book' },
    { menus = T{ 'menu    bankmenu' }, title = 'Gardening' },
    { menus = T{ 'menu    storage' }, title = 'Storage' },
    { menus = T{ 'menu    delivery' }, title = 'Delivery Box' },
    { menus = T{ 'menu    region' }, title = 'Region Info' },
    { menus = T{ 'menu    missionm', 'menu    miss00' }, title = 'Missions' },
    { menus = T{ 'menu    quest00', 'menu    quest01' }, title = 'Quests' },
    { menus = T{ 'menu    inline' }, title = 'Information' },
    { menus = T{ 'menu    cnqframe' }, title = 'Region Info' },
    { menus = T{ 'menu    map0', 'menu    mapv3', 'menu    mapframe' }, title = 'Map' },
    { menus = T{ 'menu    scanlist' }, title = 'Wide Scan' },
    { menus = T{ 'menu    scresult' }, title = 'Search Results' },
    { menus = T{ 'menu    evitem' }, title = 'Currencies' },
    { menus = T{ 'menu    evitem01' }, title = 'Key item' },
    { menus = T{ 'menu    faqsub', 'menu    faqmain' }, title = 'Help Desk' },
    { menus = T{ 'menu    guide00', 'menu    guide01' }, title = 'Adventuring Primer' },
};

data.main_menu_resources = T{
    label_dat = { id = 55652, path = 'ROM\\165\\76.DAT' },
    help_dat = { id = 55651, path = 'ROM\\165\\75.DAT' },
    rows = T{
        ['Status'] = { label = 81, help = 321 },
        ['Equipment'] = { label = 20, help = 322 },
        ['Magic List'] = { label = 76, help = 323 },
        ['Items'] = { label = 2, help = 324 },
        ['Abilities'] = { label = 68, help = 325 },
        ['Party'] = { label = 19, help = 326 },
        ['Trade'] = { label = 10, help = 327 },
        ['Search'] = { label = 0, help = 328 },
        ['Linkshell'] = { label = 71, help = 329 },
        ['Synthesis'] = { label = 114, help = 816 },
        ['Region Info'] = { label = 1, help = 331 },
        ['Map'] = { label = 8, help = 40 },
        ['Mog House'] = { label = 9, help = 41 },
        ['Missions'] = { label = 85, help = 468 },
        ['Quests'] = { label = 100, help = 469 },
        ['Key Items'] = { label = 59, help = 470 },
        ['View House'] = { label = 107, help = 471 },
        ['Set Bazaar'] = { label = 15, help = 472 },
        ['MacroPalette'] = { label = 80, help = 473 },
        ['Config'] = { label = 54, help = 474 },
        ['Help Desk'] = { label = 60, help = 475 },
        ['Communication'] = { label = 179, help = 926 },
        ['Current Time'] = { label = 111 },
        ['Shut Down'] = { label = 113, help = 479 },
        ['Log Out'] = { label = 112, help = 478 },
    },
};

data.title_lobby_menu_resources = T{
    title = 'Main menu',
    rows = T{
        [0] = {
            label = 'Select Character',
            label_source = 'native-title-button',
            help_dat = 'ROM\\165\\71.DAT',
            help_row = 99,
        },
        [1] = {
            label = 'Create Character',
            label_source = 'native-title-button',
            help_dat = 'ROM\\165\\71.DAT',
            help_row = 100,
        },
        [2] = {
            label = 'Delete Character',
            label_source = 'native-title-button',
            help_dat = 'ROM\\165\\71.DAT',
            help_row = 101,
        },
        [3] = {
            label = 'Back',
            label_dat = 'ROM\\165\\72.DAT',
            label_row = 199,
            help_dat = 'ROM\\165\\71.DAT',
            help_row = 102,
        },
        [4] = {
            label = 'Config',
            label_dat = 'ROM\\165\\72.DAT',
            label_row = 198,
            help_dat = 'ROM\\165\\75.DAT',
            help_row = 474,
        },
    },
};

data.title_config_menu_resources = T{
    title = 'Config',
    focus_rows = T{
        [0] = {
            help_dat = 'ROM\\97\\36.DAT',
            help_row = 251,
        },
        [1] = {
            help_dat = 'ROM\\97\\36.DAT',
            help_row = 252,
        },
        [2] = {
            help_dat = 'ROM\\97\\36.DAT',
            help_row = 253,
        },
        [3] = {
            help_dat = 'ROM\\97\\36.DAT',
            help_row = 254,
        },
        [4] = {
            help_dat = 'ROM\\97\\36.DAT',
            help_row = 255,
        },
        [5] = {
            help_dat = 'ROM\\97\\36.DAT',
            help_row = 256,
        },
        [6] = {
            help_dat = 'ROM\\97\\36.DAT',
            help_row = 257,
        },
        [7] = {
            help_dat = 'ROM\\97\\36.DAT',
            help_row = 270,
        },
        [8] = {
            help_dat = 'ROM\\97\\36.DAT',
            help_row = 245,
        },
        [9] = {
            help_dat = 'ROM\\97\\36.DAT',
            help_row = 246,
        },
        [10] = {
            help_dat = 'ROM\\97\\36.DAT',
            help_row = 247,
        },
        [11] = {
            help_dat = 'ROM\\97\\36.DAT',
            help_row = 248,
        },
        [14] = {
            help_dat = 'ROM\\165\\75.DAT',
            help_row = 1092,
        },
    },
};

data.character_creation_menu_resources = T{
    race = T{
        title = 'Race',
        label_dat = 'ROM\\171\\5.DAT',
        rows = T{
            [0] = { label_row = 0 },
            [1] = { label_row = 1 },
            [2] = { label_row = 2 },
            [3] = { label_row = 3 },
            [4] = { label_row = 4 },
            [5] = { label_row = 5 },
            [6] = { label_row = 6 },
            [7] = { label_row = 7 },
        },
    },
    face = T{
        title = 'Face',
        label_template_dat = 'ROM\\171\\6.DAT',
        label_template_row = 5,
        first_label_value = 1,
        count = 8,
    },
    hair = T{
        title = 'Hair',
        label_template_dat = 'ROM\\171\\6.DAT',
        label_template_row = 6,
        count = 2,
        rows = T{
            [0] = { value_dat = 'ROM\\171\\6.DAT', value_row = 11 },
            [1] = { value_dat = 'ROM\\171\\6.DAT', value_row = 12 },
        },
    },
    size = T{
        title = 'Size',
        label_template_dat = 'ROM\\171\\6.DAT',
        label_template_row = 7,
        count = 3,
        rows = T{
            [0] = { value_dat = 'ROM\\171\\6.DAT', value_row = 8 },
            [1] = { value_dat = 'ROM\\171\\6.DAT', value_row = 9 },
            [2] = { value_dat = 'ROM\\171\\6.DAT', value_row = 10 },
        },
    },
    job = T{
        title = 'Initial job',
        label_dat = 'ROM\\165\\86.DAT',
        count = 6,
        rows = T{
            [0] = { label_row = 1 },
            [1] = { label_row = 2 },
            [2] = { label_row = 3 },
            [3] = { label_row = 4 },
            [4] = { label_row = 5 },
            [5] = { label_row = 6 },
        },
    },
    name = T{
        title = '',
        rows = T{
            [0] = { label_dat = 'ROM\\165\\69.DAT', label_row = 4, label_kind = 'prompt' },
        },
    },
    worldpass = T{
        title = '',
        rows = T{
            [0] = { label_dat = 'ROM\\97\\36.DAT', label_row = 113, label_kind = 'prompt' },
        },
    },
    nation = T{
        title = 'Starting country',
        prompt_dat = 'ROM\\97\\36.DAT',
        prompt_row = 114,
        rows = T{
            [1] = { title_dat = 'ROM\\97\\36.DAT', title_row = 29, body_dat = 'ROM\\97\\36.DAT', body_row = 30 },
            [2] = { title_dat = 'ROM\\97\\36.DAT', title_row = 40, body_dat = 'ROM\\97\\36.DAT', body_row = 41 },
            [3] = { title_dat = 'ROM\\97\\36.DAT', title_row = 51, body_dat = 'ROM\\97\\36.DAT', body_row = 52 },
        },
    },
};

data.character_creation_confirmation_resource = T{
    register_dat = 'ROM\\97\\36.DAT',
    register_row = 175,
    begin_dat = 'ROM\\97\\36.DAT',
    begin_row = 176,
    yes_dat = 'ROM\\97\\37.DAT',
    yes_row = 106,
    no_dat = 'ROM\\97\\37.DAT',
    no_row = 107,
};

data.character_creation_error_dialog_resources = T{
    name_unavailable = T{
        title = 'Character creation',
        error_dat = 'ROM\\97\\35.DAT',
        error_row = 1,
        error_code = 3313,
        message_dat = 'ROM\\97\\35.DAT',
        message_row = 39,
        message_kind = 'prompt',
    },
};

data.friend_list_rows = T{
    [1] = {
        label = 'Top List',
        help = 'Edit Friend List.',
        label_source = 'screenshot:Zaltar_2026.06.18_155534.png',
        help_source = 'dat:ROM/97/42.DAT',
    },
    [2] = {
        label = 'Messages',
        help = 'View PlayOnline messages.',
        label_source = 'dat:ROM/97/41.DAT',
        help_source = 'dat:ROM/97/42.DAT',
    },
    [3] = {
        label = 'Online Stat.',
        help = 'Change your online status.',
        label_source = 'dat:ROM/97/41.DAT',
        help_source = 'dat:ROM/97/42.DAT',
    },
};

data.window_title_fallbacks = T{
    { menus = T{ 'menu    mogdoor' }, fallback = 'Door' },
    { menus = T{ 'menu    roomlist' }, fallback = 'Area' },
    { menus = T{ 'menu    playermo' }, fallback = '' },
};

data.name_contains_titles = T{
    { contains = T{ 'jobp', 'jpoint', 'jp_' }, title = 'Job Points' },
};

data.post_special_name_contains_titles = T{
    { contains = T{ 'menu    merit' }, title = 'Merit options' },
};

data.window_contains_titles = T{
    { contains = T{ 'Job Points', 'Job Point', 'Capacity Points' }, title = 'Job Points' },
};

data.synthesis_window_titles = T{
    { window = 'Synthesis', title = 'Synthesis' },
    { window = 'Crystal Synthesis', title = 'Crystal Synthesis' },
    { window = 'Synthesis History', title = 'Synthesis History' },
    { window = 'History', title = 'Synthesis History' },
};

return data;
