--[[--
Pure-Lua core of the Calibre Organizer plugin.

Nothing in here touches KOReader APIs or the filesystem directly, so it can be
unit-tested with plain LuaJIT. It knows how to:

  * render a Calibre-style save template for one book entry
  * turn a list of Calibre metadata entries into a list of planned moves
]]

local Core = {}

-- Characters that are not allowed in FAT32 / Windows file names.
local INVALID_CHARS = '[<>:"/\\|%?%*%c]'
local MAX_COMPONENT_LEN = 120

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Format a series index the way Calibre shows it: 1.0 -> "1", 1.5 -> "1.5".
local function formatNumber(n)
    if n == math.floor(n) then
        return string.format("%d", n)
    end
    local s = string.format("%.2f", n):gsub("0+$", ""):gsub("%.$", "")
    return s
end

--- Is this value "empty" for template purposes?
local function isEmpty(v)
    if v == nil then return true end
    if type(v) == "string" then return v == "" end
    if type(v) == "table" then return next(v) == nil end
    -- rapidjson.null and friends are userdata/functions: treat as empty
    if type(v) ~= "number" and type(v) ~= "boolean" then return true end
    return false
end

--- Make one field value safe to use inside a single path component.
function Core.sanitizeValue(s)
    s = tostring(s or "")
    s = s:gsub(INVALID_CHARS, "_")
    return trim(s)
end

--- Make one path component safe (applied after template rendering).
function Core.sanitizeComponent(s)
    s = trim(s)
    -- Windows/FAT do not allow trailing dots or spaces.
    s = s:gsub("[%. ]+$", "")
    if #s > MAX_COMPONENT_LEN then
        -- cut on a UTF-8 character boundary
        local cut = MAX_COMPONENT_LEN
        while cut > 0 do
            local b = s:byte(cut + 1)
            if not b or b < 0x80 or b >= 0xC0 then break end
            cut = cut - 1
        end
        s = trim(s:sub(1, cut))
        s = s:gsub("[%. ]+$", "")
    end
    return s
end

--- Get the raw value of a template field from a Calibre metadata entry.
function Core.getField(book, name)
    if name:sub(1, 1) == "#" then
        local um = book.user_metadata
        if type(um) ~= "table" then return nil end
        local col = um[name]
        if type(col) ~= "table" then return nil end
        return col["#value#"]
    end
    if name == "author" then name = "authors" end
    -- Calibre's {id} is the book id, stored as application_id on the device.
    if name == "id" then return book.application_id end
    -- Like Calibre: a series index means nothing without a series.
    if name == "series_index" and isEmpty(book.series) then
        return nil
    end
    return book[name]
end

--- Convert a raw field value into a string (before formatting).
local function valueToString(name, v)
    if isEmpty(v) then return "" end
    if type(v) == "table" then
        local parts = {}
        for _, item in ipairs(v) do
            if not isEmpty(item) then
                table.insert(parts, tostring(item))
            end
        end
        local sep = (name == "authors") and " & " or ", "
        return table.concat(parts, sep)
    end
    if type(v) == "number" then
        return formatNumber(v)
    end
    if type(v) == "boolean" then
        return v and "Yes" or "No"
    end
    return tostring(v)
end

--- Apply a small subset of the Python format mini-language:
--- [[fill]align][width][.precision][type], types s, d, f.
function Core.applyFormat(raw, str, fmt)
    if fmt == nil or fmt == "" then return str end
    local fill, align, rest = fmt:match("^(.)([<>%^])(.*)$")
    if not fill then
        align, rest = fmt:match("^([<>%^])(.*)$")
        fill = " "
        if not align then
            align, rest = nil, fmt
        end
    end
    local width, precision, ftype = rest:match("^(%d*)%.?(%d*)([sdf]?)$")
    if width == nil then
        return str -- unsupported spec, leave the value alone
    end
    local num = tonumber(raw) or tonumber(str)
    if ftype == "d" and num then
        str = string.format("%d", math.floor(num + 0.5))
    elseif ftype == "f" and num then
        str = string.format("%." .. (precision ~= "" and precision or "6") .. "f", num)
    elseif ftype == "s" and precision ~= "" then
        str = str:sub(1, tonumber(precision))
    end
    width = tonumber(width)
    if width and #str < width then
        local pad = string.rep(fill, width - #str)
        align = align or (num and ftype ~= "s" and ">" or "<")
        if align == ">" then
            str = pad .. str
        elseif align == "<" then
            str = str .. pad
        else
            local left = math.floor((width - #str) / 2)
            str = string.rep(fill, left) .. str .. string.rep(fill, width - #str - left)
        end
    end
    return str
end

--- Render a single {...} template expression.
local function renderExpr(book, expr)
    local name, spec = expr:match("^([#%w_]+)(.*)$")
    if not name then
        return nil, "bad template field: {" .. expr .. "}"
    end
    local fmt, prefix, suffix = "", "", ""
    if spec ~= "" then
        if spec:sub(1, 1) == ":" then
            spec = spec:sub(2)
        elseif spec:sub(1, 1) ~= "|" then
            return nil, "bad template field: {" .. expr .. "}"
        end
        local parts = {}
        for part in (spec .. "|"):gmatch("([^|]*)|") do
            table.insert(parts, part)
        end
        fmt = parts[1] or ""
        prefix = parts[2] or ""
        suffix = parts[3] or ""
    end
    local raw = Core.getField(book, name)
    local str = valueToString(name, raw)
    if str == "" then
        return ""
    end
    str = Core.sanitizeValue(Core.applyFormat(raw, str, fmt))
    if str == "" then
        return ""
    end
    return prefix .. str .. suffix
end

--- Check that a template only uses the supported Calibre syntax.
--- Returns true, or nil and an error message.
function Core.validate(template)
    if type(template) ~= "string" or template:match("^%s*$") then
        return nil, "template is empty"
    end
    if template:match("^%s*program:") or template:match("^%s*python:") then
        return nil, "Calibre template programs (program:/python:) are not supported"
    end
    local depth = 0
    for ch in template:gmatch("[{}]") do
        depth = depth + (ch == "{" and 1 or -1)
        if depth < 0 or depth > 1 then
            return nil, "unbalanced or nested { } in template"
        end
    end
    if depth ~= 0 then
        return nil, "unbalanced { } in template"
    end
    for expr in template:gmatch("{([^{}]*)}") do
        if expr:match("^[#%w_]+:'") or expr:match("^[#%w_]+:%s*%w+%(") then
            return nil, "template functions are not supported: {" .. expr .. "}"
        end
        if not expr:match("^[#%w_]+") then
            return nil, "bad template field: {" .. expr .. "}"
        end
    end
    return true
end

--- Render a template for a book. Returns the relative path WITHOUT extension.
function Core.render(template, book)
    local valid, verr = Core.validate(template)
    if not valid then return nil, verr end
    local err
    local out = template:gsub("{([^{}]*)}", function(expr)
        local s, e = renderExpr(book, expr)
        if not s then
            err = err or e
            return ""
        end
        return s
    end)
    if err then return nil, err end

    -- Normalise into clean components.
    local parts = {}
    for comp in out:gmatch("[^/\\]+") do
        comp = Core.sanitizeComponent(comp)
        if comp ~= "" and comp ~= "." and comp ~= ".." then
            table.insert(parts, comp)
        end
    end
    if #parts == 0 then
        return nil, "template produced an empty name"
    end
    return table.concat(parts, "/")
end

--- Extension of a path, including the dot ("" if none).
function Core.getExtension(path)
    local ext = path:match("(%.[^%./\\]+)$")
    return ext or ""
end

local function joinRel(a, b)
    if a == nil or a == "" then return b end
    a = a:gsub("/+$", "")
    return a .. "/" .. b
end

--- Build the move plan.
-- @param books   array of Calibre metadata entries (each has .lpath)
-- @param opts    { template = string, base = string ("documents"),
--                  exists = function(lpath) -> bool,
--                  skip = { [lpath] = reason } }
-- @return plan { moves = {{book, from, to}}, skipped = {{book, from, reason}},
--               unchanged = n }
function Core.plan(books, opts)
    local exists = opts.exists or function() return false end
    local skip = opts.skip or {}
    local plan = { moves = {}, skipped = {}, unchanged = 0 }
    local claimed = {} -- lowercased target lpath -> true
    local sources = {} -- lowercased source lpath -> true

    for _, book in ipairs(books) do
        if type(book.lpath) == "string" then
            sources[book.lpath:lower()] = true
        end
    end

    for _, book in ipairs(books) do
        local from = book.lpath
        if type(from) ~= "string" or from == "" then
            table.insert(plan.skipped, { book = book, from = tostring(from), reason = "no path in metadata" })
        elseif skip[from] then
            table.insert(plan.skipped, { book = book, from = from, reason = skip[from] })
        elseif not exists(from) then
            table.insert(plan.skipped, { book = book, from = from, reason = "file not found" })
        else
            local rel, err = Core.render(opts.template, book)
            if not rel then
                table.insert(plan.skipped, { book = book, from = from, reason = err })
            else
                local to = joinRel(opts.base, rel) .. Core.getExtension(from)
                local to_l = to:lower()
                if to == from then
                    plan.unchanged = plan.unchanged + 1
                    claimed[to_l] = true
                elseif claimed[to_l] then
                    table.insert(plan.skipped, { book = book, from = from, reason = "another book already uses " .. to })
                elseif to_l ~= from:lower() and (exists(to) or sources[to_l]) then
                    table.insert(plan.skipped, { book = book, from = from, reason = "target already exists: " .. to })
                else
                    claimed[to_l] = true
                    table.insert(plan.moves, { book = book, from = from, to = to })
                end
            end
        end
    end
    return plan
end

--- Short human-readable description of a book for lists.
function Core.describe(book)
    local title = valueToString("title", book.title)
    if title == "" then title = book.lpath or "?" end
    return title
end

return Core
