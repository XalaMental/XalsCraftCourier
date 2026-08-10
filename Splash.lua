-- ============================================================
-- Splash.lua  —  Xal's Craft Courier
-- Handles: welcome splash screen + crafter setup panel
--
-- FLOW:
--   1. XC.Splash:Open()      → shows the welcome splash
--   2. Player clicks "Begin Setup"
--   3. XC.Splash:GoToSetup() → swaps content to setup panel
--   4. Player fills in crafters, clicks "Done" → frame hides,
--      XC_CharDB.seenSplash = true (never auto-shows again)
-- ============================================================

XC = XC or {}
XC.Splash = {}
local S = XC.Splash
local Brand = XC.BrandStyle

-- ── Frame dimensions ──────────────────────────────────────────
local FW = 580   -- frame width  (pixels)
local FH = 420   -- frame height (pixels)

-- ── Colours (r, g, b) ─────────────────────────────────────────
-- Aliased to the shared brand module - these ARE where the brand's
-- accent/gold colors originally came from, so the values are unchanged,
-- just sourced from one shared place now instead of redefined per file.
local ACCENT = Brand.ACCENT
local GOLD   = Brand.GOLD


-- ==============================================================
-- UTILITY HELPERS  (shared brand module - same T()/FS() signatures
-- this file always used, just no longer redefined locally)
-- ==============================================================
local T  = Brand.T
local FS = Brand.FS


-- ==============================================================
-- BUTTON FACTORY
-- Xal's shared flat button style (Brand.MakeButton) - replaces the old
-- beveled "steel" look, which read visually inconsistent once several
-- buttons sat in a row. `primary` now maps to SetSelected(true): a
-- brighter fill + white label for the emphasized action in a pair,
-- same visual role the old primary=true used to carry.
-- ==============================================================
local function MakeButton(parent, text, w, h, primary)
    local btn = Brand.MakeButton(parent, text, w, h, nil)
    if primary then btn:SetSelected(true) end
    return btn
end


-- ==============================================================
-- SPLASH PANEL  (the welcome screen content)
-- ==============================================================
local function BuildSplashPanel(f)
    local panel = CreateFrame("Frame", nil, f)
    panel:SetAllPoints(f)

    local CX = FW / 2   -- pixel centre of the frame

    -- Title — MORPHEUS.TTF, WoW's own ornate built-in font (used for mail
    -- text and quest log headers), instead of the same FRIZQT sans-serif
    -- used everywhere else in the addon. Brand.Title handles the
    -- drop-shadow layer behind it.
    local title = Brand.Title(panel, "Xal's Craft Courier", 34, "TOP", panel, "TOP", 0, -38)

    -- Tagline
    local tag = FS(panel, "PERSONAL  &  GUILD  CRAFTING  LOGISTICS  PLATFORM",
        "Fonts\\ARIALN.TTF", Brand.DESC_FONT_SIZE, "",
        GOLD[1]-0.12, GOLD[2]-0.13, GOLD[3]-0.11)
    tag:SetPoint("TOP", title, "BOTTOM", 0, -12)
    tag:SetJustifyH("CENTER")

    -- Divider line — well clear of the tagline's own text height, so it
    -- can never render as a strikethrough through it again.
    Brand.DrawDivider(panel, 80, 140, FW-160)

    -- Feature bullet list
    local features = {
        "Assign a dedicated crafter for every profession",
        "One-click mailing of materials at any mailbox",
        "Filter system — send only the mats each crafter needs",
        "Full guild crafter support across your roster",
    }
    for i, line in ipairs(features) do
        local y = 156 + (i-1) * 28
        -- Small diamond bullet
        T(panel, CX-188, y+6, 5, 5, ACCENT[1]*0.7, ACCENT[2]*0.7, ACCENT[3]*0.7)
        -- Feature text
        local ft = FS(panel, line, "Fonts\\ARIALN.TTF", 13, "",
            GOLD[1], GOLD[2], GOLD[3])
        ft:SetPoint("TOPLEFT", panel, "TOPLEFT", CX-177, -y)
    end

    -- Second divider
    Brand.DrawDivider(panel, 80, 278, FW-160)

    -- Buttons (centred as a pair)
    local btnSetup = MakeButton(panel, "BEGIN SETUP",  140, 40, true)
    local btnSkip  = MakeButton(panel, "SKIP FOR NOW", 140, 40, false)

    btnSetup:SetPoint("CENTER", panel, "TOP", -80, -314)
    btnSkip:SetPoint( "CENTER", panel, "TOP",  80, -314)

    -- Footer
    local foot = FS(panel,
        "v" .. XC.VERSION .. "  ·  by Xal  ·  A Xal's Creation",
        "Fonts\\ARIALN.TTF", Brand.DESC_FONT_SIZE, "",
        0.55, 0.47, 0.30)
    foot:SetPoint("BOTTOM", panel, "BOTTOM", 0, 20)
    foot:SetJustifyH("CENTER")

    -- ── Button actions ────────────────────────────────────────
    btnSetup:SetScript("OnClick", function()
        XC.Splash:GoToSetup()
    end)

    btnSkip:SetScript("OnClick", function()
        XC_CharDB.seenSplash = true   -- never auto-show again for this char
        XC.Splash.frame:Hide()
    end)

    return panel
end


-- ==============================================================
-- SETUP PANEL  (crafter assignment screen)
-- Replaces the splash welcome content when "Begin Setup" is clicked.
--
-- Features:
--   ← Back button          returns to the welcome splash
--   Progress counter        X / 13 configured (live updating)
--   Themed rows             gold labels, green dot for configured, dim for empty
--   Current character       marked "(you)" in the alt dropdown
--   Me button               one-click to fill current character name
--   Clear All               two-step confirmation to wipe everything
--   Open Full Options       shortcut to /xcc options for filter setup
--   Done                    saves seenSplash, closes frame
-- ==============================================================
local function BuildSetupPanel(f)
    local panel = CreateFrame("Frame", nil, f)
    panel:SetAllPoints(f)
    panel:Hide()

    -- Keep references to all edit boxes so Clear All can wipe them
    local allBoxes = {}

    -- ── HEADER BAR ────────────────────────────────────────────
    -- No filled backdrop — the bottom divider line alone separates it
    -- from the profession rows, matching the clean-line look everywhere else.
    local hdrBg = panel:CreateTexture(nil, "BACKGROUND")
    hdrBg:SetPoint("TOPLEFT",  panel, "TOPLEFT",  20, -18)
    hdrBg:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -20, -18)
    hdrBg:SetHeight(32)
    hdrBg:SetColorTexture(0, 0, 0, 0)

    local hdrLine = panel:CreateTexture(nil, "ARTWORK")
    hdrLine:SetPoint("BOTTOMLEFT",  hdrBg, "BOTTOMLEFT",  0, 0)
    hdrLine:SetPoint("BOTTOMRIGHT", hdrBg, "BOTTOMRIGHT", 0, 0)
    hdrLine:SetHeight(Brand.LINE_THICKNESS)
    hdrLine:SetColorTexture(ACCENT[1]*0.5, ACCENT[2]*0.5, ACCENT[3]*0.5, 1)

    -- ← Back button (top-left of header)
    local btnBack = MakeButton(panel, "← Back", 76, 24, false)
    btnBack:SetPoint("LEFT", hdrBg, "LEFT", 6, 0)
    btnBack:SetScript("OnClick", function()
        XC.Splash:Open()
    end)

    -- Title (centred in header) — same branded Morpheus treatment
    -- (with drop-shadow) as the splash screen and every other panel.
    local title = Brand.Title(panel, "Crafter Setup", 20, "CENTER", hdrBg, "CENTER", 0, 0)

    -- Progress counter (top-right of header, updates on every save)
    local progressLbl = panel:CreateFontString(nil, "OVERLAY")
    progressLbl:SetFont("Fonts\\ARIALN.TTF", Brand.DESC_FONT_SIZE, "")
    progressLbl:SetPoint("RIGHT", hdrBg, "RIGHT", -8, 0)
    progressLbl:SetJustifyH("RIGHT")

    -- Quick Setup only ever writes XC_DB.crafters[prof] (a plain name),
    -- but the actual mail router (Mailbox.lua AssignItem) reads from
    -- XC_DB.profConfig[prof].crafters — a list of full crafter configs
    -- with per-expansion/item-type filters, same structure the Options
    -- panel uses. Without this, a crafter "set" here would show as
    -- configured but never actually receive any mail. isQuickSetup marks
    -- the entry this function owns, so it never touches crafters added
    -- manually through the Options panel for the same profession.
    local function SyncQuickCrafter(prof, name)
        XC_DB.profConfig[prof] = XC_DB.profConfig[prof] or { crafters = {}, guildCraftersByGuild = {} }
        local crafters = XC_DB.profConfig[prof].crafters
        local idx
        for i, cfg in ipairs(crafters) do
            if cfg.isQuickSetup then idx = i; break end
        end
        if name and name ~= "" then
            if idx then
                crafters[idx].name    = name
                crafters[idx].enabled = true
            else
                local cfg = XC.DATA:DefaultCrafterConfig(prof)
                cfg.name         = name
                cfg.isQuickSetup = true
                table.insert(crafters, cfg)
            end
        elseif idx then
            table.remove(crafters, idx)
        end
    end

    local function RefreshProgress()
        local count = 0
        for _, prof in ipairs(XC.PROFESSIONS) do
            if XC_DB.crafters[prof] and XC_DB.crafters[prof] ~= "" then
                count = count + 1
            end
        end
        local total = #XC.PROFESSIONS
        local col   = (count == total) and "|cff22cc55" or "|cffcc9922"
        progressLbl:SetText(col .. count .. " / " .. total .. "|r configured")
    end

    -- Subtitle / hint strip
    local sub = FS(panel,
        "Quick setup: assign one crafter per profession.  For filters & guild crafters: /xcc options",
        "Fonts\\ARIALN.TTF", Brand.DESC_FONT_SIZE, "",
        GOLD[1]-0.18, GOLD[2]-0.18, GOLD[3]-0.16)
    sub:SetPoint("TOP", hdrBg, "BOTTOM", 0, -5)
    sub:SetJustifyH("CENTER")

    -- ── SCROLL FRAME ─────────────────────────────────────────
    local ROW_H_CONTENT = 36   -- height of each profession row

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     panel, "TOPLEFT",     20, -68)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -38, 56)

    local contentW = FW - 62
    local content  = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(contentW, #XC.PROFESSIONS * ROW_H_CONTENT + 4)
    scrollFrame:SetScrollChild(content)

    -- ── SHARED DROPDOWN ───────────────────────────────────────
    local dropdown = CreateFrame("Frame", "XC_SetupAltDD", UIParent)
    dropdown:SetFrameStrata("TOOLTIP")
    dropdown:SetSize(240, 10)
    dropdown:Hide()
    dropdown.rows = {}; dropdown.activeBox = nil

    local ddBg = dropdown:CreateTexture(nil, "BACKGROUND")
    ddBg:SetAllPoints(); ddBg:SetColorTexture(0.07, 0.07, 0.07, 0.97)
    -- Thin outline only - a single texture sized to the whole frame here
    -- would sit on top of the BACKGROUND layer and paint over it entirely.
    local ddBTop    = dropdown:CreateTexture(nil, "BORDER")
    ddBTop:SetPoint("TOPLEFT"); ddBTop:SetPoint("TOPRIGHT"); ddBTop:SetHeight(Brand.LINE_THICKNESS)
    local ddBBottom = dropdown:CreateTexture(nil, "BORDER")
    ddBBottom:SetPoint("BOTTOMLEFT"); ddBBottom:SetPoint("BOTTOMRIGHT"); ddBBottom:SetHeight(Brand.LINE_THICKNESS)
    local ddBLeft   = dropdown:CreateTexture(nil, "BORDER")
    ddBLeft:SetPoint("TOPLEFT"); ddBLeft:SetPoint("BOTTOMLEFT"); ddBLeft:SetWidth(Brand.LINE_THICKNESS)
    local ddBRight  = dropdown:CreateTexture(nil, "BORDER")
    ddBRight:SetPoint("TOPRIGHT"); ddBRight:SetPoint("BOTTOMRIGHT"); ddBRight:SetWidth(Brand.LINE_THICKNESS)
    for _, line in ipairs({ ddBTop, ddBBottom, ddBLeft, ddBRight }) do
        line:SetColorTexture(ACCENT[1]*0.5, ACCENT[2]*0.5, ACCENT[3]*0.5, 1)
    end

    local function CloseDropdown() dropdown:Hide() end

    local function OpenDropdown(anchorBtn, targetBox)
        if dropdown:IsShown() and dropdown.activeBox == targetBox then
            CloseDropdown(); return
        end
        dropdown.activeBox = targetBox
        for _, r in ipairs(dropdown.rows) do r:Hide() end
        dropdown.rows = {}

        local chars   = XC_DB.knownChars or {}
        local myRealm = XC_CharDB.realm  or ""
        local myName  = UnitName("player") or ""
        local DRH     = 22

        if #chars == 0 then
            local hint = dropdown:CreateFontString(nil, "OVERLAY")
            hint:SetFont("Fonts\\ARIALN.TTF", Brand.DESC_FONT_SIZE, "")
            hint:SetTextColor(0.45, 0.45, 0.45, 1)
            hint:SetText("  (Log in on each alt to register them)")
            hint:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 4, -6)
            hint:SetWidth(232); dropdown:SetHeight(28)
            table.insert(dropdown.rows, hint)
        else
            for idx, fullName in ipairs(chars) do
                local charName = fullName:match("^([^%-]+)") or fullName
                local isMe     = (charName == myName)
                local row      = CreateFrame("Button", nil, dropdown)
                row:SetSize(240, DRH)
                row:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 0, -(idx-1)*DRH)
                -- Row bg: green tint for current char, dark for others.
                -- Avoid HIGHLIGHT layer — it renders permanently on some WoW builds.
                local rowBg = row:CreateTexture(nil, "BACKGROUND"); rowBg:SetAllPoints()
                local bgR = isMe and 0.06 or 0.04
                local bgG = isMe and 0.16 or 0.04
                local bgB = isMe and 0.06 or 0.04
                local bgA = isMe and 0.55 or 0.25
                rowBg:SetColorTexture(bgR, bgG, bgB, bgA)
                row:SetScript("OnEnter", function()
                    rowBg:SetColorTexture(0.24, 0.17, 0.07, 0.92)
                end)
                row:SetScript("OnLeave", function()
                    rowBg:SetColorTexture(bgR, bgG, bgB, bgA)
                end)
                local rl = row:CreateFontString(nil, "OVERLAY")
                rl:SetFont("Fonts\\ARIALN.TTF", Brand.BUTTON_LABEL_SIZE, "")
                rl:SetPoint("LEFT", row, "LEFT", 6, 0)
                if isMe then
                    rl:SetTextColor(0.30, 0.85, 0.35, 1)
                    rl:SetText(fullName .. "  |cff888888(you)|r")
                else
                    rl:SetTextColor(0.85, 0.75, 0.55, 1)
                    rl:SetText(fullName)
                end
                row:SetScript("OnClick", function()
                    local n, realm = fullName:match("^(.+)-(.+)$")
                    local val = (realm == myRealm) and (n or fullName) or fullName
                    targetBox:SetText(val)
                    XC_DB.crafters[targetBox.profession] = val
                    print(XC.TAG .. " |cffcc6600" .. targetBox.profession .. "|r → |cff88aaff" .. val .. "|r")
                    RefreshProgress()
                    CloseDropdown()
                end)
                table.insert(dropdown.rows, row)
            end
            dropdown:SetHeight(#chars * DRH + 2)
        end
        dropdown:ClearAllPoints()
        dropdown:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
        dropdown:Show()
    end

    -- ── PROFESSION ROWS ───────────────────────────────────────
    -- Each profession gets its own row frame so all child elements
    -- anchor cleanly to it — no complex Y math.
    local myName = UnitName("player") or ""

    for i, prof in ipairs(XC.PROFESSIONS) do
        -- Row frame — sits directly on the content frame
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(contentW, ROW_H_CONTENT)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i-1) * ROW_H_CONTENT)

        -- Thin separator line at bottom of each row
        local sep = row:CreateTexture(nil, "BACKGROUND")
        sep:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
        sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        sep:SetHeight(Brand.LINE_THICKNESS)
        sep:SetColorTexture(0.16, 0.12, 0.05, 0.8)

        -- Configured indicator dot — anchored LEFT-CENTRE of the row
        local dot = row:CreateTexture(nil, "OVERLAY")
        dot:SetSize(7, 7)
        dot:SetPoint("LEFT", row, "LEFT", 6, 0)

        -- Profession label — vertically centred in row
        local lbl = row:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts\\ARIALN.TTF", Brand.BUTTON_LABEL_SIZE, "")
        lbl:SetTextColor(GOLD[1], GOLD[2]-0.04, GOLD[3]-0.07, 1)
        lbl:SetText(prof)
        lbl:SetPoint("LEFT",  row, "LEFT",  18, 0)
        lbl:SetPoint("RIGHT", row, "LEFT", 140, 0)
        lbl:SetJustifyH("LEFT")

        -- Character name input — vertically centred
        local box = CreateFrame("EditBox",
            "XC_SBox_" .. prof:gsub("%s",""),
            row, "InputBoxTemplate")
        box:SetSize(166, 24)
        box:SetPoint("LEFT", row, "LEFT", 144, 0)
        box:SetAutoFocus(false)
        box:SetMaxLetters(60)
        box:SetText(XC_DB.crafters[prof] or "")
        box.profession = prof
        table.insert(allBoxes, { box = box, dot = dot })

        -- dropdown — anchored left of box's right edge
        local ddBtn = MakeButton(row, "v", 24, 22, false)
        ddBtn:SetPoint("LEFT", box, "RIGHT", 4, 0)
        ddBtn:SetScript("OnClick", function() OpenDropdown(ddBtn, box) end)

        -- Me — fills current character name
        local meBtn = MakeButton(row, "Me", 34, 22, false)
        meBtn:SetPoint("LEFT", ddBtn, "RIGHT", 4, 0)
        meBtn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(meBtn, "ANCHOR_TOP")
            GameTooltip:AddLine("Fill with: " .. myName); GameTooltip:Show()
        end)
        meBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        meBtn:SetScript("OnClick", function()
            box:SetText(myName)
            XC_DB.crafters[prof] = myName
            SyncQuickCrafter(prof, myName)
            print(XC.TAG .. " |cffcc6600" .. prof .. "|r → |cff88aaff" .. myName .. "|r")
            RefreshProgress()
        end)

        -- Set button
        local setBtn = MakeButton(row, "Set", 40, 22, true)
        setBtn:SetPoint("LEFT", meBtn, "RIGHT", 4, 0)

        local function Save()
            local name = box:GetText():match("^%s*(.-)%s*$")
            if name == "" then
                XC_DB.crafters[prof] = nil
                SyncQuickCrafter(prof, nil)
                print(XC.TAG .. " Cleared |cffcc6600" .. prof .. "|r")
            else
                XC_DB.crafters[prof] = name
                SyncQuickCrafter(prof, name)
                print(XC.TAG .. " |cffcc6600" .. prof .. "|r → |cff88aaff" .. name .. "|r")
            end
            RefreshProgress()
            CloseDropdown()
        end
        setBtn:SetScript("OnClick", Save)
        box:SetScript("OnEnterPressed", function(self) Save(); self:ClearFocus() end)
    end

    -- ── REFRESH HELPERS ───────────────────────────────────────
    local function RefreshDots()
        for _, entry in ipairs(allBoxes) do
            local set = XC_DB.crafters[entry.box.profession]
            if set and set ~= "" then
                entry.dot:SetColorTexture(0.10, 0.85, 0.25, 1)    -- green
            else
                entry.dot:SetColorTexture(0.50, 0.12, 0.12, 0.7)  -- dim red
            end
        end
    end

    local function Refresh()
        -- Always reset scroll to top so player sees Alchemy first
        scrollFrame:SetVerticalScroll(0)
        RefreshProgress()
        RefreshDots()
        for _, entry in ipairs(allBoxes) do
            local saved = XC_DB.crafters[entry.box.profession] or ""
            if entry.box:GetText() ~= saved then entry.box:SetText(saved) end
        end
    end

    panel:SetScript("OnShow", function() Refresh() end)

    -- ── BOTTOM BAR ────────────────────────────────────────────
    Brand.DrawDivider(panel, 20, FH-52, FW-40)

    -- Clear All (two-step confirm)
    local clearPending = false
    local btnClear = MakeButton(panel, "Clear All", 90, 28, false)
    btnClear:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 26, 18)
    btnClear:SetScript("OnClick", function()
        if not clearPending then
            clearPending = true
            btnClear.label:SetText("Confirm?")
            C_Timer.After(3.0, function()
                if clearPending then
                    clearPending = false
                    btnClear.label:SetText("Clear All")
                end
            end)
        else
            -- Confirmed — wipe everything
            clearPending = false
            btnClear.label:SetText("Clear All")
            for _, prof in ipairs(XC.PROFESSIONS) do
                XC_DB.crafters[prof] = nil
                SyncQuickCrafter(prof, nil)
            end
            Refresh()
            print(XC.TAG .. " All simple crafters cleared.")
        end
    end)

    -- Open Full Options shortcut
    local btnOptions = MakeButton(panel, "Full Options", 112, 28, false)
    btnOptions:SetPoint("LEFT", btnClear, "RIGHT", 8, 0)
    btnOptions:SetScript("OnClick", function()
        XC.Splash.frame:Hide()
        XC_CharDB.seenSplash = true
        XC.Options:Open()
    end)
    btnOptions:SetScript("OnEnter", function()
        GameTooltip:SetOwner(btnOptions, "ANCHOR_TOP")
        GameTooltip:AddLine("Open the full options panel")
        GameTooltip:AddLine("Set expansion filters, guild crafters,", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("multiple crafters per profession, and more.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btnOptions:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Done
    local btnDone = MakeButton(panel, "DONE", 110, 28, true)
    btnDone:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 18)
    btnDone:SetScript("OnClick", function()
        XC_CharDB.seenSplash = true
        XC.Splash.frame:Hide()
        print(XC.TAG .. " Setup saved!  Use |cffaaaaaa/xcc options|r for advanced filters.")
    end)

    return panel
end


-- ==============================================================
-- PUBLIC API
-- ==============================================================

-- Builds the frame on first call, reuses it afterwards
function S:Create()
    if self.frame then return end

    -- Root frame
    local f = CreateFrame("Frame", "XCSplashFrame", UIParent)
    f:SetSize(FW, FH)
    f:SetPoint("CENTER")
    -- DIALOG (same as the mailbox send panel) so nothing else — nameplates
    -- included — can render on top of a first-run welcome screen.
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    -- A standalone floating window we fully control - scales cleanly,
    -- unlike Options' canvas which is embedded in Blizzard's own frame.
    Brand.RegisterScalable(f)

    -- Fully opaque near-black background — no translucency for anything
    -- behind it to show through.
    Brand.ApplyBackground(f)

    -- Draw the border
    Brand.DrawBorder(f)

    -- Build both content panels (only one visible at a time)
    self.splashPanel = BuildSplashPanel(f)
    self.setupPanel  = BuildSetupPanel(f)

    f:Hide()
    self.frame = f
end

-- Show the welcome splash screen
function S:Open()
    self:Create()
    self.splashPanel:Show()
    self.setupPanel:Hide()
    self.frame:Show()
end

-- Transition from splash to setup (called by "Begin Setup" button)
function S:GoToSetup()
    self:Create()
    self.splashPanel:Hide()
    self.setupPanel:Show()
    -- Frame stays visible — only the contents swap
end
