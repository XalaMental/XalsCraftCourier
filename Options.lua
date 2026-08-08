-- ============================================================
-- Options.lua  —  Xal's Craft Courier
-- Blizzard Interface → AddOns settings panel.
--
-- Layout: top-level mode tabs — Alts, then one tab per guild your alts
-- belong to, each fully separate, never an automatic fallback between
-- them — then three columns: professions, then an alt/roster name list,
-- then the crafters grid for whichever profession is selected.
--
-- Guild roster pulled live from C_GuildInfo / GetGuildRosterInfo.
-- ============================================================

XC = XC or {}
XC.Options = XC.Options or {}
local O = XC.Options

-- ─── Theme ────────────────────────────────────────────────────
local C_ACCENT   = { 0.72, 0.55, 0.22 }
local C_GREEN = { 0.10, 0.62, 0.18 }   -- WoW nameplate guild green
local C_GOLD  = { 0.60, 0.47, 0.30 }
local C_STEEL = { 0.14, 0.14, 0.14 }

-- ─── Tab layout ───────────────────────────────────────────────
local TAB_ROWS = {
    { "Alchemy","Blacksmithing","Cooking","Enchanting","Engineering","Fishing","Herbalism" },
    { "Inscription","Jewelcrafting","Leatherworking","Mining","Skinning","Tailoring" },
}
local ROW_H    = 26
local SLOT_PAD = 8
local HEADER_H = 36   -- global settings header above tabs
local CANVAS_W, CANVAS_H = 860, 640
local CONTENT_W = CANVAS_W - 6 - 26   -- matches the scroll frame's own horizontal insets

-- ─── State ────────────────────────────────────────────────────
O.registered  = false
O.activeProf  = nil
O.altDropdown  = nil   -- shared alt dropdown
O.guildDropdown = nil  -- shared guild dropdown
O.guildLbl      = nil  -- header guild indicator (set once canvas is built)

-- GetGuildInfo("player") can return nil if called before the guild roster
-- has synced from the server yet - it's not a live read, so the label must
-- be refreshed on PLAYER_GUILD_UPDATE rather than only set once at build time.
function O:RefreshGuildLabel()
    if not self.guildLbl then return end
    local gName = GetGuildInfo("player")
    if gName then
        self.guildLbl:SetText("|cff1a9e2e< " .. gName .. " >|r")
    else
        self.guildLbl:SetText("|cff666666(not in a guild)|r")
    end
end

-- The mode-tab bar is built once at Register() time, which runs at
-- ADDON_LOADED — before PLAYER_LOGIN, before XC:RecordMyGuild() has ever
-- had a chance to run. So the very first build almost always has zero
-- known guilds. This rebuilds the tab bar live once real guild data
-- actually arrives, instead of freezing it at that too-early snapshot.
local guildEventFrame = CreateFrame("Frame")
guildEventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
guildEventFrame:SetScript("OnEvent", function(_, _, unit)
    if unit == nil or unit == "player" then
        O:RefreshGuildLabel()
        if O.modeTabs then O.modeTabs.Rebuild() end
    end
end)


-- ══════════════════════════════════════════════════════════════
-- WIDGET FACTORIES
-- ══════════════════════════════════════════════════════════════
local function Tex(parent, x, y, w, h, r, g, b, a)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    t:SetSize(w, h); t:SetColorTexture(r, g, b, a or 1)
    return t
end

local function Lbl(parent, text, size, r, g, b, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\ARIALN.TTF", size or 12, flags or "")
    fs:SetText(text or "")
    fs:SetTextColor(r or 1, g or 1, b or 1, 1)
    return fs
end

local function MakeBtn(parent, text, w, h, primary, colorOverride)
    local base  = primary and 0.17 or 0.11
    local col   = colorOverride or (primary and C_ACCENT or { 0.55, 0.42, 0.20 })
    local btn   = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(base, base, base, 1)
    local eTop = btn:CreateTexture(nil, "OVERLAY")
    eTop:SetPoint("TOPLEFT"); eTop:SetPoint("TOPRIGHT")
    eTop:SetHeight(1); eTop:SetColorTexture(0.30, 0.30, 0.30, 1)
    local eBot = btn:CreateTexture(nil, "OVERLAY")
    eBot:SetPoint("BOTTOMLEFT"); eBot:SetPoint("BOTTOMRIGHT")
    eBot:SetHeight(1); eBot:SetColorTexture(0.06, 0.06, 0.06, 1)
    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\ARIALN.TTF", 11, "OUTLINE")
    lbl:SetPoint("CENTER"); lbl:SetText(text)
    lbl:SetTextColor(col[1], col[2], col[3], 1)
    btn.lbl = lbl
    btn:SetScript("OnEnter", function() bg:SetColorTexture(base+0.05,base+0.05,base+0.05,1) end)
    btn:SetScript("OnLeave", function() bg:SetColorTexture(base,base,base,1) end)
    btn:SetScript("OnMouseDown", function()
        bg:SetColorTexture(base-0.04,base-0.04,base-0.04,1)
        lbl:SetPoint("CENTER",btn,"CENTER",1,-1)
    end)
    btn:SetScript("OnMouseUp", function()
        bg:SetColorTexture(base,base,base,1)
        lbl:SetPoint("CENTER",btn,"CENTER",0,0)
    end)
    return btn
end

local function MakeCB(parent, label, checked, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb.text:SetFont("Fonts\\ARIALN.TTF", 11, "")
    cb.text:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 1)
    cb.text:SetText(label or "")
    cb:SetChecked(checked)
    if onChange then
        cb:SetScript("OnClick", function(self) onChange(self:GetChecked()) end)
    end
    return cb
end

-- Small border-outline checkbox with no built-in label — for dense grids
-- (the expansion/item-type filter popup) where Blizzard's stock
-- UICheckButtonTemplate gold skin, tiled dozens of times, reads as one
-- solid tan block instead of a clean grid.
local function MakeMiniCB(parent, checked, accent, onChange)
    local cb = CreateFrame("Button", nil, parent)
    cb:SetSize(14, 14)

    -- A single texture, full size, distinguished only by color/opacity -
    -- not a border-plus-inset-interior. Two overlapping textures at this
    -- size were showing inconsistent 1px gaps on different sides
    -- depending on each checkbox's exact screen position (a sub-pixel
    -- rounding mismatch between the two separately-anchored textures).
    -- One texture can't have a gap with itself.
    local box = cb:CreateTexture(nil, "ARTWORK")
    box:SetAllPoints()
    cb.box = box

    local function Restyle(enabled)
        local a = enabled and 1 or 0.4
        if cb.checked then
            box:SetColorTexture(accent[1]*a, accent[2]*a, accent[3]*a, 1)
        else
            box:SetColorTexture(accent[1]*0.35*a, accent[2]*0.35*a, accent[3]*0.35*a, 1)
        end
    end
    cb.Restyle = Restyle

    cb.checked = checked
    cb.enabled = true
    Restyle(true)

    cb.SetChecked = function(self, v) self.checked = v; Restyle(self.enabled) end
    cb.GetChecked  = function(self) return self.checked end
    cb.SetEnabled  = function(self, en)
        self.enabled = en
        Restyle(en)
    end
    cb:SetScript("OnClick", function(self)
        if not self.enabled then return end
        self.checked = not self.checked
        Restyle(self.enabled)
        if onChange then onChange(self.checked) end
    end)
    return cb
end


-- ══════════════════════════════════════════════════════════════
-- SHARED ALT DROPDOWN  (personal crafters)
-- ══════════════════════════════════════════════════════════════
local function BuildBaseDropdown(frameName, accentColor)
    local dd = CreateFrame("Frame", frameName, UIParent)
    dd:SetFrameStrata("TOOLTIP"); dd:SetSize(230, 10); dd:Hide()
    local bg = dd:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.07, 0.07, 0.07, 0.97)
    -- Thin outline only - a single texture sized to the whole frame here
    -- would sit on top of the BACKGROUND layer and paint over it entirely.
    local bTop    = dd:CreateTexture(nil, "BORDER")
    bTop:SetPoint("TOPLEFT"); bTop:SetPoint("TOPRIGHT"); bTop:SetHeight(1)
    local bBottom = dd:CreateTexture(nil, "BORDER")
    bBottom:SetPoint("BOTTOMLEFT"); bBottom:SetPoint("BOTTOMRIGHT"); bBottom:SetHeight(1)
    local bLeft   = dd:CreateTexture(nil, "BORDER")
    bLeft:SetPoint("TOPLEFT"); bLeft:SetPoint("BOTTOMLEFT"); bLeft:SetWidth(1)
    local bRight  = dd:CreateTexture(nil, "BORDER")
    bRight:SetPoint("TOPRIGHT"); bRight:SetPoint("BOTTOMRIGHT"); bRight:SetWidth(1)
    for _, line in ipairs({ bTop, bBottom, bLeft, bRight }) do
        line:SetColorTexture(accentColor[1]*0.5, accentColor[2]*0.5, accentColor[3]*0.5, 1)
    end
    dd.rows = {}; dd.activeBox = nil
    return dd
end

-- Returns true when this call just closed the dropdown (second click on
-- the same box) so callers know to skip the Show() that would otherwise
-- immediately reopen it.
local function PopulateDropdown(dd, entries, targetBox, cfg, noEntriesMsg)
    if dd:IsShown() and dd.activeBox == targetBox then dd:Hide(); return true end
    dd.activeBox = targetBox
    for _, r in ipairs(dd.rows) do r:Hide() end
    dd.rows = {}
    local RH = 22
    if #entries == 0 then
        local h = Lbl(dd, "  " .. (noEntriesMsg or "(none)"), 11, 0.45, 0.45, 0.45)
        h:SetPoint("TOPLEFT", dd, "TOPLEFT", 4, -6)
        dd:SetHeight(28); table.insert(dd.rows, h)
    else
        local myRealm = XC_CharDB.realm or ""
        for i, entry in ipairs(entries) do
            local row = CreateFrame("Button", nil, dd)
            row:SetSize(230, RH)
            row:SetPoint("TOPLEFT", dd, "TOPLEFT", 0, -(i-1)*RH)
            local hl = row:CreateTexture(nil,"BACKGROUND")
            hl:SetAllPoints(); hl:SetColorTexture(0.18,0.18,0.18,0)
            row:SetScript("OnEnter", function() hl:SetAlpha(1) end)
            row:SetScript("OnLeave", function() hl:SetAlpha(0) end)
            local rl = Lbl(row, entry.display, 12, 0.85, 0.75, 0.55)
            rl:SetPoint("LEFT", row, "LEFT", 10, 0)
            row:SetScript("OnClick", function()
                local fullName = entry.fullName
                local n, r2 = fullName:match("^(.+)-(.+)$")
                local val = (r2 == myRealm) and (n or fullName) or fullName
                targetBox:SetText(val)
                cfg.name = val
                dd:Hide()
            end)
            table.insert(dd.rows, row)
        end
        dd:SetHeight(#entries * RH + 2)
    end
end

local function ShowAltDropdown(anchorBtn, targetBox, cfg)
    if not O.altDropdown then
        O.altDropdown = BuildBaseDropdown("XC_OptAltDD", C_ACCENT)
    end
    local dd = O.altDropdown
    local chars = XC_DB.knownChars or {}
    local entries = {}
    for _, fullName in ipairs(chars) do
        table.insert(entries, { fullName = fullName, display = fullName })
    end
    if PopulateDropdown(dd, entries, targetBox, cfg,
        "(Log in on each alt to register them)") then return end
    dd:ClearAllPoints()
    dd:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
    dd:Show()
end

-- ══════════════════════════════════════════════════════════════
-- GUILD DROPDOWN  (guild crafters)
-- Pulls live from the guild roster, shows rank next to name.
-- ══════════════════════════════════════════════════════════════
local function ShowGuildDropdown(anchorBtn, targetBox, cfg)
    if not O.guildDropdown then
        O.guildDropdown = BuildBaseDropdown("XC_OptGuildDD", C_GREEN)
    end
    local dd = O.guildDropdown

    -- Check guild membership first
    local guildName = GetGuildInfo("player")
    if not guildName then
        if dd:IsShown() and dd.activeBox == targetBox then dd:Hide(); return end
        dd.activeBox = targetBox
        for _, r in ipairs(dd.rows) do r:Hide() end; dd.rows = {}
        local msg = Lbl(dd, "  You are not in a guild.", 11, 0.45, 0.55, 0.45)
        msg:SetPoint("TOPLEFT", dd, "TOPLEFT", 4, -6)
        dd:SetHeight(28); table.insert(dd.rows, msg)
        dd:ClearAllPoints()
        dd:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
        dd:Show()
        return
    end

    -- Request a fresh roster from the server then populate
    C_GuildInfo.GuildRoster()

    local myName  = UnitName("player") or ""
    local myRealm = XC_CharDB.realm or ""
    local numTotal = GetNumGuildMembers()
    local entries  = {}

    for i = 1, numTotal do
        local name, rankName = GetGuildRosterInfo(i)
        if name then
            local charName = name:match("^([^%-]+)") or name
            if charName ~= myName then
                table.insert(entries, {
                    fullName = name,
                    display  = name .. " |cff888888(" .. (rankName or "?") .. ")|r",
                })
            end
        end
    end

    table.sort(entries, function(a,b) return a.fullName < b.fullName end)

    if PopulateDropdown(dd, entries, targetBox, cfg,
        "(Guild roster empty or still loading)") then return end
    dd:ClearAllPoints()
    dd:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
    dd:Show()
end

-- ══════════════════════════════════════════════════════════════
-- EXPANSION & ITEM FILTERS POPUP  (one shared floating panel, same
-- pattern as the alt/guild dropdowns above — pops out over everything
-- instead of being squeezed inside the crafter row, which was clipping
-- the rightmost item-type columns.)
-- ══════════════════════════════════════════════════════════════
O.expansionPopup    = nil
O.expansionPopupCfg = nil   -- which cfg table currently owns the popup, for toggle-close

local function ToggleExpansionPopup(anchorBtn, cfg, prof, accent)
    if O.expansionPopup and O.expansionPopup:IsShown() and O.expansionPopupCfg == cfg then
        O.expansionPopup:Hide()
        O.expansionPopupCfg = nil
        return
    end

    if not O.expansionPopup then
        local dd = CreateFrame("Frame", "XC_ExpansionPopup", UIParent)
        dd:SetFrameStrata("TOOLTIP")
        dd:Hide()
        local bg = dd:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.05, 1)
        -- Thin outline only — a previous version used a single texture
        -- sized to the whole frame here, which painted over the entire
        -- background instead of just tracing the edge.
        local bTop    = dd:CreateTexture(nil, "BORDER")
        bTop:SetPoint("TOPLEFT"); bTop:SetPoint("TOPRIGHT"); bTop:SetHeight(1)
        local bBottom = dd:CreateTexture(nil, "BORDER")
        bBottom:SetPoint("BOTTOMLEFT"); bBottom:SetPoint("BOTTOMRIGHT"); bBottom:SetHeight(1)
        local bLeft   = dd:CreateTexture(nil, "BORDER")
        bLeft:SetPoint("TOPLEFT"); bLeft:SetPoint("BOTTOMLEFT"); bLeft:SetWidth(1)
        local bRight  = dd:CreateTexture(nil, "BORDER")
        bRight:SetPoint("TOPRIGHT"); bRight:SetPoint("BOTTOMRIGHT"); bRight:SetWidth(1)
        for _, line in ipairs({ bTop, bBottom, bLeft, bRight }) do
            line:SetColorTexture(0.4, 0.32, 0.16, 1)
        end
        dd.rows = {}
        O.expansionPopup = dd
    end
    local dd = O.expansionPopup
    O.expansionPopupCfg = cfg

    for _, r in ipairs(dd.rows) do r:Hide(); r:SetParent(UIParent) end
    dd.rows = {}

    XC.DATA:MigrateCrafterConfig(cfg, prof)
    local itemTypes = XC.DATA:GetItemTypes(prof)

    -- Column headers — width grows to fit however many item-type columns
    -- this profession has, instead of a fixed width that clipped them.
    local PAD = 10
    local headerFrame = CreateFrame("Frame", nil, dd)
    headerFrame:SetPoint("TOPLEFT", dd, "TOPLEFT", PAD, -8)
    local hdrLbl = Lbl(headerFrame, "Expansion", 10, 0.50, 0.30, 0.15)
    hdrLbl:SetPoint("LEFT", headerFrame, "LEFT", 24, 0); hdrLbl:SetWidth(70)
    local hdrX = 100
    for _, itype in ipairs(itemTypes) do
        local h = Lbl(headerFrame, itype.label, 10, accent[1]*0.7, accent[2]*0.7, accent[3]*0.7)
        h:SetPoint("LEFT", headerFrame, "LEFT", hdrX + 2, 0)
        hdrX = hdrX + 20 + math.floor(#itype.label * 6.5) + 8
    end
    headerFrame:SetSize(hdrX, 18)
    table.insert(dd.rows, headerFrame)

    local totalH = 8 + 20

    -- Expansion rows
    for ei, exp in ipairs(XC.DATA.Expansions) do
        local expCfg = cfg.expansions[exp.id]

        local rowFrame = CreateFrame("Frame", nil, dd)
        rowFrame:SetSize(hdrX, ROW_H)
        rowFrame:SetPoint("TOPLEFT", dd, "TOPLEFT", PAD, -(8 + 20 + (ei-1)*ROW_H))

        local expLbl = Lbl(rowFrame, exp.short, 11, 0.72, 0.42, 0.18)
        expLbl:SetPoint("LEFT", rowFrame, "LEFT", 22, 0); expLbl:SetWidth(68)

        local sep = rowFrame:CreateTexture(nil, "ARTWORK")
        sep:SetPoint("LEFT", rowFrame, "LEFT", 96, 0); sep:SetSize(1, ROW_H-4)
        sep:SetColorTexture(accent[1]*0.35, accent[2]*0.35, accent[3]*0.35, 1)

        rowFrame.itemCBs = {}

        local function UpdateItemCBs(enabled)
            for _, icb in ipairs(rowFrame.itemCBs) do
                icb:SetEnabled(enabled)
            end
        end

        local masterCB = MakeMiniCB(rowFrame, expCfg.enabled, accent, function(v)
            expCfg.enabled = v
            UpdateItemCBs(v)
        end)
        masterCB:SetPoint("LEFT", rowFrame, "LEFT", 0, 0)

        local cbX = 100
        for _, itype in ipairs(itemTypes) do
            local icb = MakeMiniCB(rowFrame, expCfg.enabled and expCfg[itype.id], accent,
                function(v) expCfg[itype.id] = v end)
            icb:SetPoint("LEFT", rowFrame, "LEFT", cbX, 0)
            cbX = cbX + 20 + math.floor(#itype.label * 6.5) + 8
            table.insert(rowFrame.itemCBs, icb)
        end

        if not expCfg.enabled then UpdateItemCBs(false) end
        table.insert(dd.rows, rowFrame)
        totalH = totalH + ROW_H
    end

    dd:SetSize(hdrX + PAD * 2, totalH + PAD)
    dd:ClearAllPoints()
    dd:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
    dd:Show()
end

-- ══════════════════════════════════════════════════════════════
-- DB HELPERS
-- ══════════════════════════════════════════════════════════════
local function GetCrafters(prof)
    XC_DB.profConfig[prof] = XC_DB.profConfig[prof] or { crafters = {}, guildCraftersByGuild = {} }
    return XC_DB.profConfig[prof].crafters
end

-- Guild crafters are scoped to ONE specific guild — a crafter set for
-- "Loser Emporium" never shows up under a different guild's tab.
local function GetGuildCrafters(prof, guildName)
    XC_DB.profConfig[prof] = XC_DB.profConfig[prof] or { crafters = {}, guildCraftersByGuild = {} }
    XC_DB.profConfig[prof].guildCraftersByGuild = XC_DB.profConfig[prof].guildCraftersByGuild or {}
    if not guildName then return {} end
    XC_DB.profConfig[prof].guildCraftersByGuild[guildName] =
        XC_DB.profConfig[prof].guildCraftersByGuild[guildName] or {}
    return XC_DB.profConfig[prof].guildCraftersByGuild[guildName]
end

local function AddCrafter(prof)
    local cfg = XC.DATA:DefaultCrafterConfig(prof)
    table.insert(GetCrafters(prof), cfg); return cfg
end

local function AddGuildCrafter(prof, guildName)
    local cfg = XC.DATA:DefaultCrafterConfig(prof)
    cfg.isGuild = true
    table.insert(GetGuildCrafters(prof, guildName), cfg); return cfg
end

local function RemoveCrafter(prof, idx) table.remove(GetCrafters(prof), idx) end
local function RemoveGuildCrafter(prof, idx, guildName)
    table.remove(GetGuildCrafters(prof, guildName), idx)
end


-- ══════════════════════════════════════════════════════════════
-- CRAFTER SLOT BUILDER
--
-- isGuild = false → red theme  (personal alt)
-- isGuild = true  → green theme (guild crafter)
-- ══════════════════════════════════════════════════════════════
local function BuildCrafterSlot(parent, prof, idx, cfg, onDelete, isGuild)
    XC.DATA:MigrateCrafterConfig(cfg, prof)

    local accent  = isGuild and C_GREEN or C_ACCENT
    local slotW   = parent:GetWidth() - 10

    local slot = CreateFrame("Frame", nil, parent)
    slot:SetWidth(slotW)

    -- Border-outline only, no filled background — same clean-line
    -- treatment as the splash screen and every other panel in the addon.
    local top    = slot:CreateTexture(nil, "ARTWORK")
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
    local bottom = slot:CreateTexture(nil, "ARTWORK")
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
    local left   = slot:CreateTexture(nil, "ARTWORK")
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(1)
    local right  = slot:CreateTexture(nil, "ARTWORK")
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
    for _, line in ipairs({ top, bottom, left, right }) do
        line:SetColorTexture(accent[1]*0.5, accent[2]*0.5, accent[3]*0.5, 1)
    end

    local curY = SLOT_PAD

    -- Enabled toggle
    local enabledCB = MakeCB(slot, "", cfg.enabled, function(v) cfg.enabled = v end)
    enabledCB:SetPoint("TOPLEFT", slot, "TOPLEFT", SLOT_PAD, -curY)

    -- Name input
    local nameBox = CreateFrame("EditBox", nil, slot, "InputBoxTemplate")
    nameBox:SetSize(170, 24)
    nameBox:SetPoint("LEFT", enabledCB, "RIGHT", 4, 0)
    nameBox:SetAutoFocus(false); nameBox:SetMaxLetters(60)
    nameBox:SetText(cfg.name or "")
    nameBox:SetScript("OnEditFocusLost", function(self)
        cfg.name = self:GetText():match("^%s*(.-)%s*$")
    end)
    nameBox:SetScript("OnEnterPressed", function(self)
        cfg.name = self:GetText():match("^%s*(.-)%s*$"); self:ClearFocus()
    end)

    -- Dropdown — alt list or guild roster depending on slot type
    local ddBtn = MakeBtn(slot, "v", 24, 24, false)
    ddBtn:SetPoint("LEFT", nameBox, "RIGHT", 3, 0)
    if isGuild then
        ddBtn:SetScript("OnClick", function() ShowGuildDropdown(ddBtn, nameBox, cfg) end)
    else
        ddBtn:SetScript("OnClick", function() ShowAltDropdown(ddBtn, nameBox, cfg) end)
    end

    -- Remove button — chained after the dropdown (not pinned to the
    -- slot's outer edge) so it stays visible even if Blizzard gives our
    -- canvas less width than CANVAS_W assumes; a right-edge anchor would
    -- clip first.
    local delBtn = MakeBtn(slot, "X Remove", 84, 22, false)
    delBtn:SetPoint("LEFT", ddBtn, "RIGHT", 12, 0)
    delBtn:SetScript("OnClick", function() onDelete(idx) end)

    curY = curY + 30

    -- Expansion & Item Filters — opens the shared floating popup (built
    -- above, same pattern as the alt/guild dropdowns) instead of
    -- expanding inline, which was clipping the item-type columns against
    -- the crafter row's own width.
    local expandBtn = CreateFrame("Button", nil, slot)
    expandBtn:SetPoint("TOPLEFT", slot, "TOPLEFT", SLOT_PAD, -curY)
    expandBtn:SetSize(220, 22)
    local expandLbl = expandBtn:CreateFontString(nil, "OVERLAY")
    expandLbl:SetFont("Fonts\\ARIALN.TTF", 11, "OUTLINE")
    expandLbl:SetPoint("LEFT")
    expandLbl:SetText("+   Expansion & Item Filters")
    expandLbl:SetTextColor(accent[1]*0.9, accent[2]*0.9, accent[3]*0.9, 1)
    local expandLine = expandBtn:CreateTexture(nil, "ARTWORK")
    expandLine:SetPoint("BOTTOMLEFT"); expandLine:SetPoint("BOTTOMRIGHT")
    expandLine:SetHeight(1)
    expandLine:SetColorTexture(accent[1]*0.4, accent[2]*0.4, accent[3]*0.4, 1)
    expandBtn:SetScript("OnClick", function()
        ToggleExpansionPopup(expandBtn, cfg, prof, accent)
    end)
    curY = curY + 26

    slot.GetContentHeight = function() return curY + 6 end
    slot:SetHeight(slot.GetContentHeight())
    return slot
end


-- ══════════════════════════════════════════════════════════════
-- MODE TABS  (Alts, then one tab per guild your alts belong to) —
-- top-level, chat-tab style, always a deliberate, separate choice.
-- Nothing ever auto-falls-back between tabs.
--
-- There's no API to see another character's guild remotely — a guild
-- only ever shows up here once some character has actually logged in
-- with the addon running while in it (see XC:RecordMyGuild in Core.lua).
--
-- Each guild tab's crafters are fully separate (guildCraftersByGuild,
-- keyed by guild name) - a crafter set up under one guild's tab never
-- shows up under a different guild's tab.
-- ══════════════════════════════════════════════════════════════
local MODE_TAB_H = 30
local PROF_COL_W = 150
local PROF_ROW_H = 26

O.activeMode      = "personal"   -- "personal" or "guild"
O.activeGuildName = nil          -- which known-guild tab is active, when in guild mode
O.selectedAltName = nil          -- currently-picked name from the name list

local function BuildModeTabs(canvas)
    local wrap = CreateFrame("Frame", nil, canvas)
    wrap:SetPoint("TOPLEFT",  canvas, "TOPLEFT",  0, -HEADER_H)
    wrap:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", 0, -HEADER_H)
    wrap:SetHeight(MODE_TAB_H)

    local wbg = wrap:CreateTexture(nil, "BACKGROUND")
    wbg:SetAllPoints(); wbg:SetColorTexture(0.05, 0.04, 0.02, 1)

    local function MakeModeTab(text, color)
        local btn = CreateFrame("Button", nil, wrap)
        btn:SetHeight(MODE_TAB_H)

        -- Selection shown as a border outline, not a filled highlight —
        -- same clean-line treatment as everywhere else in the addon now.
        local top    = btn:CreateTexture(nil, "ARTWORK")
        top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
        local bottom = btn:CreateTexture(nil, "ARTWORK")
        bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(2)
        local left   = btn:CreateTexture(nil, "ARTWORK")
        left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(2)
        local right  = btn:CreateTexture(nil, "ARTWORK")
        right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(2)
        for _, line in ipairs({ top, bottom, left, right }) do
            line:SetColorTexture(color[1], color[2], color[3], 1)
        end
        btn.borderLines = { top, bottom, left, right }

        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
        lbl:SetPoint("CENTER"); lbl:SetText(text)
        -- Size the tab to its actual measured text width, not a guessed
        -- character count — a guessed width is exactly what was letting
        -- text spill past button edges elsewhere in this panel.
        btn:SetWidth(math.max(90, lbl:GetStringWidth() + 28))
        btn.lbl   = lbl
        btn.color = color
        return btn
    end

    local tabs = {}

    local function Restyle()
        for _, t in ipairs(tabs) do
            local active = (t.mode == "personal" and O.activeMode == "personal")
                or (t.mode == "guild" and O.activeMode == "guild" and t.guildName == O.activeGuildName)
            local c = t.color
            for _, line in ipairs(t.borderLines) do line:SetShown(active) end
            t.lbl:SetTextColor(
                active and 1 or c[1]*0.8,
                active and 1 or c[2]*0.8,
                active and 1 or c[3]*0.8, 1)
        end
    end

    local function Rebuild()
        for _, t in ipairs(tabs) do t:Hide(); t:SetParent(UIParent) end
        tabs = {}

        local altsTab = MakeModeTab("ALTS", C_ACCENT)
        altsTab.mode = "personal"
        table.insert(tabs, altsTab)

        for _, guildName in ipairs(XC_DB.knownGuilds or {}) do
            local gTab = MakeModeTab(guildName, C_GREEN)
            gTab.mode      = "guild"
            gTab.guildName = guildName
            table.insert(tabs, gTab)
        end

        local x = 0
        for _, t in ipairs(tabs) do
            t:SetPoint("TOPLEFT", wrap, "TOPLEFT", x, 0)
            x = x + t:GetWidth()
            t:SetScript("OnClick", function()
                O.activeMode      = t.mode
                O.activeGuildName = t.guildName
                Restyle()
                O.RefreshBody()
            end)
        end
        Restyle()
    end

    Rebuild()
    wrap.Rebuild = Rebuild
    return wrap
end


-- ══════════════════════════════════════════════════════════════
-- PROFESSION LIST  (left side, vertical — replaces the old top tab row)
-- ══════════════════════════════════════════════════════════════
local function BuildProfessionList(canvas, bodyTop)
    local ALL_PROFS = {}
    for _, row in ipairs(TAB_ROWS) do
        for _, p in ipairs(row) do table.insert(ALL_PROFS, p) end
    end

    local list = CreateFrame("Frame", nil, canvas)
    list:SetPoint("TOPLEFT",    canvas, "TOPLEFT",    0, -bodyTop)
    list:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", 0,  0)
    list:SetWidth(PROF_COL_W)

    local bg = list:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.04, 0.02, 1)

    -- Top-edge line — part of the divider under the tab row. Drawn here
    -- (not as one texture on canvas) since this column is its own child
    -- frame sitting on top of canvas's own artwork at that seam.
    local topline = list:CreateTexture(nil, "ARTWORK")
    topline:SetPoint("TOPLEFT"); topline:SetPoint("TOPRIGHT"); topline:SetHeight(1)
    topline:SetColorTexture(C_ACCENT[1]*0.5, C_ACCENT[2]*0.5, C_ACCENT[3]*0.5, 1)

    local sepline = list:CreateTexture(nil, "ARTWORK")
    sepline:SetPoint("TOPRIGHT"); sepline:SetPoint("BOTTOMRIGHT")
    sepline:SetWidth(1)
    sepline:SetColorTexture(C_ACCENT[1]*0.4, C_ACCENT[2]*0.4, C_ACCENT[3]*0.4, 1)

    local buttons = {}
    for i, prof in ipairs(ALL_PROFS) do
        local btn = CreateFrame("Button", nil, list)
        btn:SetSize(PROF_COL_W, PROF_ROW_H)
        btn:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i-1)*PROF_ROW_H)

        -- Selection shown as a border outline, not a filled highlight —
        -- same clean-line treatment as the splash screen, hidden until active.
        local top    = btn:CreateTexture(nil, "ARTWORK")
        top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
        local bottom = btn:CreateTexture(nil, "ARTWORK")
        bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
        local left   = btn:CreateTexture(nil, "ARTWORK")
        left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(1)
        local right  = btn:CreateTexture(nil, "ARTWORK")
        right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
        for _, line in ipairs({ top, bottom, left, right } ) do
            line:SetColorTexture(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 1)
            line:Hide()
        end
        btn.borderLines = { top, bottom, left, right }

        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts\\ARIALN.TTF", 12, "")
        lbl:SetPoint("LEFT", btn, "LEFT", 10, 0)
        lbl:SetText(prof)
        btn.lbl  = lbl
        btn.prof = prof

        -- "Configured" mark — a plain dot, not a Unicode checkmark glyph
        -- (✓ is one of the characters WoW's bundled fonts don't render;
        -- same reason the ▶/▼ arrows had to go earlier). Shown when the
        -- currently-active mode/guild has at least one named crafter set
        -- for this profession.
        local mark = btn:CreateTexture(nil, "OVERLAY")
        mark:SetSize(7, 7)
        mark:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
        mark:SetColorTexture(0.15, 0.85, 0.25, 1)
        mark:Hide()
        btn.mark = mark

        btn:SetScript("OnClick", function() O.SelectProf(prof) end)
        buttons[prof] = btn
    end

    function list:Restyle()
        for prof, btn in pairs(buttons) do
            local active = (O.activeProf == prof)
            for _, line in ipairs(btn.borderLines) do line:SetShown(active) end
            btn.lbl:SetTextColor(
                active and 1 or C_GOLD[1],
                active and 1 or C_GOLD[2],
                active and 1 or C_GOLD[3], 1)
        end
    end

    -- Reads whichever store (personal/guild) is currently active, same
    -- source the crafters grid itself reads from — so the dot always
    -- agrees with what the grid would actually show for that profession.
    function list:RefreshMarks()
        for prof, btn in pairs(buttons) do
            local crafters = (O.activeMode == "guild")
                and GetGuildCrafters(prof, O.activeGuildName)
                or  GetCrafters(prof)
            local has = false
            for _, cfg in ipairs(crafters) do
                if cfg.name and cfg.name ~= "" then has = true; break end
            end
            btn.mark:SetShown(has)
        end
    end

    return list
end


-- ══════════════════════════════════════════════════════════════
-- NAME LIST  (second left-side column, between professions and the
-- grid — NOT a horizontal strip, so nothing ever runs off-screen).
-- Personal mode: your known alts. Guild mode: your guild roster.
-- Click a name to select it, then "+ Add Selected" puts it on the
-- currently-selected profession in the currently-active mode.
-- ══════════════════════════════════════════════════════════════
local NAME_COL_W = 170
local NAME_ROW_H = 22

local function BuildNameList(canvas, bodyTop)
    local col = CreateFrame("Frame", nil, canvas)
    col:SetPoint("TOPLEFT",    canvas, "TOPLEFT",    PROF_COL_W, -bodyTop)
    col:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", PROF_COL_W,  0)
    col:SetWidth(NAME_COL_W)

    local bg = col:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.045, 0.036, 0.018, 1)

    -- Top-edge line — part of the divider under the tab row (see the
    -- note in BuildProfessionList for why it's drawn per-column).
    local topline = col:CreateTexture(nil, "ARTWORK")
    topline:SetPoint("TOPLEFT"); topline:SetPoint("TOPRIGHT"); topline:SetHeight(1)
    topline:SetColorTexture(C_ACCENT[1]*0.5, C_ACCENT[2]*0.5, C_ACCENT[3]*0.5, 1)

    local sepline = col:CreateTexture(nil, "ARTWORK")
    sepline:SetPoint("TOPRIGHT"); sepline:SetPoint("BOTTOMRIGHT")
    sepline:SetWidth(1)
    sepline:SetColorTexture(C_ACCENT[1]*0.4, C_ACCENT[2]*0.4, C_ACCENT[3]*0.4, 1)

    -- Built directly (not via the shared Lbl() helper, which is hardcoded
    -- to ARIALN) so this matches the grid title's font/weight/color exactly -
    -- same FRIZQT__.TTF + OUTLINE + accent color as "Alchemy — Your Crafters".
    local hint = col:CreateFontString(nil, "OVERLAY")
    hint:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    hint:SetTextColor(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 1)
    hint:SetPoint("TOPLEFT", col, "TOPLEFT", 6, -4)
    hint:SetWidth(NAME_COL_W - 12)
    hint:SetJustifyH("LEFT")
    col.hint = hint

    local addBtn = MakeBtn(col, "+ Add Selected", NAME_COL_W - 12, 24, true)
    addBtn:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -22)
    addBtn:SetScript("OnClick", function()
        if not O.activeProf then return end
        if O.activeMode == "guild" and not O.activeGuildName then return end
        local cfg = (O.activeMode == "guild")
            and AddGuildCrafter(O.activeProf, O.activeGuildName)
            or  AddCrafter(O.activeProf)
        if O.selectedAltName then cfg.name = O.selectedAltName end
        O.RefreshGrid()
    end)

    local sf = CreateFrame("ScrollFrame", nil, col, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     addBtn, "BOTTOMLEFT", 0, -8)
    sf:SetPoint("BOTTOMRIGHT", col,    "BOTTOMRIGHT", -20, 6)
    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(NAME_COL_W - 32)
    sf:SetScrollChild(content)
    col.content = content
    col.buttons = {}

    function col:Refresh()
        for _, b in ipairs(self.buttons) do b:Hide(); b:SetParent(UIParent) end
        self.buttons = {}

        local entries = {}
        if O.activeMode == "guild" then
            -- The roster API only ever knows the CURRENT character's own
            -- guild - there's no way to see a different guild's roster
            -- remotely, even if some other alt belongs to it.
            local myGuild = GetGuildInfo("player")
            if myGuild and myGuild == O.activeGuildName then
                self.hint:SetText("Guild roster:")
                C_GuildInfo.GuildRoster()
                local myName   = UnitName("player") or ""
                local numTotal = GetNumGuildMembers()
                for i = 1, numTotal do
                    local name = GetGuildRosterInfo(i)
                    if name then
                        local charName = name:match("^([^%-]+)") or name
                        if charName ~= myName then table.insert(entries, name) end
                    end
                end
                table.sort(entries)
            else
                self.hint:SetText("Switch to a character in " ..
                    (O.activeGuildName or "this guild") .. " to see its roster.")
            end
        else
            self.hint:SetText("Known Alts:")
            for _, fullName in ipairs(XC_DB.knownChars or {}) do
                table.insert(entries, fullName)
            end
        end

        local y = 0
        for _, fullName in ipairs(entries) do
            local btn = CreateFrame("Button", nil, content)
            btn:SetSize(NAME_COL_W - 32, NAME_ROW_H)
            btn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            local selected = (O.selectedAltName == fullName)
            -- Selection shown as a border outline, not a filled highlight —
            -- same clean-line treatment as the splash screen.
            if selected then
                local top    = btn:CreateTexture(nil, "ARTWORK")
                top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
                local bottom = btn:CreateTexture(nil, "ARTWORK")
                bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
                local left   = btn:CreateTexture(nil, "ARTWORK")
                left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(1)
                local right  = btn:CreateTexture(nil, "ARTWORK")
                right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
                for _, line in ipairs({ top, bottom, left, right }) do
                    line:SetColorTexture(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 1)
                end
            end
            local lbl = btn:CreateFontString(nil, "OVERLAY")
            lbl:SetFont("Fonts\\ARIALN.TTF", 11, "")
            lbl:SetPoint("LEFT", btn, "LEFT", 4, 0)
            lbl:SetText(fullName)
            lbl:SetTextColor(
                selected and 1 or C_GOLD[1],
                selected and 1 or C_GOLD[2],
                selected and 1 or C_GOLD[3], 1)
            btn:SetScript("OnClick", function()
                O.selectedAltName = fullName
                self:Refresh()
            end)
            y = y + NAME_ROW_H
            table.insert(self.buttons, btn)
        end

        if #entries == 0 then
            local emptyText = (O.activeMode == "guild")
                and "(not in a guild, or the roster hasn't loaded yet)"
                or  "(log in on an alt with the addon running to register it)"
            local empty = Lbl(content, emptyText, 10, 0.45, 0.45, 0.45)
            empty:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
            empty:SetWidth(NAME_COL_W - 40)
            empty:SetJustifyH("LEFT")
            y = y + 30
            table.insert(self.buttons, empty)
        end

        content:SetHeight(math.max(y, 60))
    end

    return col
end


-- ══════════════════════════════════════════════════════════════
-- CRAFTERS GRID  (rightmost column)
-- Shows the crafters assigned to the selected profession, in the
-- currently-active mode. Each row's own Remove button is the "-";
-- the name list's "+ Add Selected" is the "+".
-- ══════════════════════════════════════════════════════════════
local function BuildCraftersGrid(canvas, bodyTop)
    local wrap = CreateFrame("Frame", nil, canvas)
    wrap:SetPoint("TOPLEFT",     canvas, "TOPLEFT",     PROF_COL_W + NAME_COL_W, -bodyTop)
    wrap:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", 0,                        0)

    -- Top-edge line — part of the divider under the tab row (see the
    -- note in BuildProfessionList for why it's drawn per-column).
    local topline = wrap:CreateTexture(nil, "ARTWORK")
    topline:SetPoint("TOPLEFT"); topline:SetPoint("TOPRIGHT"); topline:SetHeight(1)
    topline:SetColorTexture(C_ACCENT[1]*0.5, C_ACCENT[2]*0.5, C_ACCENT[3]*0.5, 1)

    local title = wrap:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    title:SetPoint("TOPLEFT", wrap, "TOPLEFT", 10, -6)
    wrap.title = title

    local sf = CreateFrame("ScrollFrame", nil, wrap, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     wrap, "TOPLEFT",     6,  -30)
    sf:SetPoint("BOTTOMRIGHT", wrap, "BOTTOMRIGHT", -26,  6)

    local GRID_W = CANVAS_W - PROF_COL_W - NAME_COL_W - 6 - 26
    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(GRID_W)   -- fixed, deterministic — same GetWidth()-timing
    sf:SetScrollChild(content) -- hazard as before, avoided the same way
    wrap.content = content
    wrap.slots = {}

    function wrap:Refresh()
        for _, s in ipairs(self.slots) do s:Hide(); s:SetParent(UIParent) end
        self.slots = {}

        local prof = O.activeProf
        if not prof then return end
        local isGuild = (O.activeMode == "guild")
        local accent  = isGuild and C_GREEN or C_ACCENT

        local suffix = isGuild
            and (" — Guild Crafters (" .. (O.activeGuildName or "?") .. ")")
            or  " — Your Crafters"
        self.title:SetText(prof .. suffix)
        self.title:SetTextColor(accent[1], accent[2], accent[3], 1)

        local crafters = isGuild and GetGuildCrafters(prof, O.activeGuildName) or GetCrafters(prof)
        local yPos = 0

        if #crafters == 0 then
            local hint = Lbl(content,
                "No " .. (isGuild and "guild" or "personal") .. " crafters for " .. prof ..
                " yet. Pick a name above and click '+ Add Selected'.",
                12, 0.45, 0.35, 0.20)
            hint:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -yPos)
            yPos = yPos + 24
            table.insert(self.slots, hint)
        else
            for i, cfg in ipairs(crafters) do
                local slot = BuildCrafterSlot(content, prof, i, cfg,
                    function(idx)
                        if isGuild then RemoveGuildCrafter(prof, idx, O.activeGuildName)
                        else            RemoveCrafter(prof, idx) end
                        O.RefreshGrid()
                    end,
                    isGuild)
                slot:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yPos)
                yPos = yPos + slot.GetContentHeight() + 4
                table.insert(self.slots, slot)
            end
        end

        content:SetHeight(math.max(yPos + 10, 80))
    end

    return wrap
end


-- ══════════════════════════════════════════════════════════════
-- PUBLIC API
-- ══════════════════════════════════════════════════════════════
function O:Register()
    if self.registered then return end
    self.registered = true

    local canvas = CreateFrame("Frame", "XC_OptionsCanvas", UIParent)
    canvas:SetSize(CANVAS_W, CANVAS_H)
    self.canvasFrame = canvas

    local bg = canvas:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.035, 0.035, 0.035, 1)

    -- ── Global header bar ─────────────────────────────────────
    local hdrBg = canvas:CreateTexture(nil, "BACKGROUND")
    hdrBg:SetPoint("TOPLEFT");  hdrBg:SetPoint("TOPRIGHT")
    hdrBg:SetHeight(HEADER_H); hdrBg:SetColorTexture(0.07, 0.05, 0.02, 1)

    local hdrLine = canvas:CreateTexture(nil, "ARTWORK")
    hdrLine:SetPoint("BOTTOMLEFT",  hdrBg, "BOTTOMLEFT",  0, 0)
    hdrLine:SetPoint("BOTTOMRIGHT", hdrBg, "BOTTOMRIGHT", 0, 0)
    hdrLine:SetHeight(1)
    hdrLine:SetColorTexture(C_ACCENT[1]*0.5, C_ACCENT[2]*0.5, C_ACCENT[3]*0.5, 1)

    local hdrTitle = canvas:CreateFontString(nil, "OVERLAY")
    hdrTitle:SetFont("Fonts\\MORPHEUS.TTF", 22, "OUTLINE")
    hdrTitle:SetTextColor(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 1)
    hdrTitle:SetText("Xal's Craft Courier")
    hdrTitle:SetPoint("LEFT", hdrBg, "LEFT", 10, 0)

    -- Guild indicator in header — GetGuildInfo can return nil if the guild
    -- roster hasn't synced from the server yet at the moment this panel is
    -- first built, so this needs to be able to refresh later, not just once.
    local guildLbl = canvas:CreateFontString(nil, "OVERLAY")
    guildLbl:SetFont("Fonts\\ARIALN.TTF", 11, "")
    -- Anchored to the title's own measured width, not a guessed fixed
    -- offset - MORPHEUS renders wider than FRIZQT did, so a hardcoded
    -- x-position risked the exact same overlap bug fixed twice already.
    guildLbl:SetPoint("LEFT", hdrTitle, "RIGHT", 16, 0)
    self.guildLbl = guildLbl
    self:RefreshGuildLabel()

    -- ── Body: mode tabs, then three columns — professions, names, grid ──
    local modeTabs = BuildModeTabs(canvas)
    self.modeTabs  = modeTabs
    local bodyTop  = HEADER_H + MODE_TAB_H

    -- NOTE: the divider under the tab row is drawn as each column's OWN
    -- top-edge line (inside BuildProfessionList/BuildNameList/
    -- BuildCraftersGrid), not as one texture here on canvas directly.
    -- Those three columns are separate child frames that sit ON TOP of
    -- canvas's own artwork at that exact seam, so a single line drawn
    -- here would be hidden everywhere except the tiny gaps between them.

    local profList = BuildProfessionList(canvas, bodyTop)
    local nameList = BuildNameList(canvas, bodyTop)
    local grid     = BuildCraftersGrid(canvas, bodyTop)

    O.SelectProf = function(prof)
        O.activeProf = prof
        profList:Restyle()
        grid:Refresh()
    end
    O.RefreshBody = function()
        nameList:Refresh()
        grid:Refresh()
        profList:RefreshMarks()
    end
    O.RefreshGrid = function()
        grid:Refresh()
        profList:RefreshMarks()
    end

    nameList:Refresh()
    O.SelectProf(TAB_ROWS[1][1])

    -- The canvas itself has to exist early (ADDON_LOADED) so the category
    -- shows up in the AddOns list at all - but nothing says its CONTENT has
    -- to be frozen from that early snapshot. Every time the panel is
    -- actually opened, refresh everything to current reality: guild label,
    -- which guild tabs exist, and the currently-selected view.
    canvas:SetScript("OnShow", function()
        O:RefreshGuildLabel()
        modeTabs.Rebuild()
        O.RefreshBody()
    end)

    -- The alt/guild dropdowns and the expansion-filter popup are all
    -- separate floating frames parented to UIParent (so they can render
    -- above everything, same as a tooltip) - not children of this canvas.
    -- Closing the canvas doesn't hide them on its own, so they'd stay on
    -- screen after the options panel itself was closed.
    canvas:SetScript("OnHide", function()
        if O.altDropdown then O.altDropdown:Hide() end
        if O.guildDropdown then O.guildDropdown:Hide() end
        if O.expansionPopup then O.expansionPopup:Hide() end
        O.expansionPopupCfg = nil
    end)

    local category = Settings.RegisterCanvasLayoutCategory(canvas, "Xal's Craft Courier")
    category:SetCategorySet(Settings.CategorySet.AddOns)
    Settings.RegisterAddOnCategory(category)
    self.categoryID = category:GetID()
end

function O:Open()
    if not self.registered then self:Register() end
    Settings.OpenToCategory(self.categoryID)
end
