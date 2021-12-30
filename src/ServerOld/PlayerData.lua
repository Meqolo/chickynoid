local PlayerData = {}
PlayerData.__index = PlayerData

function PlayerData.new(player)
    local self = setmetatable({}, PlayerData)

    self.player = player
    self.name = player.name
    self.userId = player.userId

    self.connected = false
    self.lastConfirmedCommand = 0
    self.unprocessedCommands = {}

    self.counter = 0

    return self
end

function PlayerData:Spawn()
    local list = {}
    for key, value in pairs(game.Workspace:GetDescendants()) do
        if value:IsA("SpawnLocation") and value.Enabled == true then
            table.insert(list, value)
        end
    end

    if #list > 0 then
        local spawn = list[math.random(1, #list)]
        self.chickynoid.pos = (Vector3.new(spawn.Position.x, spawn.Position.y + 5, spawn.Position.z))
    else
        self.chickynoid.pos = Vector3.new(0, 10, 0)
    end

    local event = {}
    event.id = "spawn"
    event.pos = self.chickynoid.pos

    self:SendEvent(event)
end

function PlayerData:SendState()
    local event = {}
    event.id = "state"
    event.lc = self.lastConfirmedCommand

    event.state = self.chickynoid:WriteState()

    self:SendEvent(event)
end

function PlayerData:SendEvent(event)
    game.ReplicatedStorage.RemoteEvent:FireClient(self.player, event)
end

function PlayerData:PlayerRemoved()
    --destroy the chickynoid?
    if self.chickynoid then
        self.chickynoid:Destroy()
    end
end

function PlayerData:HandleEvent(event)
    if event.id == "connected" and self.connected == false then
        print("Player", self.name, " loaded")
        self.connected = true
        return
    end

    if event.id == "cmd" then
        if event.cmd and typeof(event.cmd) == "table" then
            table.insert(self.unprocessedCommands, event.cmd)
        end
    end
end

return PlayerData
