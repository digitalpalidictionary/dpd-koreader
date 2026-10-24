-- Matches DPD tools/pali_sort_key.py, including its single-letter-first regex.
-- Digraph alternatives are unreachable upstream; do not change their ordering.
-- SPDX-License-Identifier: MIT
local map = {
    ["√"]="00", a="01", ["ā"]="02", i="03", ["ī"]="04", u="05", ["ū"]="06",
    e="07", o="08", k="09", g="11", ["ṅ"]="13", c="14", j="16", ["ñ"]="18",
    ["ṭ"]="19", ["ḍ"]="21", ["ṇ"]="23", t="24", d="26", n="28", p="29",
    b="31", m="33", y="34", r="35", l="36", v="37", s="38", h="39",
    ["ḷ"]="40", ["ṃ"]="41",
}
return function(word)
    return (word:gsub("[%z\1-\127\194-\244][\128-\191]*", function(c) return map[c] or c end))
end
