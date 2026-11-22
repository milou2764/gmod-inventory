local I = AdvInv
local idOf = {}
for id, c in pairs(AdvInv.IDClass) do idOf[c] = id end
local p = player.GetBots()[1]
I.Set(p, "Uniform", {})
I.Store(p, { id = idOf.advinv_hl2_pistol, r = 12 })
local real = { net.ReadUInt, net.ReadEntity, net.ReadBool }
local q, k = { false, p, I.ContID.Uniform, 1 }, 0
local function nxt() k = k + 1 return q[k] end
net.ReadUInt, net.ReadEntity, net.ReadBool = nxt, nxt, nxt
local ok, a, b = pcall(I.ActHandlers[I.ACT.UNLOAD], p)
net.ReadUInt, net.ReadEntity, net.ReadBool = real[1], real[2], real[3]
local t = {}
for _, it in ipairs(I.Get(p, "Uniform")) do t[#t + 1] = AdvInv.IDClass[it.id] .. "(" .. (it.r or 0) .. ")" end
return { ok = ok, res = { a, b }, uniform = table.concat(t, " ") }
