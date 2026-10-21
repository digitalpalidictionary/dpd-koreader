local Json = require("json")
local Families = require("dpd/families")

local keys = {family_root="root_family_key",family_word="word_family",
    family_compound="compound_family",family_idiom="idiom",family_set="set"}
local function fixture()
    local db = {tables={},calls={},payload_queries=0,sense_queries=0,records={}}
    function db:add(table_name,key,items,extra)
        self.tables[table_name] = self.tables[table_name] or {}
        local row = extra or {}
        -- The exporter writes "[]"; lua-json would encode an empty table as "{}".
        row.family_key,row.count,row.data = key,#items,#items == 0 and "[]" or Json.encode(items)
        self.tables[table_name][key] = row
        return row
    end
    function db:query(sql,params)
        self.calls[#self.calls+1] = {sql=sql,params=params}
        local table_name = sql:match("PRAGMA table_info%(([%w_]+)%)")
        if table_name then
            if not self.tables[table_name] then return {} end
            local out = {{name=keys[table_name]},{name="data"},{name="count"}}
            if table_name == "family_root" then out[#out+1]={name="root_key"};out[#out+1]={name="root_family"} end
            return out
        end
        table_name = assert(sql:match(" FROM ([%w_]+)"))
        if sql:match("^SELECT data ") then self.payload_queries=self.payload_queries+1 end
        local rows = self.tables[table_name] or {}
        if sql:find("WHERE root_key = ?",1,true) then
            local out={};for _,row in pairs(rows) do if row.root_key == params[1] then out[#out+1]=row end end
            table.sort(out,function(a,b) return a.family_key < b.family_key end)
            return out
        end
        return rows[params[1]] and {rows[params[1]]} or {}
    end
    function db:sensesByLemma(lemmas)
        self.sense_queries = self.sense_queries+1
        self.last_lemmas = lemmas
        local out = {}
        for _,lemma in ipairs(lemmas) do
            if self.records[lemma] then out[#out+1] = self.records[lemma] end
        end
        return out
    end
    return Families.new(db),db
end

describe("lazy paginated optional DPD families",function()
    it("keeps older and minimal databases usable without optional tables",function()
        local families,db = fixture()
        assert.same({},families:groupsForDetail{family_word="dhamma",family_compound="dhamma"})
        assert.same({},families:groupsForRoot("√dhar 1"))
        assert.same({},families:page("word","dhamma").items)
        local calls=#db.calls
        families:page("word","dhamma")
        assert.equal(calls,#db.calls,"missing schemas are probed once")
        assert.same({},Families.new({}):groupsForDetail{family_word="dhamma"})
    end)

    it("discovers exact detail groups without reading JSON payloads",function()
        local families,db=fixture()
        db:add("family_root","√dhar 1 √dhar",{{"dhamma 1.01","masc","quality"}},
            {root_key="√dhar 1",root_family="√dhar"})
        db:add("family_word","buddha",{{"buddha 1","masc","awakened"}})
        db:add("family_compound","dhamma",{{"dhammacakka","nt","wheel"}})
        db:add("family_compound","cakka",{{"dhammacakka","nt","wheel"}})
        db:add("family_idiom","dhamma",{{"dhammaṃ carati","idiom","practises"}})
        local row={root_key="√dhar 1",family_root="√dhar",family_word="buddha",
            family_compound="dhamma cakka dhamma missing",family_idioms="dhamma"}
        local groups=families:groupsForDetail(row)
        assert.equal(5,#groups)
        assert.equal("√dhar 1 √dhar",groups[1].key)
        assert.equal("Root family: √dhar",groups[1].title)
        assert.equal("compound",groups[3].kind)
        assert.equal("cakka",groups[4].key)
        assert.equal(0,db.payload_queries)
        local calls=#db.calls
        assert.same(groups,families:groupsForDetail(row))
        assert.equal(calls,#db.calls,"positive and missing group metadata are cached")
    end)

    it("splits thematic set names on semicolons and quotes the set column",function()
        local families,db=fixture()
        db:add("family_set","great disciples",{{"sāriputta","masc","Sāriputta"}})
        db:add("family_set","names of monks",{{"sāriputta","masc","Sāriputta"},{"ānanda 2","masc","Ānanda"}})
        local groups=families:groupsForDetail{family_set="great disciples; missing set;names of monks; "}
        assert.equal(2,#groups)
        assert.equal("set",groups[1].kind)
        assert.equal("Thematic set: great disciples",groups[1].title)
        assert.equal("names of monks",groups[2].key)
        assert.equal(2,groups[2].count)
        local page=families:page("set","names of monks")
        assert.equal(2,page.total);assert.equal("ānanda 2",page.items[2].lemma)
        for _,call in ipairs(db.calls) do
            if call.sql:find("FROM family_set",1,true) then
                assert.is_truthy(call.sql:find('WHERE "set" = ?',1,true))
            end
        end
    end)

    it("ignores optional family schemas missing required payload columns",function()
        local families,db=fixture()
        db:add("family_word","word",{{"word","noun","meaning"}})
        local original=db.query
        function db:query(sql,params)
            if sql=="PRAGMA table_info(family_word)" then return {{name="word_family"},{name="count"}} end
            return original(self,sql,params)
        end
        assert.same({},families:groupsForDetail{family_word="word"})
        assert.same({},families:page("word","word").items)
        assert.equal(0,db.payload_queries)
    end)

    it("keeps numbered root identities separate",function()
        local families,db=fixture()
        db:add("family_root","√har 1 √har",{{"a","noun","one"}},{root_key="√har 1",root_family="√har"})
        db:add("family_root","√har 2 ā √har",{{"b","noun","two"}},{root_key="√har 2",root_family="ā √har"})
        local groups=families:groupsForRoot{root="√har 2"}
        assert.equal(1,#groups)
        assert.equal("√har 2 ā √har",groups[1].key)
        assert.equal(0,db.payload_queries)
        local calls=#db.calls
        families:groupsForRoot("√har 2")
        assert.equal(calls,#db.calls)
    end)

    it("pages twenty members at a time and batches exact numbered identities",function()
        local families,db=fixture()
        local members={}
        for i=1,25 do
            members[i]={"dhamma " .. string.format("1.%02d",i),"masc","sense " .. i,"✔"}
            db.records[members[i][1]]={id=i,lemma_1=members[i][1]}
        end
        db:add("family_compound","dhamma",members)
        local first=families:page("compound","dhamma")
        assert.equal(20,#first.items);assert.equal(25,first.total)
        assert.is_true(first.has_more);assert.equal(20,first.next_offset)
        assert.equal("dhamma 1.01",first.items[1].lemma)
        assert.equal(1,first.items[1].id);assert.is_true(first.items[1].available)
        assert.equal(1,db.payload_queries);assert.equal(1,db.sense_queries)
        assert.equal(20,#db.last_lemmas)
        local second=families:page("compound","dhamma",first.next_offset)
        assert.equal(5,#second.items);assert.equal(21,second.items[1].id)
        assert.is_false(second.has_more);assert.equal(25,second.next_offset)
        assert.equal(1,db.payload_queries,"later pages reuse decoded data")
        assert.equal(2,db.sense_queries,"resolve only the visible page")
        assert.same({},families:page("compound","dhamma",100).items)
        assert.equal(2,db.sense_queries,"empty pages do not query headwords")
    end)

    it("retains unavailable members without substituting a sibling numbered sense",function()
        local families,db=fixture()
        db:add("family_word","dhamma",{{"dhamma 1.01","masc","one"},{"dhamma 1.02","masc","two"}})
        db.records["dhamma 1.01"]={id=1,lemma_1="dhamma 1.01"}
        local page=families:page("word","dhamma")
        assert.is_true(page.items[1].available)
        assert.is_false(page.items[2].available);assert.is_nil(page.items[2].id)
        assert.equal("two",page.items[2].meaning)
    end)

    it("binds hostile keys and rejects identifiers and invalid page bounds",function()
        local families,db=fixture()
        local hostile="x' OR 1=1 --"
        db:add("family_word",hostile,{{"x","noun","one"}})
        assert.equal(1,#families:page("word",hostile).items)
        for _,call in ipairs(db.calls) do
            assert.is_falsy(call.sql:find(hostile,1,true))
        end
        assert.has_error(function()families:page("word;DROP TABLE lookup","x")end)
        for _,key in ipairs({"",string.rep("x",1025),"x\0y"}) do
            assert.has_error(function()families:page("word",key)end)
        end
        for _,offset in ipairs({-1,0.5,2147483648,math.huge}) do
            assert.has_error(function()families:page("word","x",offset)end)
        end
        for _,limit in ipairs({0,1.5,101,math.huge}) do
            assert.has_error(function()families:page("word","x",0,limit)end)
        end
    end)

    it("contains malformed optional family payloads with an actionable message",function()
        for _,raw in ipairs({'{broken','{"lemma":"x"}','[] trailing','[["x",3,"meaning"]]',
            '[["x","noun","meaning"],{"lemma":"bad"}]',string.rep(" ",1048577)}) do
            local families,db=fixture()
            db:add("family_word","bad",{{"x","noun","meaning"}}).data=raw
            local page=families:page("word","bad")
            assert.equal(0,page.total);assert.same({},page.items)
            assert.is_truthy(page.error:find("replace the database",1,true))
            assert.is_false(page.has_more)
        end
    end)

    it("allows empty optional records and missing groups",function()
        local families,db=fixture()
        db:add("family_word","empty",{})
        local page=families:page("word","empty")
        assert.same({},page.items);assert.is_nil(page.error)
        assert.same({},families:page("word","missing").items)
        assert.same({},families:groupsForDetail{family_word="empty"})
    end)

    it("bounds decoded-family retention to four opened groups",function()
        local families,db=fixture()
        for i=1,5 do db:add("family_word","group" .. i,{{"word","noun","meaning"}}) end
        for i=1,5 do families:page("word","group" .. i) end
        assert.equal(5,db.payload_queries)
        local retained=0;for _ in pairs(families.decoded) do retained=retained+1 end
        assert.equal(4,retained)
        families:page("word","group5");assert.equal(5,db.payload_queries)
        families:page("word","group1");assert.equal(6,db.payload_queries)
    end)
end)
