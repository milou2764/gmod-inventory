--[[
    Fits loaded on demand. AdvInv.Fits[playermodel][item class] = { position, angles, size } holds the
    inventory's own fits (cl_fits_data.lua); the compatible items' fits (cl_fits_compat.lua) and the
    gear packs' (sh_modelgear_items.lua) cover 1,300 playermodels each: they are sources, merged into a
    playermodel's table the first time a fit missing from it is looked up, never over a fit already
    there. A source: AdvInv.AddFitSource({ [lowercase playermodel] = true... }, function(t, playermodel)
    rawset(t, class, fit)... end).
--]]
AdvInv = AdvInv or {}

local sources = {}

-- mixed-case playermodel keys into lowercase ones, their entries merged (a lowercase table made by a
-- source must not hide the other)
local function lowerFits()
    local F = AdvInv.Fits
    if not istable(F) then return end
    local moves = {}
    for k in pairs(F) do
        if isstring(k) and k ~= string.lower(k) then moves[#moves + 1] = k end
    end
    for _, k in ipairs(moves) do
        local l, t = string.lower(k), F[k]
        F[k] = nil
        local d = rawget(F, l)
        if d == nil then
            F[l] = t
        elseif istable(d) and istable(t) then
            for c, v in pairs(t) do
                if rawget(d, c) == nil then rawset(d, c, v) end
            end
        end
    end
end

local function arm(model)
    local F = AdvInv.Fits
    local t = F[model]
    if not t then
        t = {}
        F[model] = t
    end
    if getmetatable(t) then return end
    setmetatable(t, { __index = function(tt, class)
        setmetatable(tt, nil)
        for _, src in ipairs(sources) do
            if src.models[model] and not src.done[model] then
                src.done[model] = true
                src.merge(tt, model)
            end
        end
        return rawget(tt, class)
    end })
end

function AdvInv.AddFitSource(models, merge)
    AdvInv.Fits = AdvInv.Fits or {}
    lowerFits()
    local src = { models = models, merge = merge, done = {} }
    sources[#sources + 1] = src
    for model in pairs(models) do arm(model) end
    return src
end
