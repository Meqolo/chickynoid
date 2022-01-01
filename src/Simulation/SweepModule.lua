--[=[
    @class SweepModule

    Used to calculate collisions
]=]

local SweepModule = {}
SweepModule.raycastsThisFrame = 0

local rings = {}

local RADIUS = 2.5
local DEBUG_MODE = false

--[=[
    Creates <steps> amount of contacts in a ring of size <steps>
    @private

    @param steps number -- The number of contacts in a ring
    @param radius number -- The radius of that specific ring
    @param totalRadius number -- The total radius of the sphere
]=]

function SweepModule:_makeRing(steps: number, radius: number, totalRadius: number)
    local latitude = (radius * math.pi) * 0.5
    for counter = 0, steps - 1 do
        local longitude = ((math.pi * 2) / steps) * counter

        local x = totalRadius * math.cos(longitude) * math.sin(latitude)
        local y = totalRadius * math.sin(longitude) * math.sin(latitude)
        local z = totalRadius * math.cos(latitude)

        table.insert(rings, Vector3.new(x, z, y))
    end
end

--[=[
    Creates contact rings
    @private
]=]
function SweepModule:_initRings()
    self:_makeRing(1, 0.0, RADIUS)
    self:_makeRing(8, 0.2, RADIUS)
    self:_makeRing(10, 0.4, RADIUS)
    self:_makeRing(12, 0.6, RADIUS)
    self:_makeRing(14, 0.8, RADIUS)
    self:_makeRing(16, 1, RADIUS)
    self:_makeRing(14, 1.2, RADIUS)
    self:_makeRing(12, 1.4, RADIUS)
    self:_makeRing(10, 1.6, RADIUS)
    self:_makeRing(8, 1.8, RADIUS)
    self:_makeRing(1, 2.0, RADIUS)
end

--[=[
    Creates a debug marker
    @private

    @param position Vector3 -- The position of the contact
    @param color Color3 -- The color of the contact
]=]
function SweepModule:_debugMarker(position, color)
    local part = Instance.new("Part")

    part.Position = position
    part.Color = color
    part.Size = Vector3.new(0.2, 0.2, 0.2)
    part.Anchored = true
    part.Shape = Enum.PartType.Ball
    part.Parent = workspace.DebugMarkers
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
end

--[=[
    Creates a debug beam
    @private

    @param a number -- The first position of the beam
    @param b number -- The second position of the beam
    @param color Color3 -- The color of the beam
]=]
function SweepModule:_debugBeam(a, b, color)
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

--[=[
    Ray/sphere interaction test that assumes the ray is going to either miss completely or hit the inside, perfect for capsules.
    @private
]=]
function SweepModule:_getDepth(centerOfSphere: Vector3, radius: number, rayPos: Vector3, rayUnitDir: Vector3): number
    local e = centerOfSphere - rayPos
    local esq = (e.x * e.x) + (e.y * e.y) + (e.z * e.z)
    local a = e:Dot(rayUnitDir)
    local b = math.sqrt(esq - (a * a))
    local f = math.sqrt((radius * radius) - (b * b))

    return a + f
end

--[=[
    Checks if any contacts are colliding with an object
    @public

    @param startPos Vector3 -- The start position of the ball
    @param endPos Vector3 -- The position the ball is trying to go to
    @param whiteList Dictionary<number> -- Table of whitelisted objects for the raycast
]=]
function SweepModule:SweepForContacts(startPos: Vector3, endPos: Vector3, whiteList: Dictionary<number>): table
    --Cast a bunch of rays

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Whitelist
    raycastParams.FilterDescendantsInstances = whiteList
    raycastParams.IgnoreWater = true

    local contacts = {}

    local rayVec = (endPos - startPos)
    local mag = rayVec.Magnitude
    local ray = rayVec.Unit

    for _key, value in pairs(rings) do
        if value:Dot(ray) > 0 then --We cast using the rays on the back of the sphere
            continue
        end

        local castPoint = startPos + value

        --Calculate the distance for this point along the ray to the back of the sphere (how much the ray has to be extended by to reach the other side)
        local dist = self:_getDepth(startPos, RADIUS, castPoint, ray)

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

--[=[
    Returns position, normal and time of a collision
    @public

    @param startPos Vector3 -- The start position of the ball
    @param endPos Vector3 -- The position the ball is trying to go to
    @param whiteList Dictionary<number> -- Table of whitelisted objects for the raycast
]=]
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

    if DEBUG_MODE == true then
        for _key, value in pairs(rings) do
            if value:Dot(ray) >= 0 then
                continue
            end
            local pos = value
            self:_debugMarker(startPos + pos, Color3.new(0.333333, 1, 0))
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

    for _key, value in pairs(rings) do
        if value:Dot(ray) > 0 then --We cast using the rays on the back of the sphere
            continue
        end

        local castPoint = startPos + value

        --Calculate the distance for this point along the ray to the back of the sphere (how much the ray has to be extended by to reach the other side)
        local dist = self:_getDepth(startPos, RADIUS, castPoint, ray)

        local raycastResult = workspace:Raycast(castPoint, (ray * (mag + dist)), raycastParams)
        self.raycastsThisFrame += 1

        if DEBUG_MODE == true then
            self:_debugMarker(castPoint + (ray * (dist + mag)), Color3.new(1, 0, 1))
        end

        if raycastResult then
            if DEBUG_MODE == true then
                self:_debugBeam(castPoint, raycastResult.Position, Color3.new(1, 1, 0))
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
    end

    if DEBUG_MODE == true then
        if bestPos ~= nil then
            self:_debugMarker(bestPos, Color3.new(1, 1, 1))
        end
    end

    return { endPos = bestPos, normal = bestNormal, contact = bestContact, fraction = fraction }
end

--utilities, didn't need them!
function SweepModule:_intersect(planeP, planeN, rayP, rayD)
    local d = planeP:Dot(-planeN)
    local t = -(d + rayP.Z * planeN.Z + rayP.Y * planeN.Y + rayP.X * planeN.X)
        / (rayD.Z * planeN.Z + rayD.Y * planeN.Y + rayD.X * planeN.X)
    return rayP + t * rayD
end

function SweepModule:_distanceToPlane(planeP, planeN, p)
    return planeN:Dot(p - planeP)
end

function SweepModule:_sweepSphere(planePoint, planeNormal, startPos, endPos)
    --we intersected a plane
    local d0 = self:_distanceToPlane(planePoint, planeNormal, startPos)
    local d1 = self:_distanceToPlane(planePoint, planeNormal, endPos)

    if math.abs(d0) < RADIUS then
        --start stuck
        return startPos, 0
    else
        --calculate exact time of collision
        if d0 > RADIUS and d1 < RADIUS then
            local fraction = (d0 - RADIUS) / (d0 - d1)
            fraction -= 0.001
            local pos = ((1 - fraction) * startPos) + (fraction * endPos)

            return pos, fraction
        end
        --Error
        return Vector3.zero, 0
    end
end

SweepModule:_initRings()

return SweepModule
