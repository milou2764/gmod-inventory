--[[
    A dead player's body keeps what he carried. His ragdoll (made here, on the server, in the pose
    he died in) wears his gear (helmet, vest, backpack...) and carries his weapons on the body, his
    pockets, vest and backpack still full. The weapon in his hands falls to the ground.

    Anyone within reach opens the body with the Use key: his inventory shows next to theirs.
    Equipped items are taken with a double-click or right-click > Take (they leave the body: the
    helmet taken is no longer on his head), contents are dragged out like from a crate.

        advinv_death_drop 3          0: nothing stays on the body (the player keeps it all)
                                   1: the contents of the uniform, vest and backpack
                                   2: the same and the weapons
                                   3: everything, the worn gear too (default)
        advinv_death_loot_time 300   seconds before the body disappears (0: never, map cleanup only)
        advinv_death_body_max 20     bodies at most: the oldest goes first
        advinv_death_loot_name 1     the dead player's name is shown on his body

    Hooks (server):
        AdvInv_DeathDrop(ply)               return false: nothing stays on the body this time
        AdvInv_DeathBody(ply, body)         after the body got his things

    With a character system (AdvInv_OwnerID), the emptied inventory is saved at once, so
    the next load doesn't give the items back. Without one, the inventory is reset at every spawn.
--]]
local I = AdvInv
local FLAGS = { FCVAR_ARCHIVE, FCVAR_NOTIFY }

util.AddNetworkString("advinv_open_body")

local dropMode = CreateConVar("advinv_death_drop", "3", FLAGS,
    "Left on the body: 0 nothing, 1 the contents of the uniform/vest/backpack, 2 also the weapons, 3 everything", 0, 3)
local lootTime = CreateConVar("advinv_death_loot_time", "300", FLAGS,
    "Seconds before a dead player's body disappears (0: never)", 0)
local bodyMax = CreateConVar("advinv_death_body_max", "20", FLAGS, "Bodies at most (the oldest goes first)", 1, 200)
local showName = CreateConVar("advinv_death_loot_name", "1", FLAGS, "Show the dead player's name on his body", 0, 1)

I.Bodies = I.Bodies or {}

---------------------------------------------------------------- the body

-- Server ragdoll of ply, in the pose he died in, pushed by the hit.
local function makeRagdoll(ply, dmginfo)
    local rag = ents.Create("prop_ragdoll")
    if not IsValid(rag) then return end
    rag:SetModel(ply:GetModel())
    rag:SetPos(ply:GetPos())
    rag:SetAngles(Angle(0, ply:EyeAngles().y, 0))
    rag:SetSkin(ply:GetSkin())
    for k = 0, ply:GetNumBodyGroups() - 1 do rag:SetBodygroup(k, ply:GetBodygroup(k)) end
    -- bodygroups changed for his gear (sv_modelgear.lua): back to his own when it is taken from the body
    rag.AdvInvOwnBodygroups = ply.AdvInvOwnBodygroups and table.Copy(ply.AdvInvOwnBodygroups) or nil
    rag:SetColor(ply:GetColor())
    rag:SetMaterial(ply:GetMaterial())
    rag:Spawn()
    rag:Activate()
    rag:SetCollisionGroup(COLLISION_GROUP_WEAPON) -- players walk through, the Use key finds it
    if rag.SetPlayerColor and ply.GetPlayerColor then rag:SetNWVector("AdvInvPlayerColor", ply:GetPlayerColor()) end
    local vel = ply:GetVelocity()
    local n = rag:GetPhysicsObjectCount()
    for i = 0, n - 1 do
        local phys = rag:GetPhysicsObjectNum(i)
        local m = IsValid(phys) and ply:GetBoneMatrix(rag:TranslatePhysBoneToBone(i))
        if m then
            phys:SetPos(m:GetTranslation())
            phys:SetAngles(m:GetAngles())
            phys:SetVelocity(vel)
            phys:Wake()
        end
    end
    if n == 0 then rag:SetMoveType(MOVETYPE_NONE) end -- a playermodel without ragdoll physics
    if dmginfo and n > 0 then -- the push of the shot, on the part that was hit
        local force, at = dmginfo:GetDamageForce(), dmginfo:GetDamagePosition()
        if force:LengthSqr() > 0 then
            local best, bestD
            for i = 0, n - 1 do
                local phys = rag:GetPhysicsObjectNum(i)
                local d = IsValid(phys) and phys:GetPos():DistToSqr(at)
                if d and (not bestD or d < bestD) then best, bestD = phys, d end
            end
            local len = math.min(force:Length(), 12000)
            if best then best:ApplyForceOffset(force:GetNormalized() * len * 0.5, at) end
        end
    end
    return rag
end

-- Puts an item into a slot of the body (shown on it like on a player).
local function bodySet(body, cat, item)
    body.AdvInvSlots[cat] = item
    if AdvInv.GearCat[cat] then
        body:SetNWInt(cat .. "Armor", item.a or 0)
        body:SetNW2Int(cat, item.id)
    else
        local conf = I.CarryConfig(item.id, item.c)
        local mode = item.m
        if not (mode and I.CARRY_MODES[mode]) then mode = conf and I.CARRY_INDEX[conf.default] or I.CARRY_INDEX.stowed end
        body:SetNWString(cat .. "Class", item.c or "")
        body:SetNWInt(cat .. "Rounds", item.r or 0)
        body:SetNWInt(cat .. "Carry", conf and mode or I.CARRY_INDEX.stowed)
        body:SetNWInt(cat, item.id)
    end
end

-- Empties a slot of the body (the item was taken).
function I.BodyClear(body, cat)
    body.AdvInvSlots[cat] = nil
    if AdvInv.GearCat[cat] then
        if cat == "Vest" or cat == "Rucksack" then I.Set(body, cat, {}) end
        body:SetNWInt(cat .. "Armor", 0)
        body:SetNW2Int(cat, 1)
    else
        body:SetNWInt(cat .. "Carry", I.CARRY_INDEX.stowed)
        body:SetNWString(cat .. "Class", "")
        body:SetNWInt(cat .. "Rounds", 0)
        body:SetNWInt(cat, 1)
    end
end

local function append(list, items)
    for _, it in ipairs(items or {}) do list[#list + 1] = it end
end

-- Moves what advinv_death_drop says from ply to his body; the weapon in his hands falls.
local function transfer(ply, body, mode)
    body.AdvInvSlots = {}
    local held = ply:GetActiveWeapon()
    held = IsValid(held) and held:GetClass() or nil
    if mode >= 3 then
        for _, cont in ipairs(I.PLAYER_CONTAINERS) do
            I.Set(body, cont, I.Get(ply, cont))
            I.Set(ply, cont, {})
        end
    else -- the gear stays with the player: everything carried goes into the body's pockets
        local all = {}
        for _, cont in ipairs(I.PLAYER_CONTAINERS) do
            append(all, I.Get(ply, cont))
            I.Set(ply, cont, {})
        end
        -- past I.MAX_ITEMS the client wouldn't see them (nor could they be taken): on the ground
        for k = #all, I.MAX_ITEMS + 1, -1 do
            I.SpawnItem(table.remove(all, k), body:GetPos() + Vector(math.Rand(-20, 20), math.Rand(-20, 20), 20))
        end
        I.Set(body, "Uniform", all)
    end
    if mode >= 2 then
        for _, cat in ipairs(AdvInv.WeaponCat) do
            local id, c = I.SlotRef(ply, cat)
            if id > 1 then
                local wasHeld = held and I.Info(id, c).weaponClass == held
                local item = I.TakeOff(ply, cat)
                if item and wasHeld then
                    local hand = ply:LookupBone("ValveBiped.Bip01_R_Hand")
                    local pos = hand and ply:GetBonePosition(hand) or ply:GetPos() + Vector(0, 0, 40)
                    local ent = I.SpawnItem(item, pos)
                    local phys = IsValid(ent) and ent:GetPhysicsObject()
                    if IsValid(phys) then phys:SetVelocity(ply:GetVelocity() + VectorRand() * 40) end
                elseif item then
                    bodySet(body, cat, item)
                end
            end
        end
    end
    if mode >= 3 then
        for cat in pairs(AdvInv.GearCat) do
            if I.SlotID(ply, cat) > 1 then
                local item = I.TakeOff(ply, cat)
                if item then bodySet(body, cat, item) end
            end
        end
    end
end

-- Nothing left on a body (looted, or nothing carried)?
function I.BodyEmpty(body)
    if next(body.AdvInvSlots or {}) ~= nil then return false end
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        if #I.Get(body, cont) > 0 then return false end
    end
    return #(body.AdvInvUnknownItems or {}) == 0
end

-- Over the limit: the empty bodies go first, then the oldest.
local function removeOldest()
    local list = {}
    for b in pairs(I.Bodies) do
        if IsValid(b) then list[#list + 1] = b else I.Bodies[b] = nil end
    end
    local empty = {}
    for _, b in ipairs(list) do empty[b] = I.BodyEmpty(b) end
    table.sort(list, function(a, b)
        if empty[a] ~= empty[b] then return empty[a] end
        return (a.AdvInvBorn or 0) < (b.AdvInvBorn or 0)
    end)
    for k = 1, #list - bodyMax:GetInt() do list[k]:Remove() end
end

-- ply's body with his things. -> the body, or nil (nothing left on it: no body of ours).
function I.MakeBody(ply, dmginfo)
    -- a grenade thrown just before: counted now, before the body takes the items (else, this hook
    -- running before the grenades' one, the thrown grenade stayed an item on the body)
    if I.ReconcileGrenades and ply.AdvInvGrenades then I.ReconcileGrenades(ply, true) end
    if I.RemoveJobItems then I.RemoveJobItems(ply) end -- they belong to the job, not to the body
    -- the killing hit's wear on a helmet or a vest (sv_gear.lua writes it after the damage, when the
    -- gear is already on the body): applied now, so the body's gear has it
    local wear = ply.AdvInvArmorWear
    if wear and wear.tick == engine.TickCount() then
        for cat, armor in pairs(wear.cats or {}) do ply:SetNWInt(cat .. "Armor", armor) end
        ply.AdvInvArmorWear = nil
    end
    -- underbarrel launchers' rounds into boxes first: they go to the body with the rest, or stay
    -- his when there is no body (the weapons are given again empty at the respawn)
    for _, cat in ipairs(AdvInv.WeaponCat) do
        local info = I.SlotInfo(ply, cat)
        local wep = info.weaponClass and ply:GetWeapon(info.weaponClass)
        if IsValid(wep) and I.UnloadUnderbarrel then I.UnloadUnderbarrel(ply, wep) end
    end
    local mode = dropMode:GetInt()
    -- what stays on the player is his at the next spawn: only an emptied player is reset
    -- (sv_inventory.lua)
    if mode <= 0 or hook.Run("AdvInv_DeathDrop", ply) == false then return end
    local body = makeRagdoll(ply, dmginfo)
    if not IsValid(body) then return end
    body:SetNWBool("AdvInvBody", true)
    body:SetNWString("AdvInvBodyName", showName:GetBool() and ply:Nick() or "")
    body.AdvInvBorn = CurTime()
    ply.AdvInvLastBody = body -- (a grenade another addon drops at the same death: sv_grenades.lua)
    if lootTime:GetFloat() > 0 then body.AdvInvExpire = CurTime() + lootTime:GetFloat() end
    transfer(ply, body, mode)
    if mode >= 3 then ply.AdvInvResetNextSpawn = true end
    -- the database must not keep a copy of what left him (on the body, or the weapon that fell from
    -- his hands: saved even when the body is left empty)
    local cid = I.GetOwnerID(ply)
    if cid then I.Save(ply, cid) end
    if I.BodyEmpty(body) then -- nothing on it: the gamemode's ragdoll as usual
        body:Remove()
        return
    end
    I.Bodies[body] = true
    body:CallOnRemove("AdvInv_Body", function() I.Bodies[body] = nil end)
    removeOldest()
    hook.Run("AdvInv_DeathBody", ply, body)
    return body
end

hook.Add("DoPlayerDeath", "AdvInv_DeathBody", function(ply, _, dmginfo)
    local body = I.MakeBody(ply, dmginfo)
    if not body then return end
    -- the gamemode makes its own (client) ragdoll after this hook: ours replaces it
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        local rag = ply:GetRagdollEntity()
        if IsValid(rag) then rag:Remove() end
    end)
end)

timer.Create("AdvInv_Bodies", 2, 0, function()
    for body in pairs(I.Bodies) do
        if not IsValid(body) then
            I.Bodies[body] = nil
        elseif body.AdvInvExpire and CurTime() >= body.AdvInvExpire then
            body:Remove()
        end
    end
end)

-- Use key on a body: open it.
hook.Add("PlayerUse", "AdvInv_Bodies", function(ply, ent)
    if not I.IsBody(ent) then return end
    if (ply.AdvInvBodyUse or 0) < CurTime() then
        ply.AdvInvBodyUse = CurTime() + 0.5
        if I.CanAccess(ply, ent) then
            net.Start("advinv_open_body")
            net.WriteEntity(ent)
            net.Send(ply)
        end
    end
    return false -- no physics pickup of the body
end)

---------------------------------------------------------------- taking from a body

-- ACT.LOOT: body, slot. Into the looter's slot if it is free, else into his containers.
I.ActHandlers[I.ACT.LOOT] = function(ply)
    local body, cat = net.ReadEntity(), AdvInv.IDCategory[net.ReadUInt(4)]
    if not (cat and I.IsBody(body) and I.CanAccess(ply, body)) then return end
    local item = body.AdvInvSlots and body.AdvInvSlots[cat]
    if not item then return end
    if cat == "Uniform" and #I.Get(body, "Uniform") > 0 then return false, I.L("body_empty_pockets") end
    local contents = (cat == "Vest" or cat == "Rucksack") and I.Get(body, cat) or nil
    local info = I.Info(item.id, item.c)
    local taken = false
    if I.SlotID(ply, cat) <= 1 then
        taken = I.Equip(ply, item, contents) and true or false
    end
    if not taken then
        if contents and #contents > 0 then return false, I.L("body_empty_first") end
        if not I.Store(ply, item) then return false, I.L("msg_no_room_for", info.name) end
    end
    if taken and contents then body.AdvInvData[cat] = {} end -- the contents went with it
    I.BodyClear(body, cat)
    return true
end
