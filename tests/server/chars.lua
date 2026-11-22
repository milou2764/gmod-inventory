-- The calls mrp-characters makes, with a numeric character ID (sv_inventory_link, sv_character).
local done = ASYNC(20)
local I = AdvInv
local id = function(c) return I.ClassID[c] end
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
local out = {}
local function summary(items)
    local t = {}
    for _, it in ipairs(items or {}) do t[#t + 1] = (I.IDClass[it.id] or "?") .. "(" .. (it.r or 0) .. ")" end
    table.sort(t)
    return table.concat(t, " ")
end
local function weapons(b)
    local t = {}
    for _, w in ipairs(b:GetWeapons()) do t[#t + 1] = w:GetClass() .. ":" .. w:Clip1() end
    table.sort(t)
    return table.concat(t, " ")
end
local UID = 4242
I.DeleteRecord(UID)
player.CreateNextBot("Soldier")
timer.Simple(1, function()
    local b = player.GetBots()[1]
    b:SetPos(Vector(-2800, -1500, -140))
    -- CharacterRegistration -> CreateRecord
    I.CreateRecord(UID)
    local rec = I.Record(UID)
    out.created = { exists = rec ~= nil, helmet = I.RecordSlot(rec, "Helmet") == nil }
    -- the character plays: gear and weapons
    I.SetDefaults(b)
    out.equip = {
        I.Equip(b, { id = id("advinv_barney_helmet"), a = 37 }),
        I.Equip(b, { id = id("advinv_suitcase") }, { { id = id("advinv_ammo_pistol"), r = 18 } }),
        I.Equip(b, { id = id("advinv_hl2_ar2"), r = 17 }),
        I.Equip(b, { id = id("advinv_hl2_pistol"), r = 9 }),
    }
    I.Set(b, "Uniform", { { id = id("advinv_ammo_ar2"), r = 30 } })
    local before = { b:GetNW2Int("Helmet"), b:GetNWInt("HelmetArmor"), b:GetNW2Int("Rucksack"), summary(I.Get(b, "Rucksack")),
        summary(I.Get(b, "Uniform")), b:GetNWInt("PrimaryWep"), b:GetNWInt("SecondaryWep"), I.CarryMode(b, "PrimaryWep") }
    -- MRP_SaveProgress -> Save(ply, cid)
    out.saved = I.Save(b, UID)
    -- character list: the preview slots (sendCharacterData)
    local preview = {}
    local r2 = I.Record(UID)
    for _, cat in ipairs({ "NVGs", "Helmet", "Gasmask", "Rucksack", "Vest" }) do
        local item = I.RecordSlot(r2, cat)
        preview[#preview + 1] = cat .. "=" .. (item and item.id or 1)
    end
    out.preview = table.concat(preview, " ")
    -- respawn with the character kept (equipPlayer): other weapons go, inventory ones stay
    b:Give("weapon_crowbar")
    b:GetWeapon("weapon_ar2"):SetClip1(11) -- shots fired meanwhile
    local keep = {}
    for _, cat in ipairs(I.WeaponCat) do
        local info = I.SlotInfo(b, cat)
        if info.weaponClass then keep[info.weaponClass] = true end
    end
    for _, wep in ipairs(b:GetWeapons()) do
        if not keep[wep:GetClass()] then b:StripWeapon(wep:GetClass()) end
    end
    I.GiveWeapons(b)
    out.respawnKept = weapons(b)
    -- a StripWeapons elsewhere: GiveWeapons gives them back with the slot's munitions
    b:StripWeapons()
    I.GiveWeapons(b)
    out.afterStrip = weapons(b)
    -- MRP_CharacterSelected -> Load(ply, uid) from an emptied player
    I.Clear(b)
    out.cleared = { weapons(b), b:GetNW2Int("Helmet"), summary(I.Get(b, "Uniform")) }
    I.Load(b, UID)
    local after = { b:GetNW2Int("Helmet"), b:GetNWInt("HelmetArmor"), b:GetNW2Int("Rucksack"), summary(I.Get(b, "Rucksack")),
        summary(I.Get(b, "Uniform")), b:GetNWInt("PrimaryWep"), b:GetNWInt("SecondaryWep"), I.CarryMode(b, "PrimaryWep") }
    out.load = { same = util.TableToJSON(before) == util.TableToJSON(after), before = before, after = after, weapons = weapons(b) }
    -- the same ID given as a string reads the same row
    out.stringKey = I.Record(tostring(UID)) ~= nil
    -- mrp_characters_deletion -> DeleteRecord
    I.DeleteRecord(UID)
    out.deleted = I.Record(UID) == nil
    out.table = sql.QueryValue("SELECT sql FROM sqlite_master WHERE name = 'advinv_inventory'")
    out.oldTable = sql.TableExists("mrp_inv")
    done(out)
end)
