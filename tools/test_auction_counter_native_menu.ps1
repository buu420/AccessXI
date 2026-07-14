$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$nativeMenusPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\menus\native_menus.lua'

$source = Get-Content -LiteralPath $addonPath -Raw
$nativeMenus = Get-Content -LiteralPath $nativeMenusPath -Raw

function Assert-Match {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotMatch {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Text -match $Pattern) {
        throw $Message
    }
}

Assert-Match `
    -Text $nativeMenus `
    -Pattern "menus\s*=\s*T\{\s*'menu    auc1'\s*\}.*?title\s*=\s*'Auction House'" `
    -Message 'Auction counter should be registered as a native known Auction House menu.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "menus\s*=\s*T\{\s*'menu    auc2'\s*\}.*?title\s*=\s*'Auction'" `
    -Message 'Auction bid category menu should be registered as a native known Auction menu.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "menus\s*=\s*T\{\s*'menu    aucweapo'\s*\}.*?title\s*=\s*'Weapons'" `
    -Message 'Auction weapon category menu should be registered as a native known Weapons menu.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "menus\s*=\s*T\{\s*'menu    aucarmor'\s*\}.*?title\s*=\s*'Armor'" `
    -Message 'Auction armor category menu should be registered as a native known Armor menu.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "menus\s*=\s*T\{\s*'menu    aucmagic'\s*\}.*?title\s*=\s*'Magic Scrolls'" `
    -Message 'Auction magic scroll category menu should be registered as a native known Magic Scrolls menu.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "menus\s*=\s*T\{\s*'menu    aucmater'\s*\}.*?title\s*=\s*'Materials'" `
    -Message 'Auction materials category menu should be registered as a native known Materials menu.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "menus\s*=\s*T\{\s*'menu    aucfood'\s*\}.*?title\s*=\s*'Food'" `
    -Message 'Auction food category menu should be registered as a native known Food menu.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "menus\s*=\s*T\{\s*'menu    aucmeals'\s*\}.*?title\s*=\s*'Meals'" `
    -Message 'Auction meals category menu should be registered as a native known Meals menu.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "menus\s*=\s*T\{\s*'menu    aucitem'\s*\}.*?title\s*=\s*'Others'" `
    -Message 'Auction other category menu should be registered with an Others title so Misc. stays a selectable row.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "menus\s*=\s*T\{\s*'menu    auclist'\s*\}.*?title\s*=\s*'Bid'" `
    -Message 'Auction item list should be registered as a native known Bid menu.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "menus\s*=\s*T\{\s*'menu    auc3'\s*\}.*?title\s*=\s*'Auction'" `
    -Message 'Auction item action menu should be registered as a native known Auction menu.'

Assert-Match `
    -Text $nativeMenus `
    -Pattern "menus\s*=\s*T\{\s*'menu    auchisto'\s*\}.*?title\s*=\s*'Price History'" `
    -Message 'Auction price history should be registered as a native known Price History menu.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?accessxi\.native_query_label_for_selection\(child,\s*selected,\s*count,\s*'plain'\)" `
    -Message 'Auction counter should be routed to the existing live native row label reader.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_counter_menu_speech" `
    -Message 'Auction counter should have a narrow top-command handler for the auc1 menu shape.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?menu_name:eq\('menu    auc1', true\).*?accessxi\.auction_counter_menu_speech" `
    -Message 'Auction counter should route through its command handler before the generic native row lookup.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*515,\s*'help'\)" `
    -Message 'Auction Bid help should be loaded from installed DAT row ROM\\165\\75.DAT:515.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*516,\s*'help'\)" `
    -Message 'Auction Sell help should be loaded from installed DAT row ROM\\165\\75.DAT:516.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*517,\s*'help'\)" `
    -Message 'Auction Sales Status help should be loaded from installed DAT row ROM\\165\\75.DAT:517.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\76\.DAT',\s*121,\s*'label'\)" `
    -Message 'Auction Bid label should be loaded from installed DAT row ROM\\165\\76.DAT:121.'

Assert-Match `
    -Text $source `
    -Pattern "count\s*~=\s*6" `
    -Message 'Auction top-command handler should stay scoped to the observed six-node auc1 top menu shape.'

Assert-Match `
    -Text $source `
    -Pattern "state auction-counter native" `
    -Message 'Auction top-command handler should log native evidence when it speaks.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_bid_category_menu_speech" `
    -Message 'Auction bid category menu should have a narrow auc2 handler.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?menu_name:eq\('menu    auc2', true\).*?accessxi\.auction_bid_category_menu_speech" `
    -Message 'Auction bid category menu should route through its category handler before the generic native row lookup.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*518,\s*'help'\)" `
    -Message 'Auction Weapons category help should be loaded from installed DAT row ROM\\165\\75.DAT:518.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*526,\s*'help'\)" `
    -Message 'Auction Others category help should be loaded from installed DAT row ROM\\165\\75.DAT:526.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\76\.DAT',\s*125,\s*'label'\)" `
    -Message 'Auction Weapons label should be loaded from installed DAT row ROM\\165\\76.DAT:125.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*271,\s*'label'\)" `
    -Message 'Auction Crystals label should be loaded from installed DAT row ROM\\165\\77.DAT:271.'

Assert-Match `
    -Text $source `
    -Pattern "state auction-category native" `
    -Message 'Auction bid category handler should log native evidence when it speaks.'

Assert-Match `
    -Text $source `
    -Pattern "count\s*>\s*0\s+and\s+count\s*~=\s*9\s+and\s+count\s*~=\s*12" `
    -Message 'Auction bid category handler should accept the observed native count=12 category list shape.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_weapon_category_menu_speech" `
    -Message 'Auction weapon category menu should have a narrow aucweapo handler.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?menu_name:eq\('menu    aucweapo', true\).*?accessxi\.auction_weapon_category_menu_speech" `
    -Message 'Auction weapon category menu should route through its weapon category handler before the generic native row lookup.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*24,\s*'label'\)" `
    -Message 'Auction Hand-to-Hand label should be loaded from installed DAT row ROM\\165\\77.DAT:24.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*228,\s*'label'\)" `
    -Message 'Auction Katana label should be loaded from installed DAT row ROM\\165\\77.DAT:228.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*230,\s*'label'\)" `
    -Message 'Auction Clubs label should be loaded from installed DAT row ROM\\165\\77.DAT:230.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\76\.DAT',\s*115,\s*'label'\)" `
    -Message 'Auction Ammo&Misc. label should be loaded from installed DAT row ROM\\165\\76.DAT:115.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*574,\s*'help'\)" `
    -Message 'Auction Hand-to-Hand help should be loaded from installed DAT row ROM\\165\\75.DAT:574.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*582,\s*'help'\)" `
    -Message 'Auction Katana help should be loaded from installed DAT row ROM\\165\\75.DAT:582.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*584,\s*'help'\)" `
    -Message 'Auction Clubs help should be loaded from installed DAT row ROM\\165\\75.DAT:584.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*587,\s*'help'\)" `
    -Message 'Auction Instruments help should be loaded from installed DAT row ROM\\165\\75.DAT:587.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*255,\s*'help'\)" `
    -Message 'Auction Ammo/Misc. help should be loaded from installed DAT row ROM\\165\\75.DAT:255.'

Assert-Match `
    -Text $source `
    -Pattern "state auction-weapon-category native" `
    -Message 'Auction weapon category handler should log native evidence when it speaks.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_armor_category_menu_speech" `
    -Message 'Auction armor category menu should have a narrow aucarmor handler.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?menu_name:eq\('menu    aucarmor', true\).*?accessxi\.auction_armor_category_menu_speech" `
    -Message 'Auction armor category menu should route through its armor category handler before the item list opens.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*235,\s*'label'\)" `
    -Message 'Auction Shields label should be loaded from installed DAT row ROM\\165\\77.DAT:235.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*245,\s*'label'\)" `
    -Message 'Auction Rings label should be loaded from installed DAT row ROM\\165\\77.DAT:245.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*534,\s*'help'\)" `
    -Message 'Auction Shields help should be loaded from installed DAT row ROM\\165\\75.DAT:534.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*544,\s*'help'\)" `
    -Message 'Auction Rings help should be loaded from installed DAT row ROM\\165\\75.DAT:544.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_armor_category_menu_speech.*?local\s+ah_category_id\s*=\s*tonumber\(\(rows\.ah_category_ids\s+or\s+T\{\}\)\[visible_selected\]\)\s+or\s+0.*?set_auction_current_ah_category\(ah_category_id.*?'aucarmor'\)" `
    -Message 'Auction armor subcategory handler should store the selected AH category before the item list opens.'

Assert-Match `
    -Text $source `
    -Pattern "state auction-armor-category native" `
    -Message 'Auction armor category handler should log native evidence when it speaks.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_magic_category_menu_speech" `
    -Message 'Auction magic scroll category menu should have a narrow aucmagic handler.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?menu_name:eq\('menu    aucmagic', true\).*?accessxi\.auction_magic_category_menu_speech" `
    -Message 'Auction magic scroll category menu should route through its scroll category handler before the item list opens.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*246,\s*'label'\)" `
    -Message 'Auction White Magic label should be loaded from installed DAT row ROM\\165\\77.DAT:246.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*252,\s*'label'\)" `
    -Message 'Auction Geomancy label should be loaded from installed DAT row ROM\\165\\77.DAT:252.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*555,\s*'help'\)" `
    -Message 'Auction White Magic help should be loaded from installed DAT row ROM\\165\\75.DAT:555.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*639,\s*'help'\)" `
    -Message 'Auction Dice help should be loaded from installed DAT row ROM\\165\\75.DAT:639.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*699,\s*'help'\)" `
    -Message 'Auction Geomancy help should be loaded from installed DAT row ROM\\165\\75.DAT:699.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_magic_category_menu_speech.*?local\s+ah_category_id\s*=\s*tonumber\(\(rows\.ah_category_ids\s+or\s+T\{\}\)\[visible_selected\]\)\s+or\s+0.*?set_auction_current_ah_category\(ah_category_id.*?'aucmagic'\)" `
    -Message 'Auction magic scroll subcategory handler should store the selected AH category before the item list opens.'

Assert-Match `
    -Text $source `
    -Pattern "state auction-magic-category native" `
    -Message 'Auction magic scroll category handler should log native evidence when it speaks.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.load_auction_material_category_rows" `
    -Message 'Auction materials category menu should load DAT-backed material rows.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_material_category_menu_speech" `
    -Message 'Auction materials category menu should have a narrow aucmater handler.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?menu_name:eq\('menu    aucmater', true\).*?accessxi\.auction_material_category_menu_speech" `
    -Message 'Auction materials category menu should route through its material category handler before the item list opens.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*255,\s*'label'\)" `
    -Message 'Auction Smithing material label should be loaded from installed DAT row ROM\\165\\77.DAT:255.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*283,\s*'label'\)" `
    -Message 'Auction Alchemy 2 material label should be loaded from installed DAT row ROM\\165\\77.DAT:283.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*560,\s*'help'\)" `
    -Message 'Auction Smithing material help should be loaded from installed DAT row ROM\\165\\75.DAT:560.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*805,\s*'help'\)" `
    -Message 'Auction Alchemy 2 material help should be loaded from installed DAT row ROM\\165\\75.DAT:805.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_material_category_menu_speech.*?local\s+ah_category_id\s*=\s*tonumber\(\(rows\.ah_category_ids\s+or\s+T\{\}\)\[visible_selected\]\)\s+or\s+0.*?set_auction_current_ah_category\(ah_category_id.*?'aucmater'\)" `
    -Message 'Auction materials subcategory handler should store the selected AH category before the item list opens.'

Assert-Match `
    -Text $source `
    -Pattern "state auction-material-category native" `
    -Message 'Auction materials category handler should log native evidence when it speaks.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.load_auction_material_category_rows.*?ah_category_ids\[1\]\s*=\s*38.*?ah_category_ids\[7\]\s*=\s*44.*?ah_category_ids\[8\]\s*=\s*63" `
    -Message 'Auction materials category ids should match the documented AH category ids, including Alchemy 2.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.load_auction_food_category_rows" `
    -Message 'Auction food category menu should load DAT-backed food rows.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_food_category_menu_speech" `
    -Message 'Auction food category menu should have a narrow aucfood handler.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?menu_name:eq\('menu    aucfood', true\).*?accessxi\.auction_food_category_menu_speech" `
    -Message 'Auction food category menu should route through its food category handler before the item list opens.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\76\.DAT',\s*124,\s*'label'\)" `
    -Message 'Auction Meals label should be loaded from installed DAT row ROM\\165\\76.DAT:124.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*269,\s*'label'\)" `
    -Message 'Auction Ingredients label should be loaded from installed DAT row ROM\\165\\77.DAT:269.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*270,\s*'label'\)" `
    -Message 'Auction Fish/Fishing label should be loaded from installed DAT row ROM\\165\\77.DAT:270.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*545,\s*'help'\)" `
    -Message 'Auction Meals help should be loaded from installed DAT row ROM\\165\\75.DAT:545.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*546,\s*'help'\)" `
    -Message 'Auction Ingredients help should be loaded from installed DAT row ROM\\165\\75.DAT:546.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*547,\s*'help'\)" `
    -Message 'Auction Fish help should be loaded from installed DAT row ROM\\165\\75.DAT:547.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.load_auction_food_category_rows.*?ah_category_ids\[2\]\s*=\s*59.*?ah_category_ids\[3\]\s*=\s*51" `
    -Message 'Auction food category ids should match the documented AH category ids for Ingredients and Fish.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_food_category_menu_speech.*?local\s+ah_category_id\s*=\s*tonumber\(\(rows\.ah_category_ids\s+or\s+T\{\}\)\[visible_selected\]\)\s+or\s+0.*?set_auction_current_ah_category\(ah_category_id.*?'aucfood'\)" `
    -Message 'Auction food subcategory handler should store terminal AH category ids before the item list opens.'

Assert-Match `
    -Text $source `
    -Pattern "state auction-food-category native" `
    -Message 'Auction food category handler should log native evidence when it speaks.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.load_auction_meal_category_rows" `
    -Message 'Auction meals category menu should load DAT-backed meal rows.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_meal_category_menu_speech" `
    -Message 'Auction meals category menu should have a narrow aucmeals handler.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?menu_name:eq\('menu    aucmeals', true\).*?accessxi\.auction_meal_category_menu_speech" `
    -Message 'Auction meals category menu should route through its meals category handler before the item list opens.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*262,\s*'label'\)" `
    -Message 'Auction Meat/Eggs label should be loaded from installed DAT row ROM\\165\\77.DAT:262.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*268,\s*'label'\)" `
    -Message 'Auction Drinks label should be loaded from installed DAT row ROM\\165\\77.DAT:268.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*567,\s*'help'\)" `
    -Message 'Auction Meat/Eggs help should be loaded from installed DAT row ROM\\165\\75.DAT:567.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*573,\s*'help'\)" `
    -Message 'Auction Drinks help should be loaded from installed DAT row ROM\\165\\75.DAT:573.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.load_auction_meal_category_rows.*?ah_category_ids\[1\]\s*=\s*52.*?ah_category_ids\[7\]\s*=\s*58" `
    -Message 'Auction meals category ids should match the documented AH category ids.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_meal_category_menu_speech.*?local\s+ah_category_id\s*=\s*tonumber\(\(rows\.ah_category_ids\s+or\s+T\{\}\)\[visible_selected\]\)\s+or\s+0.*?set_auction_current_ah_category\(ah_category_id.*?'aucmeals'\)" `
    -Message 'Auction meals subcategory handler should store terminal AH category ids before the item list opens.'

Assert-Match `
    -Text $source `
    -Pattern "state auction-meal-category native" `
    -Message 'Auction meals category handler should log native evidence when it speaks.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.load_auction_other_category_rows" `
    -Message 'Auction other category menu should load DAT-backed other rows.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_other_category_menu_speech" `
    -Message 'Auction other category menu should have a narrow aucitem handler.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_other_category_row_index_for_label" `
    -Message 'Auction other category menu should be able to resolve the selected DAT row by live native label.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_other_category_row_index_for_live_text" `
    -Message 'Auction other category menu should resolve live entry text against DAT labels and help text before speaking.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_other_category_row_index_for_live_text.*?rows\.labels.*?rows\.helps.*?auction_other_category_label_key" `
    -Message 'Auction other live text resolver should require exact normalized DAT label/help matches, not ordinal row positions.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_other_category_entry_live_text" `
    -Message 'Auction other category menu should read live selected-entry text pointers when generic native labels are empty.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_other_category_entry_live_text.*?read_u32\(entry \+ 0x40\).*?native_query_candidate_label_from_ptr.*?read_u32\(entry \+ 0x44\)" `
    -Message 'Auction other selected-entry text resolver should inspect entry+40 and entry+44 pointers before falling back to silence.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?menu_name:eq\('menu    aucitem', true\).*?accessxi\.auction_other_category_menu_speech" `
    -Message 'Auction other category menu should route through its other category handler before the item list opens.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*272,\s*'label'\)" `
    -Message 'Auction Misc. label should be loaded from installed DAT row ROM\\165\\77.DAT:272.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*282,\s*'label'\)" `
    -Message 'Auction Misc. 2 label should be loaded from installed DAT row ROM\\165\\77.DAT:282.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*284,\s*'label'\)" `
    -Message 'Auction Misc. 3 label should be loaded from installed DAT row ROM\\165\\77.DAT:284.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*273,\s*'label'\)" `
    -Message 'Auction Beast-made label should be loaded from installed DAT row ROM\\165\\77.DAT:273.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*274,\s*'label'\)" `
    -Message 'Auction Cards label should be loaded from installed DAT row ROM\\165\\77.DAT:274.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*275,\s*'label'\)" `
    -Message 'Auction Ninja Tools label should be loaded from installed DAT row ROM\\165\\77.DAT:275.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*276,\s*'label'\)" `
    -Message 'Auction Cursed Items label should be loaded from installed DAT row ROM\\165\\77.DAT:276.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\77\.DAT',\s*277,\s*'label'\)" `
    -Message 'Auction Automaton label should be loaded from installed DAT row ROM\\165\\77.DAT:277.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*549,\s*'help'\)" `
    -Message 'Auction Misc. help should be loaded from installed DAT row ROM\\165\\75.DAT:549.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*550,\s*'help'\)" `
    -Message 'Auction Beast-made help should be loaded from installed DAT row ROM\\165\\75.DAT:550.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*652,\s*'help'\)" `
    -Message 'Auction Automaton help should be loaded from installed DAT row ROM\\165\\75.DAT:652.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*806,\s*'help'\)" `
    -Message 'Auction Misc. 2 help should be loaded from installed DAT row ROM\\165\\75.DAT:806.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*987,\s*'help'\)" `
    -Message 'Auction Misc. 3 help should be loaded from installed DAT row ROM\\165\\75.DAT:987.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.load_auction_other_category_rows.*?ah_category_ids\[1\]\s*=\s*46.*?ah_category_ids\[2\]\s*=\s*64.*?ah_category_ids\[3\]\s*=\s*65.*?ah_category_ids\[4\]\s*=\s*50.*?ah_category_ids\[5\]\s*=\s*36.*?ah_category_ids\[6\]\s*=\s*49.*?ah_category_ids\[7\]\s*=\s*37.*?ah_category_ids\[8\]\s*=\s*61" `
    -Message 'Auction other category ids should match the documented non-sequential AH category ids.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_other_category_menu_speech.*?local\s+ah_category_id\s*=\s*tonumber\(\(rows\.ah_category_ids\s+or\s+T\{\}\)\[visible_selected\]\)\s+or\s+0.*?set_auction_current_ah_category\(ah_category_id.*?'aucitem'\)" `
    -Message 'Auction other subcategory handler should store terminal AH category ids before the item list opens.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_other_category_menu_speech.*?native_query_label_for_selection\(child,\s*visible_selected,\s*count,\s*'plain'\).*?auction_other_category_row_index_for_label\(rows,\s*native_label\).*?visible_selected\s*=\s*native_index" `
    -Message 'Auction other subcategory handler should prefer live native labels so scrolled Misc. 2 and Misc. 3 rows do not inherit Cursed Items or Automaton ids.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_other_category_menu_speech.*?auction_other_category_entry_live_text\(entry\).*?auction_other_category_row_index_for_live_text\(rows,\s*entry_live_text\).*?visible_selected\s*=\s*entry_live_index" `
    -Message 'Auction other subcategory handler should use exact live selected-entry text before failing closed.'

Assert-NotMatch `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_other_category_menu_speech(?:(?!function\s+accessxi\.).)*visible_selected\s*>\s*8" `
    -Message 'Auction other subcategory handler should use the live menu count for probing instead of hard-limiting the 11-row aucitem menu to 8 rows.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_other_category_menu_speech.*?if\s*\(native_index\s*<=\s*0\)\s*then.*?auction_other_category_missing_native_label_probe.*?return\s+nil" `
    -Message 'Auction other subcategory handler must fail closed instead of inventing speech from ordinal DAT rows when the live native label is unavailable.'

Assert-Match `
    -Text $source `
    -Pattern "state auction-other-category native" `
    -Message 'Auction other category handler should log native evidence when it speaks.'

Assert-Match `
    -Text $source `
    -Pattern "state auction-other-category missing-native-label" `
    -Message 'Auction other category handler should log probe evidence when native label lookup is empty.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_other_category_missing_native_label_probe.*?read_u32\(entry \+ 0x0C\).*?rowDesc=0x%08X.*?rowDescDwords" `
    -Message 'Auction other missing-native-label probe should log the selected native row descriptor instead of leaving us with only ordinal row evidence.'

Assert-Match `
    -Text $source `
    -Pattern 'entry40Text="%s".*entry44Text="%s"' `
    -Message 'Auction other missing-native-label probe should log compact live entry text pointer evidence.'

Assert-Match `
    -Text $source `
    -Pattern 'nativeLabel="%s".*nativeMode="%s".*nativeIndex=%d' `
    -Message 'Auction other category logs should include native label resolution evidence.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_other_category_menu_speech.*?tostring\(title or 'Others'\)" `
    -Message 'Auction other category handler should not use Misc. as the menu title because Misc. is row 1.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_item_list_menu_speech" `
    -Message 'Auction item list should have a narrow dynamic auclist handler.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?menu_name:eq\('menu    auclist', true\).*?accessxi\.auction_item_list_menu_speech" `
    -Message 'Auction item list should route through its dynamic handler before the generic native row lookup.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_action_menu_speech" `
    -Message 'Auction item action menu should have a narrow auc3 handler.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?menu_name:eq\('menu    auc3', true\).*?accessxi\.auction_action_menu_speech" `
    -Message 'Auction item action menu should route through its action handler before the generic native row lookup.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\76\.DAT',\s*119,\s*'label'\)" `
    -Message 'Auction Price History label should be loaded from installed DAT row ROM\\165\\76.DAT:119.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\76\.DAT',\s*121,\s*'label'\)" `
    -Message 'Auction action Bid label should be loaded from installed DAT row ROM\\165\\76.DAT:121.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*527,\s*'help'\)" `
    -Message 'Auction Price History action help should be loaded from installed DAT row ROM\\165\\75.DAT:527.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*528,\s*'help'\)" `
    -Message 'Auction Bid action help should be loaded from installed DAT row ROM\\165\\75.DAT:528.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*80,\s*'help'\)" `
    -Message 'Auction Sort action help should be loaded from installed DAT row ROM\\165\\75.DAT:80.'

Assert-Match `
    -Text $source `
    -Pattern "native_query_label_for_selection\(child,\s*visible_selected,\s*count,\s*'auction-action'\)" `
    -Message 'Auction item action menu should read the live native row label for each visible action.'

Assert-Match `
    -Text $source `
    -Pattern "auction_selected_item_context" `
    -Message 'Auction item action menu should use the selected item context captured by the item list.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_item_list_menu_speech.*?auction_selected_item_context\s*=\s*T\{.*?speech_name\s*=\s*speech_name" `
    -Message 'Auction item list should remember the selected item before the auc3 action menu opens.'

Assert-Match `
    -Text $source `
    -Pattern "state auction-action native" `
    -Message 'Auction item action handler should log native evidence when it speaks.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_price_history_menu_speech" `
    -Message 'Auction price history should have a narrow auchisto handler.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.native_known_menu_speech.*?menu_name:eq\('menu    auchisto', true\).*?accessxi\.auction_price_history_menu_speech" `
    -Message 'Auction price history should route through its own handler before the generic native row lookup.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\76\.DAT',\s*119,\s*'label'\)" `
    -Message 'Auction price history title should be loaded from installed DAT row ROM\\165\\76.DAT:119.'

Assert-Match `
    -Text $source `
    -Pattern "dat_index_row_text\('ROM\\\\165\\\\75\.DAT',\s*548,\s*'help'\)" `
    -Message 'Auction price history help should be loaded from installed DAT row ROM\\165\\75.DAT:548.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_price_history_remember_chat_text" `
    -Message 'Auction price history should cache live sales rows from the client text stream.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)handle_chat_text.*?auction_price_history_remember_chat_text\(entry\)" `
    -Message 'Auction price history rows should be captured from live text_in chat entries.'

Assert-Match `
    -Text $source `
    -Pattern "read_current_native_menu_index\(0x4C\)" `
    -Message 'Auction price history handler should use the native cursor index while arrowing.'

Assert-Match `
    -Text $source `
    -Pattern "state auction-price-history native" `
    -Message 'Auction price history handler should log native evidence when it speaks.'

Assert-Match `
    -Text $source `
    -Pattern "native_query_label_for_selection\(child,\s*visible_selected,\s*count,\s*'auction-item-list'\)" `
    -Message 'Auction item list should read live native row labels instead of fixed item rows.'

Assert-Match `
    -Text $source `
    -Pattern "resource_item_info_by_name\(cleaned_label\)" `
    -Message 'Auction item list should enrich rows from the live item name, not a static table.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_item_list_entry_label" `
    -Message 'Auction item list should have an entry-record fallback for menus whose child list is not text-backed.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_item_list_entry_label.*?read_u32\(entry \+ 0x44\).*?read_u32\(entry \+ 0x40\)" `
    -Message 'Auction item list entry fallback should read the selected native entry label/help pointers.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_item_list_menu_speech.*?cleaned_label == ''.*?auction_item_list_entry_label\(entry\)" `
    -Message 'Auction item list should fall back to the selected entry record when child row lookup is empty.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.enable_auction_packet_trace" `
    -Message 'Auction menus should be able to arm a bounded packet trace for dynamic auction item rows.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.trace_auction_packet" `
    -Message 'Auction item list diagnostics should trace packets while the auction menus are active.'

Assert-Match `
    -Text $source `
    -Pattern "auction_packet_trace_limit\s*=\s*math\.max" `
    -Message 'Auction packet trace should be capped so it cannot run unbounded during gameplay.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)trace_auction_packet.*?ah_search_list_packet.*?id == 0x00D or id == 0x00E.*?return" `
    -Message 'Auction packet trace should skip noisy entity update packets unless they are actual AH search-list data.'

Assert-Match `
    -Text $source `
    -Pattern "auction_packet_trace_fields_logged" `
    -Message 'Auction packet trace should log event field names once so we can find hidden packet payload variants.'

Assert-Match `
    -Text $source `
    -Pattern "auction_packet_trace_variant_limit" `
    -Message 'Auction packet trace should separately cap variant payload logging.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)trace_auction_packet.*?packet_event_string\(e,\s*'data_chunk'.*?packet_event_string\(e,\s*'packet_chunk'" `
    -Message 'Auction packet trace should inspect alternate Ashita packet event payload fields.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_item_list_memory_probe" `
    -Message 'Auction item list should have a bounded memory probe when native row labels are not exposed.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_item_list_resource_candidates" `
    -Message 'Auction item list should scan selected native row records for dynamic item id candidates.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)auction_item_list_resource_candidates.*?resource_item_info\(value\)" `
    -Message 'Auction item list item-id candidates should be resolved through the live item resources.'

Assert-Match `
    -Text $source `
    -Pattern "auction_last_bid_category" `
    -Message 'Auction item list should remember the live auction category instead of guessing item row type.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_item_list_expected_resource_type" `
    -Message 'Auction item list should derive expected item resource type from the live auction category.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)auction_item_list_resource_candidates.*?expected_type.*?resource_info\.type" `
    -Message 'Auction item list resource candidates should be ranked by the expected live auction resource type.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.capture_auction_item_list_packet" `
    -Message 'Auction item list should capture the real AH item-list packet before trying memory fallbacks.'

Assert-Match `
    -Text $source `
    -Pattern "searchhook_latest_plain_path\s*=\s*accessxi_paths\.addon_path\('logs',\s*'searchhook',\s*'latest_server_plain\.bin'\)" `
    -Message 'Auction item list should read the searchhook latest server packet from an addon-relative path.'

Assert-Match `
    -Text $source `
    -Pattern "searchhook_auction_bundle_path\s*=\s*accessxi_paths\.addon_path\('logs',\s*'searchhook',\s*'latest_auction_rows_bundle\.bin'\)" `
    -Message 'Auction item list should read bundled AH 0x95 rows from an addon-relative path.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_item_list_capture_packet_data" `
    -Message 'Auction item list should expose a reusable parser for AH 0x95 searchhook packet data.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_item_list_capture_packet_data.*?data:byte\(0x0B \+ 1\).*?0x95.*?packet_u16\(data,\s*0x0E \+ 1\).*?local\s+base\s*=\s*0x18 \+ \(i \* 0x0A\).*?packet_u16\(data,\s*base \+ 1\)" `
    -Message 'Reusable auction packet parsing should use the AH 0x95 item-list layout.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_item_list_load_searchhook_packet" `
    -Message 'Auction item list should load AH 0x95 packets captured by the native searchhook.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)auction_item_list_load_searchhook_packet.*?searchhook_auction_bundle_path.*?AXAHB001.*?auction_item_list_capture_packet_data" `
    -Message 'Auction searchhook loader should read latest_auction_rows_bundle.bin and feed the reusable AH packet parser.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.capture_auction_item_list_packet.*?auction_item_list_capture_packet_data" `
    -Message 'Auction packet capture should reuse the AH 0x95 packet parser.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_item_list_packet_label" `
    -Message 'Auction item list should resolve the selected row from the captured AH item-list packet cache.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_item_list_packet_display_rows" `
    -Message 'Auction item list should expand AH packet item rows into the visual single/stack rows shown by the client.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)auction_item_list_packet_display_rows.*?display_rows:append\(T\{.*?listing_kind\s*=\s*'single'.*?if\s*\(stack_count\s*>\s*0\).*?display_rows:append\(T\{.*?listing_kind\s*=\s*'stack'" `
    -Message 'Auction item list packet expansion should keep separate visual rows for single and stack listings.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)auction_item_list_packet_label.*?local\s+rows\s*=\s*accessxi\.auction_item_list_packet_display_rows\(\).*?local\s+total\s*=\s*#rows.*?row\s*==\s*nil\s+and\s+scroll_top\s*==\s*0" `
    -Message 'Auction item list packet lookup should use expanded display rows and avoid falling back after a real scroll offset.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)local\s+listing_count\s*=\s*tonumber\(packet_single_count\).*?packet_stack_count.*?raw_label:match" `
    -Message 'Auction stack display rows should not be misreported as single listings just because their visual label has a bracketed count.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)current_speech_key\s*=\s*\('auction-item-list:.*?packet_logical.*?packet_single_count.*?packet_stack_count" `
    -Message 'Auction item list speech keys should include packet display-row details so duplicate labels still speak.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.load_auction_bid_category_rows.*?local\s+ah_category_ids\s*=\s*T\{\}.*?ah_category_ids\[4\]\s*=\s*33.*?ah_category_ids\[5\]\s*=\s*34.*?ah_category_ids\[8\]\s*=\s*35.*?ah_category_ids\s*=\s*ah_category_ids" `
    -Message 'Auction bid category rows should define a local AH category id table for terminal categories.'

Assert-NotMatch `
    -Text $source `
    -Pattern "ah_category_ids\[6\]\s*=\s*35" `
    -Message 'Auction Materials parent row should not be tagged as the terminal Crystals category.'

Assert-NotMatch `
    -Text $source `
    -Pattern "ah_category_ids\[7\]\s*=\s*35" `
    -Message 'Auction Food parent row should not be tagged as the terminal Crystals category.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_bid_category_menu_speech.*?set_auction_current_ah_category\(ah_category_id.*?'auc2'\)" `
    -Message 'Auction bid category handler should tag category changes as auc2, not weapon subcategory changes.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_weapon_category_menu_speech.*?local\s+ah_category_id\s*=\s*tonumber\(\(rows\.ah_category_ids\s+or\s+T\{\}\)\[visible_selected\]\)\s+or\s+0.*?set_auction_current_ah_category\(ah_category_id.*?'aucweapo'\)" `
    -Message 'Auction weapon subcategory handler should store the selected AH category before the item list opens.'

Assert-NotMatch `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_counter_menu_speech(?:(?!function\s+accessxi\.).)*set_auction_current_ah_category" `
    -Message 'Auction top-command handler should not mutate the AH item-list category cache.'

Assert-NotMatch `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_counter_menu_speech(?:(?!function\s+accessxi\.).)*is_probe_pointer\(first\)(?:(?!function\s+accessxi\.).)*return\s+nil" `
    -Message 'Auction top-command handler should not reject auc1 after zoning just because child+0x14 looks like a pointer.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_packet_item_matches_current_category" `
    -Message 'Auction packet capture should validate packet item ids against the active AH category.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)auction_packet_item_matches_current_category.*?resource_info.*?type.*?resource_info.*?skill" `
    -Message 'Auction packet category validation should use item resource type and weapon skill, not just packet shape.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_item_is_crystal_category_item" `
    -Message 'Auction packet category validation should have a narrow crystal item matcher.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)auction_item_is_crystal_category_item.*?item_id\s*>=\s*4096.*?item_id\s*<=\s*4111" `
    -Message 'Auction crystal matcher should accept the installed crystal and cluster item id range.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)auction_packet_item_matches_current_category.*?category_id\s*==\s*35.*?auction_item_is_crystal_category_item\(item_id,\s*resource_info\)" `
    -Message 'Auction Crystals packet validation should use crystal item ids, not the generic resource category text.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+resource_item_info.*?windower_item.*?skill\s*=\s*(?:tonumber\(res\.Skill\)\s*or\s*)?tonumber\(windower_item\.skill\)\s*or\s*0" `
    -Message 'Resource item info should preserve Windower weapon skill metadata so AH packet rows can validate the active category.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+resource_item_info.*?windower_item.*?slots\s*=\s*tonumber\(res\.Slots\)\s*or\s*tonumber\(windower_item\.slots\)\s*or\s*0" `
    -Message 'Resource item info should preserve Windower equipment slot metadata so AH armor packet rows can validate the active category.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+resource_item_info.*?local\s+category\s*=\s*clean_resource_text\(windower_item\.category\s*or\s*''\).*?category\s*=\s*category" `
    -Message 'Resource item info should preserve Windower category metadata for AH packet category validation.'

Assert-Match `
    -Text $source `
    -Pattern "auction_armor_category_slot_masks" `
    -Message 'Auction armor category validation should define slot masks for live equipment categories.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)auction_packet_item_matches_current_category.*?armor_slot_mask.*?resource_type\s*==\s*5.*?bit\.band\(slots,\s*armor_slot_mask\)\s*~=\s*0" `
    -Message 'Auction packet category validation should use live equipment slot masks for armor rows.'

Assert-Match `
    -Text $source `
    -Pattern "auction_magic_category_spell_types" `
    -Message 'Auction magic scroll category validation should define spell types for live scroll categories.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_item_spell_type" `
    -Message 'Auction scroll packet validation should derive spell type from live item and spell resources.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_item_is_magic_die" `
    -Message 'Auction Dice packet validation should recognize dice dynamically from live item resource names.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)auction_packet_item_matches_current_category.*?category_id\s*>=\s*26\s+and\s+category_id\s*<=\s*32.*?resource_type\s*==\s*7.*?auction_item_spell_type" `
    -Message 'Auction packet category validation should filter magic scroll rows by live spell type, not by fixed item rows.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)auction_item_list_capture_packet_data.*?category_id\s*<=\s*0.*?return false.*?auction_packet_item_matches_current_category" `
    -Message 'Auction packet capture should reject AH-list-shaped packets until a live AH category is known.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)auction_item_list_menu_speech.*?auction_item_list_packet_label\(visible_selected.*?cleaned_label == ''.*?auction_item_list_resource_candidates" `
    -Message 'Auction item list should prefer captured packet rows before diagnostic-only memory item-id candidates.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_item_list_menu_speech.*?auction_item_list_load_searchhook_packet\(\).*?auction_item_list_packet_label\(visible_selected" `
    -Message 'Auction item list should refresh searchhook AH packet rows before resolving the selected row.'

Assert-Match `
    -Text $source `
    -Pattern "capture_auction_item_list_packet\(e,\s*'in'\)" `
    -Message 'Auction AH item-list packet capture should run from incoming packet events.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_sales_status_capture_packet_data" `
    -Message 'Auction Sales Status should have a packet-backed row capture function for dynamic listed/returned items.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)auction_sales_status_capture_packet_data.*?packet_u16\(data,\s*0x28\s*\+\s*1\).*?packet_u32\(data,\s*0x2C\s*\+\s*1\)" `
    -Message 'Auction Sales Status capture should derive item id and gil from the live 0x04C packet row.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)auction_sales_status_capture_packet_data.*?row_command\s*==\s*0x05.*?auction_sales_status_remove_packet_row" `
    -Message 'Auction Sales Status should shrink its packet cache when the game reports a listed item was removed.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)auction_sales_status_capture_packet_data.*?not is_valid_inventory_item_id\(item_id\).*?auction_sales_status_trim_rows\(packet_row" `
    -Message 'Auction Sales Status should use blank 0x04C terminator rows to trim or empty the live list.'

Assert-Match `
    -Text $source `
    -Pattern "capture_auction_sales_status_packet\(e,\s*'in'\)" `
    -Message 'Auction Sales Status packet capture should run from incoming packet events.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_sales_status_menu_speech" `
    -Message 'Auction Sales Status should have its own auclist speech handler instead of using the bid item-list reader.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)menu_name:eq\('menu    auclist', true\).*?auction_sales_status_menu_speech\(menu_name.*?auction_item_list_menu_speech\(menu_name" `
    -Message 'Auction auclist should try Sales Status before the generic bid item-list handler.'

Assert-Match `
    -Text $source `
    -Pattern "auction_sales_status_context_tick" `
    -Message 'Auction Sales Status should remember recent Sales Status context so an empty list does not fall into the bid reader.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_counter_menu_speech(?:(?!function\s+accessxi\.).)*visible_selected\s*==\s*3(?:(?!function\s+accessxi\.).)*auction_sales_status_context_tick\s*=\s*tick\(\)" `
    -Message 'Selecting Sales Status at the auction counter should mark the Sales Status list context.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.reset_auction_item_packet_cache(?:(?!function\s+accessxi\.).)*auction_sales_status_context_tick\s*=\s*0" `
    -Message 'Auction category resets should clear Sales Status context and stale Sales Status rows.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_sales_status_menu_speech(?:(?!function\s+accessxi\.).)*No items currently placed on auction" `
    -Message 'Empty Auction Sales Status should speak an explicit empty state instead of reusing stale rows.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_sales_status_menu_speech(?:(?!function\s+accessxi\.).)*auction_sales_status_rows\s*=\s*\{\}(?:(?!function\s+accessxi\.).)*auction_sales_status_tick\s*=\s*0" `
    -Message 'Empty Auction Sales Status should clear stale packet-backed rows before speaking.'

Assert-NotMatch `
    -Text $source `
    -Pattern 'Iridium|Rhodium Ingot|Panopt Tears|Marble Nugget|Ratatoskr Pelt' `
    -Message 'Auction Sales Status should not hardcode screenshot item names.'

Assert-Match `
    -Text $source `
    -Pattern "u16be" `
    -Message 'Auction item list item-id scan should check byte-swapped row words as well as native u16 values.'

Assert-Match `
    -Text $source `
    -Pattern "auction_item_list_entry_words" `
    -Message 'Auction item list missing-label diagnostics should include selected entry numeric words.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_item_list_offset_probe.*?read_u16\(entry \+ 0x0C\).*?raw \+ desc_offset.*?child \+ desc_offset" `
    -Message 'Auction item list diagnostics should follow the native row offset into menu-backed records.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_item_list_offset_probe.*?state auction-item-list offset-root.*?append_root\('raw\+off'.*?append_root\('child\+off'.*?append_root\('entry', entry\)" `
    -Message 'Auction item list offset diagnostics should log row-backed roots before the large entry record.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.auction_item_list_pointer_probe" `
    -Message 'Auction item list should have a bounded pointer probe for row text hidden behind native pointers.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_item_list_pointer_probe.*?read_u32\(root\.ptr \+ off\).*?state auction-item-list pointer-root" `
    -Message 'Auction item list pointer diagnostics should chase native pointers and log only bounded pointer roots.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_item_list_pointer_candidate.*?ptr\s*<\s*0x10000000.*?bit\.band\(ptr,\s*0x03\)\s*~=\s*0" `
    -Message 'Auction item list pointer diagnostics should reject low-address and unaligned byte-pattern false pointers.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)add_base\('entry',\s*entry\).*?add_base\('child',\s*child\).*?add_base\('raw',\s*raw\)" `
    -Message 'Auction item list pointer diagnostics should scan selected entry and child roots before raw byte buffers.'

Assert-NotMatch `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.auction_item_list_menu_speech(?:(?!function\s+accessxi\.).)*item_source\s*=\s*'resource-id'" `
    -Message 'Auction item list should not speak loose resource-id memory guesses as item names.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)state auction-item-list native-missing-label.*?offsetProbe=.*?auction_item_list_offset_probe.*?auction_item_list_memory_probe" `
    -Message 'Auction item list missing-label logging should include targeted row-offset and nearby native memory evidence.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)state auction-item-list native-missing-label.*?pointerProbe=.*?auction_item_list_pointer_probe" `
    -Message 'Auction item list missing-label logging should include pointer-chase evidence before broad nearby-memory evidence.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)state auction-item-list native-missing-label.*?escape_probe_log_text_wide\(accessxi\.auction_item_list_offset_probe" `
    -Message 'Auction item list offset diagnostics should use the wide log escape so row records are not clipped.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)auction_counter_menu_speech.*?enable_auction_packet_trace\(menu_name\).*?auction_bid_category_menu_speech.*?enable_auction_packet_trace\(menu_name\).*?auction_weapon_category_menu_speech.*?enable_auction_packet_trace\(menu_name\).*?auction_armor_category_menu_speech.*?enable_auction_packet_trace\(menu_name\).*?auction_magic_category_menu_speech.*?enable_auction_packet_trace\(menu_name\).*?auction_item_list_menu_speech.*?enable_auction_packet_trace\(menu_name\)" `
    -Message 'Auction packet trace should be armed from every auction menu layer before the item list opens.'

Assert-Match `
    -Text $source `
    -Pattern "trace_auction_packet\(e,\s*'in'\)" `
    -Message 'Auction packet trace should be hooked for incoming packets.'

Assert-Match `
    -Text $source `
    -Pattern "trace_auction_packet\(e,\s*'out'\)" `
    -Message 'Auction packet trace should be hooked for outgoing packets.'

Assert-Match `
    -Text $source `
    -Pattern "state auction-item-list native" `
    -Message 'Auction item list handler should log native evidence when it speaks.'

Assert-NotMatch `
    -Text $source `
    -Pattern 'View all merchandise up for auction|Place unwanted items on auction|View weapons on auction|View magic scrolls on auction|View crystals on auction|View recent sales data for this merchandise|Place a bid on this merchandise|Sales data for the last ten transactions of selected merchandise|One-handed katana|One-handed clubs|Daggers, knives|Biblo|Mailbreaker|Colichemarde|Verdun|Blaze Spikes|Yuutousei|Pergatory|Amomoia|Caious|Delysia' `
    -Message 'Auction counter rows must not be hardcoded in accessxi_reader.lua.'

Assert-NotMatch `
    -Text $nativeMenus `
    -Pattern 'View all merchandise up for auction|Place unwanted items on auction|View weapons on auction|View magic scrolls on auction|View crystals on auction|View recent sales data for this merchandise|Place a bid on this merchandise|Sales data for the last ten transactions of selected merchandise|One-handed katana|One-handed clubs|Daggers, knives|Biblo|Mailbreaker|Colichemarde|Verdun|Blaze Spikes|Yuutousei|Pergatory|Amomoia|Caious|Delysia' `
    -Message 'Auction counter rows must not be hardcoded in native_menus.lua.'

Write-Host 'auction counter native menu static checks ok'
