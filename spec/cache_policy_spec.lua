local Lookup = require("dpd/lookup")
local DBCompat = require("dpd/db_compat")

describe("detail cache ownership", function()
    it("evicts old cache rows without invalidating a frame and refetches on demand", function()
        local reads = 0
        local lookup = Lookup.new({query=function() return {} end,
            detail=function(_, id) reads = reads + 1; return {id=id, notes="detail " .. id} end})
        lookup.detail_limit = 2
        local frame_detail = lookup:detail(1)
        lookup:detail(2)
        assert.equal(frame_detail, lookup:detail(1))
        assert.equal(2, reads)
        lookup:detail(3)
        assert.is_nil(lookup.details[1])
        assert.equal("detail 1", frame_detail.notes)
        assert.equal(2, #lookup.detail_order)
        assert.equal(frame_detail.notes, lookup:detail(1).notes)
        assert.equal(4, reads)
        assert.is_nil(lookup.details[2])
        assert.equal(2, #lookup.detail_order)
    end)
end)

describe("database release metadata", function()
    it("names the tested release without gating newer ones", function()
        assert.equal("DPD " .. DBCompat.release .. ", schema " .. DBCompat.schema, DBCompat.tested())
        assert.is_nil(DBCompat.warning)
    end)
end)

