-- SPDX-License-Identifier: MIT
-- The release these checks and budgets were recorded against. Compatibility is
-- DB.new's required-column contract, not this version: newer releases with the
-- same core columns are expected to work, and optional views degrade on their own.
local Compat = {
    schema = "7",
    release = "v0.4.20260926",
}

function Compat.tested()
    return "DPD " .. Compat.release .. ", schema " .. Compat.schema
end

return Compat
