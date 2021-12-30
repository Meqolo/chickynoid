local ChickynoidClient = {}

ChickynoidClient.settings = {}
ChickynoidClient.settings.skipResimulation = true
ChickynoidClient.settings.debugSpheres = false
ChickynoidClient.settings.debugShowNumCasts = false

ChickynoidClient.chickynoidModule = require(script.Parent.Simulation)
ChickynoidClient.chickynoid = nil
ChickynoidClient.localFrame = 0
ChickynoidClient.predictedCommands = {}
ChickynoidClient.remoteEvent = nil
ChickynoidClient.stateCache = {}

function ChickynoidClient:MakeCommand(deltaTime)
    local command = {}
    local UserInputService = game:GetService("UserInputService")

    command.l = self.localFrame

    command.x = 0
    command.y = 0
    command.z = 0
    command.deltaTime = deltaTime

    if not UserInputService:GetFocusedTextBox() then
        local keysPressed = UserInputService:GetKeysPressed()
        for i, v in pairs(keysPressed) do
            if v.KeyCode == Enum.KeyCode.W then
                command.z = -1
            elseif v.KeyCode == Enum.KeyCode.S then
                command.z = 1
            elseif v.KeyCode == Enum.KeyCode.A then
                command.x = -1
            elseif v.KeyCode == Enum.KeyCode.D then
                command.x = 1
            elseif v.KeyCode == Enum.KeyCode.Space then
                command.y = 1
            end
        end
    end

    local vec = self:CalculateRawMoveVector(Vector3.new(command.x, 0, command.z))
    command.x = vec.x
    command.z = vec.z

    return command
end

function ChickynoidClient:CalculateRawMoveVector(cameraRelativeMoveVector)
    local camera = game.Workspace.CurrentCamera

    if camera == nil then
        return cameraRelativeMoveVector
    end

    local c, s
    local _, _, _, R00, R01, R02, _, _, R12, _, _, R22 = camera.CFrame:GetComponents()
    if R12 < 1 and R12 > -1 then
        -- X and Z components from back vector.
        c = R22
        s = R02
    else
        -- In this case the camera is looking straight up or straight down.
        -- Use X components from right and up vectors.
        c = R00
        s = -R01 * math.sign(R12)
    end

    local norm = math.sqrt(c * c + s * s)

    return Vector3.new(
        (c * cameraRelativeMoveVector.x + s * cameraRelativeMoveVector.z) / norm,
        0,
        (c * cameraRelativeMoveVector.z - s * cameraRelativeMoveVector.x) / norm
    )
end

function ChickynoidClient:HandleEvent(event)
    if event.id == "spawn" then
        self.chickynoid = self.chickynoidModule.new()
        self.chickynoid.whiteList = { game.Workspace.GameArea, game.Workspace.Terrain }
        self.chickynoid.pos = event.pos
        self.predictedCommands = {}

        --Bind the camera
        game.Workspace.CurrentCamera.CameraSubject = self.chickynoid.debugModel
        game.Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom

        return
    end

    --server sent us a new state
    if event.id == "state" then
        self:ClearDebugSpheres()

        --Build a list of the commands the server has not confirmed yet
        local remainingCommands = {}
        for key, cmd in pairs(self.predictedCommands) do
            ---event.lc = serial number of last confirmed command by server
            if cmd.l > event.lc then
                --server hasn't processed this yet
                table.insert(remainingCommands, cmd)
            end
        end
        self.predictedCommands = remainingCommands

        local resimulate = true

        --check to see if we can skip simulation
        if self.settings.skipResimulation == true then
            local record = self.stateCache[event.lc]
            if record then
                --This is the state we were in, if the server agrees with this, we dont have to resim
                if
                    (record.state.pos - event.state.pos).magnitude < 0.01
                    and (record.state.vel - event.state.vel).magnitude < 0.01
                then
                    resimulate = false
                    --print("skipped resim")
                end
            end

            --clear all the ones older than LC
            for key, value in pairs(self.stateCache) do
                if key < event.lc then
                    self.stateCache[key] = nil
                end
            end
        end

        if resimulate == true then
            print("resimulating")

            --Record our old state
            local oldPos = self.chickynoid.pos
            local oldVel = self.chickynoid.vel

            --reset our base simulation to match the server
            self.chickynoid:ReadState(event.state)

            --marker for where the server said we were
            ChickynoidClient:SpawnDebugSphere(self.chickynoid.pos, Color3.fromRGB(255, 170, 0))

            --Resimulate all of the commands the server has not confirmed yet
            --print("winding forward", #self.remainingCommands, "commands")
            for key, cmd in pairs(remainingCommands) do
                self.chickynoid:ProcessCommand(cmd)

                --Resimulated positions
                ChickynoidClient:SpawnDebugSphere(self.chickynoid.pos, Color3.fromRGB(255, 255, 0))
            end

            --Did we make a misprediction? We can tell if our predicted position isn't the same after reconstructing everything
            local delta = oldPos - self.chickynoid.pos
            if delta.magnitude > 0.01 then
                print("Mispredict:", delta)
            end
        end
    end
end

function ChickynoidClient:SpawnDebugSphere(pos, color)
    if self.settings.debugSpheres == false then
        return
    end

    local part = Instance.new("Part")
    part.Anchored = true
    part.Color = color
    part.Shape = Enum.PartType.Ball
    part.Size = Vector3.new(5, 5, 5)
    part.Position = pos
    part.Transparency = 0.25
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth

    part.Parent = game.Workspace.DebugParts
end

function ChickynoidClient:ClearDebugSpheres()
    if self.settings.debugSpheres == false then
        return
    end

    game.Workspace.DebugParts:ClearAllChildren()
end

function ChickynoidClient:Heartbeat(deltaTime)
    --increment our local frame
    self.localFrame += 1

    --read user input
    local cmd = self:MakeCommand(deltaTime)

    --add to buffer
    table.insert(self.predictedCommands, cmd)

    --step this frame
    if self.chickynoid then
        --process command
        self.chickynoid:ProcessCommand(cmd)

        --Marker for positions added since the last server update
        ChickynoidClient:SpawnDebugSphere(self.chickynoid.pos, Color3.fromRGB(44, 140, 39))

        if self.settings.skipResimulation == true then
            --add to our state cache, which we can use for skipping resims
            local cacheRecord = {}
            cacheRecord.l = cmd.l
            cacheRecord.state = self.chickynoid:WriteState()

            self.stateCache[cmd.l] = cacheRecord
        end

        --pass to server
        self.remoteEvent:FireServer({ id = "cmd", cmd = cmd })

        if self.settings.debugShowNumCasts == true then
            print("casts", self.chickynoid.sweepModule.raycastsThisFrame)
        end
        self.chickynoid.sweepModule.raycastsThisFrame = 0
    end
end

function ChickynoidClient:Setup()
    --Wait for GameArea
    game.Workspace:WaitForChild("GameArea")
    self.remoteEvent = game.ReplicatedStorage:WaitForChild("RemoteEvent")

    local RunService = game:GetService("RunService")
    RunService.Heartbeat:Connect(function(deltaTime)
        self:Heartbeat(deltaTime)
    end)

    self.remoteEvent.OnClientEvent:Connect(function(event)
        self:HandleEvent(event)
    end)

    local event = { id = "connected" }
    self.remoteEvent:FireServer(event)
end

return ChickynoidClient
