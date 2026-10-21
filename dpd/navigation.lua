local Navigation = {}
local Lookup = require("dpd/lookup")
Navigation.__index = Navigation
-- Similar forms already carry their loaded entries; the first ones start
-- open so a near miss reads like a result. Later ones start collapsed, a list
-- to scan: with ten open, khamma's nine forms ran to 7 pages at font 20.
Navigation.open_similar = 2
-- In-popup taps kept for Back, including the popup's own result.
Navigation.max_depth = 30

function Navigation.new(model)
    local self = setmetatable({ stack = {} }, Navigation)
    self:push(model)
    return self
end

function Navigation:current() return self.stack[#self.stack] end

local function newFrame(model)
    local analyses = {}
    for i, analysis in ipairs(model.deconstructions or {}) do
        analyses[i] = analysis.starts_open == true
    end
    local frame = { model = model, analyses = analyses,
        expanded = {}, details = {}, component_expanded = {}, component_details = {},
        suggestions = {}, references = {}, ratio = 0,
        grammar_open = false, variants_open = Lookup.isVariantOnly(model), variants_page = 1, attestations_open = false }
    for i, suggestion in ipairs(model.suggestions or {}) do
        frame.suggestions[i] = newFrame(suggestion.model)
        frame.suggestions[i].open = model.single_suggestion == true or i <= Navigation.open_similar
    end
    for i, reference in ipairs(model.references or {}) do
        if reference.model then
            frame.references[i] = newFrame(reference.model)
            frame.references[i].open = true
        end
    end
    return frame
end

function Navigation:push(model, ratio)
    if self:current() then self:current().ratio = ratio or 0 end
    self.stack[#self.stack + 1] = newFrame(model)
    -- Bound what a long chain of taps retains: forget the oldest frame above
    -- the popup's own result, which Back still returns to.
    if #self.stack > Navigation.max_depth then table.remove(self.stack, 2) end
end

function Navigation:back()
    if #self.stack > 1 then table.remove(self.stack); return true end
    return false
end

function Navigation:toggleSuggestion(index, parent)
    local frame = (parent or self:current()).suggestions[index]
    if frame then frame.open = not frame.open end
end

function Navigation:toggleReference(index, parent)
    local frame = (parent or self:current()).references[index]
    if frame then frame.open = not frame.open end
end

-- A nested control is resolved against the frame which generated it. Terminal
-- reference links intentionally remain actions, so they open the resolved model.
function Navigation:resolve(uri)
    local action = type(uri) == "string" and uri:match("^dpd:(.+)$")
    if not action then return end
    local frame = self:current()
    while true do
        local kind, index, rest = action:match("^(%a+)/(%d+)/(.+)$")
        if kind ~= "similar" and kind ~= "reference" then break end
        local children = kind == "similar" and frame.suggestions or frame.references
        frame = children and children[tonumber(index)]
        -- The compact source label sits outside the candidate's collapsed
        -- body. Its toggle remains tappable; hidden body controls do not.
        if not frame or (not frame.open and not (kind == "similar" and rest == "attestations-toggle")) then return end
        action = rest
    end
    -- Inline component details retain their own owner even when a headword
    -- appears in another component or the main result. Hidden controls cannot
    -- operate on an expansion belonging to that other owner.
    local analysis, part, rest = action:match("^component%-detail/(%d+)/(%d+)/(.+)$")
    if analysis then
        local id = tonumber(rest:match("^detail%-target/(%d+)/%d+$")
            or rest:match("^detail%-family/(%d+)/%d+$") or rest:match("^detail%-paradigm/(%d+)$")
            or rest:match("^detail%-frequency/(%d+)$") or rest:match("^detail%-sutta/(%d+)$"))
        if not id then return end
        local detail = self:componentDetail(tonumber(analysis), tonumber(part), id, frame)
        if not detail then return end
        return frame, "dpd:" .. rest, detail
    end
    return frame, "dpd:" .. action
end

function Navigation:extend(model, frame)
    frame = frame or self:current()
    local previous, children = {}, {}
    for i, suggestion in ipairs(frame.model.suggestions or {}) do
        previous[suggestion.query] = frame.suggestions[i]
    end
    for i, suggestion in ipairs(model.suggestions or {}) do
        children[i] = previous[suggestion.query]
        if not children[i] then
            children[i] = newFrame(suggestion.model)
            children[i].open = model.single_suggestion == true or i <= Navigation.open_similar
        end
    end
    frame.suggestions = children
    if model.single_suggestion and children[1] then children[1].open = true end
    frame.model = model
end

function Navigation:toggleAnalysis(index, frame)
    frame = frame or self:current()
    if not frame.model.deconstructions[index] then return end
    frame.analyses[index] = not frame.analyses[index]
end

function Navigation:toggleSense(id, detail, frame)
    frame = frame or self:current()
    local was_open = frame.expanded[id]
    frame.expanded = {}
    if not was_open then frame.expanded[id] = true; frame.details[id] = detail end
end

-- The sense a component control acts on, if that control is visible: its
-- analysis is open, the component is unique and the sense one of its first two.
function Navigation:componentSense(analysis_index, part_index, id, frame)
    frame = frame or self:current()
    local analysis = (frame.model.deconstructions or {})[analysis_index]
    if not analysis or not frame.analyses[analysis_index] or not analysis.parts
        or not (analysis.unique or {})[part_index] then return end
    local word = analysis.parts[part_index]
    local component = word and (frame.model.components or {})[word]
    for index, sense in ipairs(component and component.senses or {}) do
        if index > 2 then break end
        if sense.id == id then return sense end
    end
end

function Navigation:componentDetail(analysis, part, id, frame)
    frame = frame or self:current()
    if not self:componentSense(analysis, part, id, frame) then return end
    local expanded = (frame.component_expanded[analysis] or {})[part] or {}
    if not expanded[id] then return end
    return ((frame.component_details[analysis] or {})[part] or {})[id]
end

function Navigation:toggleComponentSense(analysis, part, id, detail, frame)
    frame = frame or self:current()
    if not self:componentSense(analysis, part, id, frame) then return end
    local expansions = frame.component_expanded
    local details = frame.component_details
    expansions[analysis] = expansions[analysis] or {}
    details[analysis] = details[analysis] or {}
    expansions[analysis][part] = expansions[analysis][part] or {}
    details[analysis][part] = details[analysis][part] or {}
    local open = expansions[analysis][part][id]
    expansions[analysis][part][id] = not open
    if not open then details[analysis][part][id] = detail end
    return true
end

return Navigation
