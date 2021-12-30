-- Return the appropriate module depending on if we are on the client or server

local RunService = game:GetService("RunService")

if RunService:IsClient() then
    return require(script.Client)
else
    return require(script.Server)
end
