-- An instance-level wrapper: other ReaderDictionary instances remain untouched.
local Direct = {}
Direct.__index = Direct

function Direct.install(dictionary, lookup, on_error)
    if type(dictionary.onLookupWord) ~= "function" then
        return nil, "KOReader's dictionary lookup API is unavailable."
    end
    local self = setmetatable({ dictionary = dictionary, original = dictionary.onLookupWord, active = true,
        own_original = rawget(dictionary, "onLookupWord") }, Direct)
    self.wrapper = function(dict, ...)
        if self.active and not self.bypass then
            local ok, handled = pcall(lookup, ...)
            if ok and handled then return true end
            if not ok and on_error then on_error(handled) end
        end
        -- Preserve every argument, including selection cleanup callbacks.
        return self.original(dict, ...)
    end
    dictionary.onLookupWord = self.wrapper
    return self
end

-- Use the live dictionary chain, bypassing DPD for this call only.
function Direct:handoff(...)
    local bypass = self.bypass
    self.bypass = true
    local function restore(ok, ...)
        self.bypass = bypass
        if not ok then error((...), 0) end
        return ...
    end
    return restore(pcall(self.dictionary.onLookupWord, self.dictionary, ...))
end

function Direct:remove()
    -- Later wrappers may retain ours as their delegate. Retire it permanently
    -- so reinstalling DPD cannot intercept the normal dictionary through it.
    self.active = false
    -- Do not overwrite another plugin's wrapper installed after ours.
    if self.dictionary.onLookupWord == self.wrapper then
        self.dictionary.onLookupWord = self.own_original
    end
end

return Direct
