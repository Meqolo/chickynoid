--[=[
    @class Character

    This class is responsible for handling the creation of the players' character, and 
    any subsequent modifications to the character
]=]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Character = {}
Character.__index = Character

function Character.new(player)
    local self = setmetatable({
        player = player,
    }, Character)

    return self
end

function Character:CreateCharacterModel(parent: Instance?)
    self.model = Players:CreateHumanoidModelFromUserId(self.player.CharacterAppearanceId)
    self.model.Parent = parent or Workspace
end

function Character:SetCharacterPosition(position: Vector3)
    if self.model:FindFirstChild("HumanoidRootPart") then
        self.model:SetPrimaryPartCFrame(CFrame.new(position))
    end
end

return Character
