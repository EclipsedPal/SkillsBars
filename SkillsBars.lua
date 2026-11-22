-- SkillsBars for WoW: Forever
-- A single draggable block of skill bars. Equipped weapons are shown
-- automatically (optional); any other skill can be picked from the
-- minimap menu.

local ADDON = ...

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

-- Skill line IDs (independent of client language)
local SKILL_DEFENSE = 95
local SKILL_UNARMED = 162

-- Weapon subclass (classID 2) -> skill line
local SUBCLASS_TO_SKILL = {
    [0]  = 44,  -- Axes
    [1]  = 172, -- Two-handed axes
    [2]  = 45,  -- Bows
    [3]  = 46,  -- Guns
    [4]  = 54,  -- Maces
    [5]  = 160, -- Two-handed maces
    [6]  = 229, -- Polearms
    [7]  = 43,  -- Swords
    [8]  = 55,  -- Two-handed swords
    [10] = 136, -- Staves
    [13] = 473, -- Fist weapons
    [15] = 173, -- Daggers
    [16] = 176, -- Thrown
    [18] = 226, -- Crossbows
    [19] = 228, -- Wands
}

-- Icons for skills picked from the menu (no weapon to take the icon from)
local SKILL_ICONS = {
    [95]  = "Interface\\Icons\\Ability_Defend",
    [162] = "Interface\\Icons\\INV_Gauntlets_04",
    [44]  = "Interface\\Icons\\INV_Axe_04",
    [172] = "Interface\\Icons\\INV_Axe_09",
    [43]  = "Interface\\Icons\\INV_Sword_04",
    [55]  = "Interface\\Icons\\INV_Sword_06",
    [54]  = "Interface\\Icons\\INV_Mace_01",
    [160] = "Interface\\Icons\\INV_Mace_04",
    [229] = "Interface\\Icons\\INV_Spear_06",
    [136] = "Interface\\Icons\\INV_Staff_08",
    [173] = "Interface\\Icons\\INV_Weapon_ShortBlade_05",
    [473] = "Interface\\Icons\\INV_Gauntlets_04",
    [45]  = "Interface\\Icons\\INV_Weapon_Bow_05",
    [46]  = "Interface\\Icons\\INV_Weapon_Rifle_01",
    [226] = "Interface\\Icons\\INV_Weapon_Crossbow_01",
    [176] = "Interface\\Icons\\INV_ThrowingKnife_02",
    [228] = "Interface\\Icons\\INV_Wand_01",
    [171] = "Interface\\Icons\\Trade_Alchemy",
    [164] = "Interface\\Icons\\Trade_BlackSmithing",
    [333] = "Interface\\Icons\\Trade_Engraving",
    [202] = "Interface\\Icons\\Trade_Engineering",
    [182] = "Interface\\Icons\\INV_Misc_Flower_02",
    [165] = "Interface\\Icons\\INV_Misc_ArmorKit_17",
    [186] = "Interface\\Icons\\Trade_Mining",
    [393] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    [197] = "Interface\\Icons\\Trade_Tailoring",
    [185] = "Interface\\Icons\\INV_Misc_Food_15",
    [129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    [356] = "Interface\\Icons\\Trade_Fishing",
    [633] = "Interface\\Icons\\Spell_Nature_MoonKey",
}
local ICON_FALLBACK = "Interface\\Icons\\INV_Misc_Book_09"

local FLAT = "Interface\\Buttons\\WHITE8X8"

local PADDING = 2 -- inner padding of the block
local GAP     = 1 -- spacing between bars
local MIN_H, MAX_H = 10, 40 -- height of a single bar
local MIN_W, MAX_W = 80, 500

local DEFAULTS = {
    locked  = false,
    hideMax = false,
    scale   = 1,
    width   = 200,
    height  = 18,
    hidden  = false,
    minimapAngle  = 225,
    minimapHidden = false,
}

-- per character: which skills to show
local CHAR_DEFAULTS = {
    showEquipped = true,
    selected = { [SKILL_DEFENSE] = true },
}

local db, cdb
local block, grip
local bars = {}     -- pool of bar frames, in display order
local lastRank = {} -- skillID -> last seen rank, for the swipe
local FONT, FONT_FLAGS = GameFontHighlightSmall:GetFont(), select(3, GameFontHighlightSmall:GetFont())

local MAX_R, MAX_G, MAX_B = 0.1, 0.8, 0.1 -- green when skill is maxed

---------------------------------------------------------------------------
-- Color: same as skill messages in chat
---------------------------------------------------------------------------

local function SkillColor()
    local c = ChatTypeInfo and ChatTypeInfo.SKILL
    if c and c.r then return c.r, c.g, c.b end
    return 0.333, 0.333, 1.0
end

-- Red below 1/3, yellow below 2/3, blue above, green at max.
-- Inside each band the color gets brighter as the value grows.
local RED    = { 1.0, 0.15, 0.10 }
local YELLOW = { 1.0, 0.80, 0.00 }

local function BarColor(rank, maxRank)
    if rank >= maxRank then return MAX_R, MAX_G, MAX_B end
    local pct = rank / maxRank
    local base, t
    if pct < 1 / 3 then
        base, t = RED, pct * 3
    elseif pct < 2 / 3 then
        base, t = YELLOW, (pct - 1 / 3) * 3
    else
        local r, g, b = SkillColor()
        base, t = { r, g, b }, (pct - 2 / 3) * 3
    end
    local k = 0.55 + 0.45 * t
    return base[1] * k, base[2] * k, base[3] * k
end

---------------------------------------------------------------------------
-- API helpers (with fallbacks)
---------------------------------------------------------------------------

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- Languages are left out of the menu (category 10, plus known IDs as a fallback)
local LANGUAGE_CATEGORY = 10
local LANGUAGE_IDS = {
    [98] = true, [109] = true, [111] = true, [113] = true, [115] = true, [137] = true,
    [138] = true, [139] = true, [140] = true, [141] = true, [313] = true, [315] = true, [673] = true,
}
local function IsLanguage(info)
    return info.skillLineCategoryID == LANGUAGE_CATEGORY or LANGUAGE_IDS[info.skillID] == true
end

-- All skill lines the character has, in skill-window order.
-- Each entry: { info = SkillLineAttributes, category = header name }
local function GetAllSkills()
    local list = {}
    if not (C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo) then
        return list
    end
    local category
    local byID, byName = {}, {}
    for i = 1, C_SkillInfo.GetNumSkillLines() do
        local info = C_SkillInfo.GetSkillLineInfo(i)
        if info then
            if info.isHeader then
                category = info.name
            elseif info.maxRank and info.maxRank > 1 -- skip 1/1 proficiencies
                and not IsLanguage(info)
                and not byID[info.skillID] then
                -- some skills (Cooking, First Aid, Fishing) come back twice with
                -- the same name: keep one, preferring the most advanced line
                local key = (category or "") .. "\0" .. (info.name or "")
                local existing = byName[key]
                if existing then
                    if info.maxRank > existing.info.maxRank
                        or (info.maxRank == existing.info.maxRank and info.rank > existing.info.rank) then
                        existing.info = info
                    end
                else
                    local entry = { info = info, category = category }
                    list[#list + 1] = entry
                    byName[key] = entry
                end
                byID[info.skillID] = true
            end
        end
    end
    return list
end

local function GetSkill(skillID)
    if not C_SkillInfo then return nil end
    if C_SkillInfo.GetSkillLineInfoByID then
        local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, skillID)
        if ok and type(info) == "table" and info.rank then
            return info
        end
    end
    for _, s in ipairs(GetAllSkills()) do
        if s.info.skillID == skillID then return s.info end
    end
end

-- skillID and icon of the weapon in a slot (nil if not a weapon)
local function WeaponSkillForSlot(slot)
    local itemID = GetInventoryItemID("player", slot)
    if not itemID then return nil end
    local _, _, _, _, icon, classID, subclassID = GetItemInfoInstant(itemID)
    if classID ~= 2 then return nil end -- shields, off-hand items, etc.
    local skillID = SUBCLASS_TO_SKILL[subclassID]
    if not skillID then return nil end
    return skillID, icon
end

---------------------------------------------------------------------------
-- Block
---------------------------------------------------------------------------

local Layout, OnLiveResize, Update, RefreshMenu, CreateMinimapButton, PlaySwipe

local function SavePosition()
    local point, _, relPoint, x, y = block:GetPoint()
    db.pos = { point, relPoint, x, y }
end

local function ApplyPosition()
    block:ClearAllPoints()
    local p = db.pos
    if p and p[1] then
        block:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        block:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    end
end

local function ShowTooltip(self)
    local d = self.data
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(d.name, SkillColor())
    if self.label then GameTooltip:AddLine(self.label, 0.7, 0.7, 0.7) end
    GameTooltip:AddDoubleLine("Level", ("%d / %d"):format(d.rank, d.maxRank), 1, 1, 1, 1, 1, 1)
    if d.modifier and d.modifier ~= 0 then
        GameTooltip:AddDoubleLine("Bonus", ("%+d"):format(d.modifier), 1, 1, 1, 0.2, 1, 0.2)
    end
    local missing = d.maxRank - d.rank
    if missing > 0 then
        GameTooltip:AddDoubleLine("Remaining", missing, 1, 1, 1, 1, 0.8, 0)
    else
        GameTooltip:AddLine("Maxed for your level", 0.2, 1, 0.2)
    end
    if not db.locked then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Drag to move. /sb lock to lock.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

-- Bars forward dragging to the block
local function DragStart() if not db.locked then block:StartMoving() end end
local function DragStop()
    block:StopMovingOrSizing()
    SavePosition()
end

local function CreateBar()
    local f = CreateFrame("Frame", nil, block)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", DragStart)
    f:SetScript("OnDragStop", DragStop)
    f:SetScript("OnEnter", ShowTooltip)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT")
    f.icon:SetPoint("BOTTOMLEFT")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", GAP, 0)
    f.bar:SetPoint("BOTTOMRIGHT")
    f.bar:SetStatusBarTexture(FLAT)

    -- bar background (empty part)
    f.track = f.bar:CreateTexture(nil, "BACKGROUND")
    f.track:SetAllPoints()
    f.track:SetTexture(FLAT)

    -- swipe when the skill goes up: a soft light band sliding left to right
    f.bar:SetClipsChildren(true)
    f.shine = CreateFrame("Frame", nil, f.bar)
    f.shine:SetPoint("TOPRIGHT", f.bar, "TOPLEFT")
    f.shine:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMLEFT")
    f.shine:SetWidth(40)
    f.shine:SetFrameLevel(f.bar:GetFrameLevel() + 1)
    f.shine:Hide()
    local left = f.shine:CreateTexture(nil, "OVERLAY")
    left:SetTexture(FLAT)
    left:SetBlendMode("ADD")
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMRIGHT", f.shine, "BOTTOM")
    left:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.55))
    local right = f.shine:CreateTexture(nil, "OVERLAY")
    right:SetTexture(FLAT)
    right:SetBlendMode("ADD")
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMLEFT", f.shine, "BOTTOM")
    right:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0.55), CreateColor(1, 1, 1, 0))

    local ag = f.shine:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    f.swipeMove = ag:CreateAnimation("Translation")
    f.swipeMove:SetDuration(0.7)
    f.swipeMove:SetSmoothing("IN_OUT")
    ag:SetScript("OnPlay", function() f.shine:Show() end)
    ag:SetScript("OnStop", function() f.shine:Hide() end)
    f.swipeAnim = ag

    -- text above the swipe
    f.textLayer = CreateFrame("Frame", nil, f.bar)
    f.textLayer:SetAllPoints()
    f.textLayer:SetFrameLevel(f.shine:GetFrameLevel() + 1)

    f.name = f.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.name:SetPoint("LEFT", 4, 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetShadowOffset(1, -1)

    f.value = f.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.value:SetPoint("RIGHT", -4, 0)
    f.value:SetJustifyH("RIGHT")
    f.value:SetShadowOffset(1, -1)
    f.name:SetPoint("RIGHT", f.value, "LEFT", -4, 0)

    f:Hide()
    return f
end

local function CreateBlock()
    block = CreateFrame("Frame", "SkillsBarsBlock", UIParent)
    block:SetClampedToScreen(true)
    block:SetMovable(true)
    block:EnableMouse(true)
    block:RegisterForDrag("LeftButton")
    block:SetScript("OnDragStart", DragStart)
    block:SetScript("OnDragStop", DragStop)

    local bg = block:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)

    -- resize grip (bottom-right corner)
    block:SetResizable(true)
    grip = CreateFrame("Button", nil, block)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", 0, 0)
    grip:SetFrameLevel(block:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        if db.locked then return end
        block.sizing = true
        block:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        if not block.sizing then return end
        block:StopMovingOrSizing()
        block.sizing = false
        SavePosition()
        Layout()
    end)
    block:SetScript("OnSizeChanged", function(self, w, h)
        if self.sizing then OnLiveResize(w, h) end
    end)

    ApplyPosition()
end

-- Stack the visible bars using the current size
local function PlaceBars(width, height)
    local shown = 0
    local fontSize = math.max(8, math.floor(height * 0.6 + 0.5))
    for _, f in ipairs(bars) do
        f:SetSize(width - PADDING * 2, height)
        f.icon:SetWidth(height)
        f.name:SetFont(FONT, fontSize, FONT_FLAGS)
        f.value:SetFont(FONT, fontSize, FONT_FLAGS)
        if f:IsShown() then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", block, "TOPLEFT", PADDING, -PADDING - shown * (height + GAP))
            shown = shown + 1
        end
    end
    return shown
end

local function BlockHeight(n, h)
    return PADDING * 2 + n * h + (n - 1) * GAP
end

local function SetBounds(n)
    local minW, minH, maxW, maxH = MIN_W, BlockHeight(n, MIN_H), MAX_W, BlockHeight(n, MAX_H)
    if block.SetResizeBounds then
        block:SetResizeBounds(minW, minH, maxW, maxH)
    else
        block:SetMinResize(minW, minH)
        block:SetMaxResize(maxW, maxH)
    end
end

local function CountShown()
    local n = 0
    for _, f in ipairs(bars) do if f:IsShown() then n = n + 1 end end
    return n
end

-- While dragging the grip: free width, height split across bars
function OnLiveResize(w, h)
    local n = math.max(1, CountShown())
    db.width = math.floor(math.max(MIN_W, math.min(MAX_W, w)) + 0.5)
    db.height = math.floor(math.max(MIN_H, math.min(MAX_H, (h - PADDING * 2 - (n - 1) * GAP) / n)) + 0.5)
    PlaceBars(w, db.height)
end

-- Stack only visible bars, without gaps, and resize the block
function Layout()
    block:SetScale(db.scale)
    grip:SetShown(not db.locked)
    local shown = PlaceBars(db.width, db.height)
    if shown == 0 or db.hidden then
        block:Hide()
    else
        SetBounds(shown)
        if not block.sizing then
            block:SetSize(db.width, BlockHeight(shown, db.height))
        end
        block:Show()
    end
end

local SWIPE_TIME = 2.1 -- seconds (3 passes)

function PlaySwipe(f)
    local w = f.bar:GetWidth()
    local sw = math.max(20, w * 0.35)
    f.shine:SetWidth(sw)
    f.swipeMove:SetOffset(w + sw, 0)
    f.swipeAnim:Stop()
    f.shine:Show()
    f.swipeAnim:Play()
    f.swipeToken = (f.swipeToken or 0) + 1
    local token = f.swipeToken
    C_Timer.After(SWIPE_TIME, function()
        if f.swipeToken == token then f.swipeAnim:Stop() end
    end)
end

-- Fill bar f with a skill; returns true if the bar is shown
local function SetBar(f, info, icon, label)
    if not info or not info.maxRank or info.maxRank <= 0
        or (db.hideMax and info.rank >= info.maxRank) then
        f.data = nil
        f:Hide()
        return false
    end

    local skillID = info.skillID
    local r, g, b = BarColor(info.rank, info.maxRank)

    -- swipe only if this bar was already showing the same skill
    local prev = lastRank[skillID]
    if prev and info.rank > prev and f.skillID == skillID then
        PlaySwipe(f)
    end
    lastRank[skillID] = info.rank

    f.skillID, f.data, f.label = skillID, info, label
    f.icon:SetTexture(icon or SKILL_ICONS[skillID] or ICON_FALLBACK)
    f.bar:SetMinMaxValues(0, info.maxRank)
    f.bar:SetValue(info.rank)
    f.bar:SetStatusBarColor(r, g, b)
    f.track:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, 1)

    f.name:SetText(info.name)
    local mod = (info.modifier and info.modifier ~= 0) and (" |cff33ff33%+d|r"):format(info.modifier) or ""
    f.value:SetText(("%d/%d%s"):format(info.rank, info.maxRank, mod))
    f:Show()
    return true
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

function Update()
    if not db then return end

    -- what to show, in order
    local entries, seen = {}, {}
    local function add(skillID, icon, label)
        if not skillID or seen[skillID] then return end
        seen[skillID] = true
        entries[#entries + 1] = { skillID = skillID, icon = icon, label = label }
    end

    if cdb.showEquipped then
        local mainSkill, mainIcon = WeaponSkillForSlot(16)
        if not mainSkill then mainSkill, mainIcon = SKILL_UNARMED, SKILL_ICONS[SKILL_UNARMED] end
        add(mainSkill, mainIcon, "Main hand")
        add(WeaponSkillForSlot(17), select(2, WeaponSkillForSlot(17)), "Off hand")
        add(WeaponSkillForSlot(18), select(2, WeaponSkillForSlot(18)), "Ranged")
    end

    -- picked skills: Defense first, then skill-window order
    local all = GetAllSkills()
    local byID = {}
    for _, s in ipairs(all) do byID[s.info.skillID] = s end
    if cdb.selected[SKILL_DEFENSE] then add(SKILL_DEFENSE, nil, byID[SKILL_DEFENSE] and byID[SKILL_DEFENSE].category) end
    for _, s in ipairs(all) do
        if cdb.selected[s.info.skillID] then add(s.info.skillID, nil, s.category) end
    end

    -- fill bars
    local used = 0
    for _, e in ipairs(entries) do
        local info = (byID[e.skillID] and byID[e.skillID].info) or GetSkill(e.skillID)
        used = used + 1
        bars[used] = bars[used] or CreateBar()
        if not SetBar(bars[used], info, e.icon, e.label) then
            used = used - 1
        end
    end
    for i = used + 1, #bars do
        bars[i].skillID, bars[i].data = nil, nil
        bars[i]:Hide()
    end

    Layout()
end

local pending = false
local function QueueUpdate()
    if pending then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        Update()
    end)
end

---------------------------------------------------------------------------
-- Weapon tooltips: your current skill / max, with the bar colors
---------------------------------------------------------------------------

-- Tooltips sit on a black background: mix colors toward white and skip the
-- dark end of the shading so text stays readable.
local function Lighten(amount, r, g, b)
    return r + (1 - r) * amount, g + (1 - g) * amount, b + (1 - b) * amount
end

local function TooltipColor(rank, maxRank)
    if rank >= maxRank then return MAX_R, MAX_G, MAX_B end
    local pct = rank / maxRank
    local base, t
    if pct < 1 / 3 then
        base, t = RED, pct * 3
    elseif pct < 2 / 3 then
        base, t = YELLOW, (pct - 1 / 3) * 3
    else
        local r, g, b = SkillColor()
        base, t = { r, g, b }, (pct - 2 / 3) * 3
    end
    local k = 0.85 + 0.15 * t
    return base[1] * k, base[2] * k, base[3] * k
end

local function AddWeaponSkillLine(tooltip, item)
    if not item or not tooltip or not tooltip.AddDoubleLine then return end
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(item)
    if classID ~= 2 then return end
    local skillID = SUBCLASS_TO_SKILL[subclassID]
    if not skillID then return end

    local info = GetSkill(skillID)
    local lr, lg, lb = Lighten(0.45, SkillColor())
    if info and info.maxRank and info.maxRank > 0 then
        local r, g, b = Lighten(0.35, TooltipColor(info.rank, info.maxRank))
        local right = ("%d / %d"):format(info.rank, info.maxRank)
        if info.modifier and info.modifier ~= 0 then
            right = right .. (" |cff33ff33%+d|r"):format(info.modifier)
        end
        tooltip:AddDoubleLine(info.name, right, lr, lg, lb, r, g, b)
    else
        local r, g, b = Lighten(0.35, RED[1], RED[2], RED[3])
        tooltip:AddDoubleLine("Weapon skill", "Not learned", lr, lg, lb, r, g, b)
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if not db then return end
        local item = data and data.id
        if not item and tooltip.GetItem then
            item = select(2, tooltip:GetItem())
        end
        AddWeaponSkillLine(tooltip, item)
    end)
else
    local function hook(tooltip)
        if not db or not tooltip.GetItem then return end
        AddWeaponSkillLine(tooltip, select(2, tooltip:GetItem()))
    end
    GameTooltip:HookScript("OnTooltipSetItem", hook)
    if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", hook) end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        SkillsBarsDB = SkillsBarsDB or {}
        db = SkillsBarsDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        SkillsBarsCharDB = SkillsBarsCharDB or {}
        cdb = SkillsBarsCharDB
        if cdb.showEquipped == nil then cdb.showEquipped = CHAR_DEFAULTS.showEquipped end
        if cdb.selected == nil then
            cdb.selected = {}
            for k, v in pairs(CHAR_DEFAULTS.selected) do cdb.selected[k] = v end
        end

        CreateBlock()
        CreateMinimapButton()
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        self:RegisterEvent("SKILL_LINES_CHANGED")
        self:RegisterEvent("CHAT_MSG_SKILL")
        self:RegisterEvent("PLAYER_LEVEL_UP")
        return
    end
    QueueUpdate()
    if RefreshMenu then RefreshMenu() end
end)

---------------------------------------------------------------------------
-- Minimap button and menu
---------------------------------------------------------------------------

local menu, minimapButton
local MENU_W, ROW_H, TITLE_H = 210, 18, 20

local function SetPanelShown(show)
    db.hidden = not show
    Layout()
end

local function TestSwipe()
    for _, f in ipairs(bars) do
        if f:IsShown() then PlaySwipe(f) end
    end
end

local function SetScale(v)
    db.scale = math.max(0.5, math.min(2, math.floor(v * 10 + 0.5) / 10))
    Layout()
end

local function UpdateMinimapPosition()
    local a = math.rad(db.minimapAngle)
    local r = Minimap:GetWidth() / 2 + 5
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function SetMinimapShown(show)
    db.minimapHidden = not show
    minimapButton:SetShown(show)
    if not show then
        if menu then menu:Hide() end
        print("|cff66ccffSkillsBars|r: minimap button hidden, type /sb minimap to bring it back.")
    end
end

local function ToggleSkill(skillID)
    cdb.selected[skillID] = not cdb.selected[skillID] or nil
    Update()
end

-- Menu content, rebuilt every time the menu opens or changes
local function BuildMenuItems()
    local items = {
        { kind = "check", text = "Show panel",        get = function() return not db.hidden end, set = function() SetPanelShown(db.hidden) end },
        { kind = "check", text = "Lock panel",        get = function() return db.locked end,     set = function() db.locked = not db.locked; Layout() end },
        { kind = "check", text = "Hide maxed skills", get = function() return db.hideMax end,    set = function() db.hideMax = not db.hideMax; Update() end },
        { kind = "header", text = "Skills" },
        { kind = "check", text = "Always show equipped weapons", get = function() return cdb.showEquipped end,
          set = function() cdb.showEquipped = not cdb.showEquipped; Update() end },
    }

    local all = GetAllSkills()
    local defense
    for _, s in ipairs(all) do
        if s.info.skillID == SKILL_DEFENSE then defense = s end
    end
    if defense then
        items[#items + 1] = { kind = "check", text = defense.info.name, indent = true,
            get = function() return cdb.selected[SKILL_DEFENSE] end, set = function() ToggleSkill(SKILL_DEFENSE) end }
    end

    local lastCategory
    for _, s in ipairs(all) do
        local id = s.info.skillID
        if id ~= SKILL_DEFENSE then
            if s.category and s.category ~= lastCategory then
                items[#items + 1] = { kind = "subheader", text = s.category }
                lastCategory = s.category
            end
            items[#items + 1] = { kind = "check", text = s.info.name, indent = true,
                get = function() return cdb.selected[id] end, set = function() ToggleSkill(id) end }
        end
    end
    if #all == 0 then
        items[#items + 1] = { kind = "subheader", text = "No skills found" }
    end

    items[#items + 1] = { kind = "header", text = " " }
    items[#items + 1] = { kind = "action", text = "Test swipe",          func = TestSwipe }
    items[#items + 1] = { kind = "action", text = "Hide minimap button", func = function() SetMinimapShown(false) end }
    return items
end

local function AcquireRow(i)
    local row = menu.rows[i]
    if row then return row end

    row = CreateFrame("Button", nil, menu)
    row:SetHeight(ROW_H)
    row:SetPoint("LEFT", 4, 0)
    row:SetPoint("RIGHT", -4, 0)

    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.08)

    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetSize(10, 10)
    row.check:SetTexture(FLAT)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetJustifyH("LEFT")
    row.text:SetPoint("RIGHT", -4, 0)

    row:SetScript("OnClick", function(self)
        local item = self.item
        if not item then return end
        if item.kind == "check" then item.set() elseif item.kind == "action" then item.func() end
        RefreshMenu()
    end)

    menu.rows[i] = row
    return row
end

function RefreshMenu()
    if not menu or not menu:IsShown() then return end
    local r, g, b = SkillColor()
    local items = BuildMenuItems()
    local y = -TITLE_H

    for i, item in ipairs(items) do
        local row = AcquireRow(i)
        row.item = item
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, y)
        row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, y)
        row.text:SetText(item.text)
        row.text:ClearAllPoints()
        row.text:SetPoint("RIGHT", -4, 0)

        local left = item.indent and 18 or 6
        if item.kind == "check" then
            row.check:Show()
            row.check:ClearAllPoints()
            row.check:SetPoint("LEFT", left, 0)
            if item.get() then
                row.check:SetVertexColor(r, g, b, 1)
            else
                row.check:SetVertexColor(0.25, 0.25, 0.25, 1)
            end
            row.text:SetPoint("LEFT", row.check, "RIGHT", 8, 0)
            row.text:SetTextColor(1, 1, 1)
            row:EnableMouse(true)
            row.hl:Show()
        elseif item.kind == "action" then
            row.check:Hide()
            row.text:SetPoint("LEFT", 6, 0)
            row.text:SetTextColor(1, 1, 1)
            row:EnableMouse(true)
            row.hl:Show()
        else -- header / subheader
            row.check:Hide()
            row.text:SetPoint("LEFT", item.kind == "subheader" and 10 or 6, 0)
            if item.kind == "header" then
                row.text:SetTextColor(r, g, b)
            else
                row.text:SetTextColor(0.6, 0.6, 0.6)
            end
            row:EnableMouse(false)
            row.hl:Hide()
        end
        row:Show()
        y = y - ROW_H
    end
    for i = #items + 1, #menu.rows do
        menu.rows[i].item = nil
        menu.rows[i]:Hide()
    end
    menu:SetHeight(-y + 6)
end

local function CreateMenu()
    menu = CreateFrame("Frame", "SkillsBarsMenu", UIParent)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetWidth(MENU_W)
    menu.rows = {}

    local bg = menu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.92)

    local accent = menu:CreateTexture(nil, "BORDER")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("TOPRIGHT")
    accent:SetHeight(2)
    accent:SetTexture(FLAT)
    accent:SetVertexColor(SkillColor())

    local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("SkillsBars")
    title:SetTextColor(SkillColor())

    menu:SetScript("OnShow", RefreshMenu)
    menu:Hide()
    tinsert(UISpecialFrames, "SkillsBarsMenu") -- Esc closes it

    -- close when clicking anywhere else
    if pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN") then
        menu:SetScript("OnEvent", function(self)
            if self:IsShown() and not self:IsMouseOver() and not minimapButton:IsMouseOver() then
                self:Hide()
            end
        end)
    end
end

local function ToggleMenu()
    if not menu then CreateMenu() end
    if menu:IsShown() then
        menu:Hide()
        return
    end
    menu:ClearAllPoints()
    local _, y = minimapButton:GetCenter()
    if y and y > UIParent:GetHeight() / 2 then
        menu:SetPoint("TOPRIGHT", minimapButton, "BOTTOMLEFT", 4, 4)
    else
        menu:SetPoint("BOTTOMRIGHT", minimapButton, "TOPLEFT", 4, -4)
    end
    menu:Show()
end

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

function CreateMinimapButton()
    local b = CreateFrame("Button", "SkillsBarsMinimapButton", Minimap)
    minimapButton = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\Icons\\INV_Sword_04")

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            db.minimapAngle = math.deg(atan2(cy / scale - my, cx / scale - mx))
            UpdateMinimapPosition()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            SetPanelShown(db.hidden)
            RefreshMenu()
        else
            ToggleMenu()
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("SkillsBars", SkillColor())
        GameTooltip:AddLine("Left-click: menu", 1, 1, 1)
        GameTooltip:AddLine("Right-click: show/hide panel", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdateMinimapPosition()
    b:SetShown(not db.minimapHidden)
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------

local function Print(msg)
    print("|cff66ccffSkillsBars|r: " .. msg)
end

local function HandleSlash(msg)
    local cmd, arg = (msg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "lock" then
        db.locked = true
        Layout()
        Print("block locked.")
    elseif cmd == "unlock" then
        db.locked = false
        Layout()
        Print("block unlocked: drag to move, use the bottom-right corner to resize.")
    elseif cmd == "reset" then
        db.pos = nil
        ApplyPosition()
        Print("position reset.")
    elseif cmd == "scale" and tonumber(arg) then
        SetScale(tonumber(arg))
        Print(("scale %.2f"):format(db.scale))
    elseif cmd == "width" and tonumber(arg) then
        db.width = math.max(MIN_W, math.min(MAX_W, tonumber(arg)))
        Layout()
        Print("width " .. db.width)
    elseif cmd == "height" and tonumber(arg) then
        db.height = math.max(MIN_H, math.min(MAX_H, tonumber(arg)))
        Layout()
        Print("height " .. db.height)
    elseif cmd == "test" then
        TestSwipe()
    elseif cmd == "show" then
        SetPanelShown(true)
    elseif cmd == "hide" then
        SetPanelShown(false)
    elseif cmd == "toggle" then
        SetPanelShown(db.hidden)
    elseif cmd == "minimap" then
        SetMinimapShown(db.minimapHidden)
    elseif cmd == "menu" then
        ToggleMenu()
    elseif cmd == "hidemax" then
        db.hideMax = not db.hideMax
        Print("hide maxed skills: " .. (db.hideMax and "yes" or "no"))
        Update()
    else
        Print("commands:")
        print("  /sb menu           - open the menu (pick skills here)")
        print("  /sb show | hide | toggle - show/hide the panel")
        print("  /sb minimap        - show/hide the minimap button")
        print("  /sb lock | unlock  - lock/unlock dragging and resizing")
        print("  /sb reset          - default position")
        print("  /sb scale 0.5-2    - scale")
        print("  /sb width N | height N")
        print("  /sb hidemax        - hide skills that are already maxed")
        print("  /sb test           - preview the swipe")
    end
end

SLASH_SKILLSBARS1 = "/skillsbars"
SLASH_SKILLSBARS2 = "/sb"
SlashCmdList.SKILLSBARS = function(msg)
    HandleSlash(msg)
    RefreshMenu()
end
