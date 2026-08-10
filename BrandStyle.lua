-- BrandStyle.lua
-- Xal's Craft Courier
--
-- Xal's shared visual brand. Background/accent/title treatment ARE Craft
-- Courier's own original splash-panel look (this addon is where that half
-- of the standard came from); the button style is from Xal's Compendium -
-- Courier's own previous beveled/PNG-graphic buttons looked visually off
-- (inconsistent highlight/shadow read) once several sat in a horizontal
-- row, so Compendium's flat button replaced it as the standard, confirmed
-- 2026-08-09. Every border/divider line is at least 2px - a 1px line can
-- fail to render reliably depending on UI scale.
--
-- Use these helpers for splash screens, settings panels, and any other
-- custom-drawn frame. Standard interactive controls that AREN'T part of
-- this brand spec (checkboxes, sliders, edit boxes) still use Blizzard's
-- native templates (UICheckButtonTemplate etc.) - only buttons/borders/
-- titles get the custom treatment.
XC = XC or {}
XC.BrandStyle = {}
local Brand = XC.BrandStyle

-- ── Colours (r, g, b) ─────────────────────────────────────────
Brand.ACCENT = { 0.72, 0.55, 0.22 }   -- warm bronze-gold
Brand.GOLD   = { 0.60, 0.47, 0.30 }   -- secondary/body text tone
Brand.BG     = { 0.035, 0.035, 0.035, 1 } -- near-black, fully opaque
Brand.LINE_THICKNESS = 2 -- minimum for ANY border/divider - never go below this
-- Minimum gap between a panel's true outer edge and the nearest button/text.
Brand.SAFE_MARGIN = 14
-- Confirmed settings-panel typography standard (2026-08-09): 13px for
-- dim/description text, 14px for brighter label/button/checkbox text -
-- Blizzard's own template defaults (~10-12px) read too small against
-- busy WoW terrain. Applies addon-wide, not just literal "settings" text.
Brand.DESC_FONT_SIZE   = 13
Brand.BUTTON_LABEL_SIZE = 14

-- ── Scale settings ─────────────────────────────────────────────
-- Two SEPARATE controls, both user-settable from Options -> Settings:
--   fontScale - multiplies every font size this module hands out
--               (Brand.FS/Title/MakeButton's label). Baked into each
--               FontString at creation, so a change only takes effect on
--               panels built/opened after it - existing open panels need
--               a /reload.
--   uiScale   - applied via frame:SetScale() to whichever frames call
--               Brand.RegisterScalable(frame) - takes effect immediately
--               on already-open panels, since SetScale() rescales
--               everything already drawn on that frame live.
-- Both default to 1.0 here since XC_DB doesn't exist yet when this file's
-- top-level code runs (files execute before ADDON_LOADED fires) -
-- Brand.RefreshSavedScales() is called from Core.lua's OnLoad once it does.
Brand.fontScale = 1.0
Brand.uiScale   = 1.0

function Brand.RefreshSavedScales()
    if not (XC_DB and XC_DB.settings) then return end
    Brand.fontScale = XC_DB.settings.fontScale or 1.0
    Brand.uiScale   = XC_DB.settings.uiScale   or 1.0
end

function Brand.SetFontScale(scale)
    Brand.fontScale = scale
    if XC_DB and XC_DB.settings then XC_DB.settings.fontScale = scale end
end

-- Weak-keyed so a frame that gets destroyed doesn't leak a reference here.
Brand.scalableFrames = setmetatable({}, { __mode = "k" })

function Brand.RegisterScalable(frame)
    Brand.scalableFrames[frame] = true
    frame:SetScale(Brand.uiScale)
end

function Brand.SetUIScale(scale)
    Brand.uiScale = scale
    if XC_DB and XC_DB.settings then XC_DB.settings.uiScale = scale end
    for frame in pairs(Brand.scalableFrames) do
        frame:SetScale(scale)
    end
end

-- ── T()  ─ solid-colour texture rectangle.
-- x, y measured from the parent's TOP-LEFT corner (y increases downward).
-- Uses PixelUtil so every edge snaps to a whole physical screen pixel.
function Brand.T(parent, x, y, w, h, r, g, b, a, layer)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")
    PixelUtil.SetPoint(tex, "TOPLEFT", parent, "TOPLEFT", x, -y)
    PixelUtil.SetSize(tex, w, h)
    tex:SetColorTexture(r, g, b, a or 1)
    return tex
end

-- ── FS()  ─ a FontString with a specific font/size/colour. Size is
-- multiplied by Brand.fontScale, so every title/label/button text this
-- module creates responds to the Font Size setting.
function Brand.FS(parent, text, fontPath, size, flags, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(fontPath, math.floor(size * Brand.fontScale + 0.5), flags or "")
    fs:SetText(text)
    fs:SetTextColor(r, g, b, 1)
    return fs
end

-- ── Title()  ─ the branded Morpheus-font title treatment, with its
-- drop-shadow layer, in one call. Returns the visible (front) fontstring.
function Brand.Title(parent, text, size, anchorPoint, relTo, relPoint, x, y)
    local shadow = Brand.FS(parent, text, "Fonts\\MORPHEUS.TTF", size, "OUTLINE", 0.05, 0.04, 0.02)
    PixelUtil.SetPoint(shadow, anchorPoint, relTo, relPoint, x + 2, y - 2)
    shadow:SetJustifyH("CENTER")

    local title = Brand.FS(parent, text, "Fonts\\MORPHEUS.TTF", size, "OUTLINE",
        Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3])
    PixelUtil.SetPoint(title, anchorPoint, relTo, relPoint, x, y)
    title:SetJustifyH("CENTER")
    return title
end

-- ── MakeButton()  ─ Xal's Compendium's flat button (the confirmed
-- standard): thin border, semi-transparent dark fill, no bevel/gradient -
-- reads cleanly even in a horizontal row. Selected vs. normal state is
-- carried by fill brightness AND label color (see SetSelected below).
-- Call btn:SetSelected(true/false) for a brighter fill + white label (tabs).
local BTN_BORDER = { Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3], 1 }
local BTN_BORDER_SELECTED = { Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3], 1 }
-- Unselected label color - a warm amber-orange, deliberately more vivid
-- than Brand.GOLD (that's the muted secondary body-text tone) so an
-- inactive button label still pops against the dark fill.
local BTN_LABEL_UNSELECTED = { 0.95, 0.60, 0.10 }

function Brand.MakeButton(parent, text, w, h, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    PixelUtil.SetSize(btn, w, h)
    -- Fill only - no backdrop edge. Blizzard's backdrop-edge system computes
    -- each side's thickness independently and isn't guaranteed symmetric at
    -- a non-integer UI Scale. Border is hand-drawn below instead, using the
    -- same pixel-snapped technique as Brand.DrawBorder.
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.6)

    local thick = Brand.LINE_THICKNESS
    local borderTop = btn:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(borderTop, "TOPLEFT", btn, "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(borderTop, "TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    PixelUtil.SetHeight(borderTop, thick)

    local borderBottom = btn:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(borderBottom, "BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    PixelUtil.SetPoint(borderBottom, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    PixelUtil.SetHeight(borderBottom, thick)

    local borderLeft = btn:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(borderLeft, "TOPLEFT", btn, "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(borderLeft, "BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    PixelUtil.SetWidth(borderLeft, thick)

    local borderRight = btn:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(borderRight, "TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    PixelUtil.SetPoint(borderRight, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    PixelUtil.SetWidth(borderRight, thick)

    local function SetBorderColor(r, g, b, a)
        borderTop:SetColorTexture(r, g, b, a)
        borderBottom:SetColorTexture(r, g, b, a)
        borderLeft:SetColorTexture(r, g, b, a)
        borderRight:SetColorTexture(r, g, b, a)
    end
    SetBorderColor(BTN_BORDER[1], BTN_BORDER[2], BTN_BORDER[3], BTN_BORDER[4])

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(text)
    label:SetTextColor(BTN_LABEL_UNSELECTED[1], BTN_LABEL_UNSELECTED[2], BTN_LABEL_UNSELECTED[3], 1)
    -- GameFontNormal's inherited size (~12px) is under the confirmed
    -- settings-panel typography standard's 14px label floor - explicitly
    -- override it (keeping the template's actual font FACE) rather than
    -- leaving every button on whatever Blizzard's default happens to be.
    do
        local baseFont, _, baseFlags = label:GetFont()
        if baseFont then
            label:SetFont(baseFont, math.floor(Brand.BUTTON_LABEL_SIZE * Brand.fontScale + 0.5), baseFlags)
        end
    end
    btn.label = label

    btn:SetScript("OnEnter", function(self)
        if not self.selected then self:SetBackdropColor(0.18, 0.18, 0.18, 0.75) end
    end)
    btn:SetScript("OnLeave", function(self)
        if not self.selected then self:SetBackdropColor(0.1, 0.1, 0.1, 0.6) end
    end)
    if onClick then btn:SetScript("OnClick", onClick) end

    function btn:SetSelected(selected)
        self.selected = selected
        if selected then
            self:SetBackdropColor(0.22, 0.22, 0.22, 0.85)
            SetBorderColor(BTN_BORDER_SELECTED[1], BTN_BORDER_SELECTED[2], BTN_BORDER_SELECTED[3], BTN_BORDER_SELECTED[4])
            label:SetTextColor(1, 1, 1, 1)
        else
            self:SetBackdropColor(0.1, 0.1, 0.1, 0.6)
            SetBorderColor(BTN_BORDER[1], BTN_BORDER[2], BTN_BORDER[3], BTN_BORDER[4])
            label:SetTextColor(BTN_LABEL_UNSELECTED[1], BTN_LABEL_UNSELECTED[2], BTN_LABEL_UNSELECTED[3], 1)
        end
    end

    function btn:SetBorderColor(r, g, bC, a)
        SetBorderColor(r, g, bC, a)
    end

    return btn
end

-- ── DrawBorder()  ─ single clean accent-color line around a frame.
function Brand.DrawBorder(f, inset)
    inset = inset or 6
    local thick = Brand.LINE_THICKNESS
    local r, g, b = Brand.ACCENT[1], Brand.ACCENT[2], Brand.ACCENT[3]

    local top = f:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(top, "TOPLEFT", f, "TOPLEFT", inset, -inset)
    PixelUtil.SetPoint(top, "TOPRIGHT", f, "TOPRIGHT", -inset, -inset)
    PixelUtil.SetHeight(top, thick)
    top:SetColorTexture(r, g, b, 1)

    local bottom = f:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(bottom, "BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset)
    PixelUtil.SetPoint(bottom, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    PixelUtil.SetHeight(bottom, thick)
    bottom:SetColorTexture(r, g, b, 1)

    local left = f:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(left, "TOPLEFT", f, "TOPLEFT", inset, -inset)
    PixelUtil.SetPoint(left, "BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset)
    PixelUtil.SetWidth(left, thick)
    left:SetColorTexture(r, g, b, 1)

    local right = f:CreateTexture(nil, "ARTWORK")
    PixelUtil.SetPoint(right, "TOPRIGHT", f, "TOPRIGHT", -inset, -inset)
    PixelUtil.SetPoint(right, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    PixelUtil.SetWidth(right, thick)
    right:SetColorTexture(r, g, b, 1)

    return top, bottom, left, right
end

-- ── DrawDivider()  ─ the thin section-separator line used between content
-- blocks (feature lists, header bars, etc.)
function Brand.DrawDivider(parent, x, y, width)
    return Brand.T(parent, x, y, width, Brand.LINE_THICKNESS, 0.16, 0.12, 0.05, 1)
end

-- ── ApplyBackground()  ─ the standard opaque near-black frame background.
function Brand.ApplyBackground(f)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(Brand.BG[1], Brand.BG[2], Brand.BG[3], Brand.BG[4])
    return bg
end
