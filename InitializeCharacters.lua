-- Replace Humanoid physics with a ControllerManager when a character loads into the workspace

local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		character.Humanoid.EvaluateStateMachine = false
		wait()
	end)	
end)