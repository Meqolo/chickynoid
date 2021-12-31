--!strict

--[=[
    @class ChickynoidClient
    @client

    Client namespace for the Chickynoid package.
]=]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ClientTransport = require(script.ClientTransport)
local ClientCharacter = require(script.ClientCharacter)

local Enums = require(script.Parent.Enums)
local EventType = Enums.EventType

local ChickynoidClient = {}
ChickynoidClient._characters = {}

--[=[
    Setup default connections for the client-side Chickynoid. This mostly
    includes handling character spawns/despawns, for both the local player
    and other players.

    Everything done:
    - Prepare the [ClientTransport] by caching the replication remote early.
    - Listen for our own character spawn event and construct a LocalCharacter
    class.
    - TODO

    @error "Remote cannot be found" -- Thrown when the client cannot find a remote after waiting for it for some period of time.
    @yields
]=]
function ChickynoidClient.Setup()
    ClientTransport:PrepareRemote()

    ClientTransport:OnEventTypeReceived(EventType.CharacterAdded, function(event)
        local position = event.position
        print("Character spawned at", position)

        local character = ClientCharacter.new(Players.LocalPlayer, position)
        ChickynoidClient._characters[Players.LocalPlayer] = character
    end)

    ClientTransport:OnEventTypeReceived(EventType.State, function(event)
        local character = ChickynoidClient._characters[event.player]
        if character then
            character:HandleNewState(event.state, event.lastConfirmed)
        end
    end)

    RunService.Heartbeat:Connect(function(dt)
        for _, character in pairs(ChickynoidClient._characters) do
            character:Heartbeat(dt)
        end
    end)
end

return ChickynoidClient
