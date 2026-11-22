AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "base_entity"
ENT.PrintName = AdvInv.T("Supply crate", "Caisse de ravitaillement")
ENT.Category = AdvInv.T("Inventory: Furniture", "Inventaire : mobilier")
ENT.Model = "models/props_junk/wood_crate001a.mdl" -- (spawn menu icon)
ENT.Spawnable = true

-- Contenant « Storage » (voir sh_containers.lua) ; capacité : ENT.MaxLoad, sinon
-- AdvInv.Config.CrateLoad. Le contenu n'est pas sauvegardé au redémarrage.
-- ENT.MaxLoad = 1000

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_junk/wood_crate001a.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:GetPhysicsObject():EnableMotion(false)
        self:SetUseType(SIMPLE_USE)
    end

    -- Un objet lancé contre la caisse y est rangé s'il a la place.
    function ENT:PhysicsCollide(data, _)
        local item = data.HitEntity
        if IsValid(item) and AdvInv.ItemFromEntity(item) then
            timer.Simple(0, function()
                if IsValid(self) and IsValid(item) then AdvInv.StoreEntityIn(self, item) end
            end)
        end
    end

    -- Touche Utiliser : ouvre la caisse (inventaire du joueur + contenu de la caisse), ou demande
    -- son code si elle est verrouillée (sv_storage.lua).
    util.AddNetworkString("advinv_open_storage")
    function ENT:Use(activator)
        AdvInv.StorageUse(self, activator)
    end
else
    function ENT:Draw()
        self:DrawModel()
    end

    net.Receive("advinv_open_storage", function()
        local ent = net.ReadEntity()
        if IsValid(ent) and AdvInv.OpenStorage then AdvInv.OpenStorage(ent) end
    end)
end
