local DEBUG = true

local function ResolveNpcName(kind, dataId)
    local k = tostring(kind):lower()

    -- ENpcResident fast-path
    do
        local en = Excel.GetSheet("ENpcResident")
        if en then
            local row = en:GetRow(dataId)
            if row and (row.Singular or row.Name) then
                if DEBUG then print(("ENpcResident(%d) → %s"):format(dataId, row.Singular or row.Name)) end
                return row.Singular or row.Name, "ENpcResident"
            end
        end
    end

    -- EventNpc → ENpcResident
    if k == "eventnpc" or k == "3" then
        local ev = Excel.GetSheet("EventNpc")
        if ev then
            local evRow = ev:GetRow(dataId)
            if evRow then
                local link = evRow.ENpcResident or evRow.NameId or evRow.ENpcResidentId
                local linkId = (type(link) == "table" and link.RowId) or link
                local en = Excel.GetSheet("ENpcResident")
                local enRow = en and linkId and en:GetRow(linkId)
                if enRow and (enRow.Singular or enRow.Name) then
                    if DEBUG then print(("EventNpc(%d) → ENpcResident(%d) → %s"):format(dataId, linkId, enRow.Singular or enRow.Name)) end
                    return enRow.Singular or enRow.Name, "EventNpc → ENpcResident"
                end
            end
        end
    end

    -- BNpcBase → BNpcName
    do
        local base = Excel.GetSheet("BNpcBase")
        local b = base and base:GetRow(dataId)
        if b then
            local link = b.BNpcName or b.NameId
            local nameId = (type(link) == "table" and link.RowId) or link
            local names = Excel.GetSheet("BNpcName")
            local nm = names and names:GetRow(nameId)
            if nm and (nm.Singular or nm.Name) then
                if DEBUG then print(("BNpcBase(%d) → BNpcName(%d) → %s"):format(dataId, nameId, nm.Singular or nm.Name)) end
                return nm.Singular or nm.Name, "BNpcBase → BNpcName"
            end
        end
    end

    if DEBUG then print(("Unresolved: kind=%s dataId=%s"):format(k, tostring(dataId))) end
    return nil, "unresolved"
end

local npcCache = {}

local function GetNpcName(kind, dataId)
    local key = tostring(kind) .. ":" .. tostring(dataId)
    local cached = npcCache[key]
    if cached ~= nil then return cached.name, cached.source end
    local name, source = ResolveNpcName(kind, dataId)
    npcCache[key] = { name = name, source = source }
    return name, source
end

-- usage
local name, source = GetNpcName("EventNpc", 1052642)
print("Resolved NPC name:", name or "<not found>", "from sheet:", source)
