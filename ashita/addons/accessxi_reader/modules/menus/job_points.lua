local data = {};

-- Packet/resource job point ids are grouped by job. The visible menu's first
-- three rows are ordered 0, 2, 1 in the client, then continue sequentially.
data.option_order_offsets = T{ 0, 2, 1, 3, 4, 5, 6, 7, 8, 9 };

return data;
