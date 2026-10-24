-- Velthuis input for the manual lookup dialog only, as DPD's webapp converts
-- its search box (exporter/webapp/static/home.js uniCoder): the same eleven
-- sequences, replaced in the same order. Opt-in and Pāḷi mode only, so an
-- English query such as "aardvark" is never changed; book selections are
-- never converted. Searching the other dictionaries adds the standard
-- Sanskrit sequences, which Pāḷi mode leaves as typed.
-- SPDX-License-Identifier: MIT
local Velthuis = {}

Velthuis.map = {
    { "aa", "ā" }, { "ii", "ī" }, { "uu", "ū" }, { '"n', "ṅ" }, { "~n", "ñ" },
    { ".t", "ṭ" }, { ".d", "ḍ" }, { ".n", "ṇ" }, { ".m", "ṃ" }, { ".l", "ḷ" }, { ".h", "ḥ" },
}
-- .rr before .r, so ṝ is not read as ṛ followed by r.
Velthuis.sanskrit = { { ".rr", "ṝ" }, { ".r", "ṛ" }, { '"s', "ś" }, { ".s", "ṣ" } }

local function escape(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end

local function apply(text, map)
    for _, pair in ipairs(map) do text = text:gsub(escape(pair[1]), pair[2]) end
    return text
end

--- Converts Velthuis sequences; text without them is returned unchanged.
--- @param options table|nil { sanskrit = true } also converts ṛ ṝ ś ṣ
function Velthuis.toUnicode(text, options)
    text = tostring(text or "")
    if options and options.sanskrit then text = apply(text, Velthuis.sanskrit) end
    return apply(text, Velthuis.map)
end

return Velthuis
