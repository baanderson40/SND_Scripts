local sheet = Excel.GetSheet("ClassJob")
assert(sheet, "ClassJob sheet not found")
local jobs = {}
for id = 1, 45 do
    local row = sheet:GetRow(id)
    if row then
        local name = row.Name or row["Name"]
        local abbr = row.Abbreviation or row["Abbreviation"]
        if name and abbr then
            jobs[id] = { name = name, abbr = abbr }
        else
            print(("ClassJob %d: missing Name/Abbreviation"):format(id))
        end
    else
        print(("ClassJob %d: row not found"):format(id))
    end
end
