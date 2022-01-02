local SweepModule = {}

local rings = {}

local debug = 1
SweepModule.raycastsThisFrame = 0

local constants = {}
constants.radius = 2.5

function SweepModule:MakeContacts(stepsX, stepsY, stepsZ, partSize, offsetAmount)
    for countX = 0, stepsX - 1 do
        local x = (partSize.X / stepsX) * countX
        for countY = 0, stepsY - 1 do
            local y = (partSize.Y / stepsY) * countY
            for countZ = 0, stepsZ - 1 do
                local z = (partSize.Z / stepsZ) * countZ
                table.insert(rings, Vector3.new(x, y, z) + offsetAmount)
            end
        end
    end
end

function SweepModule:InitContacts(partSize)
    self:MakeContacts(5, 5, 1, partSize, Vector3.new(0, 0, partSize.Z / 2))
    self:MakeContacts(5, 5, 1, partSize, Vector3.new(0, 0, -partSize.Z / 2))

    self:MakeContacts(1, 5, 1, partSize, Vector3.new(partSize.X / 2, 0, 0))
    self:MakeContacts(1, 5, 1, partSize, Vector3.new(-partSize.X / 2, 0, 0))
    self:MakeContacts(5, 1, 1, partSize, Vector3.new(0, partSize / 2, 0))
    self:MakeContacts(5, 1, 1, partSize, Vector3.new(0, -partSize / 2, 0))
end

function SweepModule:DebugMarker(pos, color)
    local part = Instance.new("Part")

    part.Position = pos
    part.Color = color
    part.Size = Vector3.new(0.2, 0.2, 0.2)
    part.Anchored = true
    part.Shape = Enum.PartType.Ball
    part.Parent = workspace.DebugMarkers
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
end

function SweepModule:DebugBeam(a, b, color)
    local d = (a - b).Magnitude

    local part = Instance.new("Part")
    part.Size = Vector3.new(0.1, 0.1, d)
    part.CFrame = CFrame.lookAt(a, b) * CFrame.new(Vector3.new(0, 0, -d * 0.5))
    part.Color = color
    part.Anchored = true
    part.CanQuery = false
    part.CanTouch = false
    part.CanCollide = false
    part.Parent = game.Workspace.DebugMarkers
end

--Short version of ray/sphere intersection test that assumes the ray is going to either miss completely or hit the inside, perfect for capsules.
function SweepModule:GetDepth(centerOfSphere, radius, rayPos, rayUnitDir)
    local e = centerOfSphere - rayPos
    -- print(e)
    -- self:DebugMarker(e + centerOfSphere, Color3.new(1, 0, 0))
    local esq = (e.x * e.x) + (e.y * e.y) + (e.z * e.z)
    local a = e:Dot(rayUnitDir)
    local b = math.sqrt(esq - (a * a))
    local f = math.sqrt((radius * radius) - (b * b))

    return a + f
end

function SweepModule:SweepForContacts(startPos, endPos, whiteList) --radius is fixed to 2.5
    --Cast a bunch of rays

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Whitelist
    raycastParams.FilterDescendantsInstances = whiteList
    raycastParams.IgnoreWater = true

    local contacts = {}

    local rayVec = (endPos - startPos)
    local mag = rayVec.Magnitude
    local ray = rayVec.Unit

    for key, value in pairs(rings) do
        if value:Dot(ray) > 0 then --We cast using the rays on the back of the sphere
            continue
        end

        local castPoint = startPos + value

        --Calculate the distance for this point along the ray to the back of the sphere (how much the ray has to be extended by to reach the other side)
        local dist = self:GetDepth(startPos, constants.radius, castPoint, ray)
        -- print(dist)

        local raycastResult = workspace:Raycast(castPoint, (ray * (mag + dist)), raycastParams)
        self.raycastsThisFrame += 1

        if raycastResult then
            --don't collide with orthogonal stuff
            if raycastResult.Normal:Dot(ray) > -0.00001 then
                continue
            end
            table.insert(contacts, raycastResult)
        end
    end
    return contacts
end

--Returns position, normal, time

function SweepModule:Sweep(startPos, endPos, whiteList) --radius is fixed to 2.5
    local debugMarkers = game.Workspace:FindFirstChild("DebugMarkers")
    if debugMarkers == nil then
        debugMarkers = Instance.new("Folder")
        debugMarkers.Name = "DebugMarkers"
        debugMarkers.Parent = game.Workspace
    end
    debugMarkers:ClearAllChildren()

    --early out
    local rayVec = (endPos - startPos)
    local mag = rayVec.Magnitude
    local ray = rayVec.Unit

    if mag < 0.00001 then
        return { endPos = startPos, normal = nil, contact = nil, fraction = 1 }
    end

    if debug >= 1 then
        for key, value in pairs(rings) do
            if value:Dot(ray) >= 0 then
                continue
            end
            local pos = value
            print(startPos)
            self:DebugMarker(startPos + pos, Color3.new(0.333333, 1, 0))
        end
    end

    --Cast a bunch of rays

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Whitelist
    raycastParams.FilterDescendantsInstances = whiteList
    raycastParams.IgnoreWater = true

    -- Cast the ray

    local bestClipped = 0
    local bestPos = endPos
    local bestContact = nil
    local bestNormal = nil

    local fraction = 1

    for key, value in pairs(rings) do
        if value:Dot(ray) > 0 then --We cast using the rays on the back of the sphere
            continue
        end

        local castPoint = startPos + value

        --Calculate the distance for this point along the ray to the back of the sphere (how much the ray has to be extended by to reach the other side)
        local dist = self:GetDepth(startPos, constants.radius, castPoint, ray)

        local raycastResult = workspace:Raycast(castPoint, (ray * (mag + dist)), raycastParams)
        self.raycastsThisFrame += 1

        if debug >= 1 then
            self:DebugMarker(castPoint + (ray * (dist + mag)), Color3.new(1, 0, 1))
        end

        if raycastResult then
            if debug >= 1 then
                self:DebugBeam(castPoint, raycastResult.Position, Color3.new(1, 1, 0))
            end

            --don't collide with orthogonal stuff
            if raycastResult.Normal:Dot(ray) > -0.01 then
                continue
            end

            --Did the ray even make it all the way through the sphere?
            if raycastResult.Distance < dist then
                return {
                    endPos = startPos,
                    normal = raycastResult.Normal,
                    contact = raycastResult.Position,
                    fraction = 0,
                } --we started solid
            end

            --How far the ray was short by?
            local clipped = (mag + dist) - raycastResult.Distance

            if clipped > bestClipped then
                bestClipped = clipped

                bestNormal = raycastResult.Normal
                bestContact = raycastResult.Position
            end
        end
    end

    if bestContact and bestNormal then
        --how much was the ray clipped short by
        bestPos = endPos - (ray * bestClipped)

        fraction = (startPos - bestPos).magnitude / mag

        if debug >= 1 then
            local part = Instance.new("Part")
            part.Shape = Enum.PartType.Ball
            part.Position = bestPos
            part.Color = Color3.new(0.666667, 0.333333, 1)
            part.Transparency = 0.75
            part.Size = Vector3.new(5, 5, 5)
            part.Anchored = true
            part.Parent = debugMarkers
            part.CanCollide = false
        end
    end

    if debug == true then
        if bestPos ~= nil then
            self:DebugMarker(bestPos, Color3.new(1, 1, 1))

            local part = Instance.new("Part")
            part.Shape = Enum.PartType.Ball
            part.Position = bestPos
            part.Color = Color3.new(0, 0.333333, 1)
            part.Transparency = 0.5
            part.Size = Vector3.new(5, 5, 5)
            part.Anchored = true
            part.Parent = debugMarkers
            part.CanCollide = false
        end

        local part = Instance.new("Part")
        part.Shape = Enum.PartType.Ball
        part.Position = startPos
        part.Color = Color3.new(0.666667, 0.333333, 1)
        part.Transparency = 0.5
        part.Size = Vector3.new(5, 5, 5)
        part.Anchored = true
        part.Parent = debugMarkers
        part.CanCollide = false

        local part = Instance.new("Part")
        part.Shape = Enum.PartType.Ball
        part.Position = endPos
        part.Color = Color3.new(1, 0, 0.498039)
        part.Transparency = 0.5
        part.Size = Vector3.new(5, 5, 5)
        part.Anchored = true
        part.Parent = debugMarkers
        part.CanCollide = false
    end

    return { endPos = bestPos, normal = bestNormal, contact = bestContact, fraction = fraction }
end

--utilities, didn't need them!
-- function SweepModule:Intersect(planeP, planeN, rayP, rayD)
--     local d = planeP:Dot(-planeN)
--     local t = -(d + rayP.Z * planeN.Z + rayP.Y * planeN.Y + rayP.X * planeN.X)
--         / (rayD.Z * planeN.Z + rayD.Y * planeN.Y + rayD.X * planeN.X)
--     return rayP + t * rayD
-- end

-- function SweepModule:DistanceToPlane(planeP, planeN, p)
--     return planeN:Dot(p - planeP)
-- end

-- function SweepModule:SweepSphere(planePoint, planeNormal, startPos, endPos)
--     --we intersected a plane
--     local d0 = self:DistanceToPlane(planePoint, planeNormal, startPos)
--     local d1 = self:DistanceToPlane(planePoint, planeNormal, endPos)

--     if math.abs(d0) < constants.radius then
--         --start stuck
--         return startPos, 0
--     else
--         --calculate exact time of collision
--         if d0 > constants.radius and d1 < constants.radius then
--             local fraction = (d0 - constants.radius) / (d0 - d1)
--             fraction -= 0.001
--             local pos = ((1 - fraction) * startPos) + (fraction * endPos)

--             return pos, fraction
--         end
--         --Error
--         return Vector3.zero, 0
--     end
-- end
-- SweepModule:InitRings()

return SweepModule
