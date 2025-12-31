-- KARLSON & RE:RUN inspired movement system
-- By JR_mcnugget / josiahgame

-- Roblox Services
local tweenservice = game:GetService('TweenService')
local userInput = game:GetService('UserInputService')
local collectionServ = game:GetService('CollectionService')
local replicatedstorage = game.ReplicatedStorage
local datastoreUpdater = replicatedstorage.RequestPowerup

-- define landed state
local JUMP_LANDED = {
	[Enum.HumanoidStateType.Landed] = true;
	[Enum.HumanoidStateType.Swimming] = true;
	[Enum.HumanoidStateType.Running] = true;
	[Enum.HumanoidStateType.RunningNoPhysics] = true;
}

local function onStateChange(old, new, self) -- check state change
	if old == Enum.HumanoidStateType.Running and new == Enum.HumanoidStateType.Freefall and self.numJumps == 0 then
		self.jumpBuffer = true
	end
	if (JUMP_LANDED[new]) then -- if landed
		self.numJumps = 0
		if self.crouching and self.hrp.AssemblyLinearVelocity.Y < -7 then
			self:beginSlide()
		end
		if self.wallRunning == true then
			self:stopWallRun()
		end
		if self.isSpider then
			self:stopSpider()
		end
		if #self.spiderNormals > 0 then
			table.clear(self.spiderNormals)
			self.lastSpider = nil
		end
		if #self.wallRunNormals > 0 then
			table.clear(self.wallRunNormals)
			self.lastWallRunNormal = nil
		end
		self.orbsHit = 0
		if self.velBasedOnPos.Y < -105 and not self.crouching and not self._isBall and not self.isSlamming then -- stun player if hit ground hard (pseudo fall-damage)
			local rng = math.random(1,3)
			self.landHardSounds[rng]:Play()
			if self.reduceMotion.Value == false then
				self.camShake:ShakeOnce(3, self.velBasedOnPos.Y * 0.2, 0.2, 1.5)
			end
			self.stunTick = tick()
			self.stunShow:Play()
			self.humanoid.CameraOffset = Vector3.new(0,-2,0)
			task.wait(0.5)
			self.resetOffset:Play()
			task.wait(1)
		elseif not self.isSliding and self.velBasedOnPos.Y < -15 and not self._isBall and ((tick() - self.crouchTick) > 0.4) and not self.isSlamming then
			local rng = math.random(1, 4)
			self.landSounds[rng]:Play()
		elseif self.isSlamming then
			self.isSlamming = false
			for _, i in pairs(self.slamAirborneParticles) do
				i.Enabled = false
			end
			self.groundImpactSound:Play()
			local sensedPart = self.controller.GroundSensor.SensedPart
			if sensedPart then
				local bslam = sensedPart:HasTag('BounceSlam')
				local bslamP = sensedPart:GetAttribute('BouncePower') or 50
				if not bslam then
					self.hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
				else
					self.hrp.AssemblyLinearVelocity = self.controller.GroundSensor.HitNormal * bslamP
					self.slamslideS.PitchEffect.Octave = 1.1
					self.swordHitPogo:Play()
					self.slamslideS:Play()
				end
				self:particleHandler(self.slamParticle, 0.048, 4, self.controller.GroundSensor.HitFrame.Position)
				if self.controller.GroundSensor.SensedPart:HasTag('WetSound') then
					self.waterSlamSound:Play()
					self:particleHandler(self.splashParticle, 0.1, 3, self.controller.GroundSensor.HitFrame.Position)
				end
				if self.reduceMotion.Value == false then
					self.camShake:ShakeOnce(1, 15, 0.2, 0.8)
				end
				if self.controller.GroundSensor.HitNormal.Y ~= 1 and not bslam then
					self.slamSliding = true
					self:crouch(true)
					local slopedir = ((self.controller.GroundSensor.HitNormal * 1) + Vector3.new(0, -2, 0)).Unit
					self.SliceVelocity.VectorVelocity = slopedir * 80
					self.hrp:ApplyImpulse(slopedir * 50)
					self.slamslideS.PitchEffect.Octave = 0.8
					self.slamslideS:Play()
					--self.hrp.CFrame = CFrame.new(self.hrp.CFrame.X, self.hrp.CFrame.Y+1, self.hrp.CFrame.Z) * self.hrp.CFrame.Rotation 
				else
					self.SliceVelocity.Enabled = false
					self.slamLandedTick = tick()
				end
			end
		end
	end
end 

local PlayerMovement = {}
local playerMoveMeta = {__index = PlayerMovement};

--define playervariables upon loading module
function PlayerMovement.new(plr)
	local self = {}

	repeat task.wait(0.1) until plr.Character ~= nil -- wait until the character actually exists

	self.gameFocused = true -- if the player isnt in the esc menu or not

	--player values
	self.char = plr.Character
	self.plr = plr
	self.hrp = self.char.HumanoidRootPart
	self.headCollider = self.char.HeadCollider
	self.humanoid = self.char.Humanoid
	self.airVel = self.hrp.VectorForce
	self.controller = self.char.ControllerManager
	self.hitBox = self.char.Hitbox
	self.hitBoxOffset = self.hrp.Hitbox
	self.mainHud = self.plr.PlayerGui.MainHud
	self.hudAnim = require(self.mainHud.Animator)
	self.isDead = false
	self.cleanup = false
	self.inHitStop = false
	self.inHB = {}
	self.mobile = false
	self.keyboard = false
	self.console = false
	self.hurtTick = tick()
	self.requestReturn = nil

	local EzUISpring = require(replicatedstorage.EzUISpring)
	local Frame = self.mainHud.DisplayHud.HP
	self.inTutorial = false

	local SpringParams = EzUISpring.newSpringParams()
	SpringParams.SpringIntensity = 1.5
	SpringParams.BaseRotationOffset = Vector3.new(17,0,0)
	if userInput.TouchEnabled then
		Frame.Position = UDim2.new(0.1, 0, 0.2, 0)
		SpringParams.SizeFactor = 0.9
	else
		SpringParams.BasePositionOffset = Vector3.new(0, 0.1, 0.2)
	end
	self.HPUISpringObject = EzUISpring.new(Frame, SpringParams)

	self.HPUISpringObject:Apply3DSpringEffect()
	self.StaminaFillBar = self.HPUISpringObject.GuiObject.StaminaDisplay.Fillbar
	self.StaminaUseBar = self.HPUISpringObject.GuiObject.StaminaDisplay.UseBar
	self.StaminaS1 = self.HPUISpringObject.GuiObject.StaminaDisplay.S1
	self.StaminaS2 = self.HPUISpringObject.GuiObject.StaminaDisplay.S2

	self.humanoid.StateChanged:Connect(function(old, new) onStateChange(old, new, self); end); -- call function when state changes

	--settings
	self.data = self.plr:WaitForChild('DATA')
	self.settings = self.data:WaitForChild('Settings')
	self.reduceMotion = self.settings:WaitForChild('reduceMotion')
	self.HPU = self.data:WaitForChild('HPUpgrades')
	self.MaxHealth = 99
	self.health = self.MaxHealth

	--aim assit
	self.AimAssistObjs = {}

	-- sword variables
	self.swingSwordTick = tick()
	self.swingNum = 1
	self.blocking = false

	--active abilities (essentially if player has acquired them)
	self.isDoubleJumpActive = self.data.DoubleJump
	self.isSpiderActive = self.data.Spider
	self.isSliceActive = self.data.Slice
	self.isGrappleActive = self.data.Grapple
	self.isLungeActive = self.data.Lunge
	self.isFinsActive = self.data.Fins
	self.isSwordActive = self.data.Sword
	self.isSlamActive = self.data.Slam
	self.isBallActive = self.data.Ball

	self.numJumps = 0
	self.jumpBuffer = false

	--slice variables
	self.chargingSlice = false
	self.sliceMomentum = false
	self.beginCharge = false
	self.endCharge = false
	self.sliceTick = tick() - 2
	self.dashJumpTick = tick()
	self.sliceColor = Color3.fromRGB(127, 0, 191)
	self.SliceVelocity = self.hrp.SliceVelocity
	self.sliceStamina = 3
	self.sliceStaminaDisplay = 3
	self.orbsHit = 0

	--grapple variables
	self.grappleReady = false
	self.isGrapple = false
	self.grapplePoint = nil
	self.grappleCamCFrame = CFrame.new(0,0,0)
	self.grappleRope = Instance.new('RopeConstraint')
	self.grappleRope.Parent = self.hrp
	self.grappleRope.WinchEnabled = true
	self.grappleRope.WinchTarget = 10
	self.grappleRope.WinchForce = 9999999999999
	self.grappleRope.Restitution = 0.5
	self.grappleRope.Attachment0 = self.hrp.RootGrappleAttachment
	self.grappleRope.WinchSpeed = 10
	self.grappleTick = tick() - 0.25

	--lunge variables
	self.isLunge = false
	self.lungePoint = nil

	--wallrun variables
	self.wallRunning = false
	self.lastWallRunNormal = nil
	self.wallRunSide = 0
	self.wallrunPart = nil
	self.wallRunTick = tick()
	self.wallRunAttach = (workspace.Terrain:FindFirstChild('Attachment') or Instance.new('Attachment'))
	self.wallRunY = nil
	self.fallSpeed = 0
	self.wallRunVel = 0
	self.wallRunNormals = {}
	self.wallRunAttach.Parent = workspace.Terrain
	self.alignPos = self.hrp.AlignPosition
	self.alignPos.Attachment1 = self.wallRunAttach

	self.audioMuffle = game.SoundService.MuffledAudio.Muffle
	self.colorOverlay = self.mainHud.ColorOverlay.ImageLabel
	self.flashOverlay = self.mainHud.ColorOverlay.Flash
	self.overlayShow = tweenservice:Create(self.colorOverlay, TweenInfo.new(0.2), {ImageTransparency = 0.3})
	self.overlayHide = tweenservice:Create(self.colorOverlay, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {ImageTransparency = 1})
	self.overlayFHide = tweenservice:Create(self.flashOverlay, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {ImageTransparency = 1})
	self.overlayFullShow = tweenservice:Create(self.colorOverlay, TweenInfo.new(0.5), {ImageTransparency = 0})

	--spider variables
	self.isSpider = false
	self.lastSpider = nil
	self.spiderTick = tick()
	self.spiderNormals = {}
	self.spiderPart = nil

	self.lastPosition = nil
	self.lastTime = tick()
	self.velBasedOnPos = Vector3.new(0,0,0)

	self.isRunningIntoWall = false

	--jump variables
	self.isJumping = false
	self.jumpTick = tick()

	self.lastGrounded = tick()

	self.CAddMulti = 0

	--crouch variables
	self.crouching = false
	self.crouchInput = false
	self.crouchTick = tick()
	self.isSliding = false
	self.slideForce = self.hrp.SlideForce

	--ground slam variables
	self.lastCrouchInput = tick()
	self.isSlamming = false
	self.slamSliding = false
	self.slamTick = tick() - 5
	self.slamLandedTick = tick()

	--powerball variables
	self.ball = replicatedstorage.RidingBall:Clone()
	self.ball.Parent = replicatedstorage
	self._isBall = false
	self.chargingBall = false
	self.ballChargeTick = tick() - 5
	self.ballHighlight = self.ball.PowerBall.Highlight
	self.ballHighlightShow = tweenservice:Create(self.ballHighlight, TweenInfo.new(2, Enum.EasingStyle.Sine), {OutlineTransparency = 0, FillTransparency = 0.2})
	self.ballHighlightHide = tweenservice:Create(self.ballHighlight, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {OutlineTransparency = 1, FillTransparency = 1})
	self.morphTick = tick()

	self.hrp.Running.Volume = 0 -- stop default footsteps

	--fluid variables
	self.inFluid = false
	self.collorCorrect = game.Lighting.ColorCorrection
	self.correctAboveColor = tweenservice:Create(self.collorCorrect, TweenInfo.new(0.3), {TintColor = Color3.fromRGB(255, 233, 216)})
	self.correctBelowColor = tweenservice:Create(self.collorCorrect, TweenInfo.new(0.3), {TintColor = Color3.fromRGB(103, 94, 88)})
	self.blur = game.Lighting.Blur
	self.fluidPart = nil
	self.fluidSubmerge = 0

	--camera and camshaker
	self.cam = workspace.CurrentCamera
	self.cameraShaker = require(replicatedstorage.CameraShaker)
	self.shakeCF = CFrame.new(0,0,0)
	self.camShake = self.cameraShaker.new(Enum.RenderPriority.Character.Value, function(shakeCFrame)
		self.cam.CFrame = self.cam.CFrame * shakeCFrame
	end)
	self.camShakeLunge = self.cameraShaker.new(Enum.RenderPriority.Character.Value, function(shakeCFrame)
		self.shakeCF = shakeCFrame
	end)
	self.camShakeLunge:StartShake(2, 5, 0.3, 0, 0.8)
	self.plr.CameraMinZoomDistance = 0.1
	self.plr.CameraMaxZoomDistance = 0.1
	self.cam.CameraType = 'Custom'
	self.cam.CameraSubject = self.humanoid
	self.plr.CameraMode = Enum.CameraMode.Classic
	self.prevCF = self.cam.CFrame
	self.camCheckParts = {}
	self.camShake:Start()

	--camera rotation values
	self.rot = Instance.new('NumberValue')
	self.rot.Name = "RotAmount"
	self.rot.Parent = self.char
	self.rot.Value = 0
	self.ImpactCorrect = game.Lighting.Impact1
	self.ImpactCorrect2 = game.Lighting.Impact2

	--particles
	local particlesF = replicatedstorage.Particles
	self.jumpParticle = particlesF.JumpParticleDust
	self.jumpParticle2 = particlesF.JumpParticleRing
	self.slamParticle = particlesF.SlamParticle
	self.splashParticle = particlesF.FluidSplash
	self.slamAirborneP = particlesF.SlamAirborne:Clone()
	self.slamAirborneP.Parent = self.cam
	self.slamAirborneParticles = self.slamAirborneP:GetChildren()
	self.screenRain = particlesF.screenrain:Clone()
	self.screenRain.Parent = self.cam
	self.waterRipple = particlesF.WaterRipple:Clone()
	self.waterRipple.Parent = self.cam

	--viewport wind particles
	self.windParticles = particlesF.WindParticle:Clone()
	self.windParticles.Parent = self.cam

	--viewport variables
	self.viewport = replicatedstorage.viewport3:Clone()
	self.viewport.Parent = self.cam
	self.bobAmount = 0.026
	self.bobbingSpeed = 10
	self.grappleBeams = {}
	for _, i in pairs(self.viewport:GetDescendants()) do
		if i.ClassName == "Beam" then
			table.insert(self.grappleBeams, i)
		end
	end

	--viewport animations
	self.viewportClimb= self.viewport.AnimationController.Animator:LoadAnimation(replicatedstorage.Anims.Viewport_Climb)
	self.viewportGIdle = self.viewport.AnimationController.Animator:LoadAnimation(replicatedstorage.Anims.Viewport_GIlde)
	self.viewportGStart = self.viewport.AnimationController.Animator:LoadAnimation(replicatedstorage.Anims.Viewport_GStart)
	self.viewportGRepel = self.viewport.AnimationController.Animator:LoadAnimation(replicatedstorage.Anims.Viewport_GRepel)
	self.viewportGPull = self.viewport.AnimationController.Animator:LoadAnimation(replicatedstorage.Anims.Viewport_GPull)
	self.viewportPull = self.viewport.AnimationController.Animator:LoadAnimation(replicatedstorage.Anims.Viewport_Pull)
	self.viewportIdle = self.viewport.AnimationController.Animator:LoadAnimation(replicatedstorage.Anims.Viewport_Idle)
	self.viewportInteract = self.viewport.AnimationController.Animator:LoadAnimation(replicatedstorage.Anims.Viewport_interact)
	self.viewportInteractR = self.viewport.AnimationController.Animator:LoadAnimation(replicatedstorage.Anims.Viewport_interactready)
	self.viewportIdle:Play()

	--sound effects folders
	self.sfxFolder = self.plr.PlayerGui.SFX
	self.sfxGeneral = self.sfxFolder.General
	self.sfxCombat = self.sfxFolder.Combat

	--general sfx
	self.sfxFootsteps = self.sfxFolder.Footsteps
	self.footSounds = self.sfxFootsteps:GetChildren()
	self.lastFootstep = tick()
	self.windSound = self.sfxGeneral.Wind
	self.windSound:Play()
	self.slideSound = self.sfxGeneral.slideLoop
	self.jumpSound =  self.sfxGeneral.Jump
	self.jump2Sound = self.sfxGeneral.Jump2
	self.slideSSound = self.sfxGeneral.slideStart
	self.morphSound =  self.sfxGeneral.Morph
	self.morphJumpSound = self.sfxGeneral.MorphJump
	self.morphBoostSound = self.sfxGeneral.ballBoost
	self.morphBoostChargeSound = self.sfxGeneral.ballBoostCharge
	self.morphLoop = self.sfxGeneral.ballLoop
	self.morphBoostChargeTween = tweenservice:Create(self.morphBoostChargeSound, TweenInfo.new(2), {Volume = 1})
	self.errorSound = self.sfxGeneral.Error
	self.vault2Sound = self.sfxGeneral.vault2
	self.dashCharge = self.sfxGeneral.dashcharge
	self.dashSound = self.sfxGeneral.dash
	self.dashSoundG = self.sfxGeneral.dashG
	self.dashRegen = self.sfxGeneral.dashregen
	self.swordSwipeSound = self.sfxGeneral.swordSwipe
	self.landSounds = {self.sfxGeneral.land1, self.sfxGeneral.land2, self.sfxGeneral.land3, self.sfxGeneral.land4}
	self.landHardSounds = {self.sfxGeneral["body-collapse01"], self.sfxGeneral["body-collapse02"], self.sfxGeneral["body-collapse03"]}
	self.waterSlamSound = self.sfxGeneral.fluidSlam
	self.waterEnterSound = self.sfxGeneral.enterFluid
	self.waterSplashSound = self.sfxGeneral.Splash
	self.waterExitSound = self.sfxGeneral.exitFluid
	self.targetSound = self.sfxGeneral.Target
	self.NotifSound = self.sfxGeneral.Notification
	self.hurtSound = self.sfxGeneral.hurt
	self.healSound = self.sfxGeneral.heal

	--combat sfx
	self.grappleStartSound = self.sfxCombat.grappleStart
	self.grappleLoop = self.sfxCombat.grappleLoop
	self.swordHitPogo = self.sfxCombat.bounce
	self.lungeSound = self.sfxCombat.launch
	self.lungeHitSound = self.sfxCombat.Impact1
	self.groundImpactSound = self.sfxCombat.groundImpact
	self.slamSound = self.sfxCombat.slamStart
	self.earthburstS = {self.sfxCombat.earthburst2, self.sfxCombat.earthburst3}
	self.woodburstS = {self.sfxCombat.woodburst, self.sfxCombat.woodburst2, self.sfxCombat.woodburst3}
	self.glassShatterS = {self.sfxCombat.glassShatter, self.sfxCombat.glassShatter2}
	self.slamslideS = self.sfxCombat.SlamSlide
	self.orbShatter = self.sfxCombat.orbShatter
	self.ding = self.sfxCombat.ding

	--stun variables
	self.stunTick = tick()
	self.stunImg = self.mainHud.Stun.ImageLabel
	self.stunImg.ImageTransparency = 1
	self.stunShow = tweenservice:Create(self.stunImg, TweenInfo.new(0.2), {ImageTransparency = 0})
	self.stunHide = tweenservice:Create(self.stunImg, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {ImageTransparency = 1})
	self.resetOffset = tweenservice:Create(self.humanoid, TweenInfo.new(1.3), {CameraOffset = Vector3.new(0,0,0)})
	self.resetOffsetFast = tweenservice:Create(self.humanoid, TweenInfo.new(0.2), {CameraOffset = Vector3.new(0,0,0)})

	self.toolTips = self.mainHud.Tooltip

	--cursor variables
	self.Cursor = self.mainHud.Cursor
	self.CursorHit = nil

	-- ray exclusion for checking if the player can uncroucn or unmorph
	self.rayExclude = {}
	for c, i in pairs(self.char:GetChildren()) do
		if i.ClassName == 'Part' or i.ClassName == 'UnionOperation' then
			table.insert(self.rayExclude, i)
		end
	end
	for c, i in pairs(self.ball:GetDescendants()) do
		if i.ClassName == 'Part' or i.ClassName == 'MeshPart' or i.ClassName == 'UnionOperation' then
			table.insert(self.rayExclude, i)
		end
	end
	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self.rayParams.FilterDescendantsInstances = self.rayExclude
	self.rayParams.RespectCanCollide = true

	self.Bparams = RaycastParams.new()
	self.Bparams.FilterDescendantsInstances = self.rayExclude
	self.Bparams.CollisionGroup = "Ball"

	self.BEparams = OverlapParams.new()
	self.BEparams.FilterType = Enum.RaycastFilterType.Exclude
	self.BEparams.FilterDescendantsInstances = self.rayExclude
	self.BEparams.CollisionGroup = "Ball"

	self.parryParams = OverlapParams.new()
	self.parryParams.RespectCanCollide = false

	self.stunImg.ImageTransparency = 0

	game.Lighting.FogColor = Color3.fromRGB(0,0,0)
	game.Lighting.FogEnd = 0
	task.wait(0.2)
	tweenservice:Create(game.Lighting, TweenInfo.new(5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {FogEnd = 10000}):Play()
	tweenservice:Create(self.audioMuffle.Parent, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {Volume = 1}):Play()

	return setmetatable(self, playerMoveMeta);
end

function PlayerMovement:updateHPSegments()

end

function PlayerMovement:updateHealth()

end

function PlayerMovement:hitStop(t, upward, flash)
	task.spawn(function()
		local prevVel = self.hrp.AssemblyLinearVelocity
		self.prevCF = self.cam.CFrame
		self.inHitStop = true
		local slideVel = nil
		if self.isSliding then
			slideVel = self.slideForce.Force
		end
		self.sliceMomentum = false
		self.SliceVelocity.Enabled = true
		self.SliceVelocity.VectorVelocity = Vector3.new(0,0,0)
		if flash then
			if flash == 'White' then
				self.colorOverlay.ImageColor3 = Color3.fromRGB(255,255,255)
				self.flashOverlay.ImageColor3 = Color3.fromRGB(255,255,255)
			elseif flash == 'Purple' then
				self.colorOverlay.ImageColor3 = Color3.fromRGB(170, 85, 255)
				self.flashOverlay.ImageColor3 = Color3.fromRGB(230, 165, 255)
			elseif flash == 'Green' then
				self.colorOverlay.ImageColor3 = Color3.fromRGB(85, 255, 0)
				self.flashOverlay.ImageColor3 = Color3.fromRGB(132, 222, 122)
			end
			self.colorOverlay.ImageTransparency = 0
			self.flashOverlay.ImageTransparency = 0
		end
		task.wait(t)
		if flash then
			self.overlayHide:Play()
			self.overlayFHide:Play()
		end
		self.inHitStop = false
		self.SliceVelocity.Enabled = false
		self.hrp.AssemblyLinearVelocity = prevVel
		if slideVel then
			self.slideForce.Force = slideVel 
			self:beginSlide()
		end
		if upward then
			if self:inAir() then
				self.hrp.AssemblyLinearVelocity = Vector3.new(prevVel.X,0,prevVel.Z)
				self.hrp:ApplyImpulse(Vector3.new(0,150,0))
			end
		end
	end)
end

function PlayerMovement:inAir()
	return (self.hrp.GroundSensor.SensedPart == nil)
end

function PlayerMovement:isMoving()
	return (self.humanoid.MoveDirection ~= Vector3.new(0,0,0))
end

function PlayerMovement:isAlive()
	return (self.humanoid.Health ~= 0 and not self.isDead)
end

function PlayerMovement:updateVelocity()
	local currentPosition = self.hrp.Position
	local currentTime = tick()
	if self.lastPosition then
		local deltaTime = currentTime - self.lastTime
		local deltaPosition = currentPosition - self.lastPosition
		local velocity = deltaPosition / deltaTime
		self.velBasedOnPos = velocity
	end
	self.lastPosition = currentPosition
	self.lastTime = currentTime
end

-- update the player's movementDir
function PlayerMovement:updateMovementDirection()
	if (not self.isSliding) or self:inAir() then
		local dir = self.humanoid.MoveDirection
		if (dir.Magnitude - self.controller.MovingDirection.Magnitude) >= 0.5 then
			self.lastFootstep = tick() - 2
		end
		self.controller.MovingDirection = dir
	end
end

-- get the player's deviation from moving forward
-- used to nerf the player's movement while midair to create movement feel more akin to RE:RUN
function PlayerMovement:getMovementDeviation(moveDirect, lookVec, multi)
	local cosTheta = moveDirect:Dot(lookVec)
	local deviationAngle = math.acos(cosTheta)
	local deviationDegrees = math.deg(deviationAngle)
	return (multi * (1 - deviationDegrees / 240))
end

function PlayerMovement:AimAssist()
	for c, i in self.AimAssistObjs do
		if not i:HasTag('NoAimAssist') and i.Name == "Hitbox" then
			local orgS = i:GetAttribute('origSize')
			if not orgS then
				orgS = Vector3.new(7,7,7)
			end
			local maxdist = i:GetAttribute('MaxInteractDist')
			local mindist = 0.1
			local maxHelp = i:GetAttribute('MaxAimAssist') or 2
			local distance = (self.cam.CFrame.Position - i.Position).Magnitude
			local normscale = math.clamp(distance/maxdist, 0.1, 1)
			i.Size = orgS*(normscale*maxHelp)
			if i.Size.Magnitude < orgS.Magnitude then
				i.Size = orgS
			end
		end
	end
end

-- modular system to show/hide different crosshair parts
function PlayerMovement:updateCrosshair(hit, dist, tag, cursorToShow, cursorToHide)
	local function updateVis(cursorToShow, cursorToHide, inverse)
		if inverse then
			cursorToShow.Visible = false
			if cursorToShow.Name == "interactable" and self.viewportInteractR.IsPlaying or self.blocking or (tick() - self.swingSwordTick) < 0.55 then
				self.viewportInteractR:Stop(0.4)
			end
			if cursorToHide then
				cursorToHide.Visible = true
			end
		else	
			local override = false
			if hit:HasTag('Targetable') then
				if ((hit:HasTag('GrapplePart') or hit:HasTag('GrapplePullPart')) and self.isGrappleActive.Value) or (hit:HasTag('LungePart') and self.isLungeActive.Value) then
					if not cursorToShow.Visible then
						self.targetSound:Play()
						cursorToShow.Size = UDim2.new(0.24, 0, 0.32,0)
					end
					local screenpos = self.cam:WorldToViewportPoint(hit.Position)
					cursorToShow.Position = cursorToShow.Position:Lerp(UDim2.new(0, screenpos.X, 0, screenpos.Y), 0.3)
					cursorToShow.Size = cursorToShow.Size:Lerp(UDim2.new(0.12, 0, 0.16,0), 0.3)
				else
					override = true
				end
			end
			if not override then
				cursorToShow.Visible = true
			end
			if cursorToHide then
				cursorToHide.Visible = false
			end
			if hit:HasTag('Interactable') then
				if not self.viewportInteractR.IsPlaying and not self.blocking and (tick() - self.swingSwordTick) > 0.55 then
					self.viewportInteractR:Play(0.2)
				end
			end
		end
	end
	local at = hit:GetAttribute('MaxInteractDist')
	if hit:HasTag(tag) then
		if at then
			if dist <= at then
				updateVis(cursorToShow, cursorToHide)
			else
				updateVis(cursorToShow, cursorToHide, true)
			end
		else
			updateVis(cursorToShow, cursorToHide)
		end
	else
		updateVis(cursorToShow, cursorToHide, true)
	end
end

-- find what the player is looking at and adjust crosshair accordingly
function PlayerMovement:updateCursor()
	local ray = Ray.new(self.cam.CFrame.Position, self.cam.CFrame.LookVector * 1000)
	local hit, position = game.Workspace:FindPartOnRay(ray, self.char, false, true)
	self.CursorHit = hit
	if hit then
		local dist = (self.cam.CFrame.Position - position).Magnitude
		self:updateCrosshair(hit, dist, "Interactable", self.Cursor.interactable, self.Cursor.Default)
		self:updateCrosshair(hit, dist, "Enemy", self.Cursor.Enemy)
		self:updateCrosshair(hit, dist, "Targetable", self.Cursor.Targetable)
		self:updateCrosshair(hit, dist, "Pogo", self.Cursor.Pogo)
	else -- if not looking at anything, reset to default state
		self.Cursor.Default.Visible = true
		self.Cursor.Enemy.Visible = false
		self.Cursor.interactable.Visible = false
		if self.viewportInteractR.IsPlaying then
			self.viewportInteractR:Stop(0.4)
		end
		self.Cursor.Targetable.Visible = false
	end
	if self.isLunge then
		self.Cursor.Targetable.Visible = true
		local screenpos = self.cam:WorldToViewportPoint(self.lungePoint.Position)
		self.Cursor.Targetable.Position = self.Cursor.Targetable.Position:Lerp(UDim2.new(0, screenpos.X, 0, screenpos.Y), 0.3)
	end
end

local function Lerp(a,b,t)
	return a + (b - a) * t
end

function PlayerMovement:updateViewport(dt)
	self.windParticles:PivotTo(self.cam.CFrame + self.cam.CFrame.LookVector*15)
	local desiredCF = self.cam.CFrame
	self.viewport:PivotTo(desiredCF * CFrame.new(0, -0.4, 0))
	self.slamAirborneP:PivotTo(CFrame.new(self.cam.CFrame.Position))
	self.screenRain:PivotTo(self.cam.CFrame + self.cam.CFrame.LookVector)
	if self.cam.CFrame.LookVector.Y > -0.4 and not self:checkCameraInPart(self.cam.CFrame.Position, "Fluid") then
		self.screenRain.ParticleEmitter.Enabled = true
	else
		self.screenRain.ParticleEmitter.Enabled = false
	end
	if self.viewport.Parent == nil then
		self.viewport.Parent = self.cam
	end
	local check = (self.inFluid and self.fluidSubmerge ~= 100)
	local checkBall = self._isBall
	local pulse = self.waterRipple.Attachment.Pulse
	if check then
		pulse.Enabled = true
		pulse.Rate = checkBall and self.ball.Velocity.Magnitude/3 or self.hrp.Velocity.Magnitude/2
	else
		self.waterRipple.Attachment.Pulse.Enabled = false
	end
	if checkBall then
		desiredCF = self.ball.CFrame
	end
	local offset = check and (self.fluidPart.Position.Y + self.fluidPart.Size.Y/2)+0.1 or desiredCF.Y-200
	local rippleCF = (CFrame.new(desiredCF.X, offset, desiredCF.Z))
	self.waterRipple:PivotTo(rippleCF)
end

function PlayerMovement:WindParticles()
	if self.hrp.Velocity.Magnitude > 35 then
		self.windSound.Volume = self.hrp.Velocity.Magnitude/80
	else
		self.windSound.Volume = 0
	end
	if self.velBasedOnPos.Magnitude > 40 then
		self.windParticles.ParticleEmitter.Rate = self.velBasedOnPos.Magnitude/4
		self.windParticles.ParticleEmitter.Speed = NumberRange.new(25+(self.velBasedOnPos.Magnitude/10), 55+(self.velBasedOnPos.Magnitude/10))
	else
		self.windParticles.ParticleEmitter.Rate = 0
	end
end

-- modular-ish shapecast function
-- used to check if the player can unmorph and uncrouch
function PlayerMovement:castCheck(typecast, size, dist, origin, params)
	local size = size
	local direction = Vector3.new(0,1,0)
	local distance = dist
	local origin = origin

	if typecast == "block" then
		local result = workspace:Blockcast(origin, size, direction * distance, params)
		return result
	elseif typecast == "sphere" then
		local result = workspace:Spherecast(origin, size, direction * distance, params)
		return result
	else
		warn("Invalid Cast Type!")
		return "Invalid"
	end
end

function PlayerMovement:returnFootstep(groundPart)
	local surfaceType = "None"
	if groundPart ~= nil then
		local material = groundPart.Material
		if groundPart:HasTag('StickySound') then
			surfaceType = "Enum.Material.Mud"
		elseif groundPart:HasTag('WetSound') then
			surfaceType = "Enum.Material.Water"
		elseif groundPart:HasTag('GravelSound') then
			surfaceType = "Enum.Material.Gravel"
		elseif groundPart:HasTag('WoodSound') or material == Enum.Material.WoodPlanks then
			surfaceType = "Enum.Material.Wood"
		elseif groundPart:HasTag('MetalChainSound') then
			surfaceType = "Enum.Material.Metal_Chainlink"
		else
			surfaceType = tostring(material)
			local parts = string.split(surfaceType, ".")
			local found = self.sfxFootsteps:FindFirstChild(parts[#parts])
			if not found then
				surfaceType = "Enum.Material.Plastic"
			end
		end
	end
	return surfaceType
end

function PlayerMovement:footSteps()
	if (self:isMoving() and self.hrp.Velocity.Magnitude > 1 and not self:inAir() and (self.controller.GroundSensor.HitNormal.Y > 0.6 or self.inFluid) and not self.isSliding and not self._isBall) or (self.wallRunning or self.isSpider) then
		local groundPart
		if self.wallRunning then
			groundPart = self.wallrunPart
		elseif self.isSpider and self.spiderPart ~= nil then
			groundPart = self.spiderPart
		else
			groundPart = self.controller.GroundSensor.SensedPart
		end
		local surfaceType = self:returnFootstep(groundPart)
		local slow = false

		if ((self.inFluid and self.fluidSubmerge > 50) or self.crouching or (tick() - self.stunTick) < 1.3) and not self.wallRunning then
			slow = true
		end

		for _, sound in pairs(self.footSounds) do
			if ("Enum.Material."..sound.Name) == surfaceType then
				if (slow and (tick()-self.lastFootstep) > 0.5) or (not slow and (tick()-self.lastFootstep) > 0.35) then
					local list = sound:GetChildren()
					local rng = math.random(1, #list)
					list[rng]:Play()
					if not self.wallRunning  and not self.isSpider then
						self.lastFootstep = tick()
					elseif self.isSpider then
						self.lastFootstep = tick() - 0.1
					elseif self.wallRunning then
						self.lastFootstep = tick() - self.wallRunVel*0.0025
					end
				end
			end
		end
	end
end
-- Dynamic particle system that handles placement, particle deactivation, and cleanup. 
-- Instance (BasePart), deactivation time, garbage collection time, position (Vector3)
function PlayerMovement:particleHandler(particle, deactive, garbage, pos) 
	local p = particle:Clone()
	local parts = {}
	for _, i in pairs(p:GetDescendants()) do
		if i.ClassName == "ParticleEmitter" then
			table.insert(parts, i)
		end
	end
	p.Parent = workspace
	p.CFrame = CFrame.new(pos)
	task.spawn(function()
		task.wait(deactive)
		for _, i in pairs(parts) do
			i.Enabled = false
		end
		table.clear(parts)
	end)
	game:GetService('Debris'):AddItem(p, garbage)
end

function PlayerMovement:block(t, mobile)
	if t == true and not self.isDead then
		local grappled = false
		if not mobile and not self.chargingSlice then
			grappled = self:CheckGrapple(true, false)
		end
	else
		if not mobile then
			self:CheckGrapple(false, false)
		end
	end
end

function PlayerMovement:CheckLunge()
	if self.CursorHit ~= nil and not self.isLunge and self.isLungeActive.Value and not self.isDead then
		if self.CursorHit:HasTag('LungePart') then
			self.cam.CameraType = "Scriptable"
			self.isLunge = true
			self.lungePoint = self.CursorHit
			self.lungeSound:Play()
			if self.reduceMotion.Value ~= true then
				self.camShakeLunge:Start()
			end
			self.SliceVelocity.Enabled = true
			self.SliceVelocity.VectorVelocity = Vector3.new(0,0,0)
			self.windParticles.FWOOSH.Enabled = true
			self.windParticles.LINES.Enabled = true
		end
	end
end

function PlayerMovement:EndLunge(KnockXZ, KnockY, dir)
	if self.isLunge and self.lungePoint ~= nil then
		self.isLunge = false
		self.camShakeLunge:Stop()
		self.lungeHitSound:Play()
		self.camShake:ShakeOnce(2.5, 30, 0, 1)
		self.cam.CameraType = 'Custom'
		self.windParticles.FWOOSH.Enabled = false
		self.windParticles.LINES.Enabled = false
		self:hitStop(0.25, false, "Green")
		task.wait(0.25)
		self.lungePoint = nil
		self.SliceVelocity.Enabled = false
		self.hrp:ApplyImpulse(Vector3.new(KnockXZ*dir.X,KnockY,KnockXZ*dir.Z))
	end
end

function PlayerMovement:CheckGrapple(t)
	if t == true and self.isGrappleActive.Value then
		if self.CursorHit ~= nil then
			if self.CursorHit:HasTag('GrapplePart') or self.CursorHit:HasTag('GrapplePullPart') then
				local attach = self.CursorHit:FindFirstChild('GrappleAttachent')
				local maxdist = self.CursorHit:GetAttribute('MaxInteractDist')
				if attach and maxdist then
					if self.Cursor.Targetable.Visible == true and not self.isGrapple and (tick() - self.grappleTick > 0.25) then
						self.isGrapple = true
						self.grapplePoint = self.CursorHit
						if self.grapplePoint:HasTag('GrapplePart') then
							self.grappleStartSound:Play()
							self.grappleRope.Attachment1 = self.grapplePoint.GrappleAttachent
							local at = self.grapplePoint:GetAttribute('GrappleDist')
							if at then
								self.grappleRope.WinchTarget = at
							else
								self.grappleRope.WinchTarget = 10
							end
							local at2 = self.grapplePoint:GetAttribute('GrapplePower')
							if at2 then
								self.grappleRope.WinchSpeed = at2
							else
								self.grappleRope.WinchSpeed = 10
							end
							self.grappleLoop:Play()
							self.viewportGStart:Play(0.1)
							task.spawn(function()
								task.wait(0.1)
								for _, i in pairs(self.grappleBeams) do
									i.Enabled = true
									i.Attachment1 = self.grapplePoint.GrappleAttachent
								end
								self.grappleStartSound.PitchShiftSoundEffect.Octave = Random.new():NextNumber(0.8, 1.25)
								task.wait(self.viewportGStart.Length-0.3)
								if self.isGrapple then
									self.viewportGIdle:Play(0.2, 1)
								end
							end)
							return true
						else
							local module = self.CursorHit:FindFirstChild('InteractionModule')
							if module then
								module = require(module)
								self.viewportPull:Play(0.1, 1, 1.5)
								self.isGrapple = false
								self.grappleTick = tick() + self.viewportPull.Length/1.5
								task.spawn(function()
									task.wait(0.1)
									self.grappleStartSound:Play()
									for _, i in pairs(self.grappleBeams) do
										i.Enabled = true
										i.Attachment1 = self.grapplePoint.GrappleAttachent
									end
									task.wait(0.15)
									module:Interaction(self.plr)
									task.wait(self.viewportPull.Length - 0.85)	
									for _, i in pairs(self.grappleBeams) do
										i.Enabled = false
										i.Attachment1 = nil
									end
								end)
							end
						end
					end
					return false
				else
					error('GrapplePart at '..tostring(self.CursorHit.CFrame.Position)..' is missing one or more instances, pls fix!')
					return false
				end
			end
		end
	else
		if self.isGrapple == true then
			self.isGrapple = false
			self.grapplePoint = nil
			for _, i in pairs(self.grappleBeams) do
				i.Enabled = false
				i.Attachment1 = nil
			end
			self.grappleTick = tick()
			self.grappleRope.Attachment1 = nil
			self.grappleLoop:Stop()
			self.hrp.Velocity = self.hrp.Velocity * 0.8
			self.viewportGIdle:Stop(0.4)
			self.viewportGStart:Stop(0.3)
			self.viewportGRepel:Stop(0.4)
			self.viewportGPull:Stop(0.4)
		end
	end
end

function PlayerMovement:jump(mobile, actionName, inputState, inputObject)
	local floor = self.controller.GroundSensor.SensedPart
	local ray = self:castCheck('block', Vector3.new(2, 0.5, 1), 4, self.hrp.CFrame, self.rayParams)
	if not (self.crouching and ray) and self.gameFocused and self.humanoid.Health ~= 0 then
		if (mobile or inputState == Enum.UserInputState.Begin) and not self._isBall and (self.controller.GroundSensor.HitNormal.Y > 0.6 or self.inFluid or self:inAir()) then
			if self.isGrapple and mobile then
				self:CheckGrapple(false)
			end
			if self.numJumps < 2 then
				if self.wallRunning then
					self:stopWallRun(true)
				end
				if not self.isDoubleJumpActive.Value and self.numJumps == 1 then
					return false
				end
				self.jumpBuffer = false
				self.jumpTick = tick()
				self.numJumps = self.numJumps + 1
				self.controller.RootPart.AssemblyLinearVelocity = Vector3.new(self.controller.RootPart.AssemblyLinearVelocity.X, 0, self.controller.RootPart.AssemblyLinearVelocity.Z)
				self.char.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
				local timedif = (tick() - self.slamLandedTick)
				if timedif < 0.3 then
					self.hrp:ApplyImpulse(Vector3.new(0,math.clamp(150+(((tick()-self.slamTick)-timedif)*250), 200, 400),0))
				else
					self.hrp:ApplyImpulse(Vector3.new(0,150,0))
				end
				if self.sliceMomentum and not self:inAir() then
					self.sliceMomentum = false
					self.SliceVelocity.Enabled = false
					self.hrp.AssemblyLinearVelocity = self.hrp.Velocity * 0.5
					self.dashJumpTick = tick()
					self.CAddMulti = 0.5
				end
				self.controller.ActiveController = self.controller.AirController
				if self.slamSliding then
					self.slamSliding = false
					self.SliceVelocity.Enabled = false
					self.hrp.AssemblyLinearVelocity = self.hrp.AssemblyLinearVelocity * 0.7
				end
				if self.numJumps == 2 then
					self.jump2Sound:Play()
					self:particleHandler(self.jumpParticle, 0.1, 1, self.cam.CFrame.Position)
					self:particleHandler(self.jumpParticle2, 0.15, 1, self.cam.CFrame.Position)
				else
					self.jumpSound:Play()
					self:particleHandler(self.jumpParticle, 0.1, 1, Vector3.new(self.cam.CFrame.X, self.cam.CFrame.Y - 3.1, self.cam.CFrame.Z))
				end
				self.airVel.Force = Vector3.new(0,550,0)
				if self.isSpider then
					self:stopSpider(true)
				end
			end
		elseif self._isBall and (mobile or inputState == Enum.UserInputState.Begin) then
			local ray = workspace:Raycast(self.ball.Position, Vector3.new(0,-2,0), self.rayParams)
			if ray then
				self.ball:ApplyImpulse(Vector3.new(0,1200,0)) 
				self.morphJumpSound:Play()
				self:particleHandler(self.jumpParticle, 0.1, 1, self.ball.CFrame.Position)
				self:particleHandler(self.jumpParticle2, 0.15, 1, self.ball.CFrame.Position)
			end
			self.numJumps = self.numJumps + 1
		end
	end
end

-- begin crouch
function PlayerMovement:crouch(canSlide)
	if self.gameFocused and not self.crouching and self.humanoid.Health ~= 0 and not self._isBall then
		self.crouching = true
		self.controller.GroundController.GroundOffset = 0.5
		self.hrp.GroundSensor.SearchDistance = 1
		local ray = workspace:Raycast(self.hrp.Position, Vector3.new(0, 1, 0))
		if not ray then
			self.humanoid.CameraOffset = Vector3.new(0,1.7,0)
		else
			self.humanoid.CameraOffset = Vector3.new(0,0.7,0)
		end
		self.resetOffsetFast:Cancel()
		self.resetOffsetFast:Play()
		-- hitbox shenanigans so the player doesn't die from touching anything underneath them
		self.hitBoxOffset.C0 = CFrame.new(0, 0.511, 0)
		self.hitBoxOffset.C1 = CFrame.new(0, 0.113, 0)
		self.hitBox.Size = Vector3.new(2, 3.95, 2)
		self.hrp.CFrame = CFrame.new(self.hrp.Position.X,self.hrp.Position.Y - 1.7,self.hrp.Position.Z) * self.hrp.CFrame.Rotation
		if self.hrp.Velocity.Y < 0 and (tick() - self.jumpTick > 0.2) and not self:inAir() and canSlide then
			self:beginSlide()
		end
		self.crouchTick = tick()
	end
end

-- end crouch
function PlayerMovement:uncrouch()
	local ray = self:castCheck('block', Vector3.new(2, 0.5, 1), 5, self.hrp.CFrame, self.rayParams)
	if  not self.slamSliding and not self.isSlamming and (ray == nil or ray.Distance > 4) and self.humanoid.Health ~= 0 and self.crouching then
		self.controller.GroundController.GroundOffset = 3
		self.hrp.GroundSensor.SearchDistance = 3.5
		if not self:inAir() then
			self.humanoid.CameraOffset = Vector3.new(0,-1.7,0)
		else
			self.humanoid.CameraOffset = Vector3.new(0,-0.7,0)
		end
		self.resetOffsetFast:Cancel()
		self.resetOffsetFast:Play()
		-- hitbox shenanigans
		self.hitBoxOffset.C0 = CFrame.new(0, -1, 0)
		self.hitBoxOffset.C1 = CFrame.new(0, -0.324, 0)
		self.hitBox.Size = Vector3.new(2, 6.76, 2)
		self.hrp.CFrame = CFrame.new(self.hrp.Position.X,self.hrp.Position.Y +1.5,self.hrp.Position.Z) * self.hrp.CFrame.Rotation
		self.crouching = false
		if self.isSliding then
			self:endSlide()
		end
	end
end

function PlayerMovement:groundSlam()
	if self.gameFocused and self:inAir() and self.isSlamActive.Value and not self.isLunge and not self.slamSliding and not self.isSlamming and self.humanoid.Health ~= 0 and not self.chargingSlice then
		self.SliceVelocity.Enabled = true
		if self.wallRunning == true then
			self:stopWallRun()
		end
		if self.isSpider then
			self:stopSpider()
		end
		if self.isGrapple then
			self:CheckGrapple(false)
		end
		for _, i in pairs(self.slamAirborneParticles) do
			i.Enabled = true
		end
		self.isSlamming = true
		self.SliceVelocity.VectorVelocity = Vector3.new(0, -300, 0)
		self.slamSound:Play()
		self.slamTick = tick()
	end
end

-- begin crouchslide
function PlayerMovement:beginSlide()
	if not self.isSliding and self.gameFocused and not self.isLunge and (tick() - self.jumpTick > 0.2) and self.humanoid.Health ~= 0 and (self:isMoving() or self.hrp.Velocity.Magnitude > 11) then
		self.slideSSound:Play()
		self.slideSound.Playing = true
		self.slideSound.TimePosition = 0
		self.controller.GroundController.Friction = 0
		self.slideForce.Force = self.humanoid.MoveDirection * (self.hrp.Velocity.Magnitude/2)
		if self.hrp.Velocity.Magnitude < 35 then
			self.slideForce.Force = self.slideForce.Force*1.2
		end
		self.isSliding = true
	end
end

-- stop crouchsliding
function PlayerMovement:endSlide()
	if self.isSliding and self.humanoid.Health ~= 0 then
		self.controller.GroundController.Friction = 2
		self.slideForce.Force = Vector3.new(0,0,0)
		self.isSliding = false
		self.slideSound.Playing = false
		self.rot.Value = 0
	end
end

-- entering and exiting powerball
function PlayerMovement:enterMorph()
	if self.humanoid.Health ~= 0 and self.gameFocused and self.isBallActive.Value then
		if not self._isBall and not self.isSliding and not self.isLunge and not self.isSlamming and not self.isGrapple and (tick() - self.morphTick) > 0.7 and (tick() - self.grappleTick) > 0.25 then
			local boundCheck = Instance.new('Part')
			boundCheck.Size = Vector3.new(3,3,3)
			boundCheck.Shape = 'Ball'
			boundCheck.Position = self.hrp.Position
			boundCheck.Parent = workspace
			boundCheck.CanCollide = false
			boundCheck.CanTouch = false
			boundCheck.Anchored = true
			boundCheck:AddTag('NoWallrun')
			boundCheck:AddTag('NoSpider')
			boundCheck.Transparency = 1 
			game:GetService('Debris'):AddItem(boundCheck, 0.5)
			local overlap = OverlapParams.new()
			overlap.FilterType = Enum.RaycastFilterType.Exclude
			overlap.FilterDescendantsInstances = self.rayExclude
			local ray = workspace:GetPartsInPart(boundCheck, overlap)
			local c = 0
			for _, i in pairs(ray) do
				if i.CanCollide then
					c = c + 1
				end
			end
			self.morphTick = tick()
			if c > 0 then
				self.errorSound:Play()
				return false
			end
			for c, i in pairs(self.rayExclude) do -- make stuff noncollide so the player model won't interfere with the ball
				if i.Name == "HumanoidRootPart" then
					i.CanCollide = false
				end
			end
			self._isBall = true
			tweenservice:Create(self.plr, TweenInfo.new(0.7, Enum.EasingStyle.Linear), {CameraMaxZoomDistance = 10, CameraMinZoomDistance = 10}):Play()
			self.cam.CameraSubject = self.ball
			if self.crouching then
				self:uncrouch()
			end
			self.hrp.CanCollide = false
			self.headCollider.CanCollide = false
			self.ball.Anchored = false
			self.ball.AssemblyLinearVelocity = Vector3.new(0,0,0)
			self.ball.CanCollide = true
			self.morphSound:Play()
			self.ball.Parent = workspace
			if self:inAir() then -- place the ballmover on the ground if they're grounded
				self.ball.CFrame = self.hrp.CFrame
			else
				self.ball.CFrame = CFrame.new(self.hrp.GroundSensor.HitFrame.Position)
			end
			self.morphLoop:Play()
		elseif self._isBall then
			local ray2 = self:castCheck('sphere', 2, 4, Vector3.new(self.ball.Position.X, self.ball.Position.Y-2, self.ball.Position.Z), self.Bparams)
			if not ray2 and (tick() - self.morphTick) > 0.7 then -- check if the player can actually unmorph in the space they're in
				self.morphTick = tick()
				if self.chargingBall then
					self:boostBall()
				end
				self._isBall = false
				self.plr.CameraMinZoomDistance = 0.1
				self.plr.CameraMaxZoomDistance = 0.1
				self.mainHud.Glitch.BackgroundTransparency = 0
				tweenservice:Create(self.mainHud.Glitch, TweenInfo.new(0.55, Enum.EasingStyle.Sine), {BackgroundTransparency = 1}):Play()
				self.cam.CameraSubject = self.humanoid
				self.hrp.CanCollide = true
				self.headCollider.CanCollide = true
				self.hrp.Anchored = false
				self.ball.Anchored = true
				self.morphSound:Play()
				self.ball.Parent = replicatedstorage
				self.ball.CanCollide = false
				self.morphLoop:Stop()
			else
				self.errorSound:Play() -- if can't, don't, and let the player know
			end
		else
			self.errorSound:Play()
		end
	end
end

function PlayerMovement:boostBall()
	if not self.chargingBall then
		self.ballHighlightShow:Cancel()
		self.ballHighlightShow:Play()
		self.morphBoostChargeSound:Play()
		self.morphBoostChargeTween:Play()
		self.chargingBall = true
		self.ballChargeTick = tick()
		self.ballHighlight.FillTransparency = 1
		self.ballHighlight.OutlineTransparency = 1
	else
		self.ballHighlightShow:Pause()
		self.morphBoostChargeSound.Volume = 0
		self.morphBoostChargeSound:Stop()
		local impulseP = math.clamp(math.max(800 * (math.abs(tick() - self.ballChargeTick)), 200), 200, 1500)
		self.ball:ApplyImpulse(self.humanoid.MoveDirection * impulseP)
		self.morphBoostSound:Play()
		self.ballHighlightHide:Play()
		self.chargingBall = false
	end
end

-- raycast checks for wallrunning, spider, and runningintowall
function PlayerMovement:rayChecks()
	local wallCheck = workspace:Raycast(self.hrp.Position, self.humanoid.MoveDirection * 2, self.rayParams)
	local rayL = workspace:Raycast(self.hrp.Position, -self.hrp.CFrame.RightVector * 2, self.rayParams)
	local rayR = workspace:Raycast(self.hrp.Position, self.hrp.CFrame.RightVector * 2, self.rayParams)
	local rayF = workspace:Raycast(self.hrp.Position, self.hrp.CFrame.LookVector * 1.1, self.rayParams)
	if rayL and not self.isSpider and not self.isSlamming and not self.chargingSlice and not self.isGrapple and rayL.Normal ~= self.lastWallRunNormal and ((tick() - self.crouchTick) > 0.4) and ((tick() - self.jumpTick) > 0.4) and not self._isBall  and not rayL.Instance:HasTag('NoWallrun') then
		self:setWallrun(rayL, -1)
	elseif rayR and not self.isSpider and not self.isSlamming and not self.chargingSlice and not self.isGrapple and rayR.Normal ~= self.lastWallRunNormal and ((tick() - self.crouchTick) > 0.4) and ((tick() - self.jumpTick) > 0.4) and not self._isBall and not rayR.Instance:HasTag('NoWallrun') then
		self:setWallrun(rayR, 1)
	elseif rayF and not self._isBall and not self.isSlamming and not self.chargingSlice and not self.isGrapple and ((tick() - self.crouchTick) > 0.4) and ((tick() - self.jumpTick) > 0.4) and self.isSpiderActive.Value and not rayF.Instance:HasTag('NoSpider') then
		self:beginSpider(rayF)
	end
	if wallCheck ~= nil then
		self.isRunningIntoWall = true
	else
		self.isRunningIntoWall = false
	end
end

-- set wallrun variables
function PlayerMovement:setWallrun(ray, side)
	-- check if the wall normal hasn't been used twice. if so, the player can wallrun on it
	local count = 0
	for _, i in pairs(self.wallRunNormals) do
		if i == ray.Normal then
			count = count + 1
		end
	end
	if count < 2 then
		self.wallRunning = true
		self.wallRunSide = side
		self.wallrunPart = ray.Instance
		self.wallRunAttach.Position = ray.Position + ray.Normal * 1.5
		self.alignPos.Enabled = true
		self.wallRunY = ray.Position.Y
		self.lastWallRunNormal = ray.Normal
		self.numJumps = 1
		self.wallRunTick = self.isSpiderActive.Value and tick() or tick() - 0.5
		local refVel = self.velBasedOnPos
		self.wallRunVel = Vector3.new(refVel.X, 0, refVel.Z).Magnitude*0.87
		if (self.inFluid and self.fluidSubmerge > 45) then
			self.wallRunVel = self.wallRunVel * 0.25
			self.wallRunTick = self.wallRunTick - 0.45
		end
		if self.wallRunVel >= 40 then
			self.wallRunVel = 40
		end
		table.insert(self.wallRunNormals, ray.Normal) -- put new normal into table
	end
end

function PlayerMovement:Wallrun(dt)
	self.rot.Value = 11.5 * self.wallRunSide
	local ray = workspace:Raycast(self.hrp.Position, self.hrp.CFrame.RightVector * 2 * self.wallRunSide, self.rayParams)
	if ray and not ray.Instance:HasTag('NoWallrun') then
		local wallNormal = ray.Normal
		self.wallrunPart = ray.Instance
		local wallDirection = wallNormal:Cross(Vector3.new(0, 1, 0)).Unit * self.wallRunSide
		local targetpos = Vector3.new(self.hrp.Position.X, self.wallRunY, self.hrp.Position.Z) + wallDirection * (self.wallRunVel * dt)
		local check = workspace:Raycast(self.hrp.Position, targetpos-self.hrp.Position, self.rayParams)
		if not check then
			self.wallRunAttach.Position = targetpos
		else
			self.wallRunAttach.Position = Vector3.new(self.wallRunAttach.Position.X, self.wallRunY, self.wallRunAttach.Position.Z)
		end
		if ((tick() - self.wallRunTick) > 0.65) then
			self.fallSpeed = (self.fallSpeed or 0) + (30 * dt)
			local newY = self.wallRunY - (self.fallSpeed * dt)
			local check2 = workspace:Raycast(self.hrp.Position, Vector3.new(self.hrp.Position.X, newY, self.hrp.Position.Z)-self.hrp.Position, self.rayParams)
			if not check2 then
				self.wallRunY = newY
			else
				self:stopWallRun()
			end
		else
			self.fallSpeed = 0
		end
	else
		self:stopWallRun()
	end
end

function PlayerMovement:specialFootstep(Wall)
	local surfaceType = "None"
	if Wall then
		surfaceType = self:returnFootstep(self.wallrunPart)
	else
		surfaceType = self:returnFootstep(self.spiderPart)
	end
	for _, sound in pairs(self.footSounds) do
		if ("Enum.Material."..sound.Name) == surfaceType or ("Rubber") == sound.Name then
			local list = sound:GetChildren()
			local rng = math.random(1, #list)
			list[rng]:Play()
		end
	end
end

-- stop wall run
function PlayerMovement:stopWallRun(jumped)
	if self.wallRunning then
		self.alignPos.Enabled = false
		self.wallRunning = false
		self.wallRunSide = 0

		self.rot.Value = 0
		local maxMagnitude = 30
		local clampedVelocity = self.velBasedOnPos
		if clampedVelocity.Magnitude > maxMagnitude then
			clampedVelocity = clampedVelocity.Unit * maxMagnitude
		end
		clampedVelocity = Vector3.new(clampedVelocity.X, 0, clampedVelocity.Z)
		self.hrp.AssemblyLinearVelocity = clampedVelocity * 0.8
		if clampedVelocity:Dot(self.hrp.CFrame.LookVector) < 0 then
			clampedVelocity = Vector3.new(0, 0, 0)
		end
		self.wallRunTick = tick()
		self.fallSpeed = 0
		if jumped then
			self.hrp:ApplyImpulse(self.lastWallRunNormal * 25) -- apply impulse opposite to wall, to make them "jump off it"
			if not self.isDoubleJumpActive.Value then
				self.hrp:ApplyImpulse(Vector3.new(0,120,0))
			end
			self:specialFootstep(true)
			self.hrp.CFrame = CFrame.new(self.hrp.CFrame.Position + self.lastWallRunNormal * 3)
		else
			self.hrp.CFrame = CFrame.new(self.hrp.CFrame.Position + self.lastWallRunNormal)
		end
		self.wallrunPart = nil
	end
end

-- begin spider
function PlayerMovement:beginSpider(ray)
	local yes = true
	for c, i in pairs(self.spiderNormals) do
		if i == ray.Normal then
			yes = false
		end
	end
	if yes and not self.isSpider and #self.spiderNormals < 4 then 
		-- set needed variables
		self.isSpider = true
		self.viewportClimb:Play(0.12, 1, 2.3)
		table.insert(self.spiderNormals, ray.Normal)
		self.lastSpider = ray
		self.wallRunAttach.Position = ray.Position + ray.Normal * 1.2
		self.alignPos.Enabled = true
		self.numJumps = 1
		if not (self.inFluid and self.fluidSubmerge > 40) then
			self.spiderTick = tick()
		else
			self.spiderTick = tick() - 0.5
		end
		self.wallRunY = ray.Position.Y
	end
end

function PlayerMovement:Spider(dt)
	local rayF = workspace:Raycast(self.hrp.Position, self.hrp.CFrame.LookVector * 1.25, self.rayParams)
	if rayF and not (tick() - self.spiderTick > 0.7) then
		self.wallRunY = self.wallRunY + (20 * dt)
		local targetpos = Vector3.new(self.hrp.Position.X, self.wallRunY, self.hrp.Position.Z)
		local check = workspace:Raycast(self.hrp.Position, Vector3.new(0,3,0), self.rayParams)
		if not check then
			self.wallRunAttach.Position = targetpos
		end
		self.spiderPart = rayF.Instance
	else
		self:stopSpider()
	end
end

-- stop spider
function PlayerMovement:stopSpider(jumped)
	if self.isSpider then
		self.alignPos.Enabled = false
		self.jumpTick = tick()
		self.isSpider = false
		if jumped then
			self.hrp:ApplyImpulse(self.lastSpider.Normal * 40) -- apply impulse away from wall like jumping off of it
			self:specialFootstep(false)
		else 
			local ray = workspace:Raycast(self.hrp.Position + self.hrp.CFrame.LookVector * 1.5 + Vector3.new(0, 0.5, 0), Vector3.new(0, -1, 0), self.rayParams)
			if ray and not (self.inFluid and self.fluidSubmerge > 40) then -- if not jumped, check for platform in front of the player. if platform, apply impulse for vaulting upward
				local newVel = self.velBasedOnPos * 0.6
				newVel = Vector3.new(self.velBasedOnPos.X, math.clamp(self.velBasedOnPos.Y, 0, 25), self.velBasedOnPos.Z)
				self.hrp.AssemblyLinearVelocity = newVel
				self.hrp:ApplyImpulse(Vector3.new(0,100,0))
				local rng = Random.new():NextNumber(0.8, 1.25)
				self.vault2Sound.PitchShiftSoundEffect.Octave = rng
				self.vault2Sound:Play()
			else
				local newVel = self.velBasedOnPos * 0.6
				newVel = Vector3.new(0, math.clamp(self.velBasedOnPos.Y, 0, 25), 0)
				self.hrp.AssemblyLinearVelocity = newVel
			end
		end
		self.fallSpeed = 0
		self.spiderPart = nil
		self.viewportClimb:Stop(0.4)
	end
end

function PlayerMovement:groundDash()
	if not self:inAir() and (self.sliceStamina >= 1) and not (self.beginCharge or self.chargingSlice or self.sliceMomentum) and not self.isDead and self.isSliceActive.Value then
		self.StaminaUseBar.Visible = false
		self.sliceMomentum = true
		self.SliceVelocity.Enabled = true
		if self:isMoving() then
			self.SliceVelocity.VectorVelocity = self.humanoid.MoveDirection * math.clamp((130/(3/self.sliceStamina)), 40, 100)
		else
			self.SliceVelocity.VectorVelocity = self.hrp.CFrame.LookVector * math.clamp((130/(3/self.sliceStamina)), 40, 100)
		end
		if (self.inFluid and self.fluidSubmerge > 90) then
			self.SliceVelocity.VectorVelocity = self.SliceVelocity.VectorVelocity * 0.4
		end
		self.sliceStamina = 0
		self.dashSoundG:Play()
		self.sliceTick = tick()
		task.spawn(function()
			task.wait(0.2)
			if self.sliceMomentum then
				self.hrp.AssemblyLinearVelocity = self.hrp.Velocity * 0.2
				self.sliceMomentum = false
				self.SliceVelocity.Enabled = false
			end
		end)
	elseif  (self.sliceStamina ~= 3) then
		self.errorSound:Play()
	end
end

function PlayerMovement:Slice(state)
	if self.isSliceActive.Value then
		if state == 1 then
			if self.wallRunning == true then
				self:stopWallRun()
			end
			if self.isSpider then
				self:stopSpider()
			end
			self.beginCharge = false
			self.chargingSlice = true
			self.dashCharge.TimePosition = 0
			self.dashCharge:Play()
			self.SliceVelocity.Enabled = true
			self.SliceVelocity.VectorVelocity = Vector3.new(0.01, 0.01, 0.01) * (self.velBasedOnPos*2)
			if self.reduceMotion.Value == false then
				self.camShake:ShakeOnce(1, 10, 0.3, 0.8)
				tweenservice:Create(self.cam, TweenInfo.new(0.5, Enum.EasingStyle.Sine), {FieldOfView = 85}):Play()
			end
			self.StaminaUseBar.Visible = true
			self.StaminaUseBar.Size = UDim2.new((self.sliceStamina)*0.26, 0, 0.722, 0)
		elseif state == 2 then
			self.endCharge = false
			self.dashCharge:Stop()
			self.SliceVelocity.Enabled = false
			local chargetime = math.clamp((tick()-self.sliceTick), 0, 0.5)
			local staminause = math.clamp(0.5 + ((chargetime/0.5) * (2.5)),1,3) + (self.sliceStamina - math.floor(self.sliceStamina))
			self.StaminaUseBar.Visible = false
			self.swordSwipeSound.PlaybackSpeed = 1 + chargetime
			self.swordSwipeSound:Play()
			local lookVector = self.cam.CFrame.LookVector
			local alignment = lookVector:Dot(Vector3.new(0, 1, 0))
			self.sliceMomentum = true
			local impulseStrength = math.max(1100 * (1 - math.abs(alignment)), 500)
			impulseStrength = impulseStrength * (math.floor(staminause)/3)
			if (self.inFluid and self.fluidSubmerge > 45) then
				impulseStrength = impulseStrength * 0.25
			end
			self.hrp:ApplyImpulse(lookVector * impulseStrength)
			if self.reduceMotion.Value == false then
				tweenservice:Create(self.cam, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {FieldOfView = 70}):Play()
			end
			self.chargingSlice = false
			self.dashSound:Play()
			self.sliceStamina = self.sliceStamina - staminause
			self.sliceStamina = math.ceil(math.clamp(self.sliceStamina, 0, 3))
			task.spawn(function()
				task.wait(0.2)
				if self.sliceMomentum then
					self.hrp.AssemblyLinearVelocity = self.hrp.Velocity * 0.2
					self.sliceMomentum = false
				end
			end)
		end
	end
end

function PlayerMovement:CheckBreakable()
	local ray = workspace:Raycast(self.hrp.Position, Vector3.new(0, -10, 0), self.rayParams)
	local particles = {}
	if ray then
		if ray.Instance:HasTag('Breakable') then
			ray.Instance.CanCollide = false
			ray.Instance.Transparency = 1
			for c, i in pairs(ray.Instance:GetChildren()) do
				if i.ClassName == "Decal" then
					i.Transparency = 1
				end
				if i.ClassName == "Part" then
					i.Transparency = 1
					i.CanCollide = false
				end
				if i.ClassName == "ParticleEmitter" then
					i.Enabled = true
					table.insert(particles, i)
				end
			end	
			if ray.Instance.Material == Enum.Material.WoodPlanks then
				self.woodburstS[math.random(1,#self.woodburstS)]:Play()
			elseif ray.Instance.Material == Enum.Material.Glass then
				self.glassShatterS[math.random(1,#self.glassShatterS)]:Play()
			else
				self.earthburstS[math.random(1,#self.earthburstS)]:Play()
			end
			task.spawn(function()
				task.wait(0.2)
				for a, b in pairs(particles) do
					b.Enabled = false
				end
			end)
		end
	end
end

function PlayerMovement:sliceInteractions(i, inAir)
	if i:HasTag('SliceOrb') and i:GetAttribute('Broken') == false then
		local shatterT = {}
		self.sliceStamina = 3
		self.orbShatter:Play()
		self.orbsHit = self.orbsHit + 1
		self.ding.PlaybackSpeed = 0.7 + (0.1*self.orbsHit)
		self.ding:Play()
		for a, b in pairs(i:GetDescendants()) do
			if b.Parent == i.ParticleMain then
				b.Enabled = false
			end
			if b.Parent == i.Shatter then
				b.Enabled = true
				table.insert(shatterT, b)
			end
		end
		i:SetAttribute('Broken', true)
		local vel = self.hrp.Velocity
		if (tick()-self.dashJumpTick) < 0.2 then
			self.hrp.AssemblyLinearVelocity = self.hrp.AssemblyLinearVelocity * 0.95
		elseif inAir then
			self.hrp.AssemblyLinearVelocity = Vector3.new(vel.X * 0.2, math.clamp(vel.Y, 0, 50), vel.Z * 0.2)
		else
			self.hrp.AssemblyLinearVelocity = self.hrp.AssemblyLinearVelocity * 0.9
		end
		self:hitStop(0.2, false, 'Purple')
		task.spawn(function()
			task.wait(0.1)
			for c, d in pairs(shatterT) do
				d.Enabled = false
			end
			task.wait(math.clamp(i:GetAttribute('Cooldown') - 0.1, 0, 500))
			i:SetAttribute('Broken', false)
			for a, b in pairs(i.ParticleMain:GetChildren()) do
				b.Enabled = true
			end	
			shatterT = nil
		end)
	elseif i:HasTag('SliceBreakable') and i.CanCollide == true then
		local particles = {}
		i.CanCollide = false
		i.Transparency = 1
		for c, ii in pairs(i:GetChildren()) do
			if ii.ClassName == "Decal" then
				ii.Transparency = 1
			end
			if ii.ClassName == "Part" then
				ii.Transparency = 1
				ii.CanCollide = false
			end
			if ii.ClassName == "ParticleEmitter" then
				ii.Enabled = true
				table.insert(particles, ii)
			end
		end	
		if i.Material == Enum.Material.WoodPlanks then
			self.woodburstS[math.random(1,#self.woodburstS)]:Play()
		elseif i.Material == Enum.Material.Glass then
			self.glassShatterS[math.random(1,#self.glassShatterS)]:Play()
		else
			self.earthburstS[math.random(1,#self.earthburstS)]:Play()
		end
		task.spawn(function()
			task.wait(0.2)
			for a, b in pairs(particles) do
				b.Enabled = false
			end
		end)
	end
end

function PlayerMovement:Airborne(dt)
	if self.airVel.Force.Y > -150 then
		self.airVel.Force = self.airVel.Force * (0.995 ^ dt)
	end
	if self.CAddMulti < 0.5 then
		self.CAddMulti = self.CAddMulti + (self.hrp.Velocity.Magnitude/200 * dt)
	end
	if (tick() - self.lastGrounded) > 0.15 and self.jumpBuffer then
		self.numJumps = 1
	end
	if not self.wallRunning and not self.isSpider and not self.isLunge and (tick() - self.lastGrounded) > 0.3 then
		self:rayChecks()
	elseif self.wallRunning then
		self:Wallrun(dt)
	elseif self.isSpider then
		self:Spider(dt)
	end
	if self.isSlamming then
		self:CheckBreakable()
	end
	if (tick() - self.stunTick) > 1.3 then
		self.controller.BaseMoveSpeed = 30
	else
		self.controller.BaseMoveSpeed = 15
	end
end

function PlayerMovement:Grounded(dt)
	self.lastGrounded = tick()
	if not self.isSlamming and self.SliceVelocity.VectorVelocity == Vector3.new(0, -300, 0) then
		self.SliceVelocity.Enabled = false
	end
	if not self.crouching and (tick() - self.stunTick) > 1.3 then
		if self.CAddMulti > 0 then
			if self.CAddMulti > 0.01 then
				self.CAddMulti = self.CAddMulti*0.8
			else
				self.CAddMulti = 0
			end
		end
		self.controller.BaseMoveSpeed = 30
		if self.controller.GroundSensor.SensedPart:HasTag('Enemy') then
			self.hrp.AssemblyLinearVelocity = Vector3.new(self.hrp.AssemblyLinearVelocity.X,0,self.hrp.AssemblyLinearVelocity.Z)
			self.hrp:ApplyImpulse(Vector3.new(0,150,0))
		end
		if self.controller.GroundSensor.SensedPart:HasTag('NoFriction') or self.sliceMomentum then
			self.controller.GroundController.Friction = 0
		elseif not self.isSliding then
			self.controller.GroundController.Friction = 2
		end
	else
		self.controller.BaseMoveSpeed = 15
		if self.controller.GroundSensor.HitNormal.Y < 0.95 or self.slamSliding and not self.controller.GroundSensor.SensedPart:HasTag('IncreasedFriction') then
			self.controller.GroundController.Friction = 0
		elseif not self.isSliding and not self.controller.GroundSensor.SensedPart:HasTag('IncreasedFriction') then
			self.controller.GroundController.Friction = 2
		elseif  self.controller.GroundSensor.SensedPart:HasTag('IncreasedFriction') then
			self.controller.GroundController.Friction = 0.8
		end
		if self.CAddMulti > 0 then
			if self.CAddMulti > 0.01 then
				self.CAddMulti = self.CAddMulti*0.95
			else
				self.CAddMulti = 0
			end
		end
	end
end

function PlayerMovement:BallUpd()
	self.hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
	self.ball.AngularVelocity.AngularVelocity = Vector3.new(self.humanoid.MoveDirection.Z * 30,0,self.humanoid.MoveDirection.X * -30)
	self.ball.AngularVelocity.MaxTorque = 2000
	if not self:isMoving() then
		self.ball.AngularVelocity.MaxTorque = 1500
	end
	self.windParticles.ParticleEmitter.Rate = 0
	self.windSound.Volume = 0
	-- so, apparently, this just works? V
	self.hrp.CFrame = CFrame.new(self.ball.Position) * self.hrp.CFrame.Rotation 
	-- had so much trouble with trying weird hrp desync just for this thing to magically work. precious time of my life ill never get back
	self.morphLoop.Volume = math.clamp(0.5*(self.ball.Velocity.Magnitude/10), 0.5, 2)
	self.morphLoop.PlaybackSpeed = math.clamp(self.ball.Velocity.Magnitude/12, 0.4, 1)
end

function PlayerMovement:GrappleHandler()
	local facedir = self.hrp.CFrame.LookVector
	local movedir = self.humanoid.MoveDirection
	local dotproduct = facedir:Dot(movedir)
	if dotproduct > 0 then
		self.viewportGPull:Play(0.2)
		self.viewportGRepel:Stop(0.2)
	elseif dotproduct < 0 then
		self.viewportGRepel:Play(0.2)
		self.viewportGPull:Stop(0.2)
	elseif dotproduct == 0 or movedir == Vector3.new(0,0,0) then
		self.viewportGRepel:Stop(0.2)
		self.viewportGPull:Stop(0.2)
	end
end

function PlayerMovement:LungeHandler(dt)
	local target = CFrame.new(self.headCollider.Position, self.lungePoint.Position)
	if self.reduceMotion.Value == true then
		self.cam.CFrame = target
	else
		self.cam.CFrame = target * self.shakeCF
	end
	local dir = (self.hrp.Position - self.lungePoint.Position).unit
	local newposition = self.hrp.Position + ((350*dt) * -dir)
	local distance = (self.hrp.Position - self.lungePoint.Position).magnitude
	local KValXZ = self.lungePoint:GetAttribute('KnockbackXZ')
	local KValY = self.lungePoint:GetAttribute('KnocbackY')
	local KnockXZ = KValXZ or 20
	local KnockY = KValY or 5
	if distance <= 8 then
		self:EndLunge(KnockXZ, KnockY, dir)
	else
		self.hrp.CFrame = CFrame.new(newposition) * self.hrp.CFrame.Rotation 
	end
end

function PlayerMovement:SlideUpd(dt)
	if self.controller.GroundSensor.HitNormal.Y == 1 then
		self.controller.GroundController.Friction = self.controller.GroundController.Friction + (0.1 * dt)
	else
		self.controller.GroundController.Friction = 0
	end
	self.slideForce.Force = self.slideForce.Force * (0.97^dt)
	self.controller.MovingDirection = Vector3.new(0,0,0)
	self.rot.Value = 7.5
	if (self.hrp.Velocity.Magnitude < 13 and self.controller.GroundSensor.HitNormal.Y == 1) or self.numJumps > 0 then
		self:endSlide()
	end
end

function PlayerMovement:checkCameraInPart(campos, tag, getall)
	local parts = {}
	for _, part in ipairs(self.camCheckParts) do
		if part:IsA("BasePart") and collectionServ:HasTag(part, tag) then
			local partSize = part.Size / 2
			local cameraPositionInPartSpace = part.CFrame:PointToObjectSpace(campos)

			if (math.abs(cameraPositionInPartSpace.X) <= partSize.X) and
				(math.abs(cameraPositionInPartSpace.Y) <= partSize.Y) and
				(math.abs(cameraPositionInPartSpace.Z) <= partSize.Z) then
				if not getall then
					return part
				else
					table.insert(parts, part)
				end
			end
		end
	end
	if getall and #parts > 0 then
		return parts
	else
		return false
	end
end

function PlayerMovement:checkInsideFluid()
	local prevInFluid = self.inFluid
	self.inFluid = false
	for _, i in pairs(self.inHB) do
		if i:HasTag('Fluid') then
			self.inFluid = true
			self.fluidPart = i
			local surface = (self.fluidPart.Position.Y + self.fluidPart.Size.Y/2)
			local height = self._isBall and (self.ball.Position.Y-2.77) or (self.headCollider.Position.Y-5.3)
			self.fluidSubmerge = not self.isFinsActive.Value and math.clamp(-(height - surface)* 25, 0, 100) or 0
			break
		end
	end
	if self.inFluid then
		self.hrp.CustomPhysicalProperties = PhysicalProperties.new(1.2, 0.3, 0.5)
		if self.velBasedOnPos.Y < -19 and not prevInFluid then
			self.waterSplashSound:Play()
		end
	elseif not self.inFluid then
		self.hrp.CustomPhysicalProperties = PhysicalProperties.new(1.09, 0.3, 0.5)
	end
	if self:checkCameraInPart(self.cam.CFrame.Position, "Fluid") then
		self.correctBelowColor:Play()
		self.blur.Enabled = true
		if not self.audioMuffle.Enabled then
			self.audioMuffle.Enabled = true
			self.waterEnterSound:Play()
		end
	else
		self.correctAboveColor:Play()
		self.blur.Enabled = false
		if self.audioMuffle.Enabled then
			self.audioMuffle.Enabled = false
			self.waterExitSound:Play()
		end	
	end
end

function PlayerMovement:screenrain()
	local r = self:checkCameraInPart(self.cam.CFrame.Position, "Rain", true)
	local culminative = 0
	if r then
		for c, i in pairs(r) do
			local at = i:GetAttribute('rainAmount') or 5
			culminative = culminative + at
		end
	end
	self.screenRain.ParticleEmitter.Rate = culminative
end

local db = false
function PlayerMovement:hitboxInteractions()
	print(self.requestReturn)
	local inCameraOverride = false
	for _, i in pairs(self.inHB) do
		if i:HasTag("TutorialPrompt") and not self.inTutorial then
			self.inTutorial = true
			self.NotifSound:Play()
			self.hudAnim.ShowTooltip1:Play()
			local attribute = "Prompt"
			if self.mobile then
				attribute = attribute.."M"
			elseif self.console then
				attribute = attribute.."C"
			end
			if i:GetAttribute(attribute) ~= nil then
				self.mainHud.Tooltip.Frame.TextLabel.Text = i:GetAttribute(attribute)
			else
				self.mainHud.Tooltip.Frame.TextLabel.Text = "NoDialougeFound"
			end
		elseif i:HasTag("TutorialEnd") and self.inTutorial then
			self.inTutorial = false
			self.hudAnim.ShowTooltip:Play()
		end
		if i:HasTag('CameraLock') and self._isBall then
			inCameraOverride = true
			local pos = i:GetAttribute('CamPos')
			if pos ~= nil then
				self.cam.CameraType = 'Scriptable'
				self.cam.CFrame = CFrame.lookAt(pos, self.ball.Position)
			end
		end
		if (tick() - self.hurtTick) > 0.25 then
			if i:HasTag('hurtpart') then
				self.hurtSound:Play()
				self.hurtTick = tick()
				self.camShake:ShakeOnce(2.5, 15, 0, 0.5)
				local dmg = i:GetAttribute('Damage')
				if dmg == nil then
					dmg = 10
				end
				self.health = self.health - dmg
			end
			if i:HasTag('healpart') and self.health < 99 then
				local heal = i:GetAttribute('Heal')
				if heal == nil then
					heal = 10
				end
				self.hurtTick = tick() - 0.15
				self.health = self.health + heal
				self.healSound:Play()
			end
		end
		if i:HasTag('Collectable') then
			local identifer = i:GetAttribute('Identifier')
			local typePower = i:GetAttribute("UpgradeType")
			if typePower ~= nil and db == false then
				db = true
				self.hrp.Anchored = true
				self.cam.CameraType = 'Scriptable'
				self.requestReturn = datastoreUpdater:InvokeServer(typePower, identifer)
				if self.requestReturn then
					if i.Parent ~= nil then
						i.Parent:Destroy()
					end
				end
			end
			db = false
		end
	end
	if not inCameraOverride then
		self.cam.CameraType = "Custom"
	end
end

function PlayerMovement:handleStates(dt)
	local rate = 1
	if self:inAir() then
		self:Airborne(dt)
		rate = 0.5
	else
		self:Grounded(dt)
	end
	if self.sliceMomentum or (tick()-self.dashJumpTick) < 0.2 then
		for c, i in pairs(self.inHB) do
			self:sliceInteractions(i, true)
		end
	end
	if self.sliceStamina < 3 and not self.chargingSlice then
		local newS = math.clamp(self.sliceStamina + (rate*dt), 0, 3)
		self.sliceStamina = newS
	end
	self:checkInsideFluid()
	self:screenrain()
	self:hitboxInteractions()
	if self.health > self.MaxHealth then
		self.health = self.MaxHealth
	elseif self.health < 0 then
		self.health = 0
	end
	if self.health == 0 then
		self.humanoid.Health = 0
	end
	self.HPUISpringObject.GuiObject.HPDisplay.Text = self.health
	if self.controller.GroundSensor.HitNormal.Y == 1 and self.slamSliding then
		self.slamSliding = false
		self.SliceVelocity.Enabled = false
	end
	if (tick() - self.stunTick) > 1.3 and self.stunImg.ImageTransparency == 0 then
		self.stunHide:Play()
	end
	if self.blocking == true then
		if not self.viewportSBlock.IsPlaying and not self.viewportBlockLoop.IsPlaying then
			self.viewportBlockLoop:Play()
		end
	end
	local count = 0
	for _, i in pairs(workspace:GetPartsInPart(self.char.CrouchCollider)) do
		if i.CanCollide == true then
			count = count + 1
		end
	end
	if count > 2 then
		self:crouch(false)
	end
	if self.crouching and self.crouchInput == false and count < 3  then
		self:uncrouch()
	end
	if self.isGrapple then
		self:GrappleHandler()
	end
	local chargetime = math.clamp((tick()-self.sliceTick), 0, 0.5)
	local staminause = math.clamp(0.5 + ((chargetime/0.5) * (2.5)),1,3) + (self.sliceStamina - math.floor(self.sliceStamina))
	if self.beginCharge then
		self:Slice(1)
	elseif self.endCharge or (self.chargingSlice and (tick() - self.sliceTick) >= 0.5) or (self.chargingSlice and staminause >= self.sliceStamina) then
		self:Slice(2)
	end
	if self.isLunge and self.lungePoint ~= nil then
		self:LungeHandler(dt)
	end
	if self.isSliding then
		self:SlideUpd(dt)
	end
	if self._isBall then
		self:BallUpd()
	else
		self:WindParticles()
		self.controller.FacingDirection = self.cam.CFrame.LookVector
	end
	local staminaVal = self.chargingSlice and (self.sliceStamina - staminause) or self.sliceStamina
	self.StaminaFillBar.Size = UDim2.new(staminaVal*0.26, 0, 0.722, 0)
	self.StaminaS1.BorderSizePixel = staminaVal >= 1 and 1 or 0
	self.StaminaS2.BorderSizePixel = staminaVal >= 2 and 1 or 0
end

function PlayerMovement:DeathCleanup()
	print('dclean called')
	self.isDead = true
	self.controller.MovingDirection = Vector3.new(0,0,0)
	self.slideSound.Playing = false
	if self._isBall then
		self:enterMorph()
	end
	self.windSound.Volume = 0
	game:GetService('Debris'):AddItem(self.ball, 0.05)
	game:GetService('Debris'):AddItem(self.viewport, 0.05)
	game:GetService('Debris'):AddItem(self.windParticles, 0.05)
	game:GetService('Debris'):AddItem(self.charmodel, 0.05)
	game:GetService('Debris'):AddItem(self.screenRain, 0.05)
	game:GetService('Debris'):AddItem(self.slamAirborneP, 0.05)
	self.alignPos.Enabled = false
	self.grappleBeams = nil
	self.camCheckParts = nil
	self.plr.CameraMaxZoomDistance = 1
	self.plr.CameraMinZoomDistance = 1
	self.hrp.Anchored = true
	self.HPUISpringObject.GuiObject.Parent.Enabled = false
	self.camShake:Stop()
	self.cleanup = true
end

function PlayerMovement:MoveSpeedHandler()
	if  (self.inFluid and self.fluidSubmerge > 50) then
		self.controller.GroundController.MoveSpeedFactor = 0.5
		self.controller.AirController.MoveSpeedFactor = 0.5
		self.controller.AirController.MoveMaxForce = 300
	else
		self.controller.GroundController.MoveSpeedFactor = 1.05*(self.CAddMulti+1)
		self.controller.AirController.MoveSpeedFactor = 1 *(self.CAddMulti+1)
		self.controller.AirController.MoveMaxForce = self:getMovementDeviation(self.humanoid.MoveDirection, self.hrp.CFrame.LookVector, 1000)
	end

	if self.isRunningIntoWall and self.controller.AirController.MoveMaxForce > 500 then
		self.controller.AirController.MoveMaxForce = 500
	end
end

function PlayerMovement:getPartsInHB()
	if not self._isBall then
		self.inHB = workspace:GetPartsInPart(self.hitBox, self.parryParams)
	else
		self.inHB = workspace:GetPartsInPart(self.ball, self.parryParams)
	end
end

function PlayerMovement:update(dt)
	if self:isAlive() then
		if self.hrp.CFrame.Y < -450 or self.ball.CFrame.Y < -450 then
			self.humanoid.Health = 0
			self.hrp.Anchored = true
		end
		self:getPartsInHB()
		self:AimAssist()
		self:updateCursor()
		self:updateVelocity()
		self:updateMovementDirection()
		self:handleStates(dt)
		self:footSteps() -- stomp stompity stomp stomp
		self:MoveSpeedHandler()
		self:updateViewport(dt)
	elseif not self:isAlive() and not self.cleanup then 
		self:DeathCleanup() -- collect garbage and stop player if dead
	end
end

return PlayerMovement