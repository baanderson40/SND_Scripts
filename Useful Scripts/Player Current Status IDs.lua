local list = Player.Status
if not list or not list.Count or list.Count == 0 then
    yield("/echo No statuses found.")
    return
end

local count = 0
for i = 0, list.Count - 1 do  -- zero-based index
    local s = list[i] or list:get_Item(i)
    if s then
        yield(("/echo Status %d: %d"):format(i, s.StatusId))
    end
end
