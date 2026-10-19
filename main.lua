--[[--
Calibre organizer: reorganize books on the device according to their Calibre
metadata, without losing KOReader sidecar data (notes, highlights, progress).

Flow:
  1. find the Calibre metadata file (metadata.calibre / .metadata.calibre)
  2. render a Calibre-style template for every book in it
  3. move each book (and its sidecar, history and collection entries)
  4. rewrite the lpath of each moved book in the metadata file
]]

local ConfirmBox = require("ui/widget/confirmbox")
local DocSettings = require("docsettings")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local Core = require("organizer_core")

local SETTINGS_KEY = "calibre_organizer"
local DEFAULT_BASE = "documents"
local METADATA_NAMES = { "metadata.calibre", ".metadata.calibre" }

local CalibreOrganizer
if WidgetContainer.extend then
    CalibreOrganizer = WidgetContainer:extend{ name = "calibreorganizer", is_doc_only = false }
else
    CalibreOrganizer = WidgetContainer:new{ name = "calibreorganizer", is_doc_only = false }
end

---------------------------------------------------------------------------
-- small helpers
---------------------------------------------------------------------------

local function fileExists(path)
    return lfs.attributes(path, "mode") == "file"
end

local function dirExists(path)
    return lfs.attributes(path, "mode") == "directory"
end

local function dirname(path)
    return path:match("^(.*)/[^/]*$") or "."
end

local function makePath(dir)
    if dirExists(dir) then return true end
    if util.makePath then
        local ok, err = util.makePath(dir)
        if ok or dirExists(dir) then return true end
        return false, err
    end
    local acc = dir:sub(1, 1) == "/" and "" or "."
    for comp in dir:gmatch("[^/]+") do
        acc = acc .. "/" .. comp
        if not dirExists(acc) then
            local ok, err = lfs.mkdir(acc)
            if not ok then return false, err end
        end
    end
    return true
end

local function copyFile(src, dst)
    local fin = io.open(src, "rb")
    if not fin then return false end
    local data = fin:read("*a")
    fin:close()
    local fout = io.open(dst, "wb")
    if not fout then return false end
    fout:write(data)
    fout:close()
    return true
end

local function getJson()
    local ok, rapidjson = pcall(require, "rapidjson")
    if ok and rapidjson then return rapidjson end
    return nil
end

local function callFirst(obj, names, ...)
    if not obj then return false end
    for _, name in ipairs(names) do
        if type(obj[name]) == "function" then
            local ok, err = pcall(obj[name], obj, ...)
            if not ok then logger.warn("CalibreOrganizer:", name, "failed:", err) end
            return ok
        end
    end
    return false
end

---------------------------------------------------------------------------
-- settings
---------------------------------------------------------------------------

function CalibreOrganizer:init()
    self.settings = G_reader_settings:readSetting(SETTINGS_KEY) or {}
    self.settings.base = self.settings.base or DEFAULT_BASE
    if self.settings.remove_empty_dirs == nil then
        self.settings.remove_empty_dirs = true
    end
    self.ui.menu:registerToMainMenu(self)
end

function CalibreOrganizer:saveSettings()
    G_reader_settings:saveSetting(SETTINGS_KEY, self.settings)
    if G_reader_settings.flush then G_reader_settings:flush() end
end

---------------------------------------------------------------------------
-- locating and loading the Calibre metadata
---------------------------------------------------------------------------

function CalibreOrganizer:candidateDirs()
    local dirs = {}
    local seen = {}
    local function add(d)
        if type(d) == "string" and d ~= "" then
            d = d:gsub("/+$", "")
            if not seen[d] then
                seen[d] = true
                table.insert(dirs, d)
            end
        end
    end
    add(self.settings.library_dir)
    add(G_reader_settings:readSetting("inbox_dir"))
    add(G_reader_settings:readSetting("home_dir"))
    local ok, Device = pcall(require, "device")
    if ok and Device then add(Device.home_dir) end
    add("/mnt/us") -- Kindle
    add("/mnt/onboard") -- Kobo
    return dirs
end

--- @return root dir, metadata file path (or nil)
function CalibreOrganizer:findMetadata()
    local dirs = self.settings.library_dir and { self.settings.library_dir } or self:candidateDirs()
    for _, dir in ipairs(dirs) do
        for _, name in ipairs(METADATA_NAMES) do
            local path = dir .. "/" .. name
            if fileExists(path) then
                return dir, path
            end
        end
    end
    return nil
end

local NO_TEMPLATE_TEXT = _([[No folder template yet.

Copy it from Calibre so books end up exactly where Calibre puts them:
Preferences → Plugins → Device interface → Smart Device App Interface (wireless) or the Kindle/Kobo driver (USB) → Customize plugin → Save template.

Then paste it in Calibre organizer → Folder template.]])

function CalibreOrganizer:loadLibrary()
    if not self.settings.template or self.settings.template == "" then
        return nil, NO_TEMPLATE_TEXT
    end
    local json = getJson()
    if not json then
        return nil, _("JSON support (rapidjson) is not available in this KOReader build.")
    end
    local root, path = self:findMetadata()
    if not root then
        return nil, _("No Calibre metadata file found.\n\nConnect to Calibre once, or choose the Calibre library folder in the plugin settings.")
    end
    local ok, books = pcall(json.load, path)
    if not ok or type(books) ~= "table" then
        return nil, T(_("Could not read %1"), path)
    end
    return { root = root, path = path, books = books, json = json }
end

function CalibreOrganizer:saveLibrary(lib)
    copyFile(lib.path, lib.path .. ".bak")
    local ok, err = pcall(lib.json.dump, lib.books, lib.path, { pretty = true })
    if not ok then
        logger.err("CalibreOrganizer: could not write metadata:", err)
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- planning
---------------------------------------------------------------------------

function CalibreOrganizer:makePlan(lib)
    local skip = {}
    if self.ui.document and self.ui.document.file then
        local open = self.ui.document.file
        local prefix = lib.root .. "/"
        if open:sub(1, #prefix) == prefix then
            skip[open:sub(#prefix + 1)] = _("currently open")
        end
    end
    return Core.plan(lib.books, {
        template = self.settings.template,
        base = self.settings.base,
        skip = skip,
        exists = function(lpath)
            return lfs.attributes(lib.root .. "/" .. lpath, "mode") ~= nil
        end,
    })
end

function CalibreOrganizer:planText(plan)
    local lines = {}
    table.insert(lines, T(_("To move: %1   Already in place: %2   Skipped: %3"),
        #plan.moves, plan.unchanged, #plan.skipped))
    if #plan.moves > 0 then
        table.insert(lines, "")
        table.insert(lines, _("Will move:"))
        for _, m in ipairs(plan.moves) do
            table.insert(lines, "• " .. Core.describe(m.book))
            table.insert(lines, "    " .. m.from)
            table.insert(lines, "  → " .. m.to)
        end
    end
    if #plan.skipped > 0 then
        table.insert(lines, "")
        table.insert(lines, _("Skipped:"))
        for _, s in ipairs(plan.skipped) do
            table.insert(lines, "• " .. Core.describe(s.book) .. " (" .. tostring(s.reason) .. ")")
        end
    end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- moving
---------------------------------------------------------------------------

--- Move the KOReader sidecar data that belongs to a book.
local function moveSidecar(src, dst)
    if type(DocSettings.updateLocation) == "function" then
        local ok, err = pcall(DocSettings.updateLocation, src, dst)
        if ok then return end
        logger.warn("CalibreOrganizer: updateLocation failed:", err)
    end
    -- Fallback for older KOReader: the sidecar folder next to the book.
    local old_sdr = (src:match("^(.*)%.[^./]+$") or src) .. ".sdr"
    local new_sdr = (dst:match("^(.*)%.[^./]+$") or dst) .. ".sdr"
    if dirExists(old_sdr) and not dirExists(new_sdr) then
        os.rename(old_sdr, new_sdr)
    end
end

local function updateHistoryAndCollections(src, dst)
    local ok_h, ReadHistory = pcall(require, "readhistory")
    if ok_h then callFirst(ReadHistory, { "updateItem", "updateItemByPath" }, src, dst) end
    local ok_c, ReadCollection = pcall(require, "readcollection")
    if ok_c then callFirst(ReadCollection, { "updateItem", "updateItemByPath" }, src, dst) end
end

--- Move one book on disk. Returns true or false, error.
function CalibreOrganizer:moveOne(root, from, to)
    local src = root .. "/" .. from
    local dst = root .. "/" .. to
    local old_sdr = (src:match("^(.*)%.[^./]+$") or src) .. ".sdr"
    local new_sdr = (dst:match("^(.*)%.[^./]+$") or dst) .. ".sdr"
    local had_sdr = dirExists(old_sdr)
    if had_sdr and from:lower() ~= to:lower() and dirExists(new_sdr) then
        return false, "a notes folder already exists at the target: " .. new_sdr
    end
    local ok, err = makePath(dirname(dst))
    if not ok then return false, err end
    if from:lower() == to:lower() then
        -- case-only rename on a case-insensitive filesystem (FAT32)
        local tmp = dst .. ".calibreorganizer-tmp"
        ok, err = os.rename(src, tmp)
        if ok then ok, err = os.rename(tmp, dst) end
    else
        if lfs.attributes(dst, "mode") then
            return false, "target exists"
        end
        ok, err = os.rename(src, dst)
    end
    if not ok then return false, err end
    moveSidecar(src, dst)
    updateHistoryAndCollections(src, dst)
    if had_sdr and from:lower() ~= to:lower() and not dirExists(new_sdr) then
        -- The book moved but its notes did not: report it, the old .sdr is still there.
        return true, "book moved, but its notes/progress folder (.sdr) was not: " .. old_sdr
    end
    return true
end

function CalibreOrganizer:removeEmptyDirs(root, lpaths)
    local stop = {}
    stop[root] = true
    stop[root .. "/" .. self.settings.base] = true
    local dirs = {}
    for _, lpath in ipairs(lpaths) do
        dirs[dirname(root .. "/" .. lpath)] = true
    end
    for dir in pairs(dirs) do
        local d = dir
        while not stop[d] and d:sub(1, #root + 1) == root .. "/" do
            if not lfs.rmdir(d) then break end
            d = dirname(d)
        end
    end
end

--- Apply a list of {from, to} moves and update the metadata.
function CalibreOrganizer:applyMoves(lib, moves)
    local by_lpath = {}
    for _, book in ipairs(lib.books) do
        if type(book.lpath) == "string" then by_lpath[book.lpath] = book end
    end
    local done, failed = {}, {}
    for _, m in ipairs(moves) do
        local ok, err = self:moveOne(lib.root, m.from, m.to)
        if ok then
            local book = by_lpath[m.from]
            if book then book.lpath = m.to end
            table.insert(done, { from = m.from, to = m.to })
            if err then
                logger.warn("CalibreOrganizer:", err)
                table.insert(failed, { from = m.from, reason = err })
            end
        else
            logger.warn("CalibreOrganizer: could not move", m.from, err)
            table.insert(failed, { from = m.from, reason = tostring(err) })
        end
    end
    if #done > 0 then
        if not self:saveLibrary(lib) then
            table.insert(failed, { from = lib.path, reason = "could not update the Calibre metadata file" })
        end
        if self.settings.remove_empty_dirs then
            local froms = {}
            for _, m in ipairs(done) do table.insert(froms, m.from) end
            self:removeEmptyDirs(lib.root, froms)
        end
    end
    return done, failed
end

function CalibreOrganizer:refreshFileManager()
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    if ok and FileManager and FileManager.instance then
        pcall(function() FileManager.instance:onRefresh() end)
    end
end

function CalibreOrganizer:reportResult(done, failed, verb)
    local text = T(_("%1 %2 book(s)."), verb, #done)
    if #failed > 0 then
        local lines = { text, "", _("Failed:") }
        for _, f in ipairs(failed) do
            table.insert(lines, "• " .. f.from .. " (" .. f.reason .. ")")
        end
        UIManager:show(TextViewer:new{ title = _("Calibre organizer"), text = table.concat(lines, "\n") })
    else
        UIManager:show(InfoMessage:new{ text = text })
    end
end

---------------------------------------------------------------------------
-- actions
---------------------------------------------------------------------------

function CalibreOrganizer:showError(msg)
    UIManager:show(InfoMessage:new{ text = msg })
end

function CalibreOrganizer:onPreview()
    local lib, err = self:loadLibrary()
    if not lib then return self:showError(err) end
    local plan = self:makePlan(lib)
    UIManager:show(TextViewer:new{
        title = T(_("Preview — %1"), lib.path),
        text = self:planText(plan),
    })
end

function CalibreOrganizer:onOrganize()
    local lib, err = self:loadLibrary()
    if not lib then return self:showError(err) end
    local plan = self:makePlan(lib)
    if #plan.moves == 0 then
        return self:showError(T(_("Nothing to move.\nAlready in place: %1, skipped: %2."), plan.unchanged, #plan.skipped))
    end
    UIManager:show(ConfirmBox:new{
        text = T(_("Move %1 book(s) into folders built from their Calibre metadata?\n\nNotes, highlights and reading progress move with them. Use “Preview” to see the list."), #plan.moves),
        ok_text = _("Organize"),
        ok_callback = function()
            local moves = {}
            for _, m in ipairs(plan.moves) do table.insert(moves, { from = m.from, to = m.to }) end
            local done, failed = self:applyMoves(lib, moves)
            self.settings.last_run = { root = lib.root, moves = done }
            self:saveSettings()
            self:refreshFileManager()
            self:reportResult(done, failed, _("Moved"))
        end,
    })
end

function CalibreOrganizer:onUndo()
    local last = self.settings.last_run
    if not last or not last.moves or #last.moves == 0 then
        return self:showError(_("There is nothing to undo."))
    end
    local lib, err = self:loadLibrary()
    if not lib then return self:showError(err) end
    if lib.root ~= last.root then
        return self:showError(T(_("The last run was in %1, but the current library is %2."), last.root, lib.root))
    end
    UIManager:show(ConfirmBox:new{
        text = T(_("Move %1 book(s) back to where they were before the last run?"), #last.moves),
        ok_text = _("Undo"),
        ok_callback = function()
            local moves = {}
            for i = #last.moves, 1, -1 do
                local m = last.moves[i]
                table.insert(moves, { from = m.to, to = m.from })
            end
            local done, failed = self:applyMoves(lib, moves)
            self.settings.last_run = nil
            self:saveSettings()
            self:refreshFileManager()
            self:reportResult(done, failed, _("Moved back"))
        end,
    })
end

---------------------------------------------------------------------------
-- settings dialogs
---------------------------------------------------------------------------

function CalibreOrganizer:editText(title, description, value, default, on_save)
    local dialog
    local row = {
        {
            text = _("Cancel"),
            id = "close",
            callback = function() UIManager:close(dialog) end,
        },
    }
    if default then
        table.insert(row, {
            text = _("Default"),
            callback = function() dialog:setInputText(default) end,
        })
    end
    table.insert(row, {
        text = _("Save"),
        is_enter_default = true,
        callback = function()
            local text = dialog:getInputText()
            UIManager:close(dialog)
            on_save(text)
        end,
    })
    dialog = InputDialog:new{
        title = title,
        description = description,
        input = value,
        buttons = { row },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function CalibreOrganizer:editTemplate(touchmenu_instance)
    self:editText(
        _("Folder template"),
        _("Paste the Save template from Calibre: Preferences → Plugins → Device interface → Smart Device App Interface (wireless) or the Kindle/Kobo driver (USB) → Customize plugin."),
        self.settings.template or "", nil,
        function(text)
            text = text:gsub("^%s+", ""):gsub("%s+$", "")
            if text == "" then
                self.settings.template = nil
                self:saveSettings()
                if touchmenu_instance then touchmenu_instance:updateItems() end
                return
            end
            local valid, err = Core.validate(text)
            if not valid then return self:showError(T(_("Template error: %1"), err)) end
            self.settings.template = text
            self:saveSettings()
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end)
end

function CalibreOrganizer:editBase(touchmenu_instance)
    self:editText(
        _("Base folder"),
        _("Folder inside the Calibre library folder where organized books go. On a Kindle this is normally “documents”. Leave empty to use the library folder itself."),
        self.settings.base, DEFAULT_BASE,
        function(text)
            text = text:gsub("^/+", ""):gsub("/+$", "")
            self.settings.base = text
            self:saveSettings()
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end)
end

function CalibreOrganizer:chooseLibraryDir(touchmenu_instance)
    local PathChooser = require("ui/widget/pathchooser")
    local start = self.settings.library_dir or self:findMetadata() or G_reader_settings:readSetting("home_dir") or "/"
    UIManager:show(PathChooser:new{
        select_file = false,
        show_files = false,
        path = start,
        onConfirm = function(dir)
            dir = dir:gsub("/+$", "")
            local found = false
            for _, name in ipairs(METADATA_NAMES) do
                if fileExists(dir .. "/" .. name) then found = true end
            end
            if not found then
                return self:showError(T(_("No metadata.calibre file in %1."), dir))
            end
            self.settings.library_dir = dir
            self:saveSettings()
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
end

---------------------------------------------------------------------------
-- menu
---------------------------------------------------------------------------

function CalibreOrganizer:addToMainMenu(menu_items)
    menu_items.calibre_organizer = {
        text = _("Calibre organizer"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Preview"),
                callback = function() self:onPreview() end,
            },
            {
                text = _("Organize now"),
                callback = function() self:onOrganize() end,
            },
            {
                text = _("Undo last organize"),
                enabled_func = function()
                    return self.settings.last_run ~= nil and self.settings.last_run.moves ~= nil
                        and #self.settings.last_run.moves > 0
                end,
                callback = function() self:onUndo() end,
                separator = true,
            },
            {
                text_func = function()
                    return T(_("Folder template: %1"), self.settings.template or _("not set"))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance) self:editTemplate(touchmenu_instance) end,
            },
            {
                text_func = function()
                    local base = self.settings.base
                    return T(_("Base folder: %1"), base ~= "" and base or _("(library folder)"))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance) self:editBase(touchmenu_instance) end,
            },
            {
                text_func = function()
                    return T(_("Calibre library folder: %1"), self.settings.library_dir or _("automatic"))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance) self:chooseLibraryDir(touchmenu_instance) end,
                hold_callback = function(touchmenu_instance)
                    self.settings.library_dir = nil
                    self:saveSettings()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            },
            {
                text = _("Remove empty folders after moving"),
                checked_func = function() return self.settings.remove_empty_dirs end,
                callback = function()
                    self.settings.remove_empty_dirs = not self.settings.remove_empty_dirs
                    self:saveSettings()
                end,
            },
        },
    }
end

return CalibreOrganizer
