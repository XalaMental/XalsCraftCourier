-- ============================================================
-- Data.lua  —  Xal's Craft Courier
-- All static definitions: expansions, profession item types,
-- default config builders, and DB migration helpers.
--
-- NOTE: This file defines item TYPE categories per profession.
--       Actual item IDs (mapping specific items to categories)
--       will live in a future ItemData.lua file. This keeps
--       things clean and updatable per patch.
-- ============================================================

-- Defensive: XC is normally created by Core.lua, which loads first per the
-- .toc — this guard just means load order can never break this file again.
XC = XC or {}
XC.DATA = XC.DATA or {}

-- ──────────────────────────────────────────────────────────────
-- EXPANSION LIST  (oldest → newest)
-- id     = key used in SavedVariables
-- label  = full display name
-- short  = abbreviated name used in tight UI spaces
-- ──────────────────────────────────────────────────────────────
XC.DATA.Expansions = {
    { id = "vanilla",   label = "Classic / Vanilla",       short = "Classic" },
    { id = "tbc",       label = "The Burning Crusade",     short = "TBC"     },
    { id = "wotlk",     label = "Wrath of the Lich King",  short = "WotLK"   },
    { id = "cata",      label = "Cataclysm",               short = "Cata"    },
    { id = "mop",       label = "Mists of Pandaria",       short = "MoP"     },
    { id = "wod",       label = "Warlords of Draenor",     short = "WoD"     },
    { id = "legion",    label = "Legion",                  short = "Legion"  },
    { id = "bfa",       label = "Battle for Azeroth",      short = "BfA"     },
    { id = "sl",        label = "Shadowlands",             short = "SL"      },
    { id = "df",        label = "Dragonflight",            short = "DF"      },
    { id = "tww",       label = "The War Within",          short = "TWW"     },
    { id = "midnight",  label = "Midnight",                short = "MN"      },
}

-- ──────────────────────────────────────────────────────────────
-- PROFESSION ITEM TYPES
--
-- Each profession has a list of item CATEGORIES that can be
-- toggled independently per expansion.
--
-- Fields:
--   id      = key used in SavedVariables
--   label   = shown in the UI
--   default = whether this type is ON by default for new crafters
-- ──────────────────────────────────────────────────────────────
XC.DATA.ProfessionItemTypes = {

    ["Alchemy"] = {
        { id = "herbs",     label = "Herbs",                    default = true  },
        { id = "vials",     label = "Vials & Bottles",          default = true  },
        { id = "optional",  label = "Optional Reagents",        default = true  },
        { id = "pigments",  label = "Pigments",                 default = false },
        { id = "misc",      label = "Miscellaneous",            default = false },
    },

    ["Blacksmithing"] = {
        { id = "ore",       label = "Ore",                      default = true  },
        { id = "bars",      label = "Metal Bars",               default = true  },
        { id = "stone",     label = "Stone & Rock",             default = false },
        { id = "optional",  label = "Optional Reagents",        default = true  },
        { id = "misc",      label = "Flux & Misc",              default = false },
    },

    ["Enchanting"] = {
        { id = "dust",      label = "Dust",                     default = true  },
        { id = "essences",  label = "Essences",                 default = true  },
        { id = "crystals",  label = "Crystals & Shards",        default = true  },
        { id = "optional",  label = "Optional Reagents",        default = true  },
        { id = "misc",      label = "Miscellaneous",            default = false },
    },

    ["Engineering"] = {
        { id = "ore",       label = "Ore",                      default = true  },
        { id = "bars",      label = "Metal Bars",               default = true  },
        { id = "parts",     label = "Parts & Gizmos",           default = true  },
        { id = "cloth",     label = "Cloth",                    default = false },
        { id = "optional",  label = "Optional Reagents",        default = true  },
        { id = "misc",      label = "Miscellaneous",            default = false },
    },

    ["Herbalism"] = {
        { id = "herbs",     label = "Herbs",                    default = true  },
        { id = "seeds",     label = "Seeds",                    default = false },
        { id = "misc",      label = "Miscellaneous",            default = false },
    },

    ["Inscription"] = {
        { id = "herbs",     label = "Herbs",                    default = true  },
        { id = "pigments",  label = "Pigments",                 default = true  },
        { id = "inks",      label = "Inks",                     default = true  },
        { id = "parchment", label = "Parchment",                default = true  },
        { id = "optional",  label = "Optional Reagents",        default = true  },
        { id = "misc",      label = "Miscellaneous",            default = false },
    },

    ["Jewelcrafting"] = {
        { id = "ore",       label = "Ore",                      default = true  },
        { id = "gems",      label = "Gems & Jewels",            default = true  },
        { id = "optional",  label = "Optional Reagents",        default = true  },
        { id = "misc",      label = "Miscellaneous",            default = false },
    },

    ["Leatherworking"] = {
        { id = "leather",   label = "Leather",                  default = true  },
        { id = "hides",     label = "Hides & Scales",           default = true  },
        { id = "cloth",     label = "Cloth",                    default = false },
        { id = "optional",  label = "Optional Reagents",        default = true  },
        { id = "misc",      label = "Miscellaneous",            default = false },
    },

    ["Mining"] = {
        { id = "ore",       label = "Ore",                      default = true  },
        { id = "bars",      label = "Metal Bars",               default = true  },
        { id = "stone",     label = "Stone",                    default = false },
        { id = "gems",      label = "Gems",                     default = false },
        { id = "misc",      label = "Miscellaneous",            default = false },
    },

    ["Skinning"] = {
        { id = "leather",   label = "Leather",                  default = true  },
        { id = "hides",     label = "Hides & Scales",           default = true  },
        { id = "misc",      label = "Miscellaneous",            default = false },
    },

    ["Tailoring"] = {
        { id = "cloth",     label = "Cloth",                    default = true  },
        { id = "threads",   label = "Threads & Dyes",           default = true  },
        { id = "optional",  label = "Optional Reagents",        default = true  },
        { id = "misc",      label = "Miscellaneous",            default = false },
    },

    ["Cooking"] = {
        { id = "meat",      label = "Meat & Fish",              default = true  },
        { id = "veg",       label = "Vegetables & Fruit",       default = true  },
        { id = "spices",    label = "Spices & Seasoning",       default = true  },
        { id = "misc",      label = "Miscellaneous",            default = false },
    },

    ["Fishing"] = {
        { id = "fish",      label = "Fish",                     default = true  },
        { id = "misc",      label = "Miscellaneous",            default = false },
    },
}

-- ──────────────────────────────────────────────────────────────
-- HELPERS
-- ──────────────────────────────────────────────────────────────

-- Get item type list for a profession (safe — returns {} if unknown)
function XC.DATA:GetItemTypes(profession)
    return self.ProfessionItemTypes[profession] or {}
end

-- Build a fresh default crafter config with all expansions and
-- item types pre-populated for the given profession.
--
-- DB structure for one crafter:
--   cfg = {
--     name    = "Ironveil",
--     enabled = true,
--     expansions = {
--       ["vanilla"] = {
--         enabled = true,   ← master toggle for this expansion
--         ore     = true,   ← per-item-type toggles
--         bars    = true,
--         stone   = false,
--       },
--       ["tbc"] = { ... },
--       ...
--     }
--   }
function XC.DATA:DefaultCrafterConfig(profession)
    local cfg = {
        name       = "",
        enabled    = true,
        expansions = {},
    }
    local itemTypes = self:GetItemTypes(profession)
    for _, exp in ipairs(self.Expansions) do
        cfg.expansions[exp.id] = { enabled = true }
        for _, itype in ipairs(itemTypes) do
            cfg.expansions[exp.id][itype.id] = itype.default
        end
    end
    return cfg
end

-- Ensure an existing crafter config has ALL keys.
-- Called when opening the options panel so older saved configs
-- automatically gain new expansions/item types added in updates.
function XC.DATA:MigrateCrafterConfig(cfg, profession)
    cfg.expansions = cfg.expansions or {}
    local itemTypes = self:GetItemTypes(profession)
    for _, exp in ipairs(self.Expansions) do
        -- Add missing expansion entry
        if not cfg.expansions[exp.id] then
            cfg.expansions[exp.id] = { enabled = true }
        end
        local expCfg = cfg.expansions[exp.id]
        if expCfg.enabled == nil then expCfg.enabled = true end
        -- Add missing item type keys inside this expansion
        for _, itype in ipairs(itemTypes) do
            if expCfg[itype.id] == nil then
                expCfg[itype.id] = itype.default
            end
        end
    end
end


-- ──────────────────────────────────────────────────────────────
-- EXPAC ID MAP
--
-- GetItemInfo() returns expacID as its 15th value.
-- This maps Blizzard's numeric expacID → our expansion string IDs.
-- Used by the bag scanner to determine which expansion an item
-- belongs to without needing a hand-curated item ID list.
-- ──────────────────────────────────────────────────────────────
XC.DATA.ExpacIDMap = {
    [0]  = "vanilla",
    [1]  = "tbc",
    [2]  = "wotlk",
    [3]  = "cata",
    [4]  = "mop",
    [5]  = "wod",
    [6]  = "legion",
    [7]  = "bfa",
    [8]  = "sl",
    [9]  = "df",
    [10] = "tww",
    [11] = "midnight",
}

-- ──────────────────────────────────────────────────────────────
-- SUBCLASS MAP
--
-- Maps { itemClassID, itemSubClassID } → which professions use
-- this item type, and a base type hint for that subclass.
--
-- The type hint is refined further by GetProfAndType() using
-- the item name (e.g. "Ore" vs "Bar" within Metal & Stone).
--
-- Key professions and their primary item classID/subClassID:
--   Trade Goods = classID 7
--   Gems        = classID 3
-- ──────────────────────────────────────────────────────────────
XC.DATA.SubClassMap = {
    -- ── Trade Goods (classID 7) ───────────────────────────────
    [7] = {
        [1]  = { profs = { "Engineering" },
                 type  = "parts" },              -- Parts & Gizmos
        [5]  = { profs = { "Tailoring", "Engineering" },
                 type  = "cloth" },              -- Cloth
        [6]  = { profs = { "Leatherworking", "Skinning" },
                 type  = "leather" },            -- Leather
        [7]  = { profs = { "Blacksmithing", "Engineering", "Mining", "Jewelcrafting" },
                 type  = "ore" },                -- Metal & Stone (refined by name)
        [8]  = { profs = { "Cooking" },
                 type  = "meat" },               -- Meat & Fish
        [9]  = { profs = { "Alchemy", "Inscription", "Herbalism" },
                 type  = "herbs" },              -- Herb
        [10] = { profs = { "Alchemy", "Blacksmithing", "Enchanting" },
                 type  = "misc" },               -- Elemental
        [11] = { profs = { "Alchemy", "Enchanting" },
                 type  = "misc" },               -- Other trade goods
        [12] = { profs = { "Enchanting" },
                 type  = "dust" },               -- Enchanting materials
        [13] = { profs = { "Inscription" },
                 type  = "inks" },               -- Inks & Pigments
        [16] = { profs = { "Inscription" },
                 type  = "parchment" },          -- Parchment
        [17] = { profs = { "Leatherworking", "Skinning" },
                 type  = "hides" },              -- Hides & Scales
    },
    -- ── Gems (classID 3) ──────────────────────────────────────
    [3] = {
        [0]  = { profs = { "Jewelcrafting" }, type = "gems" },
        [1]  = { profs = { "Jewelcrafting" }, type = "gems" },
        [2]  = { profs = { "Jewelcrafting" }, type = "gems" },
        [3]  = { profs = { "Jewelcrafting" }, type = "gems" },
        [4]  = { profs = { "Jewelcrafting" }, type = "gems" },
        [5]  = { profs = { "Jewelcrafting" }, type = "gems" },
        [9]  = { profs = { "Jewelcrafting" }, type = "gems" },  -- Primordial gems (TWW)
        [11] = { profs = { "Jewelcrafting" }, type = "gems" },  -- Other gems
    },
    -- ── Cooking ingredients sometimes under Food/Drink (classID 4) ──
    [4] = {
        [0]  = { profs = { "Cooking" }, type = "meat" },
        [5]  = { profs = { "Cooking" }, type = "meat" },
    },
}

-- ──────────────────────────────────────────────────────────────
-- NAME-BASED TYPE REFINEMENT
--
-- Within Metal & Stone (subClass 7 of Trade Goods), items share
-- the same subclass but are different types. We use the item name
-- to narrow down which type bucket it belongs to.
-- ──────────────────────────────────────────────────────────────
local ORE_PATTERNS  = { "Ore$", "Ore " }
local BAR_PATTERNS  = { "Bar$", "Ingot$" }
local STONE_PATTERNS= { "Stone", "Rock", "Cobble", "Gravel", "Pebble", "Granite", "Obsidian" }
local DUST_PATTERNS = { "Dust", "Powder", "Residue", "Ash" }
local ESS_PATTERNS  = { "Essence", "Shard", "Splinter", "Fragment" }
local CRYS_PATTERNS = { "Crystal", "Prism", "Gleam" }
local INK_PATTERNS  = { "Ink", "Pigment" }

local function MatchAny(name, patterns)
    for _, p in ipairs(patterns) do
        if name:find(p) then return true end
    end
    return false
end

-- ──────────────────────────────────────────────────────────────
-- GetProfAndType(classID, subClassID, itemName, quality, isCraftingReagent)
--
-- Returns:  profs (table of profession names), typeHint (string)
-- Returns:  nil, nil  if item is not a known crafting material
--
-- Called by the bag scanner for every item in the player's bags.
-- ──────────────────────────────────────────────────────────────
function XC.DATA:GetProfAndType(classID, subClassID, itemName, quality, isCraftingReagent)
    local classMap = self.SubClassMap[classID]
    if not classMap then return nil, nil end

    local entry = classMap[subClassID]
    if not entry then return nil, nil end

    local profs    = entry.profs
    local typeHint = entry.type

    -- Refine type for Metal & Stone (classID=7, subClass=7) by name
    if classID == 7 and subClassID == 7 then
        if MatchAny(itemName, ORE_PATTERNS) then
            typeHint = "ore"
        elseif MatchAny(itemName, BAR_PATTERNS) then
            typeHint = "bars"
        elseif MatchAny(itemName, STONE_PATTERNS) then
            typeHint = "stone"
        else
            typeHint = "misc"
        end
    end

    -- Refine Enchanting materials (classID=7, subClass=12) by name
    if classID == 7 and subClassID == 12 then
        if MatchAny(itemName, DUST_PATTERNS) then
            typeHint = "dust"
        elseif MatchAny(itemName, ESS_PATTERNS) then
            typeHint = "essences"
        elseif MatchAny(itemName, CRYS_PATTERNS) then
            typeHint = "crystals"
        else
            typeHint = "dust"
        end
    end

    -- Refine Inscription materials (classID=7, subClass=13) by name
    if classID == 7 and subClassID == 13 then
        if MatchAny(itemName, INK_PATTERNS) then
            typeHint = "inks"
        else
            typeHint = "pigments"
        end
    end

    -- Override to "optional" for quality crafting reagents (the star items)
    -- isCraftingReagent = true AND quality >= 2 (Uncommon or better)
    -- These are the optional/finishing reagents in Dragonflight+ crafting
    if isCraftingReagent and quality and quality >= 2 then
        typeHint = "optional"
    end

    return profs, typeHint
end
