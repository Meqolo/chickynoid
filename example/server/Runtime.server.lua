local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages

local Chickynoid = require(Packages.Chickynoid.Server)
Chickynoid.Setup()

Players.PlayerAdded:Connect(function(player)
    local character = Chickynoid.SpawnForPlayerAsync(player)

    RunService.Heartbeat:Connect(function()
        character:Heartbeat()
    end)
end)
