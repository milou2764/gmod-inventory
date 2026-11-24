-- Screenshot scene (server side of the local game): a squad of bots wearing gear of the compatible
-- addons, in a line facing SQUAD_YAW. Call twice: the first call adds the missing bots.
--   SQUAD_SET = "military" | "fallout" | "starwars" | "ww1" (default military); SQUAD_BASE, SQUAD_YAW
--   an 8th field sets bodygroups { [index] = value } (the others are reset to 0)
local I = AdvInv
local C = I.ClassID
local SETS = {
    military = {
        { "Reyes", "models/rusty/natguard/player/male_01.mdl", "advinv_c_tank_crew_cvc_helmet", "advinv_c_petruz_pmc_chalecopmc", "advinv_c_fo76_backpacks_backpack_bos_tactical", "advinv_hl2_ar2", "advinv_hl2_357" },
        { "Kowalski", "models/rusty/natguard/player/female_02.mdl", nil, "advinv_c_petruz_pmc_cartucherafem", nil, "advinv_hl2_shotgun", "advinv_hl2_pistol" },
        { "Mara", "models/rusty/natguard/player/female_04.mdl", "advinv_c_tank_crew_soviet_tanker_helmet", "advinv_c_hev_tactical_vest_hevsuit", "advinv_c_fo76_backpacks_atx_backpack_wanderer", "advinv_hl2_smg1", nil },
        { "Doc", "models/rusty/natguard/player/male_05.mdl", nil, "advinv_c_dayz_police_vest_vest_police", "advinv_c_fo76_backpacks_atx_backpack_firstresponders", "advinv_hl2_crossbow", "advinv_hl2_pistol" },
        { "Vasquez", "models/rusty/natguard/player/male_03.mdl", "advinv_barney_helmet", "advinv_c_petruz_pmc_cartuchera", "advinv_c_fo3_campish_campish_pack", "advinv_hl2_rpg", nil },
    },
    fallout = {
        { "Reyes", "models/humans/vaulttec/male_01.mdl", nil, nil, "advinv_c_fo76_backpacks_backpack_vault_survivor", "advinv_hl2_shotgun", "advinv_hl2_pistol" },
        { "Kowalski", "models/humans/vaulttec/male_02.mdl", nil, nil, "advinv_c_fo76_backpacks_atx_backpack_settler_unique", "advinv_hl2_smg1", nil },
        { "Mara", "models/humans/vaulttec/male_03.mdl", nil, nil, "advinv_c_fo76_backpacks_backpack_mrfuzzy", "advinv_hl2_crossbow", nil },
        { "Doc", "models/humans/vaulttec/male_04.mdl", nil, nil, "advinv_c_fo76_backpacks_backpack_raider", "advinv_hl2_ar2", "advinv_hl2_357" },
        { "Vasquez", "models/humans/vaulttec/male_02.mdl", nil, nil, "advinv_c_fo3_campish_campish_pack", "advinv_hl2_rpg", nil },
    },
    starwars = {
        { "Reyes", "models/nada/pms/male/Naval_Officer.mdl", "advinv_c_sw_imperial_icn_helmet_prop", nil, nil, "advinv_hl2_ar2", nil },
        { "Kowalski", "models/nada/pms/female/gunner.mdl", "advinv_c_sw_imperial_mew2_death_helm", nil, nil, "advinv_hl2_smg1", nil },
        { "Mara", "models/player/swbf_imperial_officer_colonelv2/swbf_imperial_officer_colonelv2.mdl", "advinv_c_sw_imperial_mew2_scout_helm", nil, nil, nil, "advinv_hl2_pistol" },
        { "Doc", "models/gonzo/rebelpilotvariant/rebelpilotvariant.mdl", "advinv_c_sw_rebel_pilot_rebelpilothelmet", nil, nil, nil, "advinv_hl2_pistol" },
        { "Vasquez", "models/nada/pms/male/groundcrew.mdl", "advinv_c_sw_imperial_mew2_shore_helm", nil, nil, "advinv_hl2_shotgun", nil },
    },
    ww1 = {
        { "Reyes", "models/adamwassim/player/imperialcommunity/ww1/soldatfrancais1.mdl", "advinv_c_adrian_adrian_helmet", nil, nil, nil, nil },
        { "Kowalski", "models/adamwassim/player/imperialcommunity/ww1/soldatfrancais2.mdl", "advinv_c_adrian_adrian_helmet", nil, nil, nil, nil },
        { "Mara", "models/adamwassim/player/imperialcommunity/ww1/soldatfrancais3.mdl", "advinv_c_adrian_adrian_helmet", nil, nil, nil, nil },
        { "Doc", "models/adamwassim/player/imperialcommunity/ww1/soldatfrancais4.mdl", "advinv_c_adrian_adrian_helmet", nil, nil, nil, nil },
        { "Vasquez", "models/adamwassim/player/imperialcommunity/ww1/soldatfrancais5.mdl", "advinv_c_adrian_adrian_helmet", nil, nil, nil, nil },
    },
}
-- bots stand still and upright (they would crouch: no command, and DarkRP's duck flag)
hook.Add("StartCommand", "AdvInvShots_Bots", function(ply, cmd)
    if ply:IsBot() then cmd:ClearMovement() cmd:ClearButtons() end
end)
hook.Add("Think", "AdvInvShots_Bots", function()
    for _, b in ipairs(player.GetBots()) do b:RemoveFlags(bit.bor(FL_ANIMDUCKING, FL_DUCKING)) end
end)
local set = SETS[SQUAD_SET or "military"]
local bots = player.GetBots()
if #bots < #set then
    for k = #bots + 1, #set do player.CreateNextBot(set[k][1]) end
    return { wait = true }
end
local base = SQUAD_BASE or Vector(-2052, 9708, 129)
local yaw = SQUAD_YAW or 180
local right = Angle(0, yaw, 0):Right()
local fwd = Angle(0, yaw, 0):Forward()
local OFFS = SQUAD_OFFS or { 0, -48, 48, -96, 96 }
local DEPTH = SQUAD_DEPTH or { 0, -22, -18, -40, -36 }
local TURN = SQUAD_TURN or { 0, 0, 0, 0, 0 }     -- each one turned a little (degrees)
local HOLD = SQUAD_HOLD or {}                     -- [k] = true: holds his primary weapon
for k, m in ipairs(set) do
    local b = bots[k]
    b:SetModel(m[2])
    for k2 = 0, b:GetNumBodyGroups() - 1 do b:SetBodygroup(k2, (m[8] or {})[k2] or 0) end
    b:SetPos(base + right * OFFS[k] + fwd * DEPTH[k])
    b:SetEyeAngles(Angle(0, yaw + (TURN[k] or 0), 0))
    b:SetAngles(Angle(0, yaw + (TURN[k] or 0), 0))
    I.SetDefaults(b)
    if m[3] then I.Equip(b, { id = C[m[3]], a = 100 }) end
    if m[4] then I.Equip(b, { id = C[m[4]], a = 100 }, {}) end
    if m[5] then I.Equip(b, { id = C[m[5]], a = 0 }, {}) end
    if m[6] then I.Equip(b, { id = C[m[6]], r = 10 }) end
    if m[7] then I.Equip(b, { id = C[m[7]], r = 6 }) end
    local held = HOLD[k] and m[6] and I.Info(C[m[6]]).weaponClass
    b:SelectWeapon(held or "keys")
end
return { bots = #set, base = tostring(base) }
