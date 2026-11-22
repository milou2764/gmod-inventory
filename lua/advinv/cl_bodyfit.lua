--[[
    Adaptation des objets portés au playermodel (gilets, sacs).

    Un objet riggé (bonemerge) suit les os du joueur, mais deux playermodels au squelette
    identique n'ont pas la même chair autour : poitrine plus ou moins en avant, dos plus ou
    moins épais, épaules plus ou moins hautes. Pour un objet qui déclare ENT.BodyFit, on décale
    tous ses os d'après les mesures du playermodel (cl_bodyfit_data.lua), dans le repère de
    l'os Spine4 du joueur : l'objet reste déformé par le torse et suit ses mouvements.

      ENT.BodyFit = "vest" : centré sur le torse, bretelles posées sur l'épaule
      ENT.BodyFit = "back" : collé au dos

    Les objets BodyFit doivent avoir été ajustés sur AdvInv.BodyFit.ref (male_07).
    Un playermodel absent de la table garde le placement d'origine.
--]]
AdvInv.BodyFit = AdvInv.BodyFit or {}
local BF = AdvInv.BodyFit

-- Limites du décalage (unités) : évitent les extrêmes (cols montants, paquetages, monstres).
BF.limits = BF.limits or { back = { -2, 2 }, up = { -2.5, 3.5 } }

local cache = {}

-- Décalage dans le repère local de l'os Spine4, ou nil s'il n'y a rien à faire.
function BF.LocalOffset(kind, model)
    if not kind or not model then return end
    local key = kind .. "|" .. model
    local c = cache[key]
    if c ~= nil then return c or nil end

    local m = BF.models and BF.models[string.lower(model)]
    local r = BF.refMetrics
    local result = false
    if m and r and BF.axes then
        local dBack, dUp
        if kind == "vest" then
            dBack = (m[1] + m[2]) / 2 - (r[1] + r[2]) / 2
            dUp = m[3] - r[3]
        elseif kind == "back" then
            dBack = m[2] - r[2]
            dUp = 0.5 * (m[3] - r[3])
        end
        if dBack then
            dBack = math.Clamp(dBack, BF.limits.back[1], BF.limits.back[2])
            dUp = math.Clamp(dUp, BF.limits.up[1], BF.limits.up[2])
            result = BF.axes.back * dBack + BF.axes.up * dUp
        end
    end
    cache[key] = result
    return result or nil
end

-- Rappel BuildBonePositions : décale tous les os de l'objet suivant l'os Spine4 de sa cible.
local function applyBodyFit(ent, numbones)
    local target = ent:GetParent()
    if not IsValid(target) then return end
    local offset = BF.LocalOffset(ent.advinvBodyFit, target:GetModel())
    if not offset then return end
    local spine = target:LookupBone("ValveBiped.Bip01_Spine4")
    local m = spine and target:GetBoneMatrix(spine)
    if not m then return end
    local world = LocalToWorld(offset * target:GetModelScale(), angle_zero, vector_origin, m:GetAngles())
    for i = 0, numbones - 1 do
        local bm = ent:GetBoneMatrix(i)
        if bm then
            bm:SetTranslation(bm:GetTranslation() + world)
            ent:SetBoneMatrix(i, bm)
        end
    end
end

-- Active l'adaptation sur un modèle client en bonemerge (sans effet si kind est nil).
function BF.Enable(model, kind)
    model.advinvBodyFit = kind
    if kind and not model.advinvBodyFitCallback then
        model.advinvBodyFitCallback = model:AddCallback("BuildBonePositions", applyBodyFit)
    end
end
