--!strict

--[=[
    @class ChickynoidServer
    @server

    Server namespace for the Chickynoid package.
]=]

local Players = game:GetService("Players")

local ServerCharacter = require(script.ServerCharacter)
local ServerTransport = require(script.ServerTransport)

local ChickynoidServer = {}

function ChickynoidServer.Setup()
    -- TODO: Move this into a proper public method
    ServerTransport._getRemoteEvent()
end

--[=[
    Spawns a new Chickynoid character for the specified player, handles loading
    their appearance and replicates the new character.

    @param player Player -- The player to spawn this Chickynoid for.
    @return ServerCharacter -- New character instance made for this player.
    @yields
]=]
function ChickynoidServer.SpawnForPlayerAsync(player: Player)
    local description = Players:GetHumanoidDescriptionFromUserId(math.abs(player.UserId))
    local character = ServerCharacter.new(player, description)
    return character
end

return ChickynoidServer
