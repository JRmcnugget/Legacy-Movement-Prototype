local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local rotamount = Player.Character:WaitForChild('RotAmount')
local hum = Player.Character:WaitForChild('Humanoid')

local RM = Player.DATA.Settings:WaitForChild('reduceMotion')

local Rot = CFrame.new()

RunService:BindToRenderStep("RotateCameraInDirectionPlayerIsGoing", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local Roll = 0
	if RM.Value == false then
		Roll = rotamount.Value
	end
	Rot = Rot:Lerp(CFrame.Angles(0, 0, math.rad(Roll)),4 * dt)
	Camera.CFrame *= Rot
end)

hum.HealthChanged:Connect(function()
	if hum.Health == 0 then
		RunService:UnbindFromRenderStep('RotateCameraInDirectionPlayerIsGoing')
	end
end)