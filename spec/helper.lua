-- Loaded once by .busted before every spec. Production KOReader and CI ship
-- lua-json as `json`; use it when present, else fall back to dkjson. Keep
-- this the only place that chooses: package.preload persists across files.
if not pcall(require, "json") then
    package.preload["json"] = function() return require("dkjson") end
end
