local ChickynoidServer = {}

--Modules
ChickynoidServer.playerDataModule = require(script.PlayerData)
ChickynoidServer.chickynoidModule = require(script.Parent.Simulation)

--Internals
ChickynoidServer.remoteEvent = nil
ChickynoidServer.players = {}

--Ticker
ChickynoidServer.serverFrames = 0
ChickynoidServer.serverHz = 5

--Members
function ChickynoidServer:PlayerAdded(player)
    print("Player added:", player.Name)
    ChickynoidServer.players[player.UserId] = self.playerDataModule.new(player)
end

function ChickynoidServer:PlayerRemoved(player)
    print("Player removed:", player.Name)
    local playerData = ChickynoidServer.players[player.UserId]
    print(playerData)
    playerData:PlayerRemoved()
    ChickynoidServer.players[player.UserId] = nil
end

function ChickynoidServer:Heartbeat()
    --step the world
    for key, playerData in pairs(ChickynoidServer.players) do
        if playerData.chickynoid == nil and playerData.connected then
            --Create a chickynoid for them
            playerData.chickynoid = self.chickynoidModule.new()
            playerData.chickynoid.whiteList = { game.Workspace.GameArea, game.Workspace.Terrain }
            playerData.chickynoid.debugModel:Destroy()

            --spawn
            playerData:Spawn()
        end
    end

    for key, playerData in pairs(ChickynoidServer.players) do
        if playerData.chickynoid then
            --simple version, just process all of their commands:
            --no antiwarp (if no commands, synth one, or players wont fall/will freeze in air)
            --no buffering (keep X ms of commands unprocessed)
            --no speedcheat detection (monitor sum of dt)
            for key, cmd in pairs(playerData.unprocessedCommands) do
                playerData.chickynoid:ProcessCommand(cmd)
                playerData.lastConfirmedCommand = cmd.l
            end
            playerData.unprocessedCommands = {}
        end
    end

    self.serverFrames += 1

    if self.serverFrames > 60 / self.serverHz then
        self.serverFrames = 0
        for key, playerData in pairs(ChickynoidServer.players) do
            if playerData.chickynoid then
                --send them a new base world state (and a new playerData.lastConfirmedCommand)
                --(todo: should be a method to read/write entire player state)
                playerData:SendState()
            end
        end
    end
end

function ChickynoidServer:CheckSettings()
    if game.Players.CharacterAutoLoads == true then
        game.Players.CharacterAutoLoads = false
        error("Chickynoid: game.Players.CharacterAutoLoads needs to be false.")
        return false
    end

    ChickynoidServer.remoteEvent = game.ReplicatedStorage:FindFirstChild("RemoteEvent")
    if ChickynoidServer.remoteEvent == nil then
        local remoteEvent = Instance.new("RemoteEvent")
        remoteEvent.Parent = game.ReplicatedStorage
        ChickynoidServer.remoteEvent = remoteEvent
    end

    return true
end

function ChickynoidServer:Setup()
    if self:CheckSettings() == false then
        return
    end

    --handle connecting players
    game.Players.PlayerAdded:Connect(function(player)
        ChickynoidServer:PlayerAdded(player)
    end)
    for key, player in pairs(game.Players:GetPlayers()) do
        ChickynoidServer:PlayerAdded(player)
    end

    --handle disconnecting players
    game.Players.PlayerRemoving:Connect(function(player)
        ChickynoidServer:PlayerRemoved(player)
    end)

    --handle events
    self.remoteEvent.OnServerEvent:Connect(function(player, event)
        local playerData = self.players[player.UserId]
        playerData:HandleEvent(event)
    end)

    --start main loop
    local RunService = game:GetService("RunService")
    RunService.Heartbeat:Connect(function(deltaTime)
        self:Heartbeat(deltaTime)
    end)
end

return ChickynoidServer
