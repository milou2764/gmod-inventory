include("shared.lua")

-- Gear drawn from a playermodel (sh_modelgear_items.lua): the model moved so that the gear's centre is
-- the entity's origin (where its physics hull is), its bounds those of the hull, the same hull here for
-- traces (looking at it, picking it up).
function ENT:Initialize()
    if not self.ModelOrigin then return end
    self:DrawShadow(false) -- (shadows ignore the hidden parts' material: the whole body would cast one)
    local m = Matrix()
    m:Translate(-self.ModelOrigin)
    self:EnableMatrix("RenderMultiply", m)
    if self.PhysHull then
        local mn, mx = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
        for _, p in ipairs(self.PhysHull) do
            mn = Vector(math.min(mn.x, p.x), math.min(mn.y, p.y), math.min(mn.z, p.z))
            mx = Vector(math.max(mx.x, p.x), math.max(mx.y, p.y), math.max(mx.z, p.z))
        end
        self:SetRenderBounds(mn, mx)
        self:PhysicsInitConvex(self.PhysHull)
        self:EnableCustomCollisions(true)
    end
end

function ENT:Draw(flags)
    if self.ModelPieces then -- stored look in pieces (pouches with nothing between them, pushed together)
        AdvInv.DrawModelPieces(self, self.ModelPieces, flags, -self.ModelOrigin)
    else
        self:DrawModel(flags)
    end
    -- parts on the hidden body's material, drawn apart (sh_modelgear_items.lua)
    if self.ModelSharedLooks then AdvInv.DrawSharedParts(self, self, false, -self.ModelOrigin, true) end
end
