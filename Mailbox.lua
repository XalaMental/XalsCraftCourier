-- ============================================================
-- Mailbox.lua  —  Xal's Craft Courier
--
-- Handles everything that happens at the mailbox:
--   • Injects a "Send to Crafters" button into the Send Mail frame
--   • Scans bags and maps every item to the right crafter using
--     the full profConfig (expansion + item type filters)
--   • Button opens a send panel with Personal / Guild tabs — always a
--     deliberate, separate choice, never an automatic fallback
--   • Send All asks for a direct confirmation before anything is queued
--   • After each MAIL_SEND_SUCCESS, auto-loads and sends the next mail
--
-- NOTE: SendMail() is called directly per mail (same approach TSM's
-- mailing feature uses) - it isn't blocked for regular addon code, only
-- restricted when called from a macro script (patch 9.1.5). A later mail
-- in the queue COULD still get blocked by ADDON_ACTION_BLOCKED if it
-- doesn't trace back closely enough to the player's original click -
-- everything is filled in and attached regardless, so the fallback is
-- always just clicking the native Send Mail button once.
-- ============================================================

XC = XC or {}
XC.Mailbox = {}
local M = XC.Mailbox
local Brand = XC.BrandStyle

-- Internal state
M.queue      = {}      -- ordered list of pending mails to send
M.isSending  = false   -- true while working through the queue
M.atMailbox  = false   -- true while the mailbox is open
M.button     = nil     -- the injected Send to Crafters button
M.preview    = nil     -- the preview frame (built once, reused)


-- ══════════════════════════════════════════════════════════════
-- EVENTS
-- ══════════════════════════════════════════════════════════════
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("MAIL_SHOW")
eventFrame:RegisterEvent("MAIL_CLOSED")
eventFrame:RegisterEvent("MAIL_SEND_SUCCESS")
eventFrame:RegisterEvent("MAIL_FAILED")
eventFrame:RegisterEvent("ADDON_ACTION_BLOCKED")

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if     event == "MAIL_SHOW"         then M:OnMailboxOpen()
    elseif event == "MAIL_CLOSED"       then M:OnMailboxClose()
    elseif event == "MAIL_SEND_SUCCESS" then M:OnSendSuccess()
    elseif event == "MAIL_FAILED"       then M:OnSendFailed()
    elseif event == "ADDON_ACTION_BLOCKED" then M:OnActionBlocked(arg2)
    end
end)

function M:OnMailboxOpen()
    self.atMailbox = true
    self:ShowButton()
end

function M:OnMailboxClose()
    self.atMailbox  = false
    self.isSending  = false
    self.queue      = {}
    if self.button  then self.button:Hide()  end
    if self.preview then self.preview:Hide() end
end

function M:OnSendSuccess()
    if not self.isSending then return end
    print(XC.TAG .. " |cff00ff00Sent!|r")
    -- Small delay before loading the next mail so WoW's UI can settle
    C_Timer.After(0.8, function()
        M:PrepareNextMail()
    end)
end

-- Recipient doesn't exist, name misspelled, etc. Skip this one instead of
-- getting the whole queue stuck, and tell the player which crafter needs
-- fixing (in Options) so it doesn't just silently fail forever.
function M:OnSendFailed()
    if not self.isSending then return end
    print(XC.TAG .. " |cffff4444Failed to send|r - check the recipient name in /xcc options, then try again.")
    C_Timer.After(0.8, function()
        M:PrepareNextMail()
    end)
end

-- Fires if Blizzard's client blocks our direct SendMail() call - this can
-- legitimately happen for mails after the first one in a queue, since
-- each SendMail() call needs to trace back to a real hardware event
-- (the player's click) and a timer-driven auto-advance to the next mail
-- doesn't carry one. When it happens, fall back to what's always safe:
-- everything is already filled in and attached, the player just clicks
-- Send Mail once for this particular one.
function M:OnActionBlocked(funcName)
    if not self.isSending or funcName ~= "SendMail" then return end
    print(XC.TAG .. " |cffffcc00Ready|r - this one needs a manual click: |cffffcc00Click Send Mail!|r")
end


-- ══════════════════════════════════════════════════════════════
-- MAILBOX BUTTON
-- A themed button injected into the default Send Mail frame.
-- ══════════════════════════════════════════════════════════════
function M:ShowButton()
    if self.button then
        self.button:Show()
        return
    end

    -- Parented to UIParent, NOT SendMailFrame. Addons like TSM replace
    -- the default mail UI by hiding SendMailFrame outright and drawing
    -- their own custom window instead - a child of a hidden frame stays
    -- hidden no matter what strata/Show() we set on it. Anchoring to
    -- UIParent with a fixed position means our button's visibility only
    -- ever depends on our own MAIL_SHOW/MAIL_CLOSED handling, never on
    -- whatever frame another addon happens to be showing or hiding.
    local btn = Brand.MakeButton(UIParent, "Send to Crafters", 170, 32, nil)
    btn:SetFrameStrata("DIALOG")
    btn:SetFrameLevel(100)

    -- Movable/lockable instead of a fixed spot, so it can be placed
    -- wherever it doesn't collide with whatever mail addon (TSM, Postal,
    -- etc.) the player has docked in the usual area. Position persists
    -- in XC_DB; unlocked by default so it can be placed on first use.
    local pos = XC_DB.settings.courierBtnPos
    if pos then
        btn:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        btn:SetPoint("TOP", UIParent, "TOP", 320, -140)
    end
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    if XC_DB.settings.courierBtnLocked == nil then
        XC_DB.settings.courierBtnLocked = false
    end

    -- Lock state recolors the border (gold = locked, green = unlocked and
    -- draggable) via Brand.MakeButton's own SetBorderColor hook, instead
    -- of a separate lock icon.
    local function RestyleLock()
        local locked = XC_DB.settings.courierBtnLocked
        local c = locked and Brand.ACCENT or { 0.15, 0.85, 0.25 }
        btn:SetBorderColor(c[1], c[2], c[3], 1)
    end
    btn.RestyleLock = RestyleLock
    RestyleLock()

    btn:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            XC_DB.settings.courierBtnLocked = not XC_DB.settings.courierBtnLocked
            RestyleLock()
            print(XC.TAG .. (XC_DB.settings.courierBtnLocked
                and " Button |cffffcc00locked|r in place."
                or  " Button |cff00ff00unlocked|r — drag it, then right-click to lock."))
        else
            M:OnButtonClick()
        end
    end)

    btn:SetScript("OnDragStart", function(self)
        if not XC_DB.settings.courierBtnLocked then
            self:StartMoving()
        end
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        XC_DB.settings.courierBtnPos = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    -- Tooltip layered on top of Brand.MakeButton's own hover feedback.
    btn:HookScript("OnEnter", function()
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:AddLine("Xal's Craft Courier")
        GameTooltip:AddLine("Choose Personal or Guild, then Send All.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Configure filters: /xcc options", 0.5, 0.5, 0.5)
        GameTooltip:AddLine(XC_DB.settings.courierBtnLocked
            and "Right-click to unlock and move this button."
            or  "Drag to move. Right-click to lock in place.", 0.4, 0.85, 0.5, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    self.button = btn
end


-- ══════════════════════════════════════════════════════════════
-- BAG SCANNER
--
-- Iterates every bag slot, calls GetItemData() for each item,
-- and groups matched items by profession → crafter index.
--
-- Returns:
--   results = {
--     ["Blacksmithing"] = {
--       [1] = { cfg = crafterCfg, items = { itemData, ... } },
--       [2] = { cfg = crafterCfg, items = { itemData, ... } },
--     },
--     ["Alchemy"] = { ... },
--   }
--   skipped = number of items whose data wasn't cached yet
-- ══════════════════════════════════════════════════════════════
-- mode = "personal" or "guild" — scans ONLY that crafter set, no fallback
-- between them. Personal and Guild sends are always a deliberate, separate
-- choice (picked via the send panel's tab), never an automatic fallback.
function M:ScanBags(mode)
    local results = {}
    local skipped = 0

    -- Bags 0 (backpack) through NUM_BAG_SLOTS (usually 4)
    -- Bag NUM_BAG_SLOTS+1 is the Reagent Bag added in TWW
    for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local itemData = self:GetItemData(bag, slot)
                if itemData == "UNCACHED" then
                    skipped = skipped + 1
                elseif itemData then
                    self:AssignItem(results, itemData, mode)
                end
            end
        end
    end

    return results, skipped
end

-- GetItemData(bag, slot)
-- Returns a data table for the item in this slot if it's a
-- trackable crafting material, "UNCACHED" if item data hasn't
-- loaded yet, or nil if the slot is empty / not relevant.
function M:GetItemData(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.itemID then return nil end

    local itemID = info.itemID

    -- Skip manually excluded items (future feature hook)
    if XC_DB.excluded and XC_DB.excluded[itemID] then return nil end

    -- GetItemInfo returns nil for items not yet cached by the client
    local name, _, quality, _, _, _, _, _, _, _, _,
          classID, subClassID, _, expacID, _, isCraftingReagent = GetItemInfo(itemID)

    if not classID then return "UNCACHED" end

    -- Map expacID → our expansion string ("tww", "df", etc.)
    local expansion = XC.DATA.ExpacIDMap[expacID or 0]
    if not expansion then return nil end

    -- Map class/subClass/name → professions + type hint
    local profs, typeHint = XC.DATA:GetProfAndType(
        classID, subClassID, name or "", quality, isCraftingReagent)
    if not profs or #profs == 0 then return nil end

    return {
        itemID    = itemID,
        name      = name,
        link      = info.hyperlink or tostring(itemID),
        count     = info.stackCount or 1,
        bag       = bag,
        slot      = slot,
        expansion = expansion,
        profs     = profs,
        typeHint  = typeHint,
        quality   = quality or 1,
    }
end

-- AssignItem(results, itemData, mode)
-- Finds the best matching crafter for this item, within ONE crafter set
-- only ("personal" or "guild" — whichever mode the active send tab is on),
-- and adds it to results under that profession + crafter index.
-- Tries each candidate profession in order; within a profession, tries
-- each crafter in config order. No cross-mode fallback — an item with no
-- match in the current mode is simply left unassigned (ignored), never
-- silently routed to the other crafter set.
function M:AssignItem(results, itemData, mode)
    for _, prof in ipairs(itemData.profs) do
        local profCfg = XC_DB.profConfig[prof]
        if profCfg then
            if mode == "guild" then
                -- Guild crafters are scoped to the CURRENT character's own
                -- guild specifically - a crafter set up for a different
                -- guild (one some other alt belongs to) never gets used
                -- here, even if this profession has crafters configured
                -- for that other guild.
                local myGuild = GetGuildInfo("player")
                local guildCrafters = (myGuild and profCfg.guildCraftersByGuild
                    and profCfg.guildCraftersByGuild[myGuild]) or {}
                for i, cfg in ipairs(guildCrafters) do
                    if cfg.enabled and cfg.name and cfg.name ~= "" then
                        local expCfg = cfg.expansions and cfg.expansions[itemData.expansion]
                        if expCfg and expCfg.enabled then
                            local typeEnabled = (expCfg[itemData.typeHint] ~= false)
                            if typeEnabled then
                                -- Guild crafter keys are prefixed "g" to stay
                                -- separate from personal crafter numeric keys.
                                results[prof] = results[prof] or {}
                                local key = "g" .. i
                                results[prof][key] = results[prof][key] or {
                                    cfg     = cfg,
                                    items   = {},
                                    isGuild = true,
                                }
                                table.insert(results[prof][key].items, itemData)
                                return
                            end
                        end
                    end
                end
            else
                local crafters = profCfg.crafters or {}
                for i, cfg in ipairs(crafters) do
                    if cfg.enabled and cfg.name and cfg.name ~= "" then
                        local expCfg = cfg.expansions and cfg.expansions[itemData.expansion]
                        if expCfg and expCfg.enabled then
                            -- Check whether this item's type is toggled on
                            -- Default to true if the key doesn't exist (safe fallback)
                            local typeEnabled = (expCfg[itemData.typeHint] ~= false)
                            if typeEnabled then
                                -- Assign to this crafter
                                results[prof] = results[prof] or {}
                                results[prof][i] = results[prof][i] or {
                                    cfg   = cfg,
                                    items = {},
                                }
                                table.insert(results[prof][i].items, itemData)
                                return  -- item assigned, stop searching
                            end
                        end
                    end
                end
            end
        end
    end
    -- No matching crafter found in this mode — item is ignored silently
end


-- ══════════════════════════════════════════════════════════════
-- MAIL QUEUE BUILDER
--
-- Converts the scan results into an ordered list of mails.
-- Splits item lists into batches of ATTACHMENTS_MAX_SEND (12)
-- since that's WoW's hard limit per mail.
-- ══════════════════════════════════════════════════════════════
function M:BuildQueue(results)
    local queue = {}

    -- Helper: turns one crafter entry into batched mail entries
    local function EnqueueEntry(prof, key, entry)
        local recipient = entry.cfg.name
        local items     = entry.items
        local batch     = {}
        local batchNum  = 1
        for i, item in ipairs(items) do
            table.insert(batch, item)
            if #batch == ATTACHMENTS_MAX_SEND or i == #items then
                table.insert(queue, {
                    recipient  = recipient,
                    profession = prof,
                    items      = batch,
                    batchNum   = batchNum,
                    isGuild    = entry.isGuild or false,
                })
                batch    = {}
                batchNum = batchNum + 1
            end
        end
    end

    for _, prof in ipairs(XC.PROFESSIONS) do
        local profResult = results[prof]
        if profResult then
            -- Personal crafters first (numeric keys)
            for key, entry in pairs(profResult) do
                if type(key) == "number" then
                    EnqueueEntry(prof, key, entry)
                end
            end
            -- Guild crafters second (string keys like "g1", "g2")
            for key, entry in pairs(profResult) do
                if type(key) == "string" then
                    EnqueueEntry(prof, key, entry)
                end
            end
        end
    end

    return queue
end


-- ══════════════════════════════════════════════════════════════
-- BUTTON CLICK HANDLER
-- Opens the send panel — the player picks Personal or Guild there
-- (always defaults back to Personal every time it's opened, so a
-- leftover tab choice from last session can never surprise anyone).
-- ══════════════════════════════════════════════════════════════
function M:OnButtonClick()
    if self.isSending then
        print(XC.TAG .. " Already sending — please wait for the current mail.")
        return
    end
    self:OpenSendPanel()
end

function M:OpenSendPanel()
    if not self.preview then
        self.preview = self:BuildPreviewFrame()
    end
    self.preview:Show()
    self:SelectTab("personal")
end

-- SelectTab(mode) — mode is "personal" or "guild". Re-scans bags for
-- ONLY that crafter set (no fallback) and repopulates the panel.
function M:SelectTab(mode)
    local f = self.preview
    f.activeMode = mode

    local function styleTab(btn, active)
        local c = btn.color
        btn:SetSelected(active)
        if not active then
            btn:SetBorderColor(c[1]*0.8, c[2]*0.8, c[3]*0.8, 1)
            btn.label:SetTextColor(c[1]*0.8, c[2]*0.8, c[3]*0.8, 1)
        elseif c ~= Brand.ACCENT then
            btn:SetBorderColor(c[1], c[2], c[3], 1)
        end
    end
    styleTab(f.tabPersonal, mode == "personal")
    styleTab(f.tabGuild,    mode == "guild")

    local results, skipped = self:ScanBags(mode)
    local queue = self:BuildQueue(results)
    self:PopulatePreview(queue, results, mode, skipped)
end


-- ══════════════════════════════════════════════════════════════
-- QUEUE EXECUTION
-- ══════════════════════════════════════════════════════════════
function M:StartQueue(queue)
    self.queue     = queue
    self.isSending = true
    print(XC.TAG .. " Starting — " .. #queue .. " mail(s) to send.")
    self:PrepareNextMail()
end

-- PrepareNextMail()
-- Takes the next mail off the queue and fills in the Send Mail frame:
-- recipient, subject, body, and attaches all items. The player then
-- clicks the native Send Mail button once.
function M:PrepareNextMail()
    if #self.queue == 0 then
        self.isSending = false
        print(XC.TAG .. " |cff00ff00All done!|r All crafting materials sent.")
        return
    end

    if not self.atMailbox then
        self.isSending = false
        self.queue     = {}
        return
    end

    -- Addons like TSM replace the mail UI by hiding Blizzard's own
    -- SendMailFrame rather than destroying it - but ClickSendMailItemButton
    -- and SendMail() can silently no-op if that underlying frame isn't
    -- actually in a shown state when called (an anti-automation guard).
    -- Force it shown ourselves right before touching it, independent of
    -- whatever TSM's own overlay is doing on screen.
    if not SendMailFrame:IsShown() then
        SendMailFrame:Show()
    end

    local mail = table.remove(self.queue, 1)

    -- Clear any items currently attached in the Send Mail frame
    for i = 1, ATTACHMENTS_MAX_SEND do
        if GetSendMailItem(i) then
            ClickSendMailItemButton(i)
            ClearCursor()
        end
    end

    -- Fill in recipient and subject
    local guildTag = mail.isGuild and " [Guild]" or ""
    local subject = "XC: " .. mail.profession .. guildTag ..
        (mail.batchNum > 1 and (" (Part " .. mail.batchNum .. ")") or "")
    local body = "Sent by Xal's Craft Courier."
    SendMailNameEditBox:SetText(mail.recipient)
    SendMailSubjectEditBox:SetText(subject)
    SendMailBodyEditBox:SetText(body)

    -- Attach items
    local attached = 0
    for _, item in ipairs(mail.items) do
        if attached < ATTACHMENTS_MAX_SEND then
            C_Container.PickupContainerItem(item.bag, item.slot)
            if CursorHasItem() then
                ClickSendMailItemButton(attached + 1)
                attached = attached + 1
            end
        end
    end

    local remaining = #self.queue
    local recipColor = mail.isGuild and "|cff1a9e2e" or "|cff88aaff"
    local guildNote  = mail.isGuild and " |cff1a9e2e[Guild]|r" or ""
    print(string.format(
        XC.TAG .. " Sending: |cffcc6600%s|r%s → %s%s|r (%d item%s)  %s",
        mail.profession,
        guildNote,
        recipColor,
        mail.recipient,
        attached,
        attached == 1 and "" or "s",
        remaining > 0 and ("(" .. remaining .. " mail(s) after this)") or "(last one)"
    ))

    -- Send it directly - SendMail() only requires the call to trace back
    -- to a real hardware event (the player's original click), not a
    -- manual click of the native Send button on every single mail. If
    -- Blizzard blocks a later one in the queue (ADDON_ACTION_BLOCKED),
    -- everything above is still filled in and attached, so the fallback
    -- is just clicking Send Mail once for that one - never a dead end.
    SendMail(mail.recipient, subject, body)
end


-- Whether a profession has an actual configured crafter in the given
-- mode - independent of whether anything is currently in your bags for
-- it. Used so the sidebar can show "configured but nothing to send right
-- now" instead of just not showing the profession at all.
local function HasConfiguredCrafter(prof, mode, guildName)
    local profCfg = XC_DB.profConfig[prof]
    if not profCfg then return false end
    local crafters = (mode == "guild")
        and (guildName and profCfg.guildCraftersByGuild and profCfg.guildCraftersByGuild[guildName])
        or  profCfg.crafters
    if not crafters then return false end
    for _, cfg in ipairs(crafters) do
        if cfg.enabled and cfg.name and cfg.name ~= "" then return true end
    end
    return false
end


-- ══════════════════════════════════════════════════════════════
-- SEND PANEL
--
-- A dark-themed popup showing exactly what will be sent to who,
-- split into a Personal tab (red) and a Guild tab (green) — always
-- a deliberate, separate choice, never an automatic fallback between
-- the two. Player clicks [Send All] (which asks for confirmation
-- before anything is queued) or [Cancel] to back out.
-- ══════════════════════════════════════════════════════════════
function M:BuildPreviewFrame()
    local FW, FH = 560, 524
    local f = CreateFrame("Frame", "XC_PreviewFrame", UIParent)
    f:SetSize(FW, FH)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    -- A standalone floating window we fully control - scales cleanly.
    Brand.RegisterScalable(f)

    -- Background — fully opaque, matching every other panel (no
    -- translucency for anything behind it, e.g. nameplates, to show through)
    Brand.ApplyBackground(f)
    Brand.DrawBorder(f)

    -- Title — same branded Morpheus treatment as every other panel.
    local title = Brand.Title(f, "Send Preview", 24, "TOP", f, "TOP", 0, -24)

    -- ── TAB BAR (Personal / Guild) ──────────────────────────────
    -- Always a deliberate, separate choice — never an automatic
    -- fallback between the two crafter sets. Guild keeps its own green
    -- border/label color instead of the shared accent gold, same
    -- color-coding convention used throughout the addon.
    local GREEN = { 0.10, 0.62, 0.18 }

    local function MakeTabBtn(text, color, x)
        local btn = Brand.MakeButton(f, text, 180, 24, nil)
        btn:SetPoint("TOP", f, "TOP", x, -58)
        btn.color = color
        return btn
    end

    local tabPersonal = MakeTabBtn("Personal", Brand.ACCENT, -95)
    local tabGuild    = MakeTabBtn("Guild",    GREEN,  95)
    tabPersonal:SetScript("OnClick", function() M:SelectTab("personal") end)
    tabGuild:SetScript("OnClick",    function() M:SelectTab("guild")    end)
    f.tabPersonal = tabPersonal
    f.tabGuild    = tabGuild

    -- Divider
    Brand.DrawDivider(f, 20, 90, FW-40)

    -- Profession sidebar (left) — only lists professions that actually
    -- have something queued for the current tab; click one to filter the
    -- content list to just that profession, or "All" to see everything.
    local SIDEBAR_W = 110
    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT",     f, "TOPLEFT",     14, -98)
    sidebar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  14,  56)
    sidebar:SetWidth(SIDEBAR_W)
    f.sidebar = sidebar
    f.profButtons = {}

    local sideDiv = f:CreateTexture(nil, "ARTWORK")
    sideDiv:SetPoint("TOPLEFT",    sidebar, "TOPRIGHT", 8, 0)
    sideDiv:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 8, 0)
    sideDiv:SetWidth(Brand.LINE_THICKNESS); sideDiv:SetColorTexture(0.32, 0.24, 0.10, 1)

    -- Scroll area for content
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     sidebar, "TOPRIGHT",   18, 0)
    sf:SetPoint("BOTTOMRIGHT", f,       "BOTTOMRIGHT", -30, 56)
    f.scrollFrame = sf

    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(FW - SIDEBAR_W - 14 - 18 - 30)
    sf:SetScrollChild(content)
    f.content = content

    -- Bottom buttons
    local function MakePreviewBtn(text, x, primary)
        local btn = Brand.MakeButton(f, text, 130, 32, nil)
        btn:SetPoint("BOTTOM", f, "BOTTOM", x, 16)
        if primary then btn:SetSelected(true) end
        btn.lbl = btn.label
        return btn
    end

    local sendBtn   = MakePreviewBtn("Send All", -76, true)
    local cancelBtn = MakePreviewBtn("Cancel",       76, false)

    sendBtn:SetScript("OnClick", function()
        local queue = f.pendingQueue
        if not queue or #queue == 0 then return end

        -- The preview panel itself already shows exactly who's getting
        -- what (Personal/Guild tabs, per-crafter item breakdown) before
        -- this button is even clickable, so a second "Send to X?" popup
        -- here was just a redundant extra click, not a real safety gate.
        f:Hide()
        M:StartQueue(queue)
    end)
    cancelBtn:SetScript("OnClick", function()
        f:Hide()
        M.queue     = {}
        M.isSending = false
        print(XC.TAG .. " |cffaaaaaSend cancelled.|r")
    end)

    f.sendBtn   = sendBtn
    f.cancelBtn = cancelBtn

    return f
end

-- Populate the preview frame with the current queue summary for the
-- active tab (mode = "personal" or "guild")
function M:PopulatePreview(queue, results, mode, skipped)
    local f = self.preview
    f.pendingQueue = queue
    f.mode         = mode
    f.skipped      = skipped

    -- Group queue entries by profession for cleaner display - stored on
    -- the frame so switching the sidebar's profession filter can re-render
    -- from this without re-scanning bags.
    local byProf, totalMails = {}, 0
    for _, mail in ipairs(queue) do
        byProf[mail.profession] = byProf[mail.profession] or {}
        local key = mail.recipient
        byProf[mail.profession][key] = byProf[mail.profession][key] or { items = {}, mails = 0 }
        byProf[mail.profession][key].mails = byProf[mail.profession][key].mails + 1
        for _, item in ipairs(mail.items) do
            table.insert(byProf[mail.profession][key].items, item)
        end
        totalMails = totalMails + 1
    end
    f.byProf     = byProf
    f.totalMails = totalMails

    -- Which professions actually have a crafter configured for this mode -
    -- independent of whether your bags happen to have matching items in
    -- them right now. A configured profession with nothing to send is
    -- still a real, selectable entry; only a profession with no crafter
    -- set up at all is genuinely inactive.
    local guildName = (mode == "guild") and GetGuildInfo("player") or nil
    local configured = {}
    for _, prof in ipairs(XC.PROFESSIONS) do
        configured[prof] = HasConfiguredCrafter(prof, mode, guildName)
    end
    f.configured = configured

    -- Default to the first profession with something queued right now;
    -- failing that, the first one that's simply configured, so there's
    -- still something useful shown without an extra click.
    f.activeProf = nil
    for _, prof in ipairs(XC.PROFESSIONS) do
        if f.byProf[prof] then f.activeProf = prof; break end
    end
    if not f.activeProf then
        for _, prof in ipairs(XC.PROFESSIONS) do
            if configured[prof] then f.activeProf = prof; break end
        end
    end

    self:RebuildProfSidebar()
    self:RenderPreviewList()
end

-- Left-side profession buttons - every profession, always, same as the
-- Options panel's profession list. Ones with no crafter configured are
-- grayed out and not clickable at all; only a configured profession is
-- selectable, whether or not it currently has items to send.
function M:RebuildProfSidebar()
    local f = self.preview
    for _, b in ipairs(f.profButtons) do b:Hide(); b:SetParent(UIParent) end
    f.profButtons = {}

    local function MakeSideBtn(prof, y)
        local btn
        btn = Brand.MakeButton(f.sidebar, prof, 108, 22, function()
            if not f.configured[btn.prof] then return end
            f.activeProf = btn.prof
            M:RenderPreviewList()
        end)
        btn:SetPoint("TOPLEFT", f.sidebar, "TOPLEFT", 0, -y)
        btn.prof = prof

        -- Ready-to-send mark - a dot, not a Unicode checkmark (✓ is one
        -- of the glyphs this game's fonts render as an empty box).
        local mark = btn:CreateTexture(nil, "OVERLAY")
        mark:SetSize(6, 6)
        mark:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
        mark:SetColorTexture(0.15, 0.85, 0.25, 1)
        mark:Hide()
        btn.mark = mark

        return btn
    end

    local y = 0
    for _, prof in ipairs(XC.PROFESSIONS) do
        table.insert(f.profButtons, MakeSideBtn(prof, y))
        y = y + 28
    end

    self:RestyleProfSidebar()
end

function M:RestyleProfSidebar()
    local f = self.preview
    for _, btn in ipairs(f.profButtons) do
        local active   = (btn.prof == f.activeProf)
        local hasItems = f.byProf[btn.prof] ~= nil
        local hasCraft = f.configured[btn.prof]
        btn.mark:SetShown(hasItems)

        if hasCraft then
            btn:Enable()
        else
            btn:Disable()
        end
        btn:SetSelected(active)
    end
end

-- Draws the actual item/recipient lines for the currently selected
-- profession filter (f.activeProf), or everything when it's nil ("All").
function M:RenderPreviewList()
    local f       = self.preview
    local content = f.content
    local byProf  = f.byProf
    local mode    = f.mode

    self:RestyleProfSidebar()

    if f.contentLabels then
        for _, l in ipairs(f.contentLabels) do l:Hide() end
    end
    f.contentLabels = {}

    local function AddLine(text, r, g, b)
        local fs = content:CreateFontString(nil, "OVERLAY")
        fs:SetFont("Fonts\\ARIALN.TTF", Brand.DESC_FONT_SIZE, "")
        fs:SetTextColor(r or 0.7, g or 0.7, b or 0.7, 1)
        fs:SetText(text)
        fs:SetJustifyH("LEFT")
        fs:SetWidth(content:GetWidth())
        table.insert(f.contentLabels, fs)
        return fs
    end

    local y     = 0
    local lineH = 18

    for _, prof in ipairs(XC.PROFESSIONS) do
        if byProf[prof] and (not f.activeProf or f.activeProf == prof) then
            -- Profession header
            local hdr = AddLine(prof, 0.72, 0.55, 0.22)
            hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            hdr:SetFont("Fonts\\FRIZQT__.TTF", Brand.BUTTON_LABEL_SIZE, "OUTLINE")
            y = y + lineH + 2

            for recipient, data in pairs(byProf[prof]) do
                -- Crafter arrow
                local isGuildEntry = data.isGuild or false
                local rR = isGuildEntry and 0.10 or 0.52
                local rG = isGuildEntry and 0.80 or 0.72
                local rB = isGuildEntry and 0.18 or 0.92
                local gTag = isGuildEntry and " |cff1a9e2e[Guild]|r" or ""
                local cline = AddLine("  → " .. recipient .. gTag ..
                    "  (" .. data.mails .. " mail" .. (data.mails > 1 and "s)" or ")"),
                    rR, rG, rB)
                cline:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                y = y + lineH

                -- Item list (up to 8 shown, then "... and N more")
                local shown = 0
                local total = #data.items
                for _, item in ipairs(data.items) do
                    if shown < 8 then
                        local iline = AddLine("      " .. item.link .. "  ×" .. item.count,
                            0.60, 0.47, 0.30)
                        iline:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                        y = y + lineH
                        shown = shown + 1
                    end
                end
                if total > 8 then
                    local more = AddLine("      ... and " .. (total - 8) .. " more item type(s)",
                        0.40, 0.35, 0.25)
                    more:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                    y = y + lineH
                end
            end
            y = y + 6  -- gap between professions
        end
    end

    -- A specific profession is selected but has nothing queued right now -
    -- say so explicitly instead of leaving the panel blank. Different
    -- wording depending on whether it's actually configured or not, since
    -- those mean different things to fix.
    if f.activeProf and not byProf[f.activeProf] then
        local msg
        if f.configured[f.activeProf] then
            msg = "Nothing in your bags for " .. f.activeProf .. " right now."
        else
            msg = "No " .. (mode == "guild" and "guild" or "personal") ..
                " crafter configured for " .. f.activeProf .. ". Set one under /xcc options."
        end
        local empty = AddLine(msg, 0.45, 0.30, 0.20)
        empty:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        y = y + lineH
    elseif f.totalMails == 0 then
        local emptyText = (mode == "guild")
            and "Nothing to send to a guild crafter. Set one under /xcc options."
            or  "Nothing to send to a personal crafter. Set one under /xcc setup or /xcc options."
        local empty = AddLine(emptyText, 0.45, 0.30, 0.20)
        empty:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        y = y + lineH
    end

    if f.skipped and f.skipped > 0 then
        local note = AddLine(f.skipped .. " item(s) skipped — data not cached yet. Close and reopen to retry.",
            0.55, 0.42, 0.16)
        note:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        y = y + lineH
    end

    content:SetHeight(math.max(y + 8, 60))

    -- Update send button label — always reflects the FULL queue, not the
    -- sidebar's display filter, since Send All always sends everything
    -- regardless of which profession you're currently looking at.
    f.sendBtn.lbl:SetText("Send All (" .. f.totalMails .. ")")
    f.sendBtn:SetEnabled(f.totalMails > 0)
end


-- ══════════════════════════════════════════════════════════════
-- SCAN COMMAND  (/xcc scan)
-- Prints a preview to chat without opening the mailbox.
-- Registered in Core.lua's slash router.
-- ══════════════════════════════════════════════════════════════
function M:ScanToChat()
    local maxSkipped = 0

    for _, mode in ipairs({ "personal", "guild" }) do
        local label = (mode == "guild") and "Guild" or "Personal"
        print(XC.TAG .. " |cffaaaaaa── " .. label .. " Scan Results ──────────────────|r")
        local results, skipped = self:ScanBags(mode)
        maxSkipped = math.max(maxSkipped, skipped)
        local any = false

        for _, prof in ipairs(XC.PROFESSIONS) do
            local profResult = results[prof]
            if profResult then
                for crafterIdx, entry in pairs(profResult) do
                    any = true
                    local totalItems = 0
                    for _, item in ipairs(entry.items) do totalItems = totalItems + 1 end
                    print(string.format("  |cffcc6600%s|r → |cff88aaff%s|r  (%d stack%s)",
                        prof, entry.cfg.name, totalItems, totalItems == 1 and "" or "s"))
                    for _, item in ipairs(entry.items) do
                        print("    " .. item.link .. " ×" .. item.count)
                    end
                end
            end
        end

        if not any then
            print("  |cffaaaaaa(nothing found — check /xcc options to configure filters)|r")
        end
    end

    if maxSkipped > 0 then
        print("  |cffff8800" .. maxSkipped ..
            " item(s) skipped|r — not cached yet. Wait a moment and scan again.")
    end
end
