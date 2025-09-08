-- One-call helper: TerritoryType ID -> localized PlaceName (string or nil)
local function PlaceNameByTerritory(id)
    local terr = Excel.GetSheet("TerritoryType"); if not terr then return nil end
    local row  = terr:GetRow(id);                  if not row  then return nil end
    local pn   = row.PlaceName;                    if not pn   then return nil end

    if type(pn) == "string" and #pn > 0 then return pn end

    if type(pn) == "userdata" then
        local ok,val = pcall(function() return pn.Value end)
        if ok and val then
            local ok2,name = pcall(function() return val.Singular or val.Name or val:ToString() end)
            if ok2 and name and name ~= "" then return name end
        end
        local okId,rid = pcall(function() return pn.RowId end)
        if okId and type(rid) == "number" then
            local place = Excel.GetSheet("PlaceName"); if not place then return nil end
            local prow  = place:GetRow(rid);           if not prow  then return nil end
            local ok3,name = pcall(function() return prow.Singular or prow.Name or prow:ToString() end)
            if ok3 and name and name ~= "" then return name end
        end
        return nil
    end

    if type(pn) == "number" then
        local place = Excel.GetSheet("PlaceName"); if not place then return nil end
        local prow  = place:GetRow(pn);            if not prow  then return nil end
        local ok,name = pcall(function() return prow.Singular or prow.Name or prow:ToString() end)
        if ok and name and name ~= "" then return name end
    end

    return nil
end

-- Usage (prints once):
local name = PlaceNameByTerritory(131)
print("PlaceName:", name or "<nil>")
