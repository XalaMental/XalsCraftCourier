-- ============================================================
-- Core.lua  —  Xal's Craft Courier
-- Handles: addon table, DB init, events, slash commands
-- ============================================================

-- Global addon table (accessible by all files)
XC = XC or {}
XC.ADDONNAME  = "XalsCraftCourier"
-- Read straight from the .toc's "## Version:" line at runtime, so bumping
-- a release only ever means changing it in ONE place (the .toc) instead
-- of needing to keep this in sync by hand every time.
XC.VERSION    = C_AddOns.GetAddOnMetadata(XC.ADDONNAME, "Version") or "?"

-- Master profession list used throughout the addon
XC.PROFESSIONS = {
    "Alchemy", "Blacksmithing", "Enchanting", "Engineering",
    "Herbalism", "Inscription", "Jewelcrafting", "Leatherworking",
    "Mining", "Skinning", "Tailoring", "Cooking", "Fishing",
}

-- Convenience colour prefix for chat output
XC.TAG = "|cffb88c38[Xal's Craft Courier]|r"

-- ──────────────────────────────────────────────────────────────
-- EVENT FRAME
-- ──────────────────────────────────────────────────────────────
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == XC.ADDONNAME then
        XC:OnLoad()
    elseif event == "PLAYER_LOGIN" then
        XC:OnPlayerLogin()
    elseif event == "PLAYER_GUILD_UPDATE" then
        -- GetGuildInfo can still be nil at PLAYER_LOGIN if the roster hasn't
        -- synced yet - this catches it once it actually becomes available.
        XC:RecordMyGuild()
    end
end)

-- ──────────────────────────────────────────────────────────────
-- INITIALISATION  (fires once, when the addon finishes loading)
-- ──────────────────────────────────────────────────────────────
function XC:OnLoad()
    -- XC_DB  ─ global / account-wide storage (same across all alts)
    --   crafters  : { ["ProfessionName"] = "CharacterName" }
    -- XC_DB  global/account-wide storage
    --   crafters   : simple name map from splash setup
    --   profConfig : full per-profession crafter + filter config
    --   knownChars : list of "Name-Realm" strings
    XC_DB = XC_DB or {}
    XC_DB.crafters   = XC_DB.crafters   or {}
    XC_DB.profConfig = XC_DB.profConfig or {}
    XC_DB.knownChars = XC_DB.knownChars or {}
    XC_DB.version    = XC.VERSION

    -- Ensure every profession has a profConfig entry. guildCraftersByGuild
    -- is keyed by guild name - crafters are scoped to ONE specific guild,
    -- never shared across guilds. (Old flat "guildCrafters" lists, if any
    -- exist from before this was per-guild, get migrated by RecordMyGuild
    -- once we actually know which guild they belong to.)
    for _, prof in ipairs(XC.PROFESSIONS) do
        XC_DB.profConfig[prof] = XC_DB.profConfig[prof] or {}
        XC_DB.profConfig[prof].crafters = XC_DB.profConfig[prof].crafters or {}
        XC_DB.profConfig[prof].guildCraftersByGuild = XC_DB.profConfig[prof].guildCraftersByGuild or {}

        -- One-time migration: XC_DB.crafters[prof] (set via the old/quick
        -- Setup screen) used to be a dead end - the mail router never read
        -- it. Give it a real entry in profConfig[prof].crafters so crafters
        -- assigned before this fix actually start receiving mail.
        local quickName = XC_DB.crafters[prof]
        if quickName and quickName ~= "" then
            local hasQuickEntry = false
            for _, cfg in ipairs(XC_DB.profConfig[prof].crafters) do
                if cfg.isQuickSetup then hasQuickEntry = true; break end
            end
            if not hasQuickEntry then
                local cfg = XC.DATA:DefaultCrafterConfig(prof)
                cfg.name         = quickName
                cfg.isQuickSetup = true
                table.insert(XC_DB.profConfig[prof].crafters, cfg)
            end
        end
    end

    -- Global settings (reserved for future options)
    XC_DB.settings  = XC_DB.settings  or {}
    -- Overall panel scale (Options/Splash/the mailbox send preview),
    -- applied via frame:SetScale() - takes effect immediately on
    -- already-open panels. Set from Options -> Settings.
    XC_DB.settings.uiScale = XC_DB.settings.uiScale or 1.0
    -- Independent text-size multiplier applied to every font this addon
    -- draws (titles, buttons, labels) - separate from uiScale, since
    -- panel size and font size are different things. Takes effect on
    -- panels built/opened after the change - existing open panels need a
    -- /reload to pick up a new value, since each FontString's size is
    -- baked in at creation. Set from Options -> Settings.
    XC_DB.settings.fontScale = XC_DB.settings.fontScale or 1.0
    XC.BrandStyle.RefreshSavedScales()

    -- Minimap launcher icon (LibDataBroker + LibDBIcon) - registered
    -- before Options so XC_DB.minimap already exists when the Settings
    -- window builds its "Show the minimap button" checkbox.
    XC.MinimapButton:Register()

    -- Build the standalone Options window (defined in Options.lua) - a
    -- real floating panel now, not a Blizzard AddOns-list entry.
    XC.Options:Register()

    -- XC_CharDB  ─ per-character storage (each alt is independent)
    --   seenSplash : true once this character dismisses the welcome screen
    XC_CharDB = XC_CharDB or { seenSplash = false }

    -- Register  /xcc  as the slash command
    SLASH_XALSCRAFTCOURIER1 = "/xcc"
    SlashCmdList["XALSCRAFTCOURIER"] = function(msg)
        XC:HandleSlash(msg)
    end

    print(XC.TAG .. " v" .. XC.VERSION .. " loaded.  |cffaaaaaa/xcc help|r")
end

-- ──────────────────────────────────────────────────────────────
-- PLAYER LOGIN  (fires every time this character enters the world)
-- ──────────────────────────────────────────────────────────────
function XC:OnPlayerLogin()
    -- Register this character into the account-wide known chars list.
    -- UnitName("player") returns "Name", "Realm" as two separate values.
    -- GetRealmName() returns the current realm name.
    -- We store as "Charname-Realm" so cross-realm crafters are distinct.
    local name  = UnitName("player")
    local realm = GetRealmName()
    if name and realm then
        local fullName = name .. "-" .. realm
        XC_DB.knownChars = XC_DB.knownChars or {}
        -- Only add if not already in the list
        local exists = false
        for _, v in ipairs(XC_DB.knownChars) do
            if v == fullName then exists = true; break end
        end
        if not exists then
            table.insert(XC_DB.knownChars, fullName)
            -- Keep the list alphabetical every time a new char is added
            table.sort(XC_DB.knownChars)
        end
        -- Store this character's own realm for same-realm detection in dropdown
        XC_CharDB.realm = realm
    end

    -- Only auto-show the splash if this character hasn't seen it yet
    if not XC_CharDB.seenSplash then
        -- Small delay lets WoW finish drawing the rest of the UI first
        C_Timer.After(1.5, function()
            XC.Splash:Open()
        end)
    else
        -- Only check for a what's-new splash on a character who's already
        -- been through the welcome screen before - a genuinely first-time
        -- install gets the Splash as its intro, not both popups at once.
        XC.WhatsNew:CheckAndShow()
    end

    XC:RecordMyGuild()
end

-- Records the CURRENT character's guild into the account-wide known-guilds
-- list, so Options can show a real tab per guild your alts belong to
-- (there's no API to see another character's guild remotely — this only
-- ever knows about a guild once some character has actually logged in
-- with the addon running while in it). Never removes a guild once seen,
-- same as the known-alts list — other alts may still be in it.
--
-- Also runs a one-time migration: any old flat (unscoped) guild-crafter
-- list gets moved into this guild's own bucket, since we finally know
-- which guild it was for. Safe to call repeatedly - a no-op once migrated.
function XC:RecordMyGuild()
    local guildName = GetGuildInfo("player")
    if not guildName then return end

    XC_DB.knownGuilds = XC_DB.knownGuilds or {}
    local alreadyKnown = false
    for _, g in ipairs(XC_DB.knownGuilds) do
        if g == guildName then alreadyKnown = true; break end
    end
    if not alreadyKnown then
        table.insert(XC_DB.knownGuilds, guildName)
        table.sort(XC_DB.knownGuilds)
    end

    for _, prof in ipairs(XC.PROFESSIONS) do
        local pc = XC_DB.profConfig[prof]
        if pc and pc.guildCrafters and #pc.guildCrafters > 0 then
            pc.guildCraftersByGuild = pc.guildCraftersByGuild or {}
            pc.guildCraftersByGuild[guildName] = pc.guildCraftersByGuild[guildName] or {}
            for _, cfg in ipairs(pc.guildCrafters) do
                table.insert(pc.guildCraftersByGuild[guildName], cfg)
            end
            pc.guildCrafters = nil
        end
    end
end

-- ──────────────────────────────────────────────────────────────
-- SLASH COMMAND ROUTER
-- ──────────────────────────────────────────────────────────────
function XC:HandleSlash(msg)
    local cmd = (msg:match("^(%S*)") or ""):lower()

    if cmd == "" or cmd == "help" then
        XC:PrintHelp()

    elseif cmd == "splash" then
        XC.Splash:Open()

    elseif cmd == "setup" then
        -- Open directly to the setup screen
        XC.Splash:Open()
        XC.Splash:GoToSetup()

    elseif cmd == "crafters" then
        XC:ListCrafters()

    else
        print(XC.TAG .. " Unknown command — try |cffaaaaaa/xcc help|r")
    end
end

function XC:PrintHelp()
    print(XC.TAG)
    print("  |cffaaaaaa/xcc splash|r   — Welcome screen")
    print("  |cffaaaaaa/xcc setup|r    — Crafter setup panel")
    print("  |cffaaaaaa/xcc crafters|r — List configured crafters")
end

function XC:ListCrafters()
    print(XC.TAG .. " |cffaaaaaa── Configured Crafters ──|r")
    local found = false
    for _, prof in ipairs(XC.PROFESSIONS) do
        local c = XC_DB.crafters[prof]
        if c then
            print("  |cffcc6600" .. prof .. "|r → |cff88aaff" .. c .. "|r")
            found = true
        end
    end
    if not found then
        print("  |cffaaaaaa(none yet — use /xcc setup)|r")
    end
end

-- ──────────────────────────────────────────────────────────────
-- Add "options" to slash command router (appended)
-- ──────────────────────────────────────────────────────────────
local _origSlash = XC.HandleSlash
function XC:HandleSlash(msg)
    local cmd = (msg:match("^(%S*)") or ""):lower()
    if cmd == "options" or cmd == "opt" then
        XC.Options:Open()
    elseif cmd == "scan" then
        XC.Mailbox:ScanToChat()
    else
        _origSlash(self, msg)
    end
end

-- Update help text
local _origHelp = XC.PrintHelp
function XC:PrintHelp()
    _origHelp(self)
    print("  |cffaaaaaa/xcc options|r  — Full options panel")
    print("  |cffaaaaaa/xcc scan|r     — Preview what would be sent")
end
