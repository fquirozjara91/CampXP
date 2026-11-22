-- Registro de descubrimientos (solo para el autor: /cxp dev on).
-- Anota en CampXPDB.discovered lo que el juego confirma y que aún no está en
-- Consumables.lua / Foods.lua: qué buff deja cada consumible al usarlo, qué buff
-- reemplaza a otro (no se acumulan) y qué comidas dan XP o Well Fed.
-- tools/import_discoveries.py lo pasa a los archivos del registro.
local ADDON, ns = ...

local issecret = issecretvalue or function() return false end
local WINDOW = 1.5 -- s entre usar un ítem y que se caiga otro buff

local known = {}       -- auraInstanceID > { spell, name, exp, own }
local recentLinks = {} -- consumibles recién vinculados { t, item, aura, auraName }
local recentDrops = {} -- buffs que se fueron antes de tiempo { t, spell, name, own }

local function On() return ns.db ~= nil and ns.db.dev == true end

local function Store()
    local d = ns.db.discovered
    if type(d) ~= "table" then d = {}; ns.db.discovered = d end
    d.cons, d.food, d.pairs = d.cons or {}, d.food or {}, d.pairs or {}
    return d
end

local function Version()
    local f = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return f and f(ADDON, "Version") or "?"
end

local function Print(msg) ns.Print("|cff66ccff[dev]|r " .. msg) end

local function Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

------------------------------------------------------------------------------
-- Buffs que no se acumulan: usar el ítem B hizo caer el buff A (con tiempo de sobra)
------------------------------------------------------------------------------
local function Prune(list)
    local now = GetTime()
    for i = #list, 1, -1 do
        if now - list[i].t > WINDOW * 2 then table.remove(list, i) end
    end
end

-- ítem vinculado a un aura (para saber de qué consumible era el buff que se cayó)
local function ItemForAura(spellId)
    for id, link in pairs(ns.db.consLinks or {}) do
        if link.spell == spellId then return id end
    end
end

local function CheckPairs()
    Prune(recentLinks)
    Prune(recentDrops)
    for _, l in ipairs(recentLinks) do
        l.done = l.done or {}
        for _, r in ipairs(recentDrops) do
            if not l.done[r] and math.abs(l.t - r.t) <= WINDOW and r.spell ~= l.aura then
                l.done[r] = true
                local key = r.spell .. "-" .. l.item
                local pairsT = Store().pairs
                local p = pairsT[key]
                if not p then
                    p = { first = date("%Y-%m-%d") }
                    pairsT[key] = p
                    Print(format("%s replaced %s (they don't stack)", ns.GetItemName(l.item) or l.item, r.name or r.spell))
                end
                p.item, p.itemName, p.aura, p.auraName = l.item, ns.GetItemName(l.item), l.aura, l.auraName
                p.lost, p.lostName, p.lostItem = r.spell, r.name, ItemForAura(r.spell)
                p.other = (not r.own) or nil -- buff de otro jugador (p. ej. de clase)
                p.n = (p.n or 0) + 1
                p.v = Version()
            end
        end
    end
end

local function Remember(a)
    if not a or issecret(a.spellId) or issecret(a.sourceUnit) or issecret(a.expirationTime) then return end
    if a.isHelpful == false or not a.auraInstanceID then return end
    known[a.auraInstanceID] = {
        spell = a.spellId, name = a.name, exp = a.expirationTime or 0,
        own = a.sourceUnit ~= nil and UnitIsUnit(a.sourceUnit, "player"),
    }
end

local function Refresh()
    wipe(known)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not a then break end
        Remember(a)
    end
end

function ns:DevAuraUpdate(info)
    if not On() or not info then return end
    if info.isFullUpdate then Refresh() return end
    local now = GetTime()
    for _, iid in ipairs(info.removedAuraInstanceIDs or {}) do
        local k = known[iid]
        known[iid] = nil
        -- se fue con más de 30 s por delante: lo reemplazó otro buff (o se canceló)
        if k and k.exp > 0 and k.exp - now > 30 then
            table.insert(recentDrops, { t = now, spell = k.spell, name = k.name, own = k.own })
            CheckPairs()
        end
    end
    for _, a in ipairs(info.addedAuras or {}) do Remember(a) end
    if C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
        for _, iid in ipairs(info.updatedAuraInstanceIDs or {}) do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", iid)
            if ok then Remember(a) end
        end
    end
end

------------------------------------------------------------------------------
-- Consumibles: llamado al vincular un ítem con su buff (o piedra/aceite con su encantamiento)
------------------------------------------------------------------------------
function ns:DiscoverConsumable(id, info)
    if not On() or not id then return end
    local c = ns.CONS_BY_ITEM[id]
    if c and c.confirmed then return end -- ya está confirmado en el registro
    local d = Store().cons
    local e = d[id]
    local isNew = e == nil
    e = e or { first = date("%Y-%m-%d") }
    e.name = ns.GetItemName(id) or e.name
    e.use = info.use or e.use
    e.aura, e.auraName = info.aura or e.aura, info.auraName or e.auraName
    if info.dur and info.dur > 0 then e.dur = math.floor(info.dur + 0.5) end
    e.weapon, e.wtext = info.weapon or e.weapon, info.wtext or e.wtext
    e.group = c and c.key or nil
    local use = ns.ItemUseText and ns.ItemUseText(id)
    if use then e.stats = (ns.ParseStats(use)) or e.stats end
    e.n = (e.n or 0) + 1
    e.v = Version()
    d[id] = e
    if isNew then
        Print(format("new consumable: %s (%d) > %s", e.name or "?", id, e.auraName or e.wtext or "?"))
    end
    if not info.weapon and info.aura then
        table.insert(recentLinks, { t = GetTime(), item = id, aura = info.aura, auraName = info.auraName })
        CheckPairs()
    end
end

------------------------------------------------------------------------------
-- Comidas: las de las bolsas que dan XP o Well Fed y no están en Foods.lua
------------------------------------------------------------------------------
local function ScanFoods()
    if not On() then return end
    local d = Store().food
    for id in pairs(ns.GetBagSnapshot()) do
        if ns.IsFoodItem(id) and not ns.FOOD_DB[id] and not d[id] then
            local xp, pct = ns.FoodXPKnown(id)
            if xp == nil then
                ns:FoodGivesXP(id) -- todavía leyendo el tooltip: se completa en la próxima vuelta
            else
                local wf, _, _, keys = ns:FoodGivesWellFed(id)
                if wf ~= nil and (xp or wf) then
                    local k
                    if keys then k = {} for i, v in ipairs(keys) do k[i] = v end end
                    d[id] = {
                        name = ns.GetItemName(id), xp = xp and (pct or 5) or false,
                        wf = wf or nil, keys = k, first = date("%Y-%m-%d"), v = Version(),
                    }
                    Print(format("new food: %s (%d)%s%s", d[id].name or "?", id,
                        xp and format(" +%d%% XP", pct or 5) or "", k and (" " .. table.concat(k, "/")) or ""))
                end
            end
        end
    end
end

------------------------------------------------------------------------------
-- /cxp dev [on|off|list|clear]
------------------------------------------------------------------------------
function ns:DevCommand(arg)
    if arg == "on" or arg == "off" or arg == nil or arg == "" then
        if arg == "on" then ns.db.dev = true
        elseif arg == "off" then ns.db.dev = nil
        else ns.db.dev = not ns.db.dev or nil end
        if On() then Refresh(); ScanFoods() end
        Print(On() and "recording discoveries ON (saved on /reload or logout)" or "recording discoveries OFF")
    elseif arg == "list" then
        local d = Store()
        Print(format("consumables %d · non-stacking pairs %d · foods %d", Count(d.cons), Count(d.pairs), Count(d.food)))
        for id, e in pairs(d.cons) do
            print(format("  %s (%d) > %s %s", e.name or "?", id, e.auraName or e.wtext or "?", e.group and ("[" .. e.group .. "]") or "[new]"))
        end
        for _, p in pairs(d.pairs) do
            print(format("  %s replaces %s", p.itemName or p.item, p.lostName or p.lost))
        end
        for id, f in pairs(d.food) do
            print(format("  %s (%d)%s", f.name or "?", id, f.xp and " XP" or ""))
        end
    elseif arg == "clear" then
        ns.db.discovered = nil
        Print("discoveries cleared")
    else
        Print("/cxp dev on | off | list | clear")
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    C_Timer.After(5, function() if On() then Refresh() end end)
    C_Timer.NewTicker(10, function()
        if not On() then return end
        pcall(ScanFoods)
        Prune(recentLinks)
        Prune(recentDrops)
    end)
end)
