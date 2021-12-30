local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages

local Chickynoid = require(Packages.Chickynoid.Server)

Players.PlayerAdded:Connect(function(player)
    local character = Chickynoid.SpawnForPlayerAsync(player)
end)
