-- The webapp's "Traditional Lemma", ported from DPD's tools/lemma_traditional.py.
-- SPDX-License-Identifier: MIT
local Traditional = {}

-- From DPD's tools/lemma_traditional.py. Only these patterns change; every
-- other headword keeps lemma_1, and the webapp then shows no extra row.
Traditional.endings = {
    ["ant adj"] = "antu", ["ant masc"] = "antu", ["ar fem"] = "u", ["ar masc"] = "u",
    ["ar2 masc"] = "u", ["arahant masc"] = "arahanta", ["as masc"] = "a",
    ["bhavant masc"] = "bhavantu", ["mātar fem"] = "mātu",
}

--- The traditional lemma without its homonym number ("satthar 1.02" → "satthu"),
--- or nil when it equals the DPD lemma or the stem is an inflected form ("!").
--- @param detail table detail row with stem, pattern and lemma_1
function Traditional.lemma(detail)
    if type(detail) ~= "table" or type(detail.stem) ~= "string" or detail.stem:find("!", 1, true) then return nil end
    local ending = Traditional.endings[detail.pattern]
    if not ending then return nil end
    local traditional = (detail.stem .. ending):gsub("[!*]", "")
    local clean = tostring(detail.lemma_1 or ""):gsub(" %d.*$", "")
    if traditional == clean then return nil end
    return traditional
end

return Traditional
