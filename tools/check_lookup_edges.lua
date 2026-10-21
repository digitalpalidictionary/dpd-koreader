-- Run from a desktop KOReader directory with its bundled luajit:
-- ./luajit <plugin>/tools/check_lookup_edges.lua <plugin> <dpd-mobile.db>
-- Corpus regressions verified against mobile v0.4.20260926.
require('setupkoenv')
local root = assert(arg[1], 'plugin directory required')
local path = assert(arg[2], 'DPD database required')
package.path = root .. '/?.lua;' .. package.path
local DB = require('dpd/db')
local Lookup = require('dpd/lookup')
local Normalize = require('dpd/normalize')
local Render = require('ui/dpd_render')
local Navigation = require('dpd/navigation')
local Popup = require('dpd/popup')
local db = DB.new(path)
local lookup = Lookup.new(db)
for _, key in ipairs({'bhikkhunābhinandati','sūdāni','bhuñjithā','appampī','jālante','kalahappavaḍḍhanaākiccakāriṃ','gaḷeyyasi','tatthevantaradhāyithāti','middhī'}) do
    local exact = lookup:get(key, {approximate=false})
    assert(exact.found and Lookup.directHit(exact), key .. ': correction not accepted as content')
    assert(#exact.references > 0 and exact.references[1].status, key .. ': lost unresolved reference')
    assert(not Lookup.isVariantOnly(exact), key .. ': correction mistaken for variants alone')
    local result = lookup:get(key, Popup.selection_options)
    assert(Popup.route(result) == 'dpd' and #result.suggestions == 0, key .. ': correction replaced by approximate forms')
    local html = Render.render(result, Navigation.new(result):current())
    assert(html:find('Incorrect spelling of ',1,true) and html:find(Render.escape(exact.references[1].target),1,true), key .. ': correction hidden')
    assert(not html:find('Referenced DPD entry is unavailable',1,true), key .. ': correction mislabeled as unavailable')
    assert(not html:find('No DPD entry for “',1,true), key .. ': correction mislabeled as a miss')
    print(key, 'correction visible, direct DPD hit')
end
local checked = 0
for _, row in ipairs(db:query("SELECT lookup_key FROM lookup WHERE abbrev != '' OR abbrev_other != ''")) do
    local key = row.lookup_key
    if Normalize.query(key) ~= key then
        checked = checked + 1
        for _, form in ipairs({key, '“' .. key .. '”', key}) do
            local result = lookup:get(form, {approximate=false})
            assert(result.found and result.query == key, key .. ': literal abbreviation inaccessible')
            assert(result.abbrev or #result.abbrev_other > 0, key .. ': abbreviation lost')
        end
    end
end
assert(checked == 25, 'expected 25 boundary punctuation abbreviations')
print('official boundary punctuation abbreviations verified', checked)
local compact_parts = {
    ['asītīti'] = {[2]={[1]=true}},
    ['chāyāti'] = {[1]={[1]=true}, [2]={[1]=true}},
    ['rakkhatiyeva'] = {[1]={[1]=true}, [2]={[1]=true}},
    ['middhīti'] = {[1]={[1]=true}, [2]={[1]=true}},
}
for _, case in ipairs({
    {'asītīti', {{true, true}, {true, false}}},
    {'chāyāti', {{true, true}, {true, false}}},
    {'kiṃkī', {{true, true}}},
    {'bhātime', {{true, true}, {true, false}, {true, false}}},
    {'saṅghādisesoti', {{false, true}}},
    {'rakkhatiyeva', {{true, true}, {true, false}}},
    {'rūpiyappaṭiggahaṇāpatti', {{true, true, true}, {false, false, true}}},
    {'middhīti', {{true, true}, {true, false}, {true, false}}},
}) do
    local result = lookup:get(case[1], {approximate=false})
    local frame = Navigation.new(result):current()
    for i in ipairs(result.deconstructions) do frame.analyses[i] = true end
    local html = Render.render(result, frame)
    assert(#result.deconstructions == #case[2], case[1] .. ': analysis count changed')
    for i, parts in ipairs(case[2]) do
        local analysis = result.deconstructions[i]
        assert(#analysis.parts == #parts, case[1] .. ': part count changed')
        for j, visible in ipairs(parts) do
            assert(analysis.unique[j] == visible, case[1] .. ': wrong sense selection at ' .. i .. '/' .. j)
            if visible then
                assert(analysis.has_new, case[1] .. ': analysis must be expandable')
                local compact = (((compact_parts[case[1]] or {})[i] or {})[j] == true)
                assert(((analysis.compact or {})[j] == true) == compact, case[1] .. ': wrong compact state')
                if compact then
                    assert(html:find('· only ' .. Render.escape(Render.senseNames(result.components[analysis.parts[j]].senses)), 1, true))
                end
                for n, sense in ipairs(result.components[analysis.parts[j]].senses) do
                    if n > 2 then break end
                    assert((html:find('dpd:component-sense/' .. i .. '/' .. j .. '/' .. sense.id, 1, true) ~= nil) == not compact,
                        case[1] .. ': component sense not rendered')
                end
            end
        end
    end
    if case[1] == 'middhīti' then
        assert(html:find('Incorrect spelling of atthassamiddhī', 1, true), 'middhīti: correction note hidden')
    end
    print(case[1], 'component sense selections verified')
end
db:close()
