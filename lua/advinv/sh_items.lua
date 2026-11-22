-- Objets fournis avec Advanced Inventory System. Ils n'utilisent que des modèles installés avec
-- Garry's Mod (contenu GMod et HL2), donc rien à télécharger pour les joueurs.
-- Plage d'ID réservée à l'addon : 100 à 127. Ne pas les réutiliser pour vos objets.
AdvInv.ClassID = AdvInv.ClassID or {}

local items = {
    -- Équipement (les ID 100 et 103 ne sont pas utilisés)
    advinv_top_hat = 101,
    advinv_graduation_cap = 102,
    advinv_barney_helmet = 104,
    advinv_cp_mask = 105,
    advinv_bucket = 106,
    advinv_jetpack = 107,
    advinv_suitcase = 108,

    -- Armes HL2
    advinv_hl2_pistol = 109,
    advinv_hl2_357 = 110,
    advinv_hl2_smg1 = 111,
    advinv_hl2_ar2 = 112,
    advinv_hl2_shotgun = 113,
    advinv_hl2_crossbow = 114,
    advinv_hl2_rpg = 115,

    -- Munitions HL2
    advinv_ammo_pistol = 116,
    advinv_ammo_357 = 117,
    advinv_ammo_smg1 = 118,
    advinv_ammo_smg1_grenade = 119,
    advinv_ammo_ar2 = 120,
    advinv_ammo_ar2_altfire = 121,
    advinv_ammo_buckshot = 122,
    advinv_ammo_crossbow = 123,
    advinv_ammo_rpg = 124,
}

for class, id in pairs(items) do
    AdvInv.ClassID[class] = id
end
