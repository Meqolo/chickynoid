--!strict

--- @class ServerTransport
--- @server
--- @private
---
--- Handles communication to and from individual clients on the server. Each
--- player gets their own Transport and replication packets are customized
--- to them based on factors like distances from other players.

local ServerTransport = {}
ServerTransport.__index = {}

--- Constructs a new Transport for the specified player.
--- @return ServerTransport
function ServerTransport.new(player: Player)
    local self = setmetatable({
        player = player,
    }, ServerTransport)

    return self
end

return ServerTransport
