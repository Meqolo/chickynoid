--!strict

--- @class ServerCharacter
--- @server
---
--- Server-side character which exposes methods for manipulating a players character,
--- such as teleporting and applying impulses.

local ServerCharacter = {}
ServerCharacter.__index = ServerCharacter

--- Constructs a new ServerCharacter from an optional HumanoidDescription and
--- attaches it to the specified player.
--- @return ServerCharacter
function ServerCharacter.new(player: Player, description: HumanoidDescription?)
    description = description or Instance.new("HumanoidDescription")

    local self = setmetatable({
        player = player,

        _description = description,
    }, ServerCharacter)

    return self
end

--- Constructs an R15 character rig from the character's HumanoidDescription.
--- @private
function ServerCharacter:_buildCharacterRig(): Model end

return ServerCharacter
