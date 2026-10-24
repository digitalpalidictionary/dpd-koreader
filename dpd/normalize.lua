local M = {}
local char_pattern = "[%z\1-\127\194-\244][\128-\191]*"
local lower = {
    ["Ā"] = "ā", ["Ī"] = "ī", ["Ū"] = "ū", ["Ṅ"] = "ṅ",
    ["Ñ"] = "ñ", ["Ṭ"] = "ṭ", ["Ḍ"] = "ḍ", ["Ṇ"] = "ṇ",
    ["Ḷ"] = "ḷ", ["Ṃ"] = "ṃ", ["Ṁ"] = "ṁ", ["Ŋ"] = "ŋ",
    -- Sanskrit, for searches of the bundled Sanskrit dictionaries.
    ["Ś"] = "ś", ["Ṣ"] = "ṣ", ["Ṛ"] = "ṛ", ["Ṝ"] = "ṝ", ["Ḹ"] = "ḹ", ["Ḥ"] = "ḥ",
}
local boundary = {}
for c in ("“”‘’\"'()[]{},.;:!?–—…«»।॥*|"):gmatch(char_pattern) do boundary[c] = true end

-- KOReader supplies full Unicode NFC. Standalone Lua tests/tools may not have
-- its FFI library: the fallback composes the standard Pali Latin letters only,
-- preserving all unsupported sequences rather than dropping combining marks.
local utf8proc_ok, utf8proc = pcall(require, "ffi/utf8proc")
local composition = {}
local function compose(mark, bases, letters)
    local values = {}
    for c in letters:gmatch(char_pattern) do values[#values + 1] = c end
    for i = 1, #bases do
        local base = bases:sub(i, i)
        composition[base] = composition[base] or {}
        composition[base][mark] = values[i]
    end
end
compose("̄", "aiuAIU", "āīūĀĪŪ")
compose("̃", "nN", "ñÑ")
compose("̇", "nmNM", "ṅṁṄṀ")
compose("̣", "tdnlmTDNLM", "ṭḍṇḷṃṬḌṆḶṂ")

function M.nfc(text)
    text = tostring(text or "")
    if utf8proc_ok and type(utf8proc) == "table" and type(utf8proc.normalize_NFC) == "function" then
        local ok, normalized = pcall(utf8proc.normalize_NFC, text)
        if ok and type(normalized) == "string" then return normalized end
    end
    local chars = {}
    for c in text:gmatch(char_pattern) do
        local previous = chars[#chars]
        local combined = previous and composition[previous] and composition[previous][c]
        if combined then chars[#chars] = combined else chars[#chars + 1] = c end
    end
    return table.concat(chars)
end

function M.trim(text)
    return (text:gsub(" ", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.lower(text)
    return (text:gsub(char_pattern, function(c) return lower[c] or c:lower() end))
end

-- Quiet display equivalence preserves internal apostrophes and hyphens: joining
-- those changes the selected spelling and must remain visible to the reader.
local invisible = { "\194\173", "\226\128\139", "\226\128\140", "\226\128\141", "\226\129\160", "\239\187\191" }
function M.selection(text)
    -- Invisible formatting inside a word: soft hyphen U+00AD, zero-width
    -- space, non-joiner and joiner U+200B-D, word joiner U+2060, BOM U+FEFF.
    for _, mark in ipairs(invisible) do text = text:gsub(mark, "") end
    text = M.trim(M.nfc(text))
    local chars = {}
    for c in text:gmatch(char_pattern) do chars[#chars + 1] = c end
    local first, last = 1, #chars
    while first <= last and (boundary[chars[first]] or chars[first]:match("^%s$")) do first = first + 1 end
    while last >= first and (boundary[chars[last]] or chars[last]:match("^%s$")) do last = last - 1 end
    return M.trim(table.concat(chars, "", first, last)
        :gsub("ṁ", "ṃ"):gsub("Ṁ", "ṃ"):gsub("ŋ", "ṃ"):gsub("Ŋ", "ṃ"))
end

function M.query(text)
    -- Apostrophe spellings: ASCII, curly and modifier letters (U+02BC, U+02BB).
    return (M.selection(text):gsub("'", ""):gsub("‘", ""):gsub("’", ""):gsub("ʼ", ""):gsub("ʻ", ""))
end

-- Parentheses, brackets and construction operators can be part of an
-- abbreviation key (BHS(G), [], *), rather than prose around a word. Keep
-- their literal identity ahead of boundary cleanup. Quotes are presentation
-- boundaries even for abbreviations; ordinary quoted words need no extra DB
-- probe. Leading-hyphen abbreviation lists also retain their final colon.
local quotation = {}
for c in ("“”‘’\"'«»"):gmatch(char_pattern) do quotation[c] = true end
function M.literal(text)
    text = tostring(text or "")
    -- The common prose path needs neither another NFC pass nor a raw query.
    if not text:find("[()%[%]{}*|]") and not text:find("%-") then return nil end
    text = M.trim(M.nfc(text)):gsub("­", "")
    local chars = {}
    for c in text:gmatch(char_pattern) do chars[#chars + 1] = c end
    local first, last = 1, #chars
    while first <= last and (quotation[chars[first]] or chars[first]:match("^%s$")) do first = first + 1 end
    while last >= first and (quotation[chars[last]] or chars[last]:match("^%s$")) do last = last - 1 end
    local raw = M.trim(table.concat(chars, "", first, last))
        :gsub("ṁ", "ṃ"):gsub("Ṁ", "ṃ"):gsub("ŋ", "ṃ"):gsub("Ŋ", "ṃ")
    if raw ~= M.query(text) and (raw:find("[()%[%]{}*|]") or raw:sub(1, 1) == "-") then
        return raw
    end
end

function M.literalCandidates(text)
    local raw = M.literal(text)
    if not raw then return {} end
    local out = { { key = raw, via = "exact", literal = true } }
    local lowered = M.lower(raw)
    if lowered ~= raw then out[#out + 1] = { key = lowered, via = "ci", literal = true } end
    return out
end

function M.isRewrite(original, matched)
    return M.lower(M.selection(original)) ~= M.lower(M.selection(matched))
end

-- Only join ASCII hyphens between Pali letters; do not rewrite number ranges,
-- leading/trailing hyphens or separators. The literal form is always tried first.
local pali_letter = {}
for c in ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZāīūṅñṭḍṇḷṃṁŋĀĪŪṄÑṬḌṆḶṂṀŊ"):gmatch(char_pattern) do
    pali_letter[c] = true
end
function M.isPaliLetter(char) return pali_letter[char] == true end
local function hyphen_alias(text)
    local chars, out = {}, {}
    for c in text:gmatch(char_pattern) do chars[#chars + 1] = c end
    for i, c in ipairs(chars) do
        if not (c == "-" and pali_letter[chars[i - 1]] and pali_letter[chars[i + 1]]) then
            out[#out + 1] = c
        end
    end
    return table.concat(out)
end

-- Corpus closing-quote spelling: byādhayissasī”ti for byādhayissasīti. Only a
-- double quote between a Pali letter and a final "ti" is dropped; Velthuis and
-- other internal double quotes are left alone. Single quotes are already
-- removed by M.query.
local function quote_ti_alias(text)
    local chars = {}
    for c in text:gmatch(char_pattern) do chars[#chars + 1] = c end
    local n = #chars
    if n >= 4 and (chars[n - 1] == "t" or chars[n - 1] == "T")
        and (chars[n] == "i" or chars[n] == "I")
        and (chars[n - 2] == "”" or chars[n - 2] == "\"") and pali_letter[chars[n - 3]] then
        table.remove(chars, n - 2)
    end
    return table.concat(chars)
end

function M.candidates(text)
    local q = M.query(text)
    if q == "" then return {} end
    local lowered = M.lower(q):gsub("ṁ", "ṃ")
    local out, seen = {}, {}
    local function add(key, via)
        if not seen[key] then
            seen[key] = true
            out[#out + 1] = { key = key, via = via }
        end
    end
    add(q, "exact")
    add(lowered, "ci")
    add(q .. ".", "dot")
    add(lowered .. ".", "dot")
    local alias = hyphen_alias(quote_ti_alias(q))
    if alias ~= q then
        add(alias, "alias")
        add(M.lower(alias), "alias")
        add(alias .. ".", "alias")
        add(M.lower(alias) .. ".", "alias")
    end
    return out
end

-- OCR/typing rescue is deliberately bounded, unlike search-box autocomplete.
-- Remove whole Unicode characters, retaining at least four Pali letters.
-- Up to three trailing ASCII digits (e.g. an inline footnote number) are
-- dropped first and the bare word becomes the first candidate; embedded
-- digits still reject the input. Returns the candidates and stripped digits.
function M.shortenedPrefixes(text)
    local q = M.lower(hyphen_alias(M.query(text)))
    local word, digits = q:match("^(.-)(%d%d?%d?)$")
    if not word then word, digits = q, nil end
    local chars = {}
    for c in word:gmatch(char_pattern) do
        if not pali_letter[c] then return {} end
        chars[#chars + 1] = c
        if #chars > 64 then return {} end
    end
    local out = {}
    for removed = digits and 0 or 1, math.min(2, #chars - 4) do
        out[#out + 1] = table.concat(chars, "", 1, #chars - removed)
    end
    return out, #out > 0 and digits or nil
end

-- Mobile exporter's _strip_diacritics_mobile rules, used only for suggestions.
-- Exact lookup and component identity must retain their meaningful diacritics.
-- The exporter decomposes, drops combining marks and lowercases. KOReader
-- exposes no NFD, so fold precomposed Latin letters (U+00C0–U+017F and
-- U+1E00–U+1EFF) to their lowercase ASCII base; each pair is letter + base.
-- Also the comma-below ș ț and dotless ı that KOReader's English keyboard
-- offers beside ṣ ṭ and i.
local plain = { ["≠"] = "=" }
for c, base in ([[
ÀaÁaÂaÃaÄaÅaÇcÈeÉeÊeËeÌiÍiÎiÏiÑnÒoÓoÔoÕoÖoÙuÚuÛuÜuÝyàaáaâaãaäaåa
çcèeéeêeëeìiíiîiïiñnòoóoôoõoöoùuúuûuüuýyÿyĀaāaĂaăaĄaąaĆcćcĈcĉcĊc
ċcČcčcĎdďdĒeēeĔeĕeĖeėeĘeęeĚeěeĜgĝgĞgğgĠgġgĢgģgĤhĥhĨiĩiĪiīiĬiĭiĮi
įiİiĴjĵjĶkķkĹlĺlĻlļlĽlľlŃnńnŅnņnŇnňnŌoōoŎoŏoŐoőoŔrŕrŖrŗrŘrřrŚsśs
ŜsŝsŞsşsŠsšsŢtţtŤtťtŨuũuŪuūuŬuŭuŮuůuŰuűuŲuųuŴwŵwŶyŷyŸyŹzźzŻzżzŽz
žzḀaḁaḂbḃbḄbḅbḆbḇbḈcḉcḊdḋdḌdḍdḎdḏdḐdḑdḒdḓdḔeḕeḖeḗeḘeḙeḚeḛeḜeḝeḞf
ḟfḠgḡgḢhḣhḤhḥhḦhḧhḨhḩhḪhḫhḬiḭiḮiḯiḰkḱkḲkḳkḴkḵkḶlḷlḸlḹlḺlḻlḼlḽlḾm
ḿmṀmṁmṂmṃmṄnṅnṆnṇnṈnṉnṊnṋnṌoṍoṎoṏoṐoṑoṒoṓoṔpṕpṖpṗpṘrṙrṚrṛrṜrṝrṞr
ṟrṠsṡsṢsṣsṤsṥsṦsṧsṨsṩsṪtṫtṬtṭtṮtṯtṰtṱtṲuṳuṴuṵuṶuṷuṸuṹuṺuṻuṼvṽvṾv
ṿvẀwẁwẂwẃwẄwẅwẆwẇwẈwẉwẊxẋxẌxẍxẎyẏyẐzẑzẒzẓzẔzẕzẖhẗtẘwẙyẠaạaẢaảaẤa
ấaẦaầaẨaẩaẪaẫaẬaậaẮaắaẰaằaẲaẳaẴaẵaẶaặaẸeẹeẺeẻeẼeẽeẾeếeỀeềeỂeểeỄe
ễeỆeệeỈiỉiỊiịiỌoọoỎoỏoỐoốoỒoồoỔoổoỖoỗoỘoộoỚoớoỜoờoỞoởoỠoỡoỢoợoỤu
ụuỦuủuỨuứuỪuừuỬuửuỮuữuỰuựuỲyỳyỴyỵyỶyỷyỸyỹyȘsșsȚtțtıi
]]):gsub("%s", ""):gmatch("(" .. char_pattern .. ")(%a)") do plain[c] = base end
--- One character's plain base letter: ā → a, ṃ → m; others unchanged.
function M.base(char) return plain[char] or char end

function M.fuzzy(text)
    local key = M.lower(M.query(text)):gsub("√", ""):gsub(" ", "")
    key = key:gsub(char_pattern, function(c)
        local first, second = c:byte(1, 2)
        if first == 204 or (first == 205 and second and second <= 175) then return "" end
        return plain[c] or c
    end)
    return (key:gsub("([kgcjtdpb])h", "%1"):gsub("([bcdfghjklmnpqrstvwxyz])%1", "%1"))
end

return M
