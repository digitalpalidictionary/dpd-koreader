local Direct = require("dpd/direct")

describe("direct wrapper lifecycle", function()
    it("hands off through later wrappers, preserves returns and restores interception after errors", function()
        local lookups, outer_calls, args = 0,0,nil
        local dictionary = {onLookupWord=function(_, ...)
            args={...}
            return "normal",nil,"third"
        end}
        local direct = Direct.install(dictionary,function() lookups=lookups+1; return true end)
        local delegate = dictionary.onLookupWord
        dictionary.onLookupWord=function(dict, ...)
            outer_calls=outer_calls+1
            return delegate(dict,...)
        end
        local callback=function() end
        local first,second,third=direct:handoff("word",false,nil,nil,nil,callback)
        assert.equal("normal",first);assert.is_nil(second);assert.equal("third",third)
        assert.equal(callback,args[6]);assert.equal(1,outer_calls);assert.equal(0,lookups)
        dictionary.onLookupWord=function() error("handoff failed") end
        assert.has_error(function() direct:handoff("word") end)
        dictionary.onLookupWord=delegate
        assert.is_true(dictionary:onLookupWord("word"));assert.equal(1,lookups)
    end)
    it("never reactivates a wrapper retired during handoff", function()
        local dictionary={onLookupWord=function() return "normal" end}
        local direct=Direct.install(dictionary,function() error("retired wrapper intercepted") end)
        local delegate=dictionary.onLookupWord
        dictionary.onLookupWord=function(dict,...)
            direct:remove()
            return delegate(dict,...)
        end
        assert.equal("normal",direct:handoff("word"))
        assert.is_false(direct.active)
        assert.equal("normal",dictionary:onLookupWord("word"))
    end)
    it("does not patch an unavailable upstream lookup method", function()
        local dictionary = {onLookupWord=true}
        local wrapper, err = Direct.install(dictionary, function() return true end)
        assert.is_nil(wrapper)
        assert.equal(true, dictionary.onLookupWord)
        assert.matches("lookup API is unavailable", err, 1, true)
    end)
    it("retires retained wrappers and preserves normal lookup arguments across reinstall", function()
        local lookup_calls, normal_calls, outer_calls = 0, 0, 0
        local normal_args, normal_count
        local dictionary
        dictionary = { onLookupWord = function(dict, ...)
            assert.equal(dictionary, dict)
            normal_calls = normal_calls + 1
            normal_args, normal_count = {...}, select("#", ...)
            return "normal", "second return"
        end }
        local function lookup()
            lookup_calls = lookup_calls + 1
            return true
        end
        local retired = Direct.install(dictionary, lookup)
        local delegate = dictionary.onLookupWord
        local outer = function(dict, ...)
            outer_calls = outer_calls + 1
            return delegate(dict, ...)
        end
        dictionary.onLookupWord = outer
        retired:remove()
        assert.equal(outer, dictionary.onLookupWord)
        local current = Direct.install(dictionary, lookup)
        assert.is_true(dictionary:onLookupWord("pacchima"))
        assert.equal(1, lookup_calls)
        local boxes, highlight, close = {}, {}, function() end
        local first, second = current.original(dictionary, "pacchima", false, boxes, highlight, nil, close, nil)
        assert.equal("normal", first)
        assert.equal("second return", second)
        assert.equal(1, outer_calls)
        assert.equal(1, normal_calls)
        assert.equal(1, lookup_calls)
        assert.equal(7, normal_count)
        assert.same({"pacchima", false, boxes, highlight, nil, close}, normal_args)
        retired:remove() -- Repeated removal cannot overwrite a newer hook.
        assert.equal(current.wrapper, dictionary.onLookupWord)
        current:remove()
        assert.equal(outer, dictionary.onLookupWord)
        assert.equal("normal", dictionary:onLookupWord("pacchima"))
        assert.equal(1, lookup_calls)
    end)

    it("does not call a retired lookup or error callback", function()
        local calls = 0
        local dictionary = {onLookupWord = function() calls = calls + 1; return "normal" end}
        local retired = Direct.install(dictionary, function() error("retired lookup called") end,
            function() error("retired error callback called") end)
        local retained = retired.wrapper
        retired:remove()
        assert.equal("normal", retained(dictionary, "word"))
        assert.equal(1, calls)
    end)
end)
