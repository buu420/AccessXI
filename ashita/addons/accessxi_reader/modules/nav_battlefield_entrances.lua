-- BATTLEFIELD ENTRANCES.
--
-- Generated from LandSandBoat sql/npc_list.sql. DO NOT HAND-EDIT.
--
-- Every Burning Circle in the game displays the same name, "Burning Circle",
-- but LSB's script name separates two completely different objects:
--
--   BC_Entrance     the one you walk to and trigger to enter the battlefield
--   Burning_Circle  the EXIT, standing inside an arena room you can only reach
--                   by being teleported there
--
-- There are FOUR entrances in the whole game and TWELVE exits, and they share
-- the same four zones -- so every battlefield zone offers one reachable object
-- and three that no player can ever walk to. The catalogue kept only the
-- display name, so live 2026-08-26 the player was routed at an arena-interior
-- exit for "Enter the rank 2 battlefield at Balga's Dais through the Burning
-- Circle" and had to build the route themselves. The Black Dragon has the same
-- problem: its three spawn points are the three arena rooms.
--
-- Keyed by the zone the battlefield lives in. Positions are AccessXI order
-- (x, z, y) -- note LSB writes x y z -- and FFXI's y axis is INVERTED, so a
-- SMALLER y is HIGHER ground.
return {
    [139] = {   -- Horlais Peak
        zone_id = 139,
        zone_name = "Horlais Peak",
        name = "Burning Circle",
        server_id = 17347120,
        x = -502.952, z = -212.555, y = 158.290,
        exit_server_ids = { 17347121, 17347122, 17347123 },
    },
    [144] = {   -- Waughroon Shrine
        zone_id = 144,
        zone_name = "Waughroon Shrine",
        name = "Burning Circle",
        server_id = 17367784,
        x = -339.601, z = -260.341, y = 104.304,
        exit_server_ids = { 17367785, 17367786, 17367787 },
    },
    [146] = {   -- Balga's Dais
        zone_id = 146,
        zone_name = "Balga's Dais",
        name = "Burning Circle",
        server_id = 17375822,
        x = 298.946, z = 341.304, y = -124.124,
        exit_server_ids = { 17375823, 17375824, 17375825 },
    },
    [206] = {   -- Qu'Bia Arena
        zone_id = 206,
        zone_name = "Qu'Bia Arena",
        name = "Burning Circle",
        server_id = 17621587,
        x = -213.708, z = 20.092, y = -24.624,
        exit_server_ids = { 17621588, 17621589, 17621590 },
    },
};
