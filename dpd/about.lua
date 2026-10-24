-- SPDX-License-Identifier: MIT
local About = {}

-- The bundled other dictionaries, with their authors as the database names them.
local function sources()
    local Dictionaries = require("dpd/dictionaries")
    local lines = {}
    for _, id in ipairs(Dictionaries.order) do
        local entry = Dictionaries.bibliography[id]
        if entry then lines[#lines + 1] = "\n• " .. entry[1] .. (entry[2] and (" — " .. entry[2]) or "") end
    end
    return table.concat(lines)
end

function About.text(info)
    return "Digital Pāḷi Dictionary for KOReader " .. require("dpd/version")
        .. "\n\nPlugin code: MIT License. The Lua source and full license are included in the plugin folder (LICENSE)."
        .. "\n\nDictionary data: Digital Pāḷi Dictionary, © Bodhirasa Bhikkhu. CC BY-NC-SA 4.0."
        .. "\nDatabase version: " .. tostring(info and info.dpd_release_version or "not opened / unknown")
        .. "\nhttps://www.dpdict.net/"
        .. "\nhttps://creativecommons.org/licenses/by-nc-sa/4.0/"
        .. "\n\nThe database is downloaded separately. Screenshots, examples and test fixtures that reproduce dictionary data keep the DPD license; see LICENSE-DPD and NOTICE."
        .. "\n\nAdditional dictionary content comes from sources included in the DPD database and may have separate attribution or licensing terms; see the DPD project for source details:"
        .. sources()
end

return About
