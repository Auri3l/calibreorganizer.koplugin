-- Plain LuaJIT tests for organizer_core.lua.
-- Run from the plugin folder:  luajit spec/core_spec.lua
package.path = "./?.lua;" .. package.path
local Core = require("organizer_core")

local passed, failed = 0, 0
local function eq(name, got, want)
    if got == want then
        passed = passed + 1
    else
        failed = failed + 1
        print(("FAIL %s\n  got:  %s\n  want: %s"):format(name, tostring(got), tostring(want)))
    end
end

local TPL = "{series:||/}{series_index:0>2s|| - }{title} - {authors}"

local heresy = {
    title = "Horus Rising", authors = { "Dan Abnett" },
    series = "The Horus Heresy", series_index = 1.0,
    lpath = "documents/Horus Rising - Dan Abnett.epub",
    user_metadata = { ["#folder"] = { ["#value#"] = "Warhammer 40k" } },
}
local durant = {
    title = "Our Oriental Heritage", authors = { "Will Durant" },
    series = "The Story of Civilization", series_index = 1.0,
    lpath = "documents/Durant, Will/Our Oriental Heritage - Will Durant.epub",
}
local standalone = {
    title = "Dune", authors = { "Frank Herbert" }, series = nil, series_index = 1.0,
    lpath = "documents/Dune - Frank Herbert.epub",
}

-- rendering
eq("series template", Core.render(TPL, heresy), "The Horus Heresy/01 - Horus Rising - Dan Abnett")
eq("no series -> no index", Core.render(TPL, standalone), "Dune - Frank Herbert")
eq("custom column", Core.render("{#folder:||/}{series:||/}{title}", heresy),
    "Warhammer 40k/The Horus Heresy/Horus Rising")
eq("missing custom column", Core.render("{#folder:||/}{title}", durant), "Our Oriental Heritage")
eq("fractional index", Core.render("{series_index:0>4s}", { series = "S", series_index = 2.5 }), "02.5")
eq("pad 3", Core.render("{series_index:0>3s}", { series = "S", series_index = 12 }), "012")
eq("int format", Core.render("{series_index:0>3d}", { series = "S", series_index = 7.0 }), "007")
eq("two authors", Core.render("{authors}", { authors = { "A", "B" } }), "A & B")
eq("pipe without colon", Core.render("{series||/}{title}", heresy), "The Horus Heresy/Horus Rising")
eq("invalid chars", Core.render("{title}", { title = 'What? A: "Test"/Book*' }), "What_ A_ _Test__Book_")
eq("trailing dot", Core.render("{title}", { title = "Vol. 1..." }), "Vol. 1")
eq("double slash collapsed", Core.render("a//{title}/", { title = "x" }), "a/x")
local r, err = Core.render("{title}", {})
eq("empty result", r, nil)
eq("empty result error", err ~= nil, true)
local long = string.rep("ğ", 100) -- 200 bytes, multibyte
local cut = Core.render("{title}", { title = long })
eq("utf8 cut length", #cut <= 120, true)
eq("utf8 cut valid", cut:sub(-2), "ğ")

-- Calibre's stock device template uses {id}
eq("id field", Core.render("{title} - {authors} ({id})", { title = "T", authors = { "A" }, application_id = 42 }),
    "T - A (42)")

-- validation
eq("valid", Core.validate(TPL), true)
eq("empty invalid", Core.validate("  "), nil)
eq("program mode", Core.validate("program: 'x'"), nil)
eq("function mode", Core.validate("{title:'uppercase($)'}"), nil)
eq("unbalanced", Core.validate("{title"), nil)
eq("nested", Core.validate("{a{b}}"), nil)
eq("render rejects invalid", Core.render("{title:'uppercase($)'}", { title = "x" }), nil)

-- planning
local files = {}
local function add(p) files[p:lower()] = true end
add(heresy.lpath); add(durant.lpath); add(standalone.lpath)
local exists = function(p) return files[p:lower()] == true end

local plan = Core.plan({ heresy, durant, standalone }, { template = TPL, base = "documents", exists = exists })
eq("moves", #plan.moves, 2)
eq("unchanged", plan.unchanged, 1)
eq("skipped", #plan.skipped, 0)
eq("durant target", plan.moves[2].to,
    "documents/The Story of Civilization/01 - Our Oriental Heritage - Will Durant.epub")

-- target collision with an existing unrelated file
add("documents/The Horus Heresy/01 - Horus Rising - Dan Abnett.epub")
plan = Core.plan({ heresy }, { template = TPL, base = "documents", exists = exists })
eq("collision skipped", #plan.skipped, 1)

-- two books rendering to the same name
local a = { title = "Same", authors = { "X" }, lpath = "documents/a.epub" }
local b = { title = "Same", authors = { "X" }, lpath = "documents/b.epub" }
files = {}; add(a.lpath); add(b.lpath)
plan = Core.plan({ a, b }, { template = "{title}", base = "documents", exists = exists })
eq("dup: one move", #plan.moves, 1)
eq("dup: one skip", #plan.skipped, 1)

-- missing file and explicit skip
files = {}; add(a.lpath)
plan = Core.plan({ a, b }, { template = "{title}-{lpath}", base = "", exists = exists,
    skip = { ["documents/a.epub"] = "currently open" } })
eq("skip reason", plan.skipped[1].reason, "currently open")
eq("missing file", plan.skipped[2].reason, "file not found")

-- case-only rename is allowed
local c = { title = "dune", lpath = "documents/Dune.epub" }
files = {}; add(c.lpath)
plan = Core.plan({ c }, { template = "{title}", base = "documents", exists = exists })
eq("case-only move", #plan.moves, 1)
eq("case-only target", plan.moves[1].to, "documents/dune.epub")

-- empty base
plan = Core.plan({ c }, { template = "{title}", base = "", exists = exists })
eq("empty base", plan.moves[1].to, "dune.epub")

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
