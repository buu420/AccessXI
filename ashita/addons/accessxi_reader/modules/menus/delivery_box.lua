local data = {};

data.all_menus = T{
    'menu    mogpost',
    'menu    post1',
    'menu    post2',
};

data.receive_menus = T{
    'menu    post1',
};

data.send_menus = T{
    'menu    delivery',
};

data.slot_count = 8;

data.grid_buttons = T{
    [9] = 'OK',
    [10] = 'Cancel',
};

return data;
