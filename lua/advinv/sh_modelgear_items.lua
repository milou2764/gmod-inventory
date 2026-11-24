--[[
    Gear taken from a playermodel addon's own bodygroups, as items (AIS extensions, one per playermodel
    addon, made by tools/modelgear_pack.py). An extension ships Lua only: the item is drawn with the
    playermodel's own model, its other bodygroups on their empty choice and the parts that have none
    hidden by material (materials/advinv/nodraw.vmt). On the pack's own playermodels the item is shown
    by the bodygroup itself (AdvInv.ModelGear items, rigged for that body); on the others a copy
    follows the wearer's bone with its fit (pack.fits); on the ground its physics is the gear's convex
    hull around its centre.

    An extension (a shared autorun file; it may load before or after the inventory):
        AdvInv = AdvInv or {}
        AdvInv.ModelGearPacks = AdvInv.ModelGearPacks or {}
        local pack = { key, title, wid, author, category = { en, fr }, model, blank = { [bodygroup] = empty },
            hide = { material index, ... }, items = { { class, slot, name = { en, fr }, mass, armor, load,
            bodygroups, origin, hull, attach, on = { [playermodel] = bodygroups } }, ... },
            fits = { models = { ... }, items = { [class] = "x y z p y r size|..." } } }
        if AdvInv.AddModelGearPack then AdvInv.AddModelGearPack(pack) else table.insert(AdvInv.ModelGearPacks, pack) end
    The item classes are the items' IDs: put the extension author's name in them.
--]]
local I = AdvInv
I.ModelGearPacks = I.ModelGearPacks or {}
I.NODRAW_MATERIAL = "advinv/nodraw"

-- An item's look on any entity drawing its model: stored (on the ground, in an icon) or worn (a copy
-- on another playermodel: webbing with its straps, which are folded away when it's stored).
function I.SetupItemModel(ent, t, worn)
    if not (IsValid(ent) and t) then return end
    for k, v in pairs(worn and t.WornBodygroups or t.ModelBodygroups or {}) do ent:SetBodygroup(k, v) end
    for _, i in ipairs(t.ModelHiddenMaterials or {}) do ent:SetSubMaterial(i, I.NODRAW_MATERIAL) end
    -- shadows are drawn with a material of their own: the hidden body would cast one
    if t.ModelHiddenMaterials then ent:DrawShadow(false) end
end

if CLIENT then
    -- A model drawn in pieces: once per piece { normal, distance, move } (a plane in the model's space),
    -- clipped to that side of the plane and moved. base: the move of the whole model the entity already
    -- has (the ground item's RenderMultiply: its centre at its origin). The pouches of stored webbing have
    -- nothing between them: pushed together. Each piece is moved by the render origin, its bones built
    -- again (they are built once a frame: a matrix changed between two draws wouldn't move anything).
    function I.DrawModelPieces(ent, pieces, flags, base)
        base = base or vector_origin
        local had = ent:GetRenderOrigin()
        local origin = had or ent:GetPos()
        local ang = ent:GetRenderAngles() or ent:GetAngles()
        local scale = ent:GetModelScale()
        local clip = render.EnableClipping(true)
        for _, p in ipairs(pieces) do
            local n, d, move = p[1], p[2], p[3]
            ent:SetRenderOrigin(LocalToWorld(move * scale, angle_zero, origin, ang))
            ent:SetupBones()
            local wn = LocalToWorld(n, angle_zero, vector_origin, ang)
            local wp = LocalToWorld((n * d + base + move) * scale, angle_zero, origin, ang)
            render.PushCustomClipPlane(wn, wn:Dot(wp))
            ent:DrawModel(flags)
            render.PopCustomClipPlane()
        end
        render.EnableClipping(clip)
        ent:SetRenderOrigin(had)
        ent:SetupBones()
    end

    -- Gear on a material of the hidden body (the Vietnam soldiers' suspenders are painted on the
    -- uniform's texture, the PAVN chest rig shares the boots' one): hiding the body hides it too. Those
    -- triangles are read from the installed model (those of the item's selection that the gearless one
    -- hasn't, on a hidden material) and drawn as a mesh of the model at rest, where the model is drawn
    -- (a worn copy, a ground item and an icon are rigid). Nothing is shipped. ENT.ModelSharedLooks
    -- (the pack's `shared`): which looks need it, { stored = true, worn = true }.
    local sharedParts = {}

    local function bodyValue(ent, sel)
        local v, mul = 0, 1
        for _, bg in ipairs(ent:GetBodyGroups() or {}) do
            v = v + (sel[bg.id] or 0) * mul
            mul = mul * math.max(bg.num or 1, 1)
        end
        return v
    end

    local function triKey(a, b, c)
        local function k(p) return string.format("%.2f %.2f %.2f", p.x, p.y, p.z) end
        return k(a.pos) .. "|" .. k(b.pos) .. "|" .. k(c.pos)
    end

    local function buildShared(ent, t, sel)
        local mdl = ent:GetModel()
        local hidden = {}
        local mats = ent:GetMaterials()
        for _, i in ipairs(t.ModelHiddenMaterials) do
            if mats[i + 1] then hidden[string.lower(mats[i + 1])] = true end
        end
        local blank = util.GetModelMeshes(mdl, 0, bodyValue(ent, t.ModelBlankBodygroups))
        local worn, bind = util.GetModelMeshes(mdl, 0, bodyValue(ent, sel))
        if not (blank and worn and bind) then return end
        local had = {}
        for _, m in ipairs(blank) do
            if hidden[string.lower(m.material or "")] then
                local tr = m.triangles
                for i = 1, #tr - 2, 3 do had[triKey(tr[i], tr[i + 1], tr[i + 2])] = true end
            end
        end
        -- the model's bones at rest, in its own space (a copy at the origin)
        local tmp = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
        if not IsValid(tmp) then return end
        tmp:SetNoDraw(true)
        tmp:SetPos(vector_origin)
        tmp:SetAngles(angle_zero)
        tmp:SetupBones()
        local skin = {}
        for b, info in pairs(bind) do
            local bm = tmp:GetBoneMatrix(b)
            if bm and info.matrix then skin[b] = bm * info.matrix end
        end
        tmp:Remove()
        local out = {}
        for _, m in ipairs(worn) do
            if hidden[string.lower(m.material or "")] then
                local tr, verts = m.triangles, {}
                for i = 1, #tr - 2, 3 do
                    if not had[triKey(tr[i], tr[i + 1], tr[i + 2])] then
                        for j = 0, 2 do verts[#verts + 1] = tr[i + j] end
                    end
                end
                if #verts > 0 then
                    local mesh_ = Mesh()
                    mesh.Begin(mesh_, MATERIAL_TRIANGLES, #verts / 3)
                    for _, v in ipairs(verts) do
                        local p, n = Vector(), Vector()
                        for _, w in ipairs(v.weights or {}) do
                            local M = skin[w.bone]
                            if M then
                                p:Add((M * v.pos) * w.weight)
                                n:Add((M * v.normal - M * vector_origin) * w.weight)
                            end
                        end
                        n:Normalize()
                        mesh.Position(p)
                        mesh.Normal(n)
                        mesh.TexCoord(0, v.u, v.v)
                        mesh.AdvanceVertex()
                    end
                    mesh.End()
                    out[#out + 1] = { mesh = mesh_, mat = Material(m.material) }
                end
            end
        end
        return #out > 0 and out or nil
    end

    -- worn: the worn look (else the stored one); nil when that look has nothing on the body's material
    function I.SharedPartsMesh(ent, t, worn)
        local looks = t.ModelSharedLooks
        if not (looks and looks[worn and "worn" or "stored"]) then return end
        local key = (t.ClassName or ent:GetModel()) .. (worn and ":worn" or ":stored")
        local c = sharedParts[key]
        if c == nil then
            local sel = worn and t.WornBodygroups or t.ModelBodygroups
            c = (util.GetModelMeshes and t.ModelBlankBodygroups and sel and t.ModelHiddenMaterials
                and buildShared(ent, t, sel)) or false
            sharedParts[key] = c
        end
        return c or nil
    end

    -- A mesh isn't lit by the engine like a model: lit here as the model is, from where it is (worn
    -- gear and icons set their own lighting before; a ground item asks for it: light).
    local LIGHT_DIRS = { Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0), Vector(0, 0, 1), Vector(0, 0, -1) }
    local function lightAt(pos)
        render.SuppressEngineLighting(true)
        render.SetLightingOrigin(pos)
        render.ResetModelLighting(0, 0, 0)
        for i, d in ipairs(LIGHT_DIRS) do
            local c = render.ComputeLighting(pos, d)
            render.SetModelLighting(i - 1, c.x, c.y, c.z)
        end
    end

    -- drawn right after the model itself (same place); offset: the model's own move in its space (a
    -- ground item's RenderMultiply: its gear's centre at its origin)
    function I.DrawSharedParts(ent, t, worn, offset, light)
        local parts = I.SharedPartsMesh(ent, t, worn)
        if not parts then return end
        if light then lightAt(ent:WorldSpaceCenter()) end
        local mx = Matrix()
        mx:SetTranslation(ent:GetRenderOrigin() or ent:GetPos())
        mx:SetAngles(ent:GetRenderAngles() or ent:GetAngles())
        local s = ent:GetModelScale()
        if s ~= 1 then mx:Scale(Vector(s, s, s)) end
        if offset then mx:Translate(offset) end
        -- the stored look in pieces (cut or pushed together): each piece clipped and moved like the model
        local pieces = not worn and t.ModelPieces or { { nil, 0, vector_origin } }
        local clip = pieces[1][1] and render.EnableClipping(true)
        local origin, ang = ent:GetRenderOrigin() or ent:GetPos(), ent:GetRenderAngles() or ent:GetAngles()
        for _, pc in ipairs(pieces) do
            local n, d, move = pc[1], pc[2], pc[3]
            if n then
                local wn = LocalToWorld(n, angle_zero, vector_origin, ang)
                local wp = LocalToWorld((n * d + (offset or vector_origin) + move) * s, angle_zero, origin, ang)
                render.PushCustomClipPlane(wn, wn:Dot(wp))
            end
            local m = Matrix(mx)
            m:Translate(move)
            cam.PushModelMatrix(m, true)
            for _, p in ipairs(parts) do
                render.SetMaterial(p.mat)
                p.mesh:Draw()
            end
            cam.PopModelMatrix()
            if n then render.PopCustomClipPlane() end
        end
        if pieces[1][1] then render.EnableClipping(clip) end
        if light then render.SuppressEngineLighting(false) end
    end
end

local BASES = { Helmet = "advinv_base_helmet", Rucksack = "advinv_base_rucksack", Vest = "advinv_base_pocketvest" }

-- the fits on other playermodels (client): merged once cl_gear.lua has read the inventory's own
function I.MergePackFits(pack)
    local fits = pack.fits
    if not (CLIENT and I.FitsLoaded and fits and fits.models and fits.items) or pack.fitsMerged then return end
    pack.fitsMerged = true
    I.Fits = I.Fits or {}
    for class, packed in pairs(fits.items) do
        local k = 0
        for e in string.gmatch(packed .. "|", "([^|]*)|") do
            k = k + 1
            local m = fits.models[k]
            if e ~= "" and m then
                local n = {}
                for x in string.gmatch(e, "%S+") do n[#n + 1] = tonumber(x) end
                m = string.lower(m)
                I.Fits[m] = I.Fits[m] or {}
                I.Fits[m][class] = { Vector(n[1], n[2], n[3]), Angle(n[4], n[5], n[6]), n[7] }
            end
        end
    end
end

function I.AddModelGearPack(pack)
    if pack.registered then return end
    pack.registered = true
    local here = isstring(pack.model) and file.Exists(pack.model, "GAME") or false
    pack.installed = here
    for _, it in ipairs(pack.items or {}) do
        local ENT = { Type = "anim" }
        ENT.Base = BASES[it.slot] or "advinv_base_gear"
        if it.slot == "Vest" and (it.load or 0) <= 0 then ENT.Base = "advinv_base_vest" end
        ENT.PrintName = I.T(it.name[1], it.name[2])
        ENT.Category = I.T(pack.category[1], pack.category[2])
        ENT.Author = pack.author
        ENT.Information = I.T("Gear of the playermodels \"" .. pack.title .. "\" (Workshop " .. tostring(pack.wid) .. ")",
            "Équipement des playermodels « " .. pack.title .. " » (Workshop " .. tostring(pack.wid) .. ")")
        ENT.AdvInvAvailable = here -- spawnable and given only where the playermodel addon is installed
        ENT.Spawnable = here
        ENT.AdvInvModelGearPack = pack.key
        ENT.AdvInvCategory = it.slot
        ENT.Model = pack.model
        local worn, stored = table.Copy(pack.blank or {}), table.Copy(pack.blank or {})
        for k, v in pairs(it.bodygroups or {}) do worn[k] = v end
        for k, v in pairs(it.stored or it.bodygroups or {}) do stored[k] = v end
        ENT.ModelBodygroups = stored -- on the ground and in icons
        ENT.WornBodygroups = worn    -- a copy worn on another playermodel
        ENT.ModelBlankBodygroups = table.Copy(pack.blank or {}) -- no gear at all (I.SharedPartsMesh)
        ENT.ModelSharedLooks = it.shared -- { stored, worn }: parts on the hidden body's material
        ENT.ModelHiddenMaterials = pack.hide
        ENT.ModelOrigin = it.origin
        ENT.ModelPieces = it.pieces
        ENT.PhysHull = it.hull
        ENT.WornBox = it.worn_box -- { mins, maxs } of the gear as worn, in the model's space (framing)
        ENT.BackDepth = it.back_depth -- a backpack: how far it sticks out behind the back (carried weapons)
        ENT.BackHalfWidth = it.back_half_width -- and how far to each side (a slung rifle hangs beside it)
        ENT.pocketID = false -- (the pocket vest base's pouch bodygroup: on a playermodel, another bodygroup)
        ENT.Mass = it.mass
        ENT.Armor = it.armor or 0 -- (0: none; nil would take the base's 100)
        if it.slot ~= "Helmet" then ENT.MaxLoad = it.load or 0 end
        -- rigged: bonemerged on the wearer, each part on its own bone (a holster, leg pouches: the thighs)
        ENT.Attach = not it.rigged and it.attach or nil
        ENT.IconAsWorn = true
        scripted_ents.Register(ENT, it.class)
        I.Items[it.class] = true
        -- on the pack's own playermodels: shown by their bodygroup, rigged for that body
        for pm, bgs in pairs(it.on or {}) do
            local model = string.lower(pm)
            I.ModelGear[model] = I.ModelGear[model] or {}
            I.ModelGear[model].items = I.ModelGear[model].items or {}
            I.ModelGear[model].items[it.class] = bgs
        end
    end
    -- and their gear only while it is worn: the bodygroups the items use are locked to the pack's
    -- "no gear" values (else a player of such a model shows the model's own gear without the items:
    -- the Vietnam soldiers, NPC ragdolls when their pack was made, later ported as playermodels).
    -- An entry of sh_modelgear.lua or of the server keeps its own lock.
    if pack.blank then
        local locks = {}
        for _, it in ipairs(pack.items or {}) do
            for pm, bgs in pairs(it.on or {}) do
                local model = string.lower(pm)
                locks[model] = locks[model] or {}
                for bg in pairs(bgs) do
                    if pack.blank[bg] ~= nil then locks[model][bg] = pack.blank[bg] end
                end
            end
        end
        for model, lock in pairs(locks) do
            local g = I.ModelGear[model]
            if g and g.lock == nil and next(lock) then g.lock = lock end
        end
    end
    I.MergePackFits(pack)
end

for _, pack in ipairs(I.ModelGearPacks) do I.AddModelGearPack(pack) end
