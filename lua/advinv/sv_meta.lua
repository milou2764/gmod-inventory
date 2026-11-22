-- Anciennes méthodes du système à places, gardées pour les addons qui les appellent encore :
-- elles passent par l'inventaire à capacité (sv_containers.lua).
local plyMeta = FindMetaTable("Player")

function plyMeta:AdvInv_Pickup(ent) return AdvInv.PickupEntity(self, ent) end
function plyMeta:EquipHelmet(ent) AdvInv.Use(self, ent) end
function plyMeta:EquipRucksack(ent) AdvInv.Use(self, ent) end
function plyMeta:pickupGear(ent) AdvInv.Use(self, ent) end
