local data = {};

-- DAT-backed labels from ROM\169\75.DAT / DatId 55686. The live menu object
-- supplies the visible selected row and native scroll state; this table supplies
-- the client-local strings for that resolved row.
data.category_dat_rows = T{
    [1] = { label = 'HP/MP', help = 'Adjust your maximum HP and MP. Max. total ability increases: 75' },
    [2] = { label = 'Attributes', help = 'Adjust your 7 main attributes. Max. total ability increases: 105' },
    [3] = { label = 'Combat Skills', help = 'Adjust your combat skills. Max. total ability increases: 152' },
    [4] = { label = 'Magic Skills', help = 'Adjust your magic skills. Max. total ability increases: 112' },
    [5] = { label = 'Others', help = 'Adjust various other attributes. Max. total ability increases: 10' },
    [6] = { label = 'Warrior', help = 'Adjust various abilities for WAR lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [7] = { label = 'Monk', help = 'Adjust various abilities for MNK lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [8] = { label = 'White Mage', help = 'Adjust various abilities for WHM lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [9] = { label = 'Black Mage', help = 'Adjust various abilities for BLM lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [10] = { label = 'Red Mage', help = 'Adjust various abilities for RDM lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [11] = { label = 'Thief', help = 'Adjust various abilities for THF lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [12] = { label = 'Paladin', help = 'Adjust various abilities for PLD lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [13] = { label = 'Dark Knight', help = 'Adjust various abilities for DRK lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [14] = { label = 'Beastmaster', help = 'Adjust various abilities for BST lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [15] = { label = 'Bard', help = 'Adjust various abilities for BRD lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [16] = { label = 'Ranger', help = 'Adjust various abilities for RNG lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [17] = { label = 'Samurai', help = 'Adjust various abilities for SAM lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [18] = { label = 'Ninja', help = 'Adjust various abilities for NIN lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [19] = { label = 'Dragoon', help = 'Adjust various abilities for DRG lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [20] = { label = 'Summoner', help = 'Adjust various abilities for SMN lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [21] = { label = 'Blue Mage', help = 'Adjust various abilities for BLU lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [22] = { label = 'Corsair', help = 'Adjust various abilities for COR lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [23] = { label = 'Puppetmaster', help = 'Adjust various abilities for PUP lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [24] = { label = 'Dancer', help = 'Adjust various abilities for DNC lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [25] = { label = 'Scholar', help = 'Adjust various abilities for SCH lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [26] = { label = 'Weapon Skills', help = 'Adjust weapon skills for levels 96 and above. Total ability increases: 15. Total ability increases from Primers on Martial Techniques: 5. Total ability increases from Treastises on Martial Techniques: 5.' },
    [27] = { label = 'Geomancer', help = 'Adjust various abilities for GEO lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
    [28] = { label = 'Rune Fencer', help = 'Adjust various abilities for RUN lv.75 or above. Group 1 max. total ability increases: 10 Group 2 max. total ability increases: 10' },
};

data.category_menu_order = T{
    1, 2, 3, 4, 5, 26,
    6, 7, 8, 9, 10, 11, 12, 13,
    14, 15, 16, 17, 18, 19, 20, 21,
    22, 23, 24, 25, 27, 28,
};

return data;
