local data = {};

data.parent_choices = T{
    {
        label = 'Stay in your room.',
        dat = 'ROM\\97\\37.DAT:182; ROM\\165\\72.DAT:184',
    },
    {
        label = 'Area you entered from.',
        dat = 'ROM\\97\\37.DAT:70; ROM\\165\\72.DAT:70',
    },
    {
        label = 'Change floors.',
        dat = 'ROM\\165\\72.DAT:293',
    },
    {
        label = 'Select an area to exit to.',
        dat = 'ROM\\97\\37.DAT:183; ROM\\165\\72.DAT:185',
    },
};

data.area_return_choice = {
    label = 'Area you entered from.',
    dat = 'ROM\\97\\37.DAT:70; ROM\\165\\72.DAT:70',
};

data.area_families = T{
    { family = 'sandoria', zones = T{ 230, 231, 232 } },
    { family = 'bastok', zones = T{ 234, 235, 236, 237 } },
    { family = 'windurst', zones = T{ 238, 239, 240, 241, 242 } },
    { family = 'jeuno', zones = T{ 243, 244, 245, 246 } },
    { family = 'ahturhgan', zones = T{ 48, 50 } },
    { family = 'adoulin', zones = T{ 256, 257 } },
};

return data;
