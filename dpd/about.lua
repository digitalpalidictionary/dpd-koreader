-- SPDX-License-Identifier: MIT
local About = {}

-- The other dictionaries in the open database, with their authors as it
-- names them; without one, those known here. A database without any has
-- none to credit.
local function sources(listed)
    local Dictionaries = require("dpd/dictionaries")
    if listed and #listed == 0 then return "" end
    if not listed then
        listed = {}
        for _, id in ipairs(Dictionaries.order) do
            local entry = Dictionaries.bibliography[id]
            if entry then listed[#listed + 1] = { name = entry[1], author = entry[2] } end
        end
    end
    local lines = {}
    for _, item in ipairs(listed) do
        local author = item.author ~= "" and item.author
        lines[#lines + 1] = "\n• " .. (item.name or item.id) .. (author and (" — " .. author) or "")
    end
    return table.concat(lines)
end

function About.text(info, dictionaries)
    local credited = sources(dictionaries)
    return "Digital Pāḷi Dictionary for KOReader " .. require("dpd/version")
        .. "\n\nPlugin code: MIT License. The Lua source and full license are included in the plugin folder (LICENSE)."
        .. "\n\nDictionary data: Digital Pāḷi Dictionary, © Bodhirasa Bhikkhu. CC BY-NC-SA 4.0."
        .. "\nDatabase version: " .. tostring(info and info.dpd_release_version or "not opened / unknown")
        .. "\nhttps://www.dpdict.net/"
        .. "\nhttps://creativecommons.org/licenses/by-nc-sa/4.0/"
        .. "\n\nThe database is downloaded separately. Screenshots, examples and test fixtures that reproduce dictionary data keep the DPD license; see LICENSE-DPD and NOTICE."
        .. (credited ~= "" and ("\n\nAdditional dictionary content comes from sources included in the DPD database and may have separate attribution or licensing terms; see the DPD project for source details:"
            .. credited) or "")
end

return About
