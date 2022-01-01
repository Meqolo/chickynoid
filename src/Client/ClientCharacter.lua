local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local ClientTransport = require(script.Parent.ClientTransport)
local Simulation = require(script.Parent.Parent.Simulation)

local Enums = require(script.Parent.Parent.Enums)
local EventType = Enums.EventType

local Camera = workspace.CurrentCamera

local LocalPlayer = Players.LocalPlayer
local PlayerModule = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
local ControlModule = require(PlayerModule:WaitForChild("ControlModule"))

local DebugParts = Instance.new("Folder")
DebugParts.Name = "DebugParts"
DebugParts.Parent = workspace

local SKIP_RESIMULATION = true
local DEBUG_SPHERES = false
local PRINT_NUM_CASTS = false

local ClientCharacter = {}
ClientCharacter.__index = ClientCharacter

function ClientCharacter.new(player: Player, position: Vector3)
    local self = setmetatable({
        _player = player,
        _simulation = Simulation.new(),

        _predictedCommands = {},
        _stateCache = {},

        _localFrame = 0,
    }, ClientCharacter)

    self._simulation.position = position
    self._simulation.whiteList = { workspace.GameArea, workspace.Terrain }

    if player == LocalPlayer then
        self:_handleLocalPlayer()
    end

    return self
end

function ClientCharacter:_handleLocalPlayer()
    -- Bind the camera
    Camera.CameraSubject = self._simulation.debugModel
    Camera.CameraType = Enum.CameraType.Custom
end

function ClientCharacter:_makeCommand(dt: number)
    local command = {}
    command.l = self._localFrame

    command.x = 0
    command.y = 0
    command.z = 0
    command.deltaTime = dt

    local moveVector = ControlModule:GetMoveVector() :: Vector3
    if moveVector.Magnitude > 0 then
        moveVector = moveVector.Unit
        command.x = moveVector.X
        command.y = moveVector.Y
        command.z = moveVector.Z
    end

    -- This approach isn't ideal but it's the easiest right now
    if not UserInputService:GetFocusedTextBox() then
        command.y = UserInputService:IsKeyDown(Enum.KeyCode.Space) and 1 or 0
    end

    local rawMoveVector = self:_calculateRawMoveVector(Vector3.new(command.x, 0, command.z))
    command.x = rawMoveVector.X
    command.z = rawMoveVector.Z

    return command
end

function ClientCharacter:_calculateRawMoveVector(cameraRelativeMoveVector: Vector3)
    local _, yaw = Camera.CFrame:ToEulerAnglesYXZ()
    return CFrame.fromEulerAnglesYXZ(0, yaw, 0) * Vector3.new(cameraRelativeMoveVector.X, 0, cameraRelativeMoveVector.Z)
end

function ClientCharacter:HandleNewState(state: table, lastConfirmed: number)
    self:_clearDebugSpheres()

    -- Build a list of the commands the server has not confirmed yet
    local remainingCommands = {}
    for _, cmd in pairs(self._predictedCommands) do
        -- event.lastConfirmed = serial number of last confirmed command by server

        if lastConfirmed and cmd.l > lastConfirmed then
            -- Server hasn't processed this yet
            table.insert(remainingCommands, cmd)
        end
    end
    self._predictedCommands = remainingCommands

    local resimulate = true

    -- Check to see if we can skip simulation
    if SKIP_RESIMULATION then
        local record = self._stateCache[lastConfirmed]
        if record then
            -- This is the state we were in, if the server agrees with this, we dont have to resim
            if
                (record.state.position - state.position).magnitude < 0.01
                and (record.state.velocity - state.velocity).magnitude < 0.01
            then
                resimulate = false
                -- print("skipped resim")
            end
        end

        -- Clear all the ones older than lastConfirmed
        for key, _ in pairs(self._stateCache) do
            if lastConfirmed and key < lastConfirmed then
                self._stateCache[key] = nil
            end
        end
    end

    if resimulate == true then
        print("resimulating")

        -- Record our old state
        local oldPos = self._simulation.position

        -- Reset our base simulation to match the server
        self._simulation:ReadState(state)

        -- Marker for where the server said we were
        self:_spawnDebugSphere(self._simulation.position, Color3.fromRGB(255, 170, 0))

        -- Resimulate all of the commands the server has not confirmed yet
        -- print("winding forward", #remainingCommands, "commands")
        for _, cmd in pairs(remainingCommands) do
            self._simulation:ProcessCommand(cmd)

            -- Resimulated positions
            self:_spawnDebugSphere(self._simulation.position, Color3.fromRGB(255, 255, 0))
        end

        -- Did we make a misprediction? We can tell if our predicted position isn't the same after reconstructing everything
        local delta = oldPos - self._simulation.position
        if delta.magnitude > 0.01 then
            print("Mispredict:", delta)
        end
    end
end

function ClientCharacter:Heartbeat(dt: number)
    self._localFrame += 1

    -- Read user input
    local cmd = self:_makeCommand(dt)
    table.insert(self._predictedCommands, cmd)

    -- Step this frame
    self._simulation:ProcessCommand(cmd)

    -- Marker for positions added since the last server update
    self:_spawnDebugSphere(self._simulation.position, Color3.fromRGB(44, 140, 39))

    if SKIP_RESIMULATION then
        -- Add to our state cache, which we can use for skipping resims
        local cacheRecord = {}
        cacheRecord.l = cmd.l
        cacheRecord.state = self._simulation:WriteState()

        self._stateCache[cmd.l] = cacheRecord
    end

    -- Pass to server
    ClientTransport:QueueEvent(EventType.Command, {
        command = cmd,
    })
    ClientTransport:Flush()

    if PRINT_NUM_CASTS then
        print("casts", self._simulation.sweepModule.raycastsThisFrame)
    end
    self._simulation.sweepModule.raycastsThisFrame = 0
end

function ClientCharacter:_spawnDebugSphere(position, color)
    if DEBUG_SPHERES then
        local part = Instance.new("Part")
        part.Anchored = true
        part.Color = color
        part.Shape = Enum.PartType.Ball
        part.Size = Vector3.new(5, 5, 5)
        part.Position = position
        part.Transparency = 0.25
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth

        part.Parent = DebugParts
    end
end

function ClientCharacter:_clearDebugSpheres()
    if DEBUG_SPHERES then
        DebugParts:ClearAllChildren()
    end
end

return ClientCharacter
