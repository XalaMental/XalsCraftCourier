-- ============================================================
-- Options.lua  —  Xal's Craft Courier
-- Standalone floating crafter-config window (not the Blizzard
-- Interface/AddOns settings frame — see O:Register()/O:Open()).
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
local Brand = XC.BrandStyle

-- ─── Theme ────────────────────────────────────────────────────
-- ACCENT/GOLD aliased to the shared brand module (same values, one
-- shared source of truth). GREEN is Options-specific (guild color-coding,
-- used throughout this addon), not part of the brand spec.
local C_ACCENT = Brand.ACCENT
local C_GREEN  = { 0.10, 0.62, 0.18 }   -- WoW nameplate guild green
local C_GOLD   = Brand.GOLD

-- Confirmed settings-panel typography standard (2026-08-09), aliased from
-- the shared module so there's one source of truth. Dim/description text
-- uses the 13px floor, brighter label/checkbox text uses the 14px floor.
local PANEL_DESC_FONT_SIZE  = Brand.DESC_FONT_SIZE
local PANEL_LABEL_FONT_SIZE = Brand.BUTTON_LABEL_SIZE

-- Reads a FontString's current font and reapplies it at the given size -
-- needed because some fonts here come from an inherited template
-- (GameFontNormal etc.), not a direct SetFont call.
local function BumpFont(fs, size)
    local font, _, flags = fs:GetFont()
    if font then fs:SetFont(font, size, flags) end
end

-- ─── Tab layout ───────────────────────────────────────────────
local TAB_ROWS = {
    { "Alchemy","Blacksmithing","Cooking","Enchanting","Engineering","Fishing","Herbalism" },
    { "Inscription","Jewelcrafting","Leatherworking","Mining","Skinning","Tailoring" },
}
local ROW_H    = 26
local SLOT_PAD = 8
-- Where the body (mode tabs + 3 columns) starts below the header - matches
-- Routes' standalone settings window's sidebar TOPLEFT y (-78) exactly,
-- since this header (title + close/Settings row + divider) is built the
-- same way.
local BODY_TOP = 78
-- Grid (Your Crafters) content is now sized to what a crafter slot
-- actually needs (checkbox + name box + dropdown + Remove button + real
-- padding, ~333px) instead of stretching to fill whatever's left of the
-- canvas - that leftover-space stretch was the "big old gap" past the
-- Remove button the crafter slot's own border was drawn around.
local GRID_CONTENT_W = 360
-- CANVAS_W = 2*SAFE_MARGIN(28) + PROF_COL_W(190) + NAME_COL_W(230) +
-- grid wrap width (GRID_CONTENT_W 360 + scrollframe insets 6+26=32 = 392)
-- = 840. Not independently chosen - derived from the actual column
-- widths below so the panel is only as wide as its content needs.
local CANVAS_W, CANVAS_H = 840, 700
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

-- Shared flat button style (Brand.MakeButton), replacing the old
-- hand-drawn beveled version. `primary` maps to SetSelected(true) - a
-- brighter fill + white label for the emphasized action, same visual
-- role primary=true used to carry.
local function MakeBtn(parent, text, w, h, primary)
    local btn = Brand.MakeButton(parent, text, w, h, nil)
    if primary then btn:SetSelected(true) end
    btn.lbl = btn.label
    return btn
end

local function MakeCB(parent, label, checked, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb.text:SetFont("Fonts\\ARIALN.TTF", PANEL_LABEL_FONT_SIZE, "")
    cb.text:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 1)
    cb.text:SetText(label or "")
    cb.text:SetWordWrap(true)
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
    bTop:SetPoint("TOPLEFT"); bTop:SetPoint("TOPRIGHT"); bTop:SetHeight(Brand.LINE_THICKNESS)
    local bBottom = dd:CreateTexture(nil, "BORDER")
    bBottom:SetPoint("BOTTOMLEFT"); bBottom:SetPoint("BOTTOMRIGHT"); bBottom:SetHeight(Brand.LINE_THICKNESS)
    local bLeft   = dd:CreateTexture(nil, "BORDER")
    bLeft:SetPoint("TOPLEFT"); bLeft:SetPoint("BOTTOMLEFT"); bLeft:SetWidth(Brand.LINE_THICKNESS)
    local bRight  = dd:CreateTexture(nil, "BORDER")
    bRight:SetPoint("TOPRIGHT"); bRight:SetPoint("BOTTOMRIGHT"); bRight:SetWidth(Brand.LINE_THICKNESS)
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
        local h = Lbl(dd, "  " .. (noEntriesMsg or "(none)"), PANEL_DESC_FONT_SIZE, 0.45, 0.45, 0.45)
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
            local rl = Lbl(row, entry.display, PANEL_LABEL_FONT_SIZE, 0.85, 0.75, 0.55)
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
        local msg = Lbl(dd, "  You are not in a guild.", PANEL_DESC_FONT_SIZE, 0.45, 0.55, 0.45)
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
        bTop:SetPoint("TOPLEFT"); bTop:SetPoint("TOPRIGHT"); bTop:SetHeight(Brand.LINE_THICKNESS)
        local bBottom = dd:CreateTexture(nil, "BORDER")
        bBottom:SetPoint("BOTTOMLEFT"); bBottom:SetPoint("BOTTOMRIGHT"); bBottom:SetHeight(Brand.LINE_THICKNESS)
        local bLeft   = dd:CreateTexture(nil, "BORDER")
        bLeft:SetPoint("TOPLEFT"); bLeft:SetPoint("BOTTOMLEFT"); bLeft:SetWidth(Brand.LINE_THICKNESS)
        local bRight  = dd:CreateTexture(nil, "BORDER")
        bRight:SetPoint("TOPRIGHT"); bRight:SetPoint("BOTTOMRIGHT"); bRight:SetWidth(Brand.LINE_THICKNESS)
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
    local hdrLbl = Lbl(headerFrame, "Expansion", PANEL_DESC_FONT_SIZE, 0.50, 0.30, 0.15)
    hdrLbl:SetPoint("LEFT", headerFrame, "LEFT", 24, 0); hdrLbl:SetWidth(70)
    local hdrX = 100
    for _, itype in ipairs(itemTypes) do
        local h = Lbl(headerFrame, itype.label, PANEL_DESC_FONT_SIZE, accent[1]*0.7, accent[2]*0.7, accent[3]*0.7)
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

        local expLbl = Lbl(rowFrame, exp.short, PANEL_LABEL_FONT_SIZE, 0.72, 0.42, 0.18)
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
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(Brand.LINE_THICKNESS)
    local bottom = slot:CreateTexture(nil, "ARTWORK")
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(Brand.LINE_THICKNESS)
    local left   = slot:CreateTexture(nil, "ARTWORK")
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(Brand.LINE_THICKNESS)
    local right  = slot:CreateTexture(nil, "ARTWORK")
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(Brand.LINE_THICKNESS)
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
    local expandBtn
    expandBtn = Brand.MakeButton(slot, "+ Expansion & Item Filters", 220, 22, function()
        ToggleExpansionPopup(expandBtn, cfg, prof, accent)
    end)
    expandBtn:SetPoint("TOPLEFT", slot, "TOPLEFT", SLOT_PAD, -curY)
    if isGuild then
        expandBtn:SetBorderColor(accent[1], accent[2], accent[3], 1)
    end
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
-- Wide enough that "Leatherworking" (the longest profession name) doesn't
-- crowd the button's edge or the "configured" green dot.
local PROF_COL_W = 190
local PROF_ROW_H = 30

O.activeMode      = "personal"   -- "personal" or "guild"
O.activeGuildName = nil          -- which known-guild tab is active, when in guild mode
O.selectedAltName = nil          -- currently-picked name from the name list

local function BuildModeTabs(canvas)
    local wrap = CreateFrame("Frame", nil, canvas)
    wrap:SetPoint("TOPLEFT",  canvas, "TOPLEFT",  Brand.SAFE_MARGIN,  -BODY_TOP)
    wrap:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -Brand.SAFE_MARGIN, -BODY_TOP)
    wrap:SetHeight(MODE_TAB_H)

    local wbg = wrap:CreateTexture(nil, "BACKGROUND")
    wbg:SetAllPoints(); wbg:SetColorTexture(0.05, 0.04, 0.02, 1)

    local function MakeModeTab(text, color)
        -- Placeholder width - resized right below to the label's actual
        -- measured text width, not a guessed character count (a guessed
        -- width is exactly what was letting text spill past button edges
        -- elsewhere in this panel).
        local btn = Brand.MakeButton(wrap, text, 90, MODE_TAB_H, nil)
        btn:SetWidth(math.max(90, btn.label:GetStringWidth() + 28))
        btn.lbl   = btn.label
        btn.color = color
        return btn
    end

    local tabs = {}

    -- Guild tabs keep their own green border color instead of the shared
    -- accent gold, so Personal vs. Guild stays visually distinct - the
    -- same color-coding convention used for this everywhere else in the
    -- addon (Options' crafters grid, Mailbox's send preview tabs, etc.).
    -- Brand.MakeButton's SetBorderColor is the exposed hook for exactly
    -- this kind of one-off override.
    local function Restyle()
        for _, t in ipairs(tabs) do
            local active = (t.mode == "personal" and O.activeMode == "personal")
                or (t.mode == "guild" and O.activeMode == "guild" and t.guildName == O.activeGuildName)
            t:SetSelected(active)
            if not active then
                local c = t.color
                t:SetBorderColor(c[1]*0.8, c[2]*0.8, c[3]*0.8, 1)
                t.lbl:SetTextColor(c[1]*0.8, c[2]*0.8, c[3]*0.8, 1)
            elseif t.mode == "guild" then
                t:SetBorderColor(t.color[1], t.color[2], t.color[3], 1)
            end
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

        -- Real gap between tabs instead of touching edge-to-edge, and a
        -- bigger left inset than SAFE_MARGIN alone gave.
        local TAB_GAP = 6
        local TAB_ROW_LEFT_PAD = 10
        local x = TAB_ROW_LEFT_PAD
        for _, t in ipairs(tabs) do
            t:SetPoint("TOPLEFT", wrap, "TOPLEFT", x, 0)
            x = x + t:GetWidth() + TAB_GAP
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
    list:SetPoint("TOPLEFT",    canvas, "TOPLEFT",    Brand.SAFE_MARGIN, -bodyTop)
    list:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", Brand.SAFE_MARGIN,  Brand.SAFE_MARGIN)
    list:SetWidth(PROF_COL_W)

    local bg = list:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.04, 0.02, 1)

    -- Top-edge line — part of the divider under the tab row. Drawn here
    -- (not as one texture on canvas) since this column is its own child
    -- frame sitting on top of canvas's own artwork at that seam.
    local topline = list:CreateTexture(nil, "ARTWORK")
    topline:SetPoint("TOPLEFT"); topline:SetPoint("TOPRIGHT"); topline:SetHeight(Brand.LINE_THICKNESS)
    topline:SetColorTexture(C_ACCENT[1]*0.5, C_ACCENT[2]*0.5, C_ACCENT[3]*0.5, 1)

    local sepline = list:CreateTexture(nil, "ARTWORK")
    sepline:SetPoint("TOPRIGHT"); sepline:SetPoint("BOTTOMRIGHT")
    sepline:SetWidth(Brand.LINE_THICKNESS)
    sepline:SetColorTexture(C_ACCENT[1]*0.4, C_ACCENT[2]*0.4, C_ACCENT[3]*0.4, 1)

    -- Equal padding on both sides (confirmed standard: sidebar tabs never
    -- sit flush against one edge with slack only on the other) - buttons
    -- are inset TAB_PAD from the column's left AND stop TAB_PAD short of
    -- the sepline divider on the right.
    -- TOP_PAD: the first button was anchored at y=0, the exact same spot
    -- the topline divider sits at - they were touching directly, not just
    -- close. Real vertical clearance below the divider now, same as every
    -- other column's top element (nameList's "Known Alts:" hint, grid's
    -- title) already has.
    local TAB_PAD = 12
    local TOP_PAD = 10
    -- Real vertical gap between rows - they were stacked with zero space,
    -- each button's bottom edge touching the next one's top edge directly.
    local ROW_GAP = 8
    local buttons = {}
    for i, prof in ipairs(ALL_PROFS) do
        -- The sepline itself is Brand.LINE_THICKNESS wide, sitting flush
        -- against the column's true right edge - without subtracting it
        -- here, the button's right edge landed 2px closer to the sepline
        -- than the left edge sits from the column's own edge (12px left
        -- vs. 10px right to the line), reading as lopsided.
        local btn = Brand.MakeButton(list, prof, PROF_COL_W - 2*TAB_PAD - Brand.LINE_THICKNESS, PROF_ROW_H, function() O.SelectProf(prof) end)
        btn:SetPoint("TOPLEFT", list, "TOPLEFT", TAB_PAD, -TOP_PAD - (i-1)*(PROF_ROW_H + ROW_GAP))
        btn.label:ClearAllPoints()
        btn.label:SetPoint("LEFT", btn, "LEFT", 10, 0)
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

        buttons[prof] = btn
    end

    function list:Restyle()
        for prof, btn in pairs(buttons) do
            btn:SetSelected(O.activeProf == prof)
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
-- Known Alts made wider, Your Crafters (GRID_W, derived from what's left)
-- correspondingly narrower.
local NAME_COL_W = 230
local NAME_ROW_H = 22

local function BuildNameList(canvas, bodyTop)
    local col = CreateFrame("Frame", nil, canvas)
    col:SetPoint("TOPLEFT",    canvas, "TOPLEFT",    PROF_COL_W + Brand.SAFE_MARGIN, -bodyTop)
    col:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", PROF_COL_W + Brand.SAFE_MARGIN,  Brand.SAFE_MARGIN)
    col:SetWidth(NAME_COL_W)

    local bg = col:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.045, 0.036, 0.018, 1)

    -- Top-edge line — part of the divider under the tab row (see the
    -- note in BuildProfessionList for why it's drawn per-column).
    local topline = col:CreateTexture(nil, "ARTWORK")
    topline:SetPoint("TOPLEFT"); topline:SetPoint("TOPRIGHT"); topline:SetHeight(Brand.LINE_THICKNESS)
    topline:SetColorTexture(C_ACCENT[1]*0.5, C_ACCENT[2]*0.5, C_ACCENT[3]*0.5, 1)

    local sepline = col:CreateTexture(nil, "ARTWORK")
    sepline:SetPoint("TOPRIGHT"); sepline:SetPoint("BOTTOMRIGHT")
    sepline:SetWidth(Brand.LINE_THICKNESS)
    sepline:SetColorTexture(C_ACCENT[1]*0.4, C_ACCENT[2]*0.4, C_ACCENT[3]*0.4, 1)

    -- Built directly (not via the shared Lbl() helper, which is hardcoded
    -- to ARIALN) so this matches the grid title's font/weight/color exactly -
    -- same FRIZQT__.TTF + OUTLINE + accent color as "Alchemy — Your Crafters".
    local hint = col:CreateFontString(nil, "OVERLAY")
    hint:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    hint:SetTextColor(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 1)
    hint:SetPoint("TOPLEFT", col, "TOPLEFT", 6, -10)
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

    -- -20 wasn't enough clearance between the scrollbar itself and the
    -- sepline divider at col's right edge - the scrollbar was rendering
    -- right on top of it. -32 gives it real room.
    local sf = CreateFrame("ScrollFrame", nil, col, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     addBtn, "BOTTOMLEFT", 0, -8)
    sf:SetPoint("BOTTOMRIGHT", col,    "BOTTOMRIGHT", -32, 6)
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
                top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(Brand.LINE_THICKNESS)
                local bottom = btn:CreateTexture(nil, "ARTWORK")
                bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(Brand.LINE_THICKNESS)
                local left   = btn:CreateTexture(nil, "ARTWORK")
                left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(Brand.LINE_THICKNESS)
                local right  = btn:CreateTexture(nil, "ARTWORK")
                right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(Brand.LINE_THICKNESS)
                for _, line in ipairs({ top, bottom, left, right }) do
                    line:SetColorTexture(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 1)
                end
            end
            local lbl = btn:CreateFontString(nil, "OVERLAY")
            lbl:SetFont("Fonts\\ARIALN.TTF", PANEL_LABEL_FONT_SIZE, "")
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
            local empty = Lbl(content, emptyText, PANEL_DESC_FONT_SIZE, 0.45, 0.45, 0.45)
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
    wrap:SetPoint("TOPLEFT",     canvas, "TOPLEFT",     PROF_COL_W + NAME_COL_W + Brand.SAFE_MARGIN, -bodyTop)
    wrap:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -Brand.SAFE_MARGIN,                            Brand.SAFE_MARGIN)

    -- Top-edge line — part of the divider under the tab row (see the
    -- note in BuildProfessionList for why it's drawn per-column).
    local topline = wrap:CreateTexture(nil, "ARTWORK")
    topline:SetPoint("TOPLEFT"); topline:SetPoint("TOPRIGHT"); topline:SetHeight(Brand.LINE_THICKNESS)
    topline:SetColorTexture(C_ACCENT[1]*0.5, C_ACCENT[2]*0.5, C_ACCENT[3]*0.5, 1)

    local title = wrap:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    title:SetPoint("TOPLEFT", wrap, "TOPLEFT", 10, -10)
    wrap.title = title

    local sf = CreateFrame("ScrollFrame", nil, wrap, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     wrap, "TOPLEFT",     6,  -30)
    sf:SetPoint("BOTTOMRIGHT", wrap, "BOTTOMRIGHT", -26,  6)

    -- Fixed to what the content actually needs (GRID_CONTENT_W), not
    -- derived from whatever's left of the canvas - CANVAS_W itself is now
    -- computed FROM this constant instead of the other way around.
    local GRID_W = GRID_CONTENT_W
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
                PANEL_DESC_FONT_SIZE, 0.45, 0.35, 0.20)
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
-- SETTINGS PAGE — a real second page (not a popup), toggled via the
-- header's Settings button. Built to the confirmed settings-panel
-- typography standard from the start: 13px description text, 14px
-- labels/slider endpoints, no hardcoded description width (two-point
-- anchor instead), -16 slider-to-description gap, -30 between blocks.
-- ══════════════════════════════════════════════════════════════
-- A standalone floating popup (own window, own border, own close button) -
-- NOT a swapped-in alternate view of the crafter-config window. Settings
-- opening as a sibling panel next to Options, instead of replacing the
-- crafter "character sheet" content in place, is the whole point: you're
-- never staring at a panel that says "Settings" while a "Settings" button
-- is also still sitting right there doing nothing.
local function BuildSettingsWindow(canvas)
    local page = CreateFrame("Frame", "XC_SettingsWindow", UIParent)
    -- Wider (less text wrapping) and tall enough for the worst-case wrap of
    -- both descriptions with real margin left over at the bottom - the
    -- content now grows with the actual (chained) anchors instead of a
    -- fixed height assumption.
    -- +50 to fit the minimap-button checkbox row added below the sliders.
    page:SetSize(440, 430)
    page:SetFrameStrata("DIALOG")
    page:SetMovable(true)
    page:EnableMouse(true)
    page:RegisterForDrag("LeftButton")
    page:SetScript("OnDragStart", page.StartMoving)
    page:SetScript("OnDragStop",  page.StopMovingOrSizing)
    page:SetClampedToScreen(true)
    page:Hide()

    Brand.RegisterScalable(page)
    Brand.ApplyBackground(page)
    Brand.DrawBorder(page)

    local title = Brand.Title(page, "Settings", 18, "TOP", page, "TOP", 0, -16)

    -- Branded flat "X" button, matching the main Options window and
    -- Routes' proven standalone settings window - not Blizzard's default
    -- red-X template.
    local closeBtn = Brand.MakeButton(page, "X", 24, 24, function() page:Hide() end)
    closeBtn:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Brand.SAFE_MARGIN, -Brand.SAFE_MARGIN)

    -- Shared slider builder: label + live current-value readout on one
    -- row, native slider below with real clearance above/below it, then
    -- the description - generous gaps throughout instead of stacking
    -- everything edge-to-edge. Two-point anchors (never a hardcoded
    -- SetWidth) on the text so it can't clip. Low/High endpoint text
    -- bumped to the label-tier size.
    --
    -- Each block anchors to the PREVIOUS block's actual bottom edge
    -- (anchorTo, chained via the returned descFS) instead of a fixed pixel
    -- Y - a fixed Y assumes a one-line description, and when the wrapped
    -- text actually took two lines the next block's label landed on top
    -- of it. Same pattern Routes' SettingsPanel.lua uses (CreateHeader
    -- anchoring to the previous element's BOTTOMLEFT).
    local BLOCK_GAP = 26  -- extra gap below a description before the next block's label

    local function MakeSlider(anchorTo, label, minVal, maxVal, step, current, fmt, desc, onChange)
        local lbl = Lbl(page, label, PANEL_LABEL_FONT_SIZE, 0.85, 0.75, 0.55, "OUTLINE")
        if anchorTo then
            lbl:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -BLOCK_GAP)
        else
            lbl:SetPoint("TOPLEFT", page, "TOPLEFT", Brand.SAFE_MARGIN, -54)
        end

        -- Live value readout - always shows the CURRENT setting, not just
        -- the slider's min/max endpoints. Same vertical row as the label.
        local valueFS = Lbl(page, fmt(current), PANEL_LABEL_FONT_SIZE, 1, 1, 1, "OUTLINE")
        valueFS:SetPoint("TOP", lbl, "TOP", 0, 0)
        valueFS:SetPoint("RIGHT", page, "RIGHT", -Brand.SAFE_MARGIN - 4, 0)

        local slider = CreateFrame("Slider", nil, page, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 4, -20)
        slider:SetPoint("RIGHT", page, "RIGHT", -Brand.SAFE_MARGIN - 4, 0)
        slider:SetMinMaxValues(minVal, maxVal)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
        slider:SetValue(current)
        slider.Text:SetText("")
        BumpFont(slider.Low,  PANEL_LABEL_FONT_SIZE)
        BumpFont(slider.High, PANEL_LABEL_FONT_SIZE)
        slider.Low:SetText(fmt(minVal))
        slider.High:SetText(fmt(maxVal))

        local descFS = Lbl(page, desc, PANEL_DESC_FONT_SIZE, 0.55, 0.50, 0.40)
        descFS:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -22)
        descFS:SetPoint("RIGHT", page, "RIGHT", -Brand.SAFE_MARGIN, 0)
        descFS:SetJustifyH("LEFT")
        descFS:SetWordWrap(true)

        slider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value / step + 0.5) * step
            valueFS:SetText(fmt(value))
            onChange(value)
        end)

        return descFS
    end

    local desc1 = MakeSlider(nil, "UI Size", 0.8, 1.5, 0.05, XC_DB.settings.uiScale,
        function(v) return string.format("%.2fx", v) end,
        "Resizes this Options panel, the welcome screen, and the mailbox send window. Applies immediately.",
        function(v) Brand.SetUIScale(v) end)

    local desc2 = MakeSlider(desc1, "Font Size", 0.8, 1.5, 0.05, XC_DB.settings.fontScale,
        function(v) return string.format("%.2fx", v) end,
        "Scales the text size across every panel. Takes effect on panels you open after changing this - reopen this window, or /reload, to apply it to what's already open.",
        function(v) Brand.SetFontScale(v) end)

    -- Minimap button toggle - chained off the last slider's description
    -- the same way the sliders chain off each other.
    local minimapCB = MakeCB(page, "Show the minimap button",
        not (XC_DB.minimap and XC_DB.minimap.hide),
        function(checked) XC.MinimapButton:SetShown(checked) end)
    minimapCB:SetPoint("TOPLEFT", desc2, "BOTTOMLEFT", 4, -BLOCK_GAP)
    minimapCB.text:SetPoint("RIGHT", page, "RIGHT", -Brand.SAFE_MARGIN, 0)

    return page
end


-- ══════════════════════════════════════════════════════════════
-- PUBLIC API
-- ══════════════════════════════════════════════════════════════
function O:Register()
    if self.registered then return end
    self.registered = true

    local canvas = CreateFrame("Frame", "XC_OptionsCanvas", UIParent)
    canvas:SetSize(CANVAS_W, CANVAS_H)
    canvas:SetPoint("CENTER")
    canvas:SetFrameStrata("DIALOG")
    canvas:SetMovable(true)
    canvas:EnableMouse(true)
    canvas:RegisterForDrag("LeftButton")
    canvas:SetScript("OnDragStart", canvas.StartMoving)
    canvas:SetScript("OnDragStop",  canvas.StopMovingOrSizing)
    canvas:SetClampedToScreen(true)
    canvas:Hide()
    self.canvasFrame = canvas

    -- A standalone floating window we fully control, same as Splash and
    -- the Mailbox send preview - not embedded in Blizzard's own Settings
    -- window, so the UI Size slider scales it cleanly with no clipping.
    Brand.RegisterScalable(canvas)

    Brand.ApplyBackground(canvas)
    Brand.DrawBorder(canvas)

    -- ── Header ─────────────────────────────────────────────────
    -- Matches Routes' proven standalone settings window (SettingsPanel.lua
    -- BuildStandaloneWindow, confirmed 2026-08-09) point-for-point: no
    -- separate header background bar (that's what caused content to
    -- render outside the border earlier) - just a big centered title,
    -- a branded "X" close button, and one clean divider below both.
    -- CENTER, not TOP - centers the title's own vertical midpoint between
    -- the border's visible top line (6px in, DrawBorder's default inset)
    -- and the header divider below (y=66): (6+66)/2 = 36.
    local hdrTitle = Brand.Title(canvas, "Xal's Craft Courier", 30, "CENTER", canvas, "TOP", 0, -36)

    -- Branded flat "X" button, NOT Blizzard's default red-X template -
    -- same reasoning Routes documents: the native template clashes with
    -- the rest of the panel's look.
    local closeBtn = Brand.MakeButton(canvas, "X", 24, 24, function() canvas:Hide() end)
    closeBtn:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -Brand.SAFE_MARGIN, -Brand.SAFE_MARGIN)

    -- Settings button — opens the Settings window as its own separate
    -- floating popup (built below) - it does NOT replace this panel's
    -- content, so the button never has to lie about what it does with a
    -- "< Back" swap. Same row as the close button, same SAFE_MARGIN inset.
    local settingsBtn = Brand.MakeButton(canvas, "Settings", 90, 24, nil)
    settingsBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)

    -- Guild indicator — left side of the header. Mirrors closeBtn's own
    -- anchor exactly (TOPLEFT/TOPRIGHT, both offsets = SAFE_MARGIN) - one
    -- uniform buffer rule applied to both header corners, not a separate
    -- one-off number for this element. GetGuildInfo can return nil if the
    -- guild roster hasn't synced from the server yet at the moment this
    -- panel is first built, so this needs to be able to refresh later,
    -- not just once.
    -- Bare text at the same numeric offset as a bordered button reads
    -- tighter than the button does - the button's own border/backdrop
    -- already eats into that space, but text has zero built-in padding.
    -- +10 beyond SAFE_MARGIN wasn't enough on its own - the text starts
    -- with "<", which has almost no left-side bearing in this font
    -- (unlike a letter), so the anchor point reads even closer to the
    -- edge than the same offset would for ordinary text. +18 total.
    local guildLbl = canvas:CreateFontString(nil, "OVERLAY")
    guildLbl:SetFont("Fonts\\ARIALN.TTF", PANEL_DESC_FONT_SIZE, "")
    guildLbl:SetPoint("TOPLEFT", canvas, "TOPLEFT", Brand.SAFE_MARGIN + 18, -Brand.SAFE_MARGIN)
    self.guildLbl = guildLbl
    self:RefreshGuildLabel()

    -- Header divider — same helper, same proportions as the standalone
    -- Routes reference (SAFE_MARGIN in from each side, y=66 below the top).
    Brand.DrawDivider(canvas, Brand.SAFE_MARGIN, 66, CANVAS_W - 2*Brand.SAFE_MARGIN)

    -- ── Body: mode tabs, then three columns — professions, names, grid ──
    local modeTabs = BuildModeTabs(canvas)
    self.modeTabs  = modeTabs
    -- The three columns start BELOW the tab row, not at the same height as
    -- it - BODY_TOP is where the tabs themselves start. +8 lifts the
    -- divider line (each column's own topline) off the tab row's bottom
    -- edge instead of touching it directly.
    local bodyTop  = BODY_TOP + MODE_TAB_H + 8

    -- NOTE: the divider under the tab row is drawn as each column's OWN
    -- top-edge line (inside BuildProfessionList/BuildNameList/
    -- BuildCraftersGrid), not as one texture here on canvas directly.
    -- Those three columns are separate child frames that sit ON TOP of
    -- canvas's own artwork at that exact seam, so a single line drawn
    -- here would be hidden everywhere except the tiny gaps between them.

    local profList = BuildProfessionList(canvas, bodyTop)
    local nameList = BuildNameList(canvas, bodyTop)
    local grid     = BuildCraftersGrid(canvas, bodyTop)

    local settingsWindow = BuildSettingsWindow(canvas)
    self.settingsWindow  = settingsWindow
    settingsWindow:SetPoint("TOPLEFT", canvas, "TOPRIGHT", 14, 0)
    settingsBtn:SetScript("OnClick", function()
        if settingsWindow:IsShown() then settingsWindow:Hide() else settingsWindow:Show() end
    end)

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

    -- Every time the panel is actually opened, refresh everything to
    -- current reality: guild label, which guild tabs exist, and the
    -- currently-selected view.
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
        if O.settingsWindow then O.settingsWindow:Hide() end
        O.expansionPopupCfg = nil
    end)
end

function O:Open()
    if not self.registered then self:Register() end
    self.canvasFrame:Show()
end
