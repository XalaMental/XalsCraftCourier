-- MinimapButton.lua
-- Xal's Craft Courier
--
-- The minimap launcher icon, via LibDataBroker + LibDBIcon - same
-- combination Routes/Compendium use. Left-click opens the standalone
-- Options window; right-click opens the Send Preview panel directly
-- (safe to call away from a mailbox - it only scans bags, sending itself
-- still requires being at a real mailbox).
XC = XC or {}
XC.MinimapButton = {}
local MB = XC.MinimapButton

-- Full custom-shaped icon, not masked into Blizzard's standard circular
-- border - same technique Routes uses (RemoveButtonBorder/
-- RemoveButtonBackground/SetButtonIcon, LibDBIcon rev 56+).
local MINIMAP_ICON = "Interface\\AddOns\\XalsCraftCourier\\Textures\\MinimapIcon_Envelope3.png"
local MINIMAP_ICON_SIZE = 34

function MB:Register()
    local ldb = LibStub("LibDataBroker-1.1"):NewDataObject("XalsCraftCourier", {
        type = "launcher",
        text = "Xal's Craft Courier",
        icon = MINIMAP_ICON,
        OnClick = function(_, button)
            if button == "RightButton" then
                XC.Mailbox:OpenSendPanel()
            else
                XC.Options:Open()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Xal's Craft Courier")
            tooltip:AddLine("|cff999999Left-click|r to open Options")
            tooltip:AddLine("|cff999999Right-click|r to open the Send Preview")
        end,
    })

    XC_DB.minimap = XC_DB.minimap or { hide = false }
    local icon = LibStub("LibDBIcon-1.0")
    icon:Register("XalsCraftCourier", ldb, XC_DB.minimap)

    if icon.SetButtonSize then
        icon:SetButtonSize("XalsCraftCourier", MINIMAP_ICON_SIZE)
        icon:RemoveButtonBorder("XalsCraftCourier")
        icon:RemoveButtonBackground("XalsCraftCourier")
        icon:SetButtonIcon("XalsCraftCourier", MINIMAP_ICON, MINIMAP_ICON_SIZE, "CENTER", 0, 0)
    end
end

-- Backing the Settings checkbox - LibDBIcon's own Show/Hide API, not a
-- manual texture toggle.
function MB:SetShown(shown)
    XC_DB.minimap = XC_DB.minimap or { hide = false }
    XC_DB.minimap.hide = not shown
    local icon = LibStub("LibDBIcon-1.0", true)
    if not icon then return end
    if shown then
        icon:Show("XalsCraftCourier")
    else
        icon:Hide("XalsCraftCourier")
    end
end
