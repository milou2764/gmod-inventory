--[[
    Crafting (server: sv_craft.lua, client: cl_craft.lua): the inventory's "Crafting" button, or
    a workbench (advinv_workbench) for recipes that need one. The ingredients are taken from the
    uniform, vest and backpack; the result goes into them (on the ground if there is no room).

    Recipes (shared): name in each language; needs / gives: { item = registered item class } or
    { entity = whitelisted entity class } or { weapon = weapon class } or { ammo = ammo type },
    with count (default 1); bench = true: only at a workbench; time = seconds (default 1).
        AdvInv.AddRecipe({ name = { en = "...", fr = "..." }, needs = { ... }, gives = { ... } })
    Hook (server): AdvInv_CanCraft(ply, recipe) -> false to forbid.
--]]
local I = AdvInv

-- Crafting is off unless the server turns it on (advinv_craft 1, or the admin menu).
local craftVar = CreateConVar("advinv_craft", "0", { FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED },
    "Crafting: the inventory's Crafting button and the workbenches (0: off)", 0, 1)
function I.CraftingEnabled() return craftVar:GetBool() end
if I.AddAdminSetting then I.AddAdminSetting("advinv_craft", "bool") end

I.Recipes = I.Recipes or {}

function I.AddRecipe(r)
    r.id = r.id or (#I.Recipes + 1)
    for k, old in ipairs(I.Recipes) do
        if old.id == r.id then I.Recipes[k] = r return r end
    end
    I.Recipes[#I.Recipes + 1] = r
    return r
end

I.AddRecipe({
    id = "healthkit",
    name = { en = "Health kit (from 2 vials)", fr = "Trousse de soins (avec 2 fioles)" },
    needs = { { entity = "item_healthvial", count = 2 } },
    gives = { entity = "item_healthkit" },
})
I.AddRecipe({
    id = "357",
    name = { en = ".357 rounds (from 3 pistol boxes)", fr = "Munitions .357 (avec 3 boîtes de pistolet)" },
    needs = { { item = "advinv_ammo_pistol", count = 3 } },
    gives = { item = "advinv_ammo_357" },
    bench = true,
    time = 3,
})

function I.RecipeName(r)
    if istable(r.name) then return r.name[I.Language()] or r.name.en or tostring(r.id) end
    return tostring(r.name or r.id)
end

-- Does an item match an ingredient?
function I.ItemMatches(it, spec)
    if spec.item then
        if AdvInv.ClassID[spec.item] ~= it.id then return false end
        local info = I.Info(it.id)
        return not info.isBox or (it.r or 0) >= (info.boxRounds or 0) -- boxes: full ones only
    end
    if spec.entity then return it.id == I.GENERIC_ENTITY and it.c == spec.entity end
    if spec.ammo then
        local info = I.Info(it.id, it.c)
        return info.isBox and info.ammo and string.lower(info.ammo) == string.lower(spec.ammo)
            and (it.r or 0) >= (info.boxRounds or 0) or false -- full boxes only
    end
    if spec.weapon then
        if it.id == I.GENERIC_WEAPON then return it.c == spec.weapon end
        return I.Info(it.id).weaponClass == spec.weapon
    end
    return false
end

-- How many of an ingredient ply carries (uniform, vest, backpack).
function I.CountCarried(ply, spec)
    local n = 0
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        for _, it in ipairs(I.Get(ply, cont)) do
            if I.ItemMatches(it, spec) then n = n + 1 end
        end
    end
    return n
end

-- Name of an ingredient / result.
function I.SpecName(spec)
    if spec.item and AdvInv.ClassID[spec.item] then return I.Info(AdvInv.ClassID[spec.item]).name end
    if spec.entity then return I.Info(I.GENERIC_ENTITY, spec.entity).name or spec.entity end
    if spec.weapon then
        local grenade = I.GrenadeAmmo(spec.weapon)
        if grenade and game.GetAmmoID(grenade) ~= -1 then return I.Info(I.GENERIC_AMMO, grenade).name end
        local reg = I.ItemForWeapon(spec.weapon)
        return reg and I.Info(reg).name or I.Info(I.GENERIC_WEAPON, spec.weapon).name or spec.weapon
    end
    if spec.ammo then return I.L("generic_ammo", spec.ammo) end
    return "?"
end

-- Can ply craft this now? -> true, or false and a reason. nearBench: at a workbench.
function I.CanCraft(ply, r, nearBench)
    if r.bench and not nearBench then return false, I.L("craft_need_bench") end
    for _, spec in ipairs(r.needs or {}) do
        if I.CountCarried(ply, spec) < (spec.count or 1) then return false, I.L("craft_missing", I.SpecName(spec)) end
    end
    return true
end

function I.NearBench(ply)
    for _, e in ipairs(ents.FindInSphere(ply:GetPos(), 150)) do
        if e:GetClass() == "advinv_workbench" and I.InSight(ply, e) then return true end
    end
    return false
end
