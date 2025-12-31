print('make sure to drink your milk, gamers')

local function LoadCharacter(player)
	-- Load the character
	player:LoadCharacter()
end

game.ReplicatedStorage.RespawnFunction.OnServerInvoke = LoadCharacter