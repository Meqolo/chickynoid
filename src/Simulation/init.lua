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
    @public
]=]

function Simulation.new()
    local self = setmetatable({
        position = Vector3.new(0, 5, 0),
        velocity = Vector3.new(0, 0, 0),

        remainingJump = 0, -- Remaining jump power
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
        part.Anchored = true
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth
        part.Transparency = 0.4
        part.Material = Enum.Material.SmoothPlastic
        part.Color = Color3.new(0, 1, 1)

        model.Name = "Chickynoid"
        model.PrimaryPart = part

        self.debugModel = model
        self.debugMarker = part

        debugPart.Shape = Enum.PartType.Cylinder
        debugPart.Anchored = true
        debugPart.CanQuery = false
        debugPart.CanCollide = false
        debugPart.CanTouch = false
        debugPart.Size = Vector3.new(0.01, 3.5, 3.5)
        debugPart.CFrame = CFrame.new(Vector3.new(0, PLAYER_FEET_HEIGHT))
            * CFrame.fromEulerAnglesXYZ(0, 0, math.rad(90))

        model.Parent = Workspace
        part.Parent = model
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
    @public

    @param command table -- The command to be processed
]=]

function Simulation:ProcessCommand(command: table)
    local maxSpeed = 24 * UNITS_PER_SECOND
    local accel = 400 * UNITS_PER_SECOND
    local jumpPunch = 50 * UNITS_PER_SECOND
    local brakeAccel = 400 * UNITS_PER_SECOND --how hard to brake if we're turning around

    local onGround, onLedge = self:_doGroundCheck(self.position, PLAYER_FEET_HEIGHT)
    local desiredDirection = nil
    local flatVelocity = Vector3.new(self.velocity.X, 0, self.velocity.Z)
    local shouldBrake = false

    --selene: allow(empty_if)
    if onGround == nil then
        --Figure out our acceleration (airmove vs on ground)
        --different if we're in the air?
    end

    if command.x ~= 0 or command.z ~= 0 then
        desiredDirection = Vector3.new(command.x, 0, command.z).Unit
    end

    if (desiredDirection and desiredDirection:Dot(flatVelocity.Unit) < -0.1) or (onGround and not desiredDirection) then
        shouldBrake = true
    end

    if shouldBrake == true then
        flatVelocity = self:_accelerate(Vector3.zero, maxSpeed, brakeAccel, flatVelocity, command.deltaTime)
    end

    --movement acceleration (walking/running/airmove)
    --Does nothing if we don't have an input
    if desiredDirection then
        flatVelocity = self:_accelerate(desiredDirection, maxSpeed, accel, flatVelocity, command.deltaTime)
    end

    self.velocity = Vector3.new(flatVelocity.X, self.velocity.Y, flatVelocity.Z)

    if onGround then
        if self.remainingJump > 0 then
            self.remainingJump -= command.deltaTime
        end

        --jump!
        if command.y > 0 and self.remainingJump <= 0 then
            self.velocity += Vector3.new(0, jumpPunch * (1 + self.remainingJump), 0)
            self.remainingJump = 0.2
        end
    elseif not onGround then
        -- Gravity
        self.velocity += Vector3.new(0, -198 * UNITS_PER_SECOND * command.deltaTime, 0)
    end

    --Sweep the player through the world
    local walkNewPos, walkNewVel, hitSomething = self:_projectVelocity(self.position, self.velocity)

    --STEPUP - the magic that lets us traverse uneven world geometry
    --the idea is that you redo the player movement but "if I was x units higher in the air"
    --it adds a lot of extra casts...

    flatVelocity = Vector3.new(self.velocity.X, 0, self.velocity.Z)
    if (onGround or onLedge) and hitSomething then
        -- If we need to do so, then we first move up as high as we can, then project forward before tracing down again

        local headHit = self.sweepModule:Sweep(
            self.position,
            self.position + Vector3.new(0, MAX_STEP_SIZE, 0),
            self.whiteList
        )
        local stepUpPos, stepUpVel, _stepHit = self:_projectVelocity(headHit.endPos, flatVelocity)
        local traceDownPos = stepUpPos

        local hitResult = self.sweepModule:Sweep(
            traceDownPos,
            traceDownPos - Vector3.new(0, MAX_STEP_SIZE, 0),
            self.whiteList
        )

        stepUpPos = hitResult.endPos

        --See if we're mostly on the ground after this? otherwise rewind it
        local nowOnGround, _onLedge = self:_doGroundCheck(stepUpPos, (-2.5 + MAX_STEP_SIZE))

        if nowOnGround then
            self.position = stepUpPos
            self.velocity = stepUpVel
        else
            self.position = walkNewPos
            self.velocity = walkNewVel
        end
    else
        --NO STEPUP
        self.position = walkNewPos
        self.velocity = walkNewVel
    end

    --See if our feet are dangling but we're on a ledge
    --If so, slide/push away from the ledge position
    if not onGround and onLedge then
        local ledgePosition = onLedge.Position
        local direction = Vector3.new(self.position.X - ledgePosition.X, 0, self.position.Z - ledgePosition.Z)
        flatVelocity = Vector3.new(self.velocity.X, 0, self.velocity.Z)

        local velocityChange = self:_accelerate(direction.unit, maxSpeed, 2, flatVelocity, command.deltaTime)
        if velocityChange.X == velocityChange.X then --nan check
            self.velocity = Vector3.new(velocityChange.X, self.velocity.Y, velocityChange.Z)
        end
    end

    --position the debug visualizer
    if self.debugModel then
        self.debugModel:PivotTo(CFrame.new(self.position))
    end
end

--[=[
    Calculates final velocity from a desired direction, speed and acceleration over a given time
    @private

    @param desiredDirection Vector3 -- The desired direction
    @param desiredSpeed Vector3 -- The desired speed
    @param acceleration number -- The desired acceleration not accounting for time taken 
    @param initialVelocity Vector3 -- The initial velocity of the character
    @param deltaTime number -- The time taken to accelerate

    @return finalVelocity Vector3 -- The calculated velocity
]=]
function Simulation:_accelerate(
    desiredDirection: Vector3,
    desiredSpeed: Vector3,
    acceleration: number,
    initialVelocity: Vector3,
    deltaTime: number
): Vector3
    local desiredVelocity = desiredDirection * desiredSpeed
    local pushDirection = desiredVelocity - initialVelocity
    local pushMagnitude = pushDirection.Magnitude

    if pushMagnitude < 0.01 then
        return initialVelocity
    end

    local canPush = acceleration * deltaTime * desiredSpeed
    if canPush > pushMagnitude then
        canPush = pushMagnitude
    end

    return initialVelocity + (pushDirection.Unit * canPush)
end

--[=[
    Checks whether the character is on the ground or on a ledge and returns 
    the position of the ground or ledge if it is.
    @public

    @param position Vector3 -- The position from which to check
    @param feetHeight number -- The height of the characters feet

    @return onGround RaycastResult? -- The result of the raycast if on the ground
    @return onLedge RaycastResult? -- The result of the raycast if on a ledge
]=]
function Simulation:_doGroundCheck(position: Vector3, feetHeight: number): (RaycastResult?, RaycastResult?)
    local contacts = self.sweepModule:SweepForContacts(position, position + Vector3.new(0, -0.1, 0), self.whiteList)
    local onGround = nil
    local onLedge = nil

    for _key, raycastResult in pairs(contacts) do
        local contactVariation = raycastResult.Position.Y - self.position.Y

        if contactVariation < feetHeight then
            onGround = raycastResult
        elseif contactVariation < 0 then
            onLedge = raycastResult
        end

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
function Simulation:_clipVelocity(input: Vector3, normal: Vector3, overbounce: number): Vector3
    local backoff = input:Dot(normal)

    if backoff < 0 then
        backoff = backoff * overbounce
    else
        backoff = backoff / overbounce
    end

    local change = normal * backoff

    return input - change
end

--[=[
    Project the velocity and check if any objects are collided with, then clip the velocity if there is

    @param initialPosition Vector3 -- The initial position before projecting velocity
    @param initialVelocity Vector3 -- The unclipped and unprojected velocity which is being moved at

    @return movePos Vector3 -- The position to move to
    @return moveVel Vector3 -- The velocity to move to
    @return hitSomething boolean -- Whether an object was hit
]=]
function Simulation:_projectVelocity(initialPosition: Vector3, initialVelocity: Vector3): (Vector3, Vector3, boolean)
    local movePosition = initialPosition
    local moveVelocity = initialVelocity
    local hitSomething = false

    --Project our movement through the world
    for _ = 0, 3 do
        if moveVelocity.Magnitude < 0.001 then
            break
        elseif moveVelocity:Dot(initialVelocity) < 0 then
            moveVelocity = Vector3.zero
            break
        end

        local result = self.sweepModule:Sweep(movePosition, movePosition + moveVelocity, self.whiteList)

        if result.fraction < 1 then
            hitSomething = true
        end

        --selene: allow(empty_if)
        if result.fraction == 0 then
            --Collided with object, so do nothing. However, in future we want to implement projecting along the normal
        else
            --See if we swept the whole way?
            if result.fraction == 1 then
                movePosition += moveVelocity
                break
            elseif result.fraction > 0 then
                movePosition += (moveVelocity * result.fraction)
            end
        end

        --Deflect the velocity and keep going
        moveVelocity = self:_clipVelocity(moveVelocity, result.normal, 1.0)
    end

    return movePosition, moveVelocity, hitSomething
end

--[=[
    Writes the current state of the character to a record which is then returned
    @public

    @return record table -- The state of the character
]=]
function Simulation:WriteState(): table
    return {
        position = self.position,
        velocity = self.velocity,
    }
end

--[=[
    Writes from a record to the characters' state
    @public

    @param record table -- The record from which the characters state is written
]=]
function Simulation:ReadState(record: table)
    self.position = record.position
    self.velocity = record.velocity
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
