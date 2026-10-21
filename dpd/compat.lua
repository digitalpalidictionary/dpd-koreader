-- KOReader features DPD relies on that older releases lack. The README states the
-- tested minimum; this check turns a crash on an older build into a message.
-- Add an entry whenever DPD starts relying on a KOReader API that older
-- releases lack. Checks run once, when the plugin loads.
local Compat = { minimum = "v2026.07" }
local Diag = require("dpd/diag")

Compat.features = {
    -- v2026.03: the delay ReaderHighlight uses before clearing a selection.
    { name = "DELAY_CLEAR_HIGHLIGHT_S", check = function()
        return G_defaults ~= nil and G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S") ~= nil
    end },
    -- v2026.07: reading the scroll position, used to keep the place when expanding.
    { name = "ScrollHtmlWidget:getCurrentRatio", check = function()
        return type(require("ui/widget/scrollhtmlwidget").getCurrentRatio) == "function"
    end },
}

-- Returns the names of missing features; an empty list means DPD can run.
-- A failed check is logged, but does not prove that the KOReader is too old.
function Compat.missing()
    local missing = {}
    for _, feature in ipairs(Compat.features) do
        local ok, present = Diag.protect("compatibility check " .. feature.name, feature.check)
        if ok and not present then missing[#missing + 1] = feature.name end
    end
    return missing
end

function Compat.message(missing)
    return "Digital Pāḷi Dictionary needs KOReader " .. Compat.minimum .. " or newer. "
        .. "Please update KOReader.\n\nMissing: " .. table.concat(missing, ", ")
end

return Compat
