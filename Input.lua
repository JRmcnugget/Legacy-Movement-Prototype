local rs = game:GetService("RunService")
local cas = game:GetService("ContextActionService")
local nubHud = require(game.ReplicatedStorage.NubHud)
local userinputbind = game:GetService("UserInputService")
e1=game:GetService("UserInputService").TouchEnabled

local GuiService = game:GetService("GuiService")
local TextChatService = game:GetService('TextChatService')
local collectionServ = game:GetService('CollectionService')

local character = script.Parent
local plr = game.Players:GetPlayerFromCharacter(character)
local cm = character:WaitForChild("ControllerManager")
local humanoid = character:WaitForChild("Humanoid")
local plrMovement = require(game.ReplicatedStorage.PlayerMovement).new(game.Players.LocalPlayer)

-- Returns true if the controller is assigned, in world, and being simulated
local function isControllerActive(controller : ControllerBase)
	return cm.ActiveController == controller and controller.Active
end

-- Returns true if neither the GroundSensor or ClimbSensor found a Part and, we don't have the AirController active.
local function checkFreefallState()
	return (cm.GroundSensor.SensedPart == nil
		and not (isControllerActive(cm.AirController)))
		or humanoid:GetState() == Enum.HumanoidStateType.Jumping
end

-- Returns true if the GroundSensor found a Part, we don't have the GroundController active, and we didn't just Jump
local function checkRunningState()
	return cm.GroundSensor.SensedPart ~= nil and not isControllerActive(cm.GroundController) 
		and humanoid:GetState() ~= Enum.HumanoidStateType.Jumping
end


-- The Controller determines the type of locomotion and physics behavior
-- Setting the humanoid state is just so animations will play, not required
local function updateStateAndActiveController()
	if checkRunningState() then
		cm.ActiveController = cm.GroundController
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	elseif checkFreefallState() then
		cm.ActiveController = cm.AirController
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

-- Jump input
local function doJump(actionName, inputState, inputObject)
	plrMovement:jump(false, actionName, inputState, inputObject)
end

local function doJumpMoblie()
	plrMovement:jump(true)
end
cas:BindAction('Jump', doJump, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonB)
if e1 then
	game.Players.LocalPlayer.PlayerGui.TouchGui.TouchControlFrame.JumpButton.MouseButton1Down:Connect(doJumpMoblie)
end

local function onInputBegan(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.ButtonL3 or input.KeyCode == Enum.KeyCode.C then
		if not plrMovement._isBall then
			if (tick() - plrMovement.lastCrouchInput) < 0.2 then
				plrMovement:groundSlam()
				plrMovement.crouchInput = true
			else
				if input.KeyCode == Enum.KeyCode.ButtonL3 then
					if plrMovement.crouchInput ~= true then
						plrMovement:crouch()
						plrMovement.crouchInput = true
					else
						plrMovement:uncrouch()
						plrMovement.crouchInput = false
					end
				else
					plrMovement:crouch()
					plrMovement.crouchInput = true
				end
			end
			plrMovement.lastCrouchInput = tick()
		else
			plrMovement:boostBall()
		end
	end
	if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonR3 then
		plrMovement:enterMorph()
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
		plrMovement:block(true)
	end
	if (input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonX) and not plrMovement.inHitStop then
		if plrMovement:inAir() then
			if plrMovement.sliceStamina >= 1 and not plrMovement.chargingSlice then
				plrMovement.colorOverlay.ImageColor3 = plrMovement.sliceColor
				plrMovement.sliceReady = true
				plrMovement.sliceTick = tick()
				plrMovement.beginCharge = true
			end
		else
			plrMovement:groundDash()
		end
	end
	if input.KeyCode == Enum.KeyCode.E then
		plrMovement:CheckLunge()
		interact()
	end
end

local function onInputEnded(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then
		if not plrMovement._isBall then
			plrMovement:uncrouch()
			plrMovement.crouchInput = false
		elseif plrMovement.chargingBall then
			plrMovement:boostBall()
		end
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
		plrMovement:block(false)
	end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		if plrMovement.chargingSlice then
			plrMovement.endCharge = true
		end
	end
end

local function requestAction(actionName, inputState, inputObject)
	if inputState == Enum.UserInputState.End then
		if actionName == "Crouch" then
			if plrMovement._isBall then
				plrMovement:boostBall()
			elseif plrMovement.crouching then
				plrMovement:uncrouch()
				plrMovement.crouchInput = false
			else
				plrMovement:crouch()
				plrMovement.crouchInput = true
			end
		end
		if actionName == "Block" then
			local variable = not (plrMovement.blocking or plrMovement.isGrapple or plrMovement.chargingSlice)
			plrMovement:block(variable, true)
		end
		if actionName == "Dash" then
			if plrMovement:inAir() then
				if plrMovement.sliceStamina >= 1 and not plrMovement.chargingSlice and not plrMovement.inHitStop then
					plrMovement.sliceReady = true
					plrMovement.sliceTick = tick()
					plrMovement.beginCharge = true
				elseif plrMovement.chargingSlice then
					plrMovement.endCharge = true
				end
			else
				plrMovement:groundDash()
			end
		end
		if actionName == "Attack" then
			plrMovement:swingSword()
		end
		if actionName == 'Ground Slam' then
			plrMovement:groundSlam()
		end
		if actionName == 'Glide' then
			if plrMovement.isGliding then
				plrMovement:endGlide()
			else
				plrMovement:beginGlide()
			end
		end
	end
end

function interact()
	local hit = plrMovement.CursorHit
	if hit and hit:HasTag('Interactable') and not plrMovement.blocking and (tick() - plrMovement.swingSwordTick) > 0.55 then
		local s = hit:FindFirstChild('InteractionModule') 
		local cursor = plrMovement.Cursor.interactable
		if s and cursor.Visible then
			s = require(s)
			plrMovement.viewportInteract:Play()
			s:Interaction(plrMovement.plr)
		end
	end
end

function triggerGlide()
	if plrMovement.isGliding then
		plrMovement:endGlide()
	else
		plrMovement:beginGlide()
	end
end

userinputbind.InputBegan:Connect(onInputBegan)
userinputbind.InputEnded:Connect(onInputEnded)

local buttons = {'Crouch', 'Dash', 'Ground Slam'}
local defaultpos = {UDim2.new(0.82, 0, 0.9, 0), UDim2.new(0.9, 0, 0.6, 0), UDim2.new(0.8, 0, 0.7, 0)}
local currentButtons = nubHud.GetButtons()
for c, i in ipairs(buttons) do
	local foundsame = false
	for a, b in ipairs(currentButtons) do
		if b.Name == i then
			b.TouchEnded:Connect(function()
				requestAction(i, Enum.UserInputState.End)
			end)
			foundsame = true
			break
		end
	end
	if not foundsame then
		local newbutton = nubHud.new(i)
		newbutton:SetLabel(i)
		newbutton:SetSize(UDim2.new(0,70,0,70))
		newbutton:SetPosition(defaultpos[c])
		newbutton.TouchEnded:Connect(function()
			requestAction(i, Enum.UserInputState.End)
		end)
	end
end

local function inputchange(lastinput)
	if not plrMovement.isDead then
		plrMovement.mobile = false
		plrMovement.keyboard = false
		plrMovement.console = false
		if lastinput == Enum.UserInputType.Touch then
			nubHud.Enable()
			plrMovement.mobile = true
		else
			nubHud.Disable()
			if lastinput == Enum.UserInputType.Keyboard then
				plrMovement.keyboard = true
			elseif game.UserInputService.GamepadEnabled then
				plrMovement.console = true
			end
		end
	end
end
userinputbind.LastInputTypeChanged:Connect(inputchange)


local function onTouchTap(touchpos, gameprocced)
	local screenWidth = workspace.CurrentCamera.ViewportSize.X
	local rightSideThreshold = screenWidth / 2
	for _, pos in ipairs(touchpos) do
		-- Check if the touch position is on the right side of the screen
		if pos.X > rightSideThreshold then
			plrMovement:CheckGrapple(true)
			plrMovement:CheckLunge()
			interact()
		end
	end
end

userinputbind.TouchTap:Connect(onTouchTap)

local function onPinch(touchpos, scale, vel, state, gameprocced)
	local screenWidth = workspace.CurrentCamera.ViewportSize.X
	local rightSideThreshold = screenWidth / 2
	local touchRCount = 0
	for _, pos in ipairs(touchpos) do
		-- Check if the touch position is on the right side of the screen
		if pos.X > rightSideThreshold then
			touchRCount = touchRCount + 1
		end
	end
	if state == Enum.UserInputState.Change and touchRCount >= 2 then
		if scale < 1 and not plrMovement._isBall then
			plrMovement:enterMorph()
		elseif scale > 1 and plrMovement._isBall then
			plrMovement:enterMorph()
		end
	end
end

local conn = userinputbind.TouchPinch:Connect(onPinch)

GuiService.MenuOpened:Connect(function()
	plrMovement.gameFocused = false
	if plrMovement.chargingBall then
		plrMovement:boostBall()
	end
end)

GuiService.MenuClosed:Connect(function()
	plrMovement.gameFocused = true
end)

local tags = {"Fluid", "Rain", "Targetable"}
for c, i in pairs(tags) do
	for _, part in ipairs(workspace:GetDescendants()) do
		if part:IsA("BasePart") and collectionServ:HasTag(part, tags[c]) and c ~= 3 then
			table.insert(plrMovement.camCheckParts, part)
		end
		if c == 3 and part:IsA("BasePart") and collectionServ:HasTag(part, tags[3]) then
			table.insert(plrMovement.AimAssistObjs,part)
		end
	end
end

function onInstanceAdded(instance)
	for c, i in pairs(tags) do
		if not plrMovement.isDead then
			if instance:IsA("BasePart") and collectionServ:HasTag(instance, tags[c]) and c ~= 3 then
				table.insert(plrMovement.camCheckParts, instance)
			end
			if c == 3 and instance:IsA("BasePart") and collectionServ:HasTag(instance,  tags[3]) then
				table.insert(plrMovement.AimAssistObjs,instance)
			end
		end
	end
end

function onInstanceRemoved(instance)
	if plrMovement.camCheckParts ~= nil and plrMovement.AimAssistObjs ~= nil then
		for index, part in pairs(plrMovement.camCheckParts) do
			if part == instance then
				table.remove(plrMovement.camCheckParts, index)
				break
			end
		end
		for index, part in pairs(plrMovement.AimAssistObjs) do
			if part == instance then
				table.remove(plrMovement.AimAssistObjs, index)
				break
			end
		end
	end
end

workspace.ChildAdded:Connect(onInstanceAdded)
workspace.ChildRemoved:Connect(onInstanceRemoved)

local cleanup = false
local function stepController(dt)

	updateStateAndActiveController()

	plrMovement:update(dt)

end
rs:BindToRenderStep('stepcontrol', Enum.RenderPriority.Camera.Value, stepController)
