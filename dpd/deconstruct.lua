local Normalize = require("dpd/normalize")
local M = {}

function M.parse(raw)
    if type(raw) ~= "string" or Normalize.trim(raw) == "" then return nil end
    local parts, start = {}, 1
    while true do
        local at = raw:find("+", start, true)
        local part = Normalize.trim(raw:sub(start, at and at - 1 or #raw))
        if part == "" then return nil end
        parts[#parts + 1] = part
        if not at then break end
        start = at + 1
    end
    return parts
end

function M.analyses(raws)
    local out = {}
    for i, raw in ipairs(raws) do out[i] = { raw = raw, parts = M.parse(raw) } end
    return out
end

return M
