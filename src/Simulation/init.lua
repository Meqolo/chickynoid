--!strict

--[=[
    @class Simulation

    Class for simulating the movement of the character
]=]
local Workspace = game:GetService("Workspace")

local Simulation = {}
Simulation.__index = Simulation
Simulation.sweepModule = require(script.SweepModule)

local PLAYER_FEET_HEIGHT = -1.9 -- Any point below this is considered the players' foot, any point between the feet and the middle is considered a ledge
local MAX_STEP_SIZE = 2.1
local UNITS_PER_SECOND = 1 / 60
local CREATE_DEBUG_SPHERE = true
local DEBUG_SPHERE_DIAMETER = 5

--[=[
    Initialises the simulation class
]=]

function Simulation.new()
    local self = setmetatable({
        pos = Vector3.new(0, 5, 0),
        vel = Vector3.new(0, 0, 0),

        jump = 0, -- Remaining jump power
        whiteList = { Workspace },
    }, Simulation)

    self:_createDebugSphere()

    return self
end

--[=[
    Creates the debug sphere if it is enabled

    @private
]=]

function Simulation:_createDebugSphere()
    if CREATE_DEBUG_SPHERE then
        local model = Instance.new("Model")
        local part = Instance.new("Part")
        local debugPart = Instance.new("Part")

        part.Size = Vector3.new(DEBUG_SPHERE_DIAMETER, DEBUG_SPHERE_DIAMETER, DEBUG_SPHERE_DIAMETER)
        part.Shape = Enum.PartType.Ball
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.Parent = model
        part.Anchored = true
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth
        part.Transparency = 0.4
        part.Material = Enum.Material.SmoothPlastic
        part.Color = Color3.new(0, 1, 1)

        model.Name = "Chickynoid"
        model.PrimaryPart = part
        model.Parent = Workspace

        self.debugModel = model
        self.debugMarker = part

        debugPart.Shape = Enum.PartType.Cylinder
        debugPart.Anchored = true
        debugPart.Parent = model
        debugPart.CanQuery = false
        debugPart.CanCollide = false
        debugPart.CanTouch = false
        debugPart.Size = Vector3.new(0.01, 3.5, 3.5)

        debugPart.CFrame = CFrame.new(Vector3.new(0, PLAYER_FEET_HEIGHT))
            * CFrame.fromEulerAnglesXYZ(0, 0, math.rad(90))
    end
end

--[=[
    Processes any commands which are sent and performs required actions.
    Actions performed are:
        - Calculate position and velocity due to input
        - Calculate position and velocity due to jumping
        - Calculate position and velocity due to gravity

    Ensure that this only relies on the data in the cmd object, and no other
    data can leak into this. If there is other data there will be desync
    between server and client state.

    @param cmd table -- The command to be processed
]=]

function Simulation:ProcessCommand(cmd: table)
    --Ground parameters
    local maxSpeed = 24 * UNITS_PER_SECOND
    local accel = 400 * UNITS_PER_SECOND
    local jumpPunch = 50 * UNITS_PER_SECOND
    local brakeAccel = 400 * UNITS_PER_SECOND --how hard to brake if we're turning around

    local result = nil
    local onGround = nil
    local onLedge = nil

    --Check ground
    onGround, onLedge = self:DoGroundCheck(self.pos, PLAYER_FEET_HEIGHT)

    --Figure out our acceleration (airmove vs on ground)
    if onGround == nil then
        --different if we're in the air?
    end

    --Did the player have a movement request?
    local wishDir = nil
    local flatVel = Vector3.new(self.vel.x, 0, self.vel.z)

    if cmd.x ~= 0 or cmd.z ~= 0 then
        wishDir = Vector3.new(cmd.x, 0, cmd.z).Unit
    end

    --see if we're accelerating back against our current flatvel
    local shouldBrake = false
    if wishDir ~= nil and wishDir:Dot(flatVel.Unit) < -0.1 then
        shouldBrake = true
    end
    if onGround ~= nil and wishDir == nil then
        shouldBrake = true
    end
    if shouldBrake == true then
        flatVel = self:Accelerate(Vector3.zero, maxSpeed, brakeAccel, flatVel, cmd.deltaTime)
    end

    --movement acceleration (walking/running/airmove)
    --Does nothing if we don't have an input
    if wishDir ~= nil then
        flatVel = self:Accelerate(wishDir, maxSpeed, accel, flatVel, cmd.deltaTime)
    end

    self.vel = Vector3.new(flatVel.x, self.vel.y, flatVel.z)

    --Do jumping?
    if onGround ~= nil then
        if self.jump > 0 then
            self.jump -= cmd.deltaTime
        end

        --jump!
        if cmd.y > 0 and self.jump <= 0 then
            self.vel += Vector3.new(0, jumpPunch * (1 + self.jump), 0)
            self.jump = 0.2
        end
    end

    --Gravity
    if onGround == nil then
        --gravity
        self.vel += Vector3.new(0, -198 * UNITS_PER_SECOND * cmd.deltaTime, 0)
    end

    --Sweep the player through the world
    local walkNewPos, walkNewVel, hitSomething = self:ProjectVelocity(self.pos, self.vel)

    --STEPUP - the magic that lets us traverse uneven world geometry
    --the idea is that you redo the player movement but "if I was x units higher in the air"
    --it adds a lot of extra casts...

    local flatVel = Vector3.new(self.vel.x, 0, self.vel.z)
    -- Do we even need to?
    if (onGround ~= nil or onLedge ~= nil) and hitSomething == true then
        --first move upwards as high as we can go
        local headHit = self.sweepModule:Sweep(self.pos, self.pos + Vector3.new(0, MAX_STEP_SIZE, 0), self.whiteList)

        --Project forwards
        local stepUpNewPos, stepUpNewVel, stepHitSomething = self:ProjectVelocity(headHit.endPos, flatVel)

        --Trace back down
        local traceDownPos = stepUpNewPos

        local hitResult = self.sweepModule:Sweep(
            traceDownPos,
            traceDownPos - Vector3.new(0, MAX_STEP_SIZE, 0),
            self.whiteList
        )

        stepUpNewPos = hitResult.endPos

        --See if we're mostly on the ground after this? otherwise rewind it
        local ground, ledge = self:DoGroundCheck(stepUpNewPos, (-2.5 + MAX_STEP_SIZE))

        if ground ~= nil then
            self.pos = stepUpNewPos
            self.vel = stepUpNewVel
        else
            --cancel the whole thing
            --NO STEPUP
            self.pos = walkNewPos
            self.vel = walkNewVel
        end
    else
        --NO STEPUP
        self.pos = walkNewPos
        self.vel = walkNewVel
    end

    --See if our feet are dangling but we're on a ledge
    --If so, slide/push away from the ledge pos
    if onGround == nil and onLedge ~= nil then
        local pos = onLedge.Position

        local dir = Vector3.new(self.pos.x - pos.x, 0, self.pos.z - pos.z)
        local flatVel = Vector3.new(self.vel.x, 0, self.vel.z)

        local velChange = self:Accelerate(dir.unit, maxSpeed, 2, flatVel, cmd.deltaTime)
        if velChange.x == velChange.x then --nan check
            self.vel = Vector3.new(velChange.x, self.vel.y, velChange.z)
        end
    end

    --position the debug visualizer
    if self.debugModel then
        self.debugModel:PivotTo(CFrame.new(self.pos))
    end
end

--[=[
    Calculates final velocity from a desired direction, speed and acceleration over a given time

    @param wishdir Vector3 -- The desired direction
    @param wishspeed Vector3 -- The desired speed
    @param accel Vector3 -- The desired acceleration not accounting for time taken 
    @param velocity Vector3 -- The initial velocity of the character
    @param dt number -- The time taken to accelerate

    @return finalVelocity Vector3 -- The calculated velocity
]=]
function Simulation:Accelerate(
    wishdir: Vector3,
    wishspeed: Vector3,
    accel: Vector3,
    velocity: Vector3,
    dt: number
): Vector3
    local wishVelocity = wishdir * wishspeed
    local pushDir = wishVelocity - velocity
    local pushLen = pushDir.Magnitude

    if pushLen < 0.01 then
        return velocity
    end

    local canPush = accel * dt * wishspeed
    if canPush > pushLen then
        canPush = pushLen
    end

    return velocity + (pushDir.Unit * canPush)
end

--[=[
    Checks whether the character is on the ground or on a ledge and returns 
    the position of the ground or ledge if it is.

    @param pos Vector3 -- The position from which to check
    @param feetHeight number -- The height of the characters feet

    @return onGround RaycastResult? -- The result of the raycast if on the ground
    @return onLedge RaycastResult? -- The result of the raycast if on a ledge
]=]
function Simulation:DoGroundCheck(pos: Vector3, feetHeight: number): (RaycastResult?, RaycastResult?)
    local contacts = self.sweepModule:SweepForContacts(pos, pos + Vector3.new(0, -0.1, 0), self.whiteList)
    local onGround = nil
    local onLedge = nil

    --check if we're on the ground
    for key, raycastResult in pairs(contacts) do
        --How far down the sphere was the contact
        local dif = raycastResult.Position.y - self.pos.y
        if dif < feetHeight then
            onGround = raycastResult
            --print("og")
        elseif dif < 0 then --Something is touching our sphere between the middle and the feet
            onLedge = raycastResult
            --print("ledge")
        end
        --early out
        if onGround and onLedge then
            return onGround, onLedge
        end
    end
    return onGround, onLedge
end

--[=[
    Clip the velocity

    @param input Vector3 -- The input velocity
    @param normal Vector3 -- The normal of ??
    @param overbounce number -- ??

    @return clippedVelocity Vector3 -- The clipped velocity
]=]
function Simulation:ClipVelocity(input: Vector3, normal: Vector3, overbounce: number): Vector3
    local backoff = input:Dot(normal)

    if backoff < 0 then
        backoff = backoff * overbounce
    else
        backoff = backoff / overbounce
    end

    local changex = normal.x * backoff
    local changey = normal.y * backoff
    local changez = normal.z * backoff

    return Vector3.new(input.x - changex, input.y - changey, input.z - changez)
end

--[=[
    Project the velocity and check if any objects are collided with, then clip the velocity if there is

    @param startPos Vector3 -- The initial position before projecting velocity
    @param startVel Vector3 -- The unclipped and unprojected velocity which is being moved at

    @return movePos Vector3 -- The position to move to
    @return moveVel Vector3 -- The velocity to move to
    @return hitSomething boolean -- Whether an object was hit
]=]
function Simulation:ProjectVelocity(startPos: Vector3, startVel: Vector3): (Vector3, Vector3, boolean)
    local movePos = startPos
    local moveVel = startVel
    local hitSomething = false

    --Project our movement through the world
    for bumps = 0, 3 do
        if moveVel.Magnitude < 0.001 then
            --done
            break
        end

        if moveVel:Dot(startVel) < 0 then
            --we projected back in the opposite direction from where we started. No.
            moveVel = Vector3.new(0, 0, 0)
            break
        end

        local result = self.sweepModule:Sweep(movePos, movePos + moveVel, self.whiteList)

        if result.fraction < 1 then
            hitSomething = true
        end

        if result.fraction == 0 then
            --start solid, don't do anything
            --(this doesn't mean we wont project along a normal!)
        else
            --See if we swept the whole way?
            if result.fraction == 1 then
                --Made it whole way
                movePos = movePos + moveVel

                break
            end

            if result.fraction > 0 then
                --We moved
                movePos = movePos + (moveVel * result.fraction)
            end
        end

        --Deflect the velocity and keep going
        moveVel = self:ClipVelocity(moveVel, result.normal, 1.0)
    end
    return movePos, moveVel, hitSomething
end

--[=[
    Writes the current state of the character to a record which is then returned

    @return record table -- The state of the character
]=]
function Simulation:WriteState(): table
    local record = {}
    record.pos = self.pos
    record.vel = self.vel

    return record
end

--[=[
    Writes from a record to the characters' state

    @param record table -- The record from which the characters state is written
]=]
function Simulation:ReadState(record: table)
    self.pos = record.pos
    self.vel = record.vel
end

--[=[
    Destroys the simulation class
]=]
function Simulation:Destroy()
    if self.debugModel then
        self.debugModel:Destroy()
    end
end

return Simulation
