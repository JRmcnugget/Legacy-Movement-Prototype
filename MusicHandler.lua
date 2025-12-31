local CollectionService = game:GetService('CollectionService')
local TweenService = game:GetService('TweenService')
local cam = workspace.CurrentCamera
local musicFolder = Instance.new('Folder', cam)
musicFolder.Name = 'BGM'
local currentMusic = "None"
local plr = script.Parent.Parent
local playingFade = false
local tweens = {}
local fadeCoro = nil

-- music prefabs
local Action = {
	'rbxassetid://9045397467'
}

local Cat = {
	'rbxassetid://9038275592'
}

local ChallengeCourse = {
	'rbxassetid://92047769833851'
}

local firstlight = {
	'rbxassetid://119814182676454'
}

local General1 = {
	'rbxassetid://9046475223'
}

local General2 = {
	'rbxassetid://9046474875'
}

local General3 = {
	'rbxassetid://9046474875'
}

local General4 = {
	'rbxassetid://9046476113'
}

local Otherworld = {
	'rbxassetid://1842960265'
}

local Title = {
	'rbxassetid://1840020630'
}

local Tower1 = {
	'rbxassetid://1843748008',
	'rbxassetid://1836406569'
}

local UltrakillTypeBeat = {
	'rbxassetid://105914070405455'
}

local Battle1 = {
	'rbxassetid://1841041776'
}

local strange = {
	'rbxassetid://96727522170625'
}

local Battle2 = {
	'rbxassetid://1842940651'
}

local strange2 = {
	'rbxassetid://9041781230'
}

local Temple = {
	'rbxassetid://9039982062',
	'rbxassetid://1840784387',
	'rbxassetid://9048709292'
}

local Temple2 = {
	'rbxassetid://1843005255',
	'rbxassetid://1842992846'
}

local depths = {
	'rbxassetid://9125351901'
}

local depths2 = {
	'rbxassetid://9043360237'
}

local serene = {
	'rbxassetid://9046594790',
	'rbxassetid://9116971475',
	'rbxassetid://9116258282'
}

local saveStation = {
	'rbxassetid://9042042428'
}

-- music dictionary
local musicDictionary = {
	Action = Action,
	Cat = Cat,
	ChallengeCourse = ChallengeCourse,
	General1 = General1,
	General2 = General2,
	General3 = General3,
	General4 = General4,
	Otherworld = Otherworld,
	Title = Title,
	Tower1 = Tower1,
	Depths = depths,
	Depths2 = depths2,
	UltrakillTypeBeat = UltrakillTypeBeat,
	Battle1 = Battle1,
	Battle2 = Battle2,
	strange = strange,
	strange2 = strange2,
	Temple = Temple,
	Temple2 = Temple2,
	serene = serene,
	saveStation = saveStation
}

-- le librarian function
local function getMusicTable(musicType)
	return musicDictionary[musicType]
end

local newAudio = {} -- keep track of new audio to apply tweenservice later

local function playMusic(part, musicType, fadeTime)
	if currentMusic and currentMusic ~= musicType then -- check if new music is begin requested
		local newMusicF = getMusicTable(musicType) 
		if newMusicF then -- allow if musicType has a prefab
			if fadeCoro ~= nil and playingFade == true then -- if in the process of playing previous tweens, stop
				coroutine.close(fadeCoro)
				for _, i in pairs(musicFolder:GetChildren()) do
					i:Destroy() -- we don't need that music anymore, lets free up that RAM
				end
			end

			-- Clear previous tweens
			tweens = {}

			for _, i in pairs(musicFolder:GetChildren()) do -- create fadeout tween for each playing audio
				table.insert(tweens, TweenService:Create(i, TweenInfo.new(fadeTime), {Volume = 0})) 
			end
			for _, i in pairs(newMusicF) do -- create new audio and keep track of them
				local a = Instance.new('Sound', musicFolder)
				a.SoundId = i
				a.Looped = true
				a.SoundGroup = game.SoundService.MuffledAudio
				table.insert(newAudio, a)
			end

			currentMusic = musicType -- switch to new music
			fadeCoro = coroutine.create(function() -- fade coroutine for audio, so we can stop it later if needed 
				playingFade = true

				for _, tween in pairs(tweens) do
					tween:Play()
				end

				wait(fadeTime)

				for _, tween in pairs(tweens) do
					tween.Instance:Destroy() -- we don't need that music anymore, lets free up that RAM
				end

				for _, i in pairs(newAudio) do -- fade in the new music
					i.Volume = 0
					i:Play()
					local volume = part:GetAttribute('volume')
					local vol = volume and volume or 0.5
					local fadeInTween = TweenService:Create(i, TweenInfo.new(fadeTime), {Volume = vol})
					fadeInTween:Play()
				end

				fadeCoro = nil -- no longer playing fade, get rid of coroutine
				playingFade = false
			end)

			coroutine.resume(fadeCoro) -- actually start the whole coroutine
		else
			warn('MusicPart at '..tostring(part.Position).. 'tried to play an invalid music type! Did you enter the value correctly?')
		end
	end
end

local connections = {} -- keep track of all touch connections

local function onInstanceAdded(object)
	if object:IsA("BasePart") then -- apply function to play music to each part with tag
		connections[object] = object.Touched:Connect(function(hit)
			local fadeQuery = object:GetAttribute("fadetime")
			local musicType = object:GetAttribute("musicType")
			local fadeTime = (fadeQuery~=nil) and fadeQuery or 0

			if musicType and fadeTime and hit.Parent:FindFirstChild('Humanoid') then
				playMusic(object, musicType, fadeTime)
			end
		end)
	end
end

local function onInstanceRemoved(object) -- remove touch connection when instance removed to prevent memory leaks
	if connections[object] then
		connections[object]:Disconnect()
		connections[object] = nil
	end
end

for _, object in pairs(CollectionService:GetTagged('musictrigger')) do -- find all currently in workspace tagged parts
	onInstanceAdded(object)
end

CollectionService:GetInstanceAddedSignal('musictrigger'):Connect(onInstanceAdded)
CollectionService:GetInstanceRemovedSignal('musictrigger'):Connect(onInstanceRemoved)