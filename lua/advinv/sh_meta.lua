local meta = FindMetaTable('Entity')

function meta:AdvInvHas(category)
    return self:GetNWInt(category) > 1
end

-- Table of the item in a slot (an entity-like table for a generic weapon, see sh_generic.lua).
function meta:AdvInvEntityTable(cat)
    return AdvInv.DefTable(AdvInv.SlotRef(self, cat))
end

function meta:AdvInvRLauncher()
    return self:AdvInvEntityTable("RocketLauncher")
end

function meta:AdvInvRLRounds()
    return self:GetNWInt('RocketLauncherRounds')
end

function meta:AdvInvPWep()
    return self:AdvInvEntityTable("PrimaryWep")
end

function meta:AdvInvPWepRounds()
    return self:GetNWInt('PrimaryWepRounds')
end

function meta:AdvInvSecWep()
    return self:AdvInvEntityTable("SecondaryWep")
end

function meta:AdvInvSecWepRounds()
    return self:GetNWInt('SecondaryWepRounds')
end

local plyMeta = FindMetaTable('Player')

function plyMeta:AdvInvGetID(cat)
    return plyMeta:GetNWInt(cat)
end

function plyMeta:AdvInvWeapon(cat)
    local wepClass = self:AdvInvEntityTable(cat).WeaponClass
    return self:GetWeapon(wepClass)
end

function plyMeta:AdvInvHasHelmet()
    return self:GetNW2Int("Helmet")>1
end

function plyMeta:AdvInvGasmask()
    return self:GetNW2Int("Gasmask")
end

function plyMeta:AdvInvSecondaryWep()
    return self:GetNWInt('SecondaryWep')
end

function plyMeta:AdvInvHas(category)
    return self:GetNWInt(category) > 1
end

function plyMeta:HasNVGs()
    return self:GetNW2Int('NVGs') > 1
end
