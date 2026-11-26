local done = ASYNC(30)
local I = AdvInv
local idOf = {}
for id, c in pairs(AdvInv.IDClass) do idOf[c] = id end
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
local out = {}
local function summary(items)
    local t = {}
    for _, it in ipairs(items) do t[#t + 1] = (AdvInv.IDClass[it.id] or "?") .. (it.c and ("[" .. it.c .. "]") or "") end
    table.sort(t)
    return table.concat(t, " ")
end
local function call(fn, ply, q)
    local real = { net.ReadUInt, net.ReadEntity, net.ReadString, net.ReadBool }
    local k = 0
    local function nxt() k = k + 1 return q[k] end
    net.ReadUInt, net.ReadEntity, net.ReadString, net.ReadBool = nxt, nxt, nxt, nxt
    local ok, a, b = pcall(fn, ply)
    net.ReadUInt, net.ReadEntity, net.ReadString, net.ReadBool = real[1], real[2], real[3], real[4]
    if not ok then return "ERROR " .. tostring(a) end
    return { a, b }
end
-- the check that follows every item index in an action (I.ItemCheck: the item the client saw)
local function ck(holder, cid, index)
    local it = AdvInv.Get(holder, AdvInv.IDCont[cid])[index]
    return it and AdvInv.ItemCheck(it) or 0
end
local H, ACT = I.ActHandlers, I.ACT
local found
hook.Add("AdvInv_Searched", "test", function(_, _, f) found = f end)
player.CreateNextBot("Cop") player.CreateNextBot("Suspect")
timer.Simple(1, function()
    local cop, sus = player.GetBots()[1], player.GetBots()[2]
    for _, p in ipairs({ cop, sus }) do I.SetDefaults(p) end
    cop:SetPos(Vector(-2800, -1800, -140)) sus:SetPos(Vector(-2740, -1800, -140))
    I.Equip(sus, { id = idOf.advinv_hl2_ar2, r = 20 })
    I.Store(sus, { id = I.GENERIC_ENTITY, c = "item_healthkit" })
    I.Store(sus, { id = idOf.advinv_ammo_ar2, r = 20 })
    I.IllegalItems["item_healthkit"] = true
    RunConsoleCommand("advinv_search_mode", "1") RunConsoleCommand("advinv_search_time", "1")
    timer.Simple(0.2, function()
        out.citizenMode1 = { I.CanSearch(cop, sus) }
        RunConsoleCommand("advinv_search_mode", "2")
        timer.Simple(0.2, function()
            out.anyoneMode2 = { I.CanSearch(cop, sus) }
            out.start = call(H[ACT.SEARCH], cop, { 1, sus })
            out.during = { canAccess = I.CanAccess(cop, sus), searchedBy = tostring(sus:GetNWEntity("AdvInvSearchedBy")) }
            timer.Simple(1.5, function()
                out.after = { canAccess = I.CanAccess(cop, sus), viewer = sus.AdvInvViewers and sus.AdvInvViewers[cop] or false, found = found }
                -- take the health kit (index 1) into the cop's uniform
                out.take = call(H[ACT.MOVE], cop, { sus, I.ContID.Uniform, 1, ck(sus, I.ContID.Uniform, 1), cop, I.ContID.Uniform, 1 })
                -- plant: refused
                out.plant = call(H[ACT.MOVE], cop, { cop, I.ContID.Uniform, 1, ck(cop, I.ContID.Uniform, 1), sus, I.ContID.Uniform, 1 })
                out.afterMoves = { cop = summary(I.Get(cop, "Uniform")), suspect = summary(I.Get(sus, "Uniform")) }
                -- confiscate the equipped AR2
                out.takeSlot = call(H[ACT.SEARCH], cop, { 3, sus, AdvInv.CategoryID.PrimaryWep })
                out.afterTakeSlot = { suspectPrimary = sus:GetNWInt("PrimaryWep"), cop = summary(I.Get(cop, "Uniform")), copPrimary = cop:GetNWInt("PrimaryWep") }
                -- walk away: the search ends
                cop:SetPos(Vector(-2000, -1000, -140))
                timer.Simple(1.2, function()
                    out.awayCanAccess = I.CanAccess(cop, sus)
                    out.awayTake = call(H[ACT.MOVE], cop, { sus, I.ContID.Uniform, 1, ck(sus, I.ContID.Uniform, 1), cop, I.ContID.Uniform, 1 })
                    -- cancelled by distance before the end
                    cop:SetPos(Vector(-2800, -1800, -140))
                    RunConsoleCommand("advinv_search_time", "3")
                    timer.Simple(0.2, function()
                        call(H[ACT.SEARCH], cop, { 1, sus })
                        timer.Simple(0.5, function()
                            cop:SetPos(Vector(-2000, -1000, -140))
                            timer.Simple(0.6, function()
                                out.cancelled = { endTime = cop:GetNWFloat("AdvInvSearchEnd"), view = cop.AdvInvSearchView ~= nil }
                                RunConsoleCommand("advinv_search_mode", "1") RunConsoleCommand("advinv_search_time", "5")
                                I.IllegalItems["item_healthkit"] = nil
                                hook.Remove("AdvInv_Searched", "test")
                                done(out)
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end)
end)
