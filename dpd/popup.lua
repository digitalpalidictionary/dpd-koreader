-- Shared reading-selection routing and HTML preparation. Keep the headless
-- budget check on the same path as the real popup; native layout stays in UI.
local Lookup = require("dpd/lookup")
local Render = require("ui/dpd_render")
local Popup = { selection_options = { prefix = false } }

function Popup.route(model)
    -- Manual English searches keep a recoverable popup even on a miss.
    if model.matched_via == "english" then return "dpd" end
    -- A long Pāḷi miss with a known beginning or ending offers those parts.
    if model.long_miss then return "dpd" end
    return Lookup.directHit(model) and "dpd" or "dictionary"
end

function Popup.render(lookup, frame, options)
    options = options or {}
    frame.paradigm_columns = options.paradigm_columns
    frame.content_em = options.content_em
    frame.other_dictionaries, frame.dictionaries_error = false, nil
    if options.dictionaries ~= nil and #options.dictionaries > 0 and lookup.hasOtherDictionaries then
        local ready, err = lookup:hasOtherDictionaries()
        frame.other_dictionaries, frame.dictionaries_error = ready == true, err
    end
    return Render.niggahita(Render.render(frame.model, frame, nil,
        options.edit_search, options.layout), options.niggahita)
end

return Popup
