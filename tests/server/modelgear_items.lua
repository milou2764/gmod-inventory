-- Gear taken from a playermodel's bodygroups (sh_modelgear_items.lua), with the WW1 French extension
-- (addons/advinv-ext-ww1-french) and its playermodels' models on the server. Needs a bot. Asynchronous
-- (the item dropped on the ground settles): run with ASYNC.
local I, C = AdvInv, AdvInv.ClassID
local done = ASYNC(12)
local WW1 = "models/adamwassim/player/imperialcommunity/ww1/soldatfrancais1.mdl"
local ADRIAN, WEB, CIT = "advinv_milou_ww1fr_adrian", "advinv_milou_ww1fr_berthier_webbing", "models/player/group01/male_07.mdl"
if not I.Items[WEB] then return done({ skipped = "the WW1 French extension isn't installed" }) end
if not util.IsValidModel(WW1) then return done({ skipped = "the WW1 French playermodels aren't installed" }) end
local b = player.GetBots()[1]
if not IsValid(b) then return done({ skipped = "no bot" }) end
if not b:Alive() then b:Spawn() end
local out = {}

-- registered by name: a session number from the server's range, the item's table
out.numberedByName = (C[WEB] or 0) >= I.DYNAMIC_ID_START and I.IDClass[C[WEB]] == WEB -- true
local t = scripted_ents.Get(WEB)
out.available = t.AdvInvAvailable == true                                -- true
out.slot = t.AdvInvCategory                                              -- "Vest"
out.storedNoStraps = t.ModelBodygroups[5] ~= t.WornBodygroups[5]         -- true (straps folded away when stored)
out.inPieces = t.ModelPieces ~= nil                                      -- true

-- on the ground: its bodygroups, the body hidden, its hull's physics, settling
local tr = util.TraceLine({ start = b:GetPos() + Vector(60, 0, 60), endpos = b:GetPos() + Vector(60, 0, -200) })
local ent = ents.Create(WEB)
ent:SetPos(tr.HitPos + Vector(0, 0, 30))
ent:Spawn()
local phys = ent:GetPhysicsObject()
out.physics = IsValid(phys)                                              -- true
out.groundPouches = ent:GetBodygroup(8)                                  -- 0 (Berthier pouches)
out.groundStraps = ent:GetBodygroup(5)                                   -- 1 (none)
out.groundMoustache = ent:GetBodygroup(1)                                -- 0 (none: not the pocket vests' pouch bodygroup)
out.wornBox = t.WornBox ~= nil and t.WornBox[2].z > t.WornBox[1].z       -- true
out.bodyHidden = ent:GetSubMaterial(t.ModelHiddenMaterials[1]) == I.NODRAW_MATERIAL -- true
local startZ = ent:GetPos().z

-- worn: shown by its bodygroup on its own playermodel, a fitted copy elsewhere; its own one locked off
I.SetDefaults(b)
b:SetModel(WW1)
b:SetBodygroup(6, 4) -- the player picks the kepi
I.ApplyModelGear(b)
out.kepiLocked = b:GetBodygroup(6)                                       -- 6 (none: gear comes from the inventory)
out.wearsWebbing = I.Equip(b, { id = C[WEB] }, {}) == true               -- true
I.ApplyModelGear(b)
out.webbingByBodygroup = b:GetBodygroup(5) .. "," .. b:GetBodygroup(8)   -- "0,0" (straps and Berthier pouches)
out.shownByModel = I.ShownByModel(b, b:GetNW2Int("Vest"))                -- true
out.wearsAdrian = I.Equip(b, { id = C[ADRIAN], a = 60 }) == true          -- true
I.ApplyModelGear(b)
out.adrianByBodygroup = b:GetBodygroup(6)                                -- 0
-- saved by class name
I.Save(b, "advinv_test_mgi")
local rec = I.Record("advinv_test_mgi")
out.savedByClass = rec.s.Vest and rec.s.Vest[1]                          -- "advinv_milou_ww1fr_berthier_webbing"
I.DeleteRecord("advinv_test_mgi")
I.TakeOff(b, "Vest")
I.TakeOff(b, "Helmet")
I.ApplyModelGear(b)
out.offAgain = b:GetBodygroup(5) .. "," .. b:GetBodygroup(8) .. "," .. b:GetBodygroup(6) -- "1,4,6"
b:SetModel(CIT)
out.citizenWears = I.Equip(b, { id = C[ADRIAN], a = 60 }) == true        -- true
out.citizenProp = not I.ShownByModel(b, b:GetNW2Int("Helmet"))          -- true (a fitted copy)
I.TakeOff(b, "Helmet")
I.SetDefaults(b)

timer.Simple(4, function()
    if IsValid(ent) then
        local p = ent:GetPhysicsObject()
        out.fell = math.Round(startZ - ent:GetPos().z, 1)                -- about 30 minus the half height: it fell
        out.resting = IsValid(p) and (p:IsAsleep() or p:GetVelocity():Length() < 1) -- true
        ent:Remove()
    end
    done(out)
end)
