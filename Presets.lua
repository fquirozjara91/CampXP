-- Predeterminados por spec (End Game): los consumibles recomendados para cada clase/spec,
-- según la guía de consumibles de WoW Forever. El jugador elige la spec a mano (clic derecho
-- en el ícono de Consumibles): las builds híbridas hacen poco fiable adivinarla.
--
--   tier 1 = Casual (lo básico: comida, venenos)
--   tier 2 = Gamer (+ elixires principales)
--   tier 3 = Hardcore (+ pergamino y frasco)
--   kind   = "food" (grilla de comida) o "cons" (consumibles)
--
-- Pociones, runas y componentes no van: duran poco o no son buffs (CampXP vigila 15 min o más).
-- IDs verificados en wowhead.com/forever (nov 2026).
local ADDON, ns = ...
local L = ns.L

local function F(id, tier) return { id = id, tier = tier or 1, kind = "food" } end
local function C(id, tier) return { id = id, tier = tier, kind = "cons" } end

-- Ítems
local SAGES_TEA, TURTLE_STEW, FLANK, DUMPLINGS, LOBSTER = 249870, 250068, 250069, 20452, 13933
local CLERIC, OWL, GMAGEBLOOD, WHALE = 250333, 250337, 250341, 250348
local MONGOOSE, FIREWATER, GRIZZLY, PHALANX, BRUTE = 13452, 12820, 250351, 250329, 13453
local HOLY, NATURE, GARCANE, SHADOW = 21546, 250343, 13454, 9264
local SCROLL_AGI, SCROLL_STR = 10309, 10310
local TITANS, WISDOM, SUPREME = 13510, 13511, 13512
local INSTANT6 = 8928

local HEALER = { F(SAGES_TEA), C(CLERIC, 2), C(OWL, 2), C(GMAGEBLOOD, 2), C(WHALE, 2), C(WISDOM, 3) }
local CASTER = function(power) return { F(LOBSTER), C(power, 2), C(GARCANE, 2), C(SUPREME, 3) } end
local TANK = { F(TURTLE_STEW), C(PHALANX, 2), C(TITANS, 3) }

ns.PRESETS = {
    HUNTER = {
        { key = "all", name = L["All specs"],
          items = { F(FLANK), C(MONGOOSE, 2), C(SCROLL_AGI, 3), C(TITANS, 3) } },
    },
    PALADIN = {
        { key = "holy", name = L["Holy"], items = HEALER },
        { key = "prot", name = L["Protection"], items = TANK },
        { key = "ret", name = L["Retribution"],
          items = { F(DUMPLINGS), C(GRIZZLY, 2), C(HOLY, 2), C(TITANS, 3) } },
    },
    SHAMAN = {
        { key = "resto", name = L["Restoration"], items = HEALER },
        { key = "enh", name = L["Enhancement"],
          items = { F(DUMPLINGS), C(GRIZZLY, 2), C(FIREWATER, 2), C(TITANS, 3) } },
        { key = "ele", name = L["Elemental"], items = CASTER(NATURE) },
    },
    WARRIOR = {
        { key = "prot", name = L["Protection"],
          items = { F(TURTLE_STEW), C(PHALANX, 2), C(BRUTE, 2), C(TITANS, 3) } },
        { key = "dps", name = L["Arms / Fury"],
          items = { F(DUMPLINGS), C(GRIZZLY, 2), C(FIREWATER, 2), C(SCROLL_STR, 3), C(TITANS, 3) } },
    },
    MAGE = {
        { key = "all", name = L["All specs"],
          items = { F(LOBSTER), C(OWL, 2), C(GARCANE, 2), C(SUPREME, 3) } },
    },
    DRUID = {
        { key = "resto", name = L["Restoration"], items = HEALER },
        { key = "bear", name = L["Bear (tank)"], items = TANK },
        { key = "cat", name = L["Cat"],
          items = { F(FLANK), C(MONGOOSE, 2), C(FIREWATER, 2), C(TITANS, 3) } },
        { key = "balance", name = L["Balance"], items = CASTER(NATURE) },
    },
    PRIEST = {
        { key = "holy", name = L["Holy / Discipline"], items = HEALER },
        { key = "shadow", name = L["Shadow"], items = CASTER(SHADOW) },
    },
    WARLOCK = {
        { key = "all", name = L["All specs"], items = CASTER(SHADOW) },
    },
    ROGUE = {
        { key = "all", name = L["All specs"],
          items = { F(FLANK), C(INSTANT6, 1), C(MONGOOSE, 2), C(FIREWATER, 2), C(SCROLL_AGI, 3), C(TITANS, 3) } },
    },
}

ns.PRESET_TIERS = {
    { tier = 1, name = L["Casual"], desc = L["the basics"] },
    { tier = 2, name = L["Gamer"], desc = L["+ the main elixirs"] },
    { tier = 3, name = L["Hardcore"], desc = L["everything + flask"] },
}

local function Settings()
    local eg = ns.cdb and ns.cdb.endgame
    if not eg then return {} end
    eg.preset = eg.preset or { tier = 2 }
    return eg.preset
end

-- Specs de la clase del personaje
function ns:PresetSpecs()
    local _, class = UnitClass("player")
    return ns.PRESETS[class or ""] or {}
end

-- Spec activa (solo en End Game) o nil
function ns:ActivePreset()
    if not self:IsEndgame() then return nil end
    local key = Settings().spec
    if not key then return nil end
    for _, s in ipairs(self:PresetSpecs()) do
        if s.key == key then return s end
    end
end

function ns:PresetTier() return Settings().tier or 2 end

function ns:SetPreset(spec, tier)
    local st = Settings()
    if spec ~= nil then st.spec = (spec ~= false) and spec or nil end
    if tier then st.tier = tier end
    self:FullUpdate()
    if self.Display and self.Display.picker and self.Display.picker:IsShown() and not InCombatLockdown() then
        self.Display:BuildPicker()
    end
end

-- Nivel mínimo del ítem (nil si aún no cargó)
local function MinLevel(id)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local ok, _, _, _, _, minLevel = pcall(fn, id)
    if ok then return minLevel end
end

-- Ítems del predeterminado activo de un tipo ("food" / "cons"), en orden, que el personaje puede usar
function ns:PresetItems(kind)
    local spec = self:ActivePreset()
    if not spec then return {} end
    local tier, lvl, out = self:PresetTier(), UnitLevel("player") or 60, {}
    for _, e in ipairs(spec.items) do
        if e.kind == kind and e.tier <= tier then
            local need = MinLevel(e.id)
            if not need or need <= lvl then out[#out + 1] = e.id end
        end
    end
    return out
end

-- Conjunto {id = true} del predeterminado activo
function ns:PresetSet(kind)
    local set = {}
    for _, id in ipairs(self:PresetItems(kind)) do set[id] = true end
    return set
end

------------------------------------------------------------------------------
-- Buscar en la casa de subastas (Auctionator si está; si no, la del juego)
------------------------------------------------------------------------------
function ns:AuctionOpen()
    return (AuctionFrame and AuctionFrame:IsShown()) or (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or false
end

function ns:SearchAuction(id)
    local name = ns.GetItemName(id)
    if not name then return end
    if not self:AuctionOpen() then
        self.Print(format(L["Open the Auction House to search for %s."], name))
        return
    end
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.MultiSearchExact and pcall(api.MultiSearchExact, ADDON, { name }) then return end
    if AuctionFrame and AuctionFrame:IsShown() and BrowseName then
        if AuctionFrameTab1 and AuctionFrameTab_OnClick then pcall(AuctionFrameTab_OnClick, AuctionFrameTab1) end
        BrowseName:SetText(name)
        if AuctionFrameBrowse_Search then pcall(AuctionFrameBrowse_Search) end
        return
    end
    local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
    if bar and bar.SearchBox then
        bar.SearchBox:SetText(name)
        if bar.StartSearch then pcall(bar.StartSearch, bar) end
    end
end
