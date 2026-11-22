-- Registro de descubrimientos (solo para el autor: /cxp dev on).
-- Cuando usas un consumible o comes algo que aún no está en Consumables.lua / Foods.lua,
-- se abre una ventana de revisión con lo que se va a anotar (ítem, buff, duración,
-- estadísticas). Guardar lo pasa a CampXPDB.discovered; tools/import_discoveries.py
-- lo lleva después a los archivos del registro.
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
    d.pending = d.pending or {}
    d.reviewed = d.reviewed or {} -- [key] = { kind, id, name, verdict = "saved"|"discarded", date }
    if not d.revMigrated then -- lo guardado antes de existir la lista también figura como revisado
        d.revMigrated = true
        for id, e in pairs(d.cons) do
            d.reviewed["cons:" .. id] = d.reviewed["cons:" .. id] or { kind = "cons", id = id, name = e.name, verdict = "saved", date = e.first }
        end
        for id, e in pairs(d.food) do
            d.reviewed["food:" .. id] = d.reviewed["food:" .. id] or { kind = "food", id = id, name = e.name, verdict = "saved", date = e.first }
        end
        for k, e in pairs(d.pairs) do
            d.reviewed[k] = d.reviewed[k] or { kind = "pair", id = e.item, name = (e.itemName or "?") .. " / " .. (e.lostName or "?"), verdict = "saved", date = e.first }
        end
    end
    return d
end

local function Version()
    local f = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return f and f(ADDON, "Version") or "?"
end

local function Print(msg) ns.Print("|cff66ccff[dev]|r " .. msg) end

local function Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

local function Today() return date("%Y-%m-%d") end

------------------------------------------------------------------------------
-- Cola de revisión: nada se guarda sin pasar por la ventana
------------------------------------------------------------------------------
local ShowReview -- (más abajo)

local function MarkReviewed(p, verdict)
    local e = p.data or {}
    Store().reviewed[p.key] = {
        kind = p.kind, id = p.id or e.item, name = p.title or e.name, verdict = verdict, date = Today(),
    }
end

local function Queue(entry)
    local r = Store().reviewed[entry.key]
    if r and r.verdict == "discarded" then return end -- ya lo descartaste: no volver a preguntar
    local pending = Store().pending
    for i, p in ipairs(pending) do
        if p.key == entry.key then pending[i] = entry; ShowReview() return end
    end
    pending[#pending + 1] = entry
    Print(format("to review: %s", entry.title or entry.key))
    ShowReview()
end

local function Commit(p)
    local d = Store()
    MarkReviewed(p, "saved")
    if p.kind == "cons" then
        local e = p.data
        e.n, e.v, e.first = 1, Version(), e.first or Today()
        d.cons[p.id] = e
        -- si elegiste otro buff a mano, el vínculo del addon también se corrige
        if e.aura and e.picked then ns:SaveItemLink(p.id, e.aura, e.auraName, true) end
        Print(format("saved consumable: %s > %s", e.name or p.id, e.auraName or e.wtext or "?"))
    elseif p.kind == "food" then
        local f = p.data
        f.v, f.first = Version(), f.first or Today()
        d.food[p.id] = f
        Print(format("saved food: %s", f.name or p.id))
    elseif p.kind == "pair" then
        local q = p.data
        q.n, q.v, q.first = 1, Version(), q.first or Today()
        d.pairs[p.key] = q
        Print(format("saved: %s replaces %s", q.itemName or q.item, q.lostName or q.lost))
    end
end

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
    local guess
    for id, link in pairs(ns.db.consLinks or {}) do
        if link.spell == spellId then
            if link.exact then return id end -- un vínculo exacto gana a uno deducido
            guess = guess or id
        end
    end
    return guess
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
                local saved = Store().pairs[key]
                if saved then
                    saved.n = (saved.n or 0) + 1
                else
                    Queue({
                        kind = "pair", key = key, title = (ns.GetItemName(l.item) or l.item) .. " / " .. (r.name or r.spell),
                        data = {
                            item = l.item, itemName = ns.GetItemName(l.item), aura = l.aura, auraName = l.auraName,
                            lost = r.spell, lostName = r.name, lostItem = ItemForAura(r.spell),
                            other = (not r.own) or nil, -- buff de otro jugador (p. ej. de clase)
                        },
                    })
                end
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
    local saved = Store().cons[id]
    -- ya revisado y con el mismo buff: solo se cuenta
    if saved and (saved.aura == info.aura) and (saved.wtext == info.wtext) then
        saved.n = (saved.n or 0) + 1
    else
        local use = ns.ItemUseText and ns.ItemUseText(id)
        Queue({
            kind = "cons", key = "cons:" .. id, id = id, title = ns.GetItemName(id) or tostring(id),
            data = {
                name = ns.GetItemName(id), use = info.use, aura = info.aura, auraName = info.auraName,
                dur = info.dur and info.dur > 0 and math.floor(info.dur + 0.5) or nil,
                weapon = info.weapon, wtext = info.wtext, enchant = info.enchant, group = c and c.key or nil,
                stats = use and (ns.ParseStats(use)) or nil, useText = use,
            },
        })
    end
    if not info.weapon and info.aura then
        table.insert(recentLinks, { t = GetTime(), item = id, aura = info.aura, auraName = info.auraName })
        CheckPairs()
    end
end

------------------------------------------------------------------------------
-- Comidas: al aparecer el Well Fed de una comida que no está en Foods.lua
------------------------------------------------------------------------------
function ns:DiscoverFoodEaten(itemId, spellId, a)
    if not On() or not itemId or not ns.IsFoodItem(itemId) then return end
    if ns.FOOD_DB[itemId] or Store().food[itemId] then return end
    -- unos segundos para que carguen los tooltips del buff y del ítem
    C_Timer.After(3, function()
        local xp, pct = ns:FoodGivesXP(itemId)
        local auraXP, auraPct = ns:TooltipSaysXP(a)
        if auraXP then xp, pct = true, auraPct or pct end
        local wf, stat, _, keys = ns:FoodGivesWellFed(itemId)
        if wf == false then return end -- su tooltip no da Well Fed (p. ej. una bebida)
        local k
        if keys then k = {} for i, v in ipairs(keys) do k[i] = v end end
        Queue({
            kind = "food", key = "food:" .. itemId, id = itemId, title = ns.GetItemName(itemId) or tostring(itemId),
            data = {
                name = ns.GetItemName(itemId), xp = xp and (pct or 5) or false, wf = true, keys = k, stat = stat,
                aura = spellId, auraName = a.name, dur = a.duration and a.duration > 0 and math.floor(a.duration + 0.5) or nil,
                useText = ns.ItemUseText and ns.ItemUseText(itemId),
            },
        })
    end)
end

------------------------------------------------------------------------------
-- Ventana de revisión
------------------------------------------------------------------------------
local W, H = 420, 300
local frame

local function OwnAuras()
    local list = {}
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return list end
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not a then break end
        if not issecret(a.spellId) and not issecret(a.sourceUnit) and a.sourceUnit
            and UnitIsUnit(a.sourceUnit, "player") and (a.duration or 0) > 0 then
            list[#list + 1] = a
        end
    end
    table.sort(list, function(x, y) return (x.name or "") < (y.name or "") end)
    return list
end

local function Line(parent, y, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetWidth(W - 32)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    return fs
end

local function IconRow(parent, y)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetSize(28, 28)
    tex:SetPoint("TOPLEFT", 16, y)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", tex, "RIGHT", 8, 0)
    fs:SetWidth(W - 70)
    fs:SetJustifyH("LEFT")
    return tex, fs
end

local function Fmin(s) return s and format("%d min", math.floor(s / 60 + 0.5)) or "?" end

local function Build()
    local f = CreateFrame("Frame", "CampXPDevReview", UIParent, "BackdropTemplate")
    f:SetSize(W, H)
    f:SetPoint("CENTER", 0, 160)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    f:SetBackdropBorderColor(0.4, 0.8, 1, 1)
    tinsert(UISpecialFrames, "CampXPDevReview")

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -12)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    f.reviewedBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.reviewedBtn:SetSize(110, 20)
    f.reviewedBtn:SetPoint("TOPLEFT", 10, -10)
    f.reviewedBtn:SetScript("OnClick", function() ns:ShowReviewed() end)

    f.kind = Line(f, -38, "GameFontNormal")
    f.itemIcon, f.itemText = IconRow(f, -58)
    f.buffLabel = Line(f, -92, "GameFontNormalSmall")
    f.auraIcon, f.auraText = IconRow(f, -106)
    f.details = Line(f, -142, "GameFontHighlightSmall")
    f.useText = Line(f, -188, "GameFontDisableSmall")

    -- elegir otro buff si el detectado no es el correcto
    local ok, dd = pcall(CreateFrame, "DropdownButton", nil, f, "WowStyle1DropdownTemplate")
    if ok and dd and dd.SetupMenu then
        dd:SetWidth(240)
        dd:SetPoint("BOTTOMLEFT", 16, 46)
        f.pick = dd
        f.pickLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.pickLabel:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 0, 3)
        f.pickLabel:SetText("Wrong buff? Pick the right one:")
    elseif ok and dd then
        dd:Hide()
    end

    local function Btn(text, x, onClick)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(120, 24)
        b:SetPoint("BOTTOM", x, 14)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end
    f.save = Btn("Save", -128, function()
        local pending = Store().pending
        local p = table.remove(pending, 1)
        if p then Commit(p) end
        ShowReview(true)
    end)
    f.discard = Btn("Discard", 0, function()
        local p = table.remove(Store().pending, 1)
        if p then
            MarkReviewed(p, "discarded")
            Print(format("discarded: %s (won't ask again; see Reviewed)", p.title or p.key))
        end
        ShowReview(true)
    end)
    f.later = Btn("Later", 128, function()
        local pending = Store().pending
        if #pending > 1 then table.insert(pending, table.remove(pending, 1)) ShowReview(true)
        else f:Hide() end
    end)
    return f
end

local function Fill(f, p, total)
    local e = p.data
    f.title:SetText(format("|cff66ccffCampXP dev|r — review (1/%d)", total))
    f.reviewedBtn:SetText(format("Reviewed (%d)", Count(Store().reviewed)))
    local kinds = { cons = "New consumable", food = "New food", pair = "Buffs that don't stack" }
    f.kind:SetText(kinds[p.kind] or p.kind)
    local itemId = p.id or e.item
    f.itemIcon:SetTexture(ns.GetItemIcon(itemId) or 134400)
    f.itemText:SetText(format("%s |cffaaaaaa(%d)|r", e.name or e.itemName or ns.GetItemName(itemId) or "?", itemId))

    local auraId, auraName = e.aura, e.auraName
    if p.kind == "pair" then
        f.buffLabel:SetText("Its buff:")
    elseif e.weapon then
        f.buffLabel:SetText("Weapon enchant it applied:")
    else
        f.buffLabel:SetText("Buff it gave you:")
    end
    if e.weapon then
        f.auraIcon:SetTexture(ns.GetItemIcon(itemId) or 134400)
        f.auraText:SetText(format("%s |cffaaaaaa(enchant %s)|r", e.wtext or "?", tostring(e.enchant or "?")))
    else
        f.auraIcon:SetTexture((auraId and ns.GetSpellIcon(auraId)) or 134400)
        f.auraText:SetText(format("%s |cffaaaaaa(%s)|r", auraName or "?", tostring(auraId or "?")))
    end

    local det = {}
    if p.kind == "cons" then
        det[#det + 1] = "Duration: " .. Fmin(e.dur)
        if e.stats then det[#det + 1] = "Stats: " .. e.stats end
        if e.use and e.use ~= e.aura then det[#det + 1] = "Use spell: " .. e.use .. " (differs from buff)" end
        det[#det + 1] = "Group: " .. (e.group and (e.group .. " (unconfirmed)") or "new")
    elseif p.kind == "food" then
        det[#det + 1] = "XP: " .. (e.xp and ("|cff40ff40+" .. e.xp .. "%|r") or "no")
        det[#det + 1] = "Stats: " .. (e.stat or (e.keys and table.concat(e.keys, "/")) or "none detected")
        det[#det + 1] = "Duration: " .. Fmin(e.dur)
    elseif p.kind == "pair" then
        det[#det + 1] = format("It replaced |cffffd100%s|r (%s)", e.lostName or "?", tostring(e.lost))
        det[#det + 1] = e.other and "that buff came from another player (class buff)"
            or ("that buff came from item " .. tostring(e.lostItem and (ns.GetItemName(e.lostItem) or e.lostItem) or "?"))
        det[#det + 1] = "|cffaaaaaaSave only if they really don't stack (not if you cancelled it).|r"
    end
    f.details:SetText(table.concat(det, "\n"))
    f.useText:SetText(e.useText and ns.CleanGameText(e.useText) or "")

    if f.pick then
        local show = p.kind ~= "pair" and not e.weapon
        f.pick:SetShown(show)
        f.pickLabel:SetShown(show)
        if show then
            f.pick:SetupMenu(function(_, root)
                for _, a in ipairs(OwnAuras()) do
                    root:CreateRadio(format("%s (%d) · %s", a.name, a.spellId, Fmin(a.duration)),
                        function() return e.aura == a.spellId end,
                        function()
                            e.aura, e.auraName, e.picked = a.spellId, a.name, true
                            e.dur = math.floor(a.duration + 0.5)
                            Fill(f, p, total)
                        end)
                end
            end)
            if f.pick.OverrideText then
                f.pick:OverrideText(auraName and format("%s (%s)", auraName, tostring(auraId)) or "Pick a buff")
            end
        end
    end
end

ShowReview = function(force)
    if not On() then return end
    local pending = Store().pending
    if #pending == 0 then
        if frame then frame:Hide() end
        return
    end
    if InCombatLockdown() and not force then return end -- se abre al salir de combate
    frame = frame or Build()
    Fill(frame, pending[1], #pending)
    frame:Show()
end

------------------------------------------------------------------------------
-- Ventana "Reviewed": lo ya guardado o descartado (Forget = que vuelva a preguntar)
------------------------------------------------------------------------------
local revFrame
local ROW_H = 26

local function Forget(key)
    local d = Store()
    local r = d.reviewed[key]
    d.reviewed[key] = nil
    if r and r.verdict == "saved" then
        if r.kind == "cons" then d.cons[r.id] = nil
        elseif r.kind == "food" then d.food[r.id] = nil
        elseif r.kind == "pair" then d.pairs[key:gsub("^pair:", "")] = nil end
    end
    Print(format("forgotten: %s (will ask again next time)", r and r.name or key))
end

local function FillReviewed()
    local f = revFrame
    local d = Store()
    local keys = {}
    for k in pairs(d.reviewed) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local x, y = d.reviewed[a], d.reviewed[b]
        if x.date ~= y.date then return (x.date or "") > (y.date or "") end
        return (x.name or "") < (y.name or "")
    end)
    f.title:SetText(format("|cff66ccffCampXP dev|r — reviewed (%d)", #keys))
    f.empty:SetShown(#keys == 0)
    local kinds = { cons = "consumable", food = "food", pair = "don't stack" }
    for i, k in ipairs(keys) do
        local r = d.reviewed[k]
        local row = f.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, f.child)
            row:SetSize(W - 50, ROW_H)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(20, 20)
            row.icon:SetPoint("LEFT", 2, 0)
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.text:SetWidth(W - 160)
            row.text:SetJustifyH("LEFT")
            row.btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.btn:SetSize(60, 20)
            row.btn:SetPoint("RIGHT", -2, 0)
            row.btn:SetText("Forget")
            f.rows[i] = row
        end
        row.icon:SetTexture((r.id and ns.GetItemIcon(r.id)) or 134400)
        local color = r.verdict == "saved" and "|cff40ff40saved|r" or "|cffff6060discarded|r"
        row.text:SetText(format("%s |cffaaaaaa(%s · %s)|r\n%s %s", r.name or k, kinds[r.kind] or r.kind,
            tostring(r.id or "?"), color, r.date or ""))
        row.btn:SetScript("OnClick", function() Forget(k) FillReviewed() if frame and frame:IsShown() then ShowReview(true) end end)
        row:Show()
    end
    for i = #keys + 1, #f.rows do f.rows[i]:Hide() end
    f.child:SetHeight(math.max(1, #keys * ROW_H))
end

function ns:ShowReviewed()
    if not revFrame then
        local f = CreateFrame("Frame", "CampXPDevReviewed", UIParent, "BackdropTemplate")
        f:SetSize(W, 340)
        f:SetPoint("CENTER", W / 2 + 20, 140)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
        f:SetBackdropBorderColor(0.4, 0.8, 1, 1)
        tinsert(UISpecialFrames, "CampXPDevReviewed")
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -12)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", 16, -36)
        hint:SetText("Discarded items are not asked again. Forget = ask again next time.")
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 14, -54)
        sf:SetPoint("BOTTOMRIGHT", -32, 14)
        f.child = CreateFrame("Frame", nil, sf)
        f.child:SetSize(W - 50, 1)
        sf:SetScrollChild(f.child)
        f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        f.empty:SetPoint("CENTER")
        f.empty:SetText("Nothing reviewed yet.")
        f.rows = {}
        revFrame = f
    end
    FillReviewed()
    revFrame:Show()
end

------------------------------------------------------------------------------
-- /cxp dev export: todo lo anotado como texto para copiar y pegar (Discord, etc.)
-- Formato por línea (separador ";", sin "|" que el chat/editbox interpreta):
--   C;item;nombre;hechizoUsar;aura;nombreAura;dur;arma(0/1);textoArma;grupo
--   F;item;nombre;xp;keys(a/b);aura;dur
--   P;item;aura;auraPerdida;nombrePerdida;ítemPerdido;deOtro(0/1);nombreÍtem
--   L;item;aura;nombreAura;textoArma;encantamiento;confirmado(0/1);vecesVisto   (vínculos exactos)
------------------------------------------------------------------------------
local function Clean(v)
    if v == nil or v == false then return "" end
    if v == true then return "1" end
    return (tostring(v):gsub("[;|\n]", " "))
end

local function ExportText()
    local d = Store()
    local out = { format("CampXP-export;%s;%s", Version(), Today()) }
    local function Row(...)
        local t = { ... }
        for i = 1, select("#", ...) do t[i] = Clean(t[i]) end
        out[#out + 1] = table.concat(t, ";")
    end
    for id, e in pairs(d.cons) do
        Row("C", id, e.name, e.use, e.aura, e.auraName, e.dur, e.weapon, e.wtext, e.group)
    end
    for id, f in pairs(d.food) do
        Row("F", id, f.name, f.xp, f.keys and table.concat(f.keys, "/"), f.aura, f.dur)
    end
    for _, p in pairs(d.pairs) do
        Row("P", p.item, p.aura, p.lost, p.lostName, p.lostItem, p.other, p.itemName)
    end
    for id, link in pairs(ns.db.consLinks or {}) do
        if link.exact then
            local n = 0
            for _, c in pairs(link.obs or {}) do if c > n then n = c end end
            Row("L", id, link.spell, link.name, link.wtext, link.enchant, link.conf or link.manual, n > 0 and n or nil)
        end
    end
    return table.concat(out, "\n"), #out - 1
end

local expFrame
function ns:ShowExport()
    local text, n = ExportText()
    if not expFrame then
        local f = CreateFrame("Frame", "CampXPDevExport", UIParent, "BackdropTemplate")
        f:SetSize(460, 320)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
        f:SetBackdropBorderColor(0.4, 0.8, 1, 1)
        tinsert(UISpecialFrames, "CampXPDevExport")
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -12)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 16, -38)
        hint:SetWidth(428)
        hint:SetJustifyH("LEFT")
        hint:SetText("The text is selected: press Ctrl+C, then paste it to the CampXP author (Ctrl+V).")
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 16, -60)
        sf:SetPoint("BOTTOMRIGHT", -34, 16)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(400)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        -- solo lectura: si se edita, vuelve al texto exportado
        eb:SetScript("OnTextChanged", function(self, user)
            if user then self:SetText(f.text or "") self:HighlightText() end
        end)
        eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        sf:SetScrollChild(eb)
        f.eb = eb
        expFrame = f
    end
    expFrame.text = text
    expFrame.title:SetText(format("|cff66ccffCampXP|r export (%d)", n))
    expFrame.eb:SetText(text)
    expFrame:Show()
    expFrame.eb:SetFocus()
    expFrame.eb:HighlightText()
end

------------------------------------------------------------------------------
-- /cxp dev [on|off|review|reviewed|export|list|clear]
------------------------------------------------------------------------------
function ns:DevCommand(arg)
    if arg == "on" or arg == "off" or arg == nil or arg == "" then
        if arg == "on" then ns.db.dev = true
        elseif arg == "off" then ns.db.dev = nil
        else ns.db.dev = not ns.db.dev or nil end
        if On() then Refresh() elseif frame then frame:Hide() end
        Print(On() and "recording discoveries ON (saved on /reload or logout)" or "recording discoveries OFF")
    elseif arg == "review" then
        if #Store().pending == 0 then Print("nothing to review") else ShowReview(true) end
    elseif arg == "export" then
        ns:ShowExport()
    elseif arg == "reviewed" then
        ns:ShowReviewed()
    elseif arg == "list" then
        local d = Store()
        Print(format("saved: consumables %d · non-stacking pairs %d · foods %d · to review %d",
            Count(d.cons), Count(d.pairs), Count(d.food), #d.pending))
        for id, e in pairs(d.cons) do
            print(format("  %s (%d) > %s %s", e.name or "?", id, e.auraName or e.wtext or "?", e.group and ("[" .. e.group .. "]") or "[new]"))
        end
        for _, p in pairs(d.pairs) do
            print(format("  %s replaces %s", p.itemName or p.item, p.lostName or p.lost))
        end
        for id, f in pairs(d.food) do
            print(format("  %s (%d)%s", f.name or "?", id, f.xp and (" +" .. f.xp .. "% XP") or ""))
        end
    elseif arg == "clear" then
        ns.db.discovered = nil
        if frame then frame:Hide() end
        Print("discoveries cleared")
    else
        Print("/cxp dev on | off | review | reviewed | export | list | clear")
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if On() then C_Timer.After(1, function() ShowReview() end) end
        return
    end
    C_Timer.After(5, function()
        if not On() then return end
        Refresh()
        ShowReview() -- lo que quedó pendiente de la sesión anterior
    end)
    C_Timer.NewTicker(10, function()
        Prune(recentLinks)
        Prune(recentDrops)
    end)
end)
