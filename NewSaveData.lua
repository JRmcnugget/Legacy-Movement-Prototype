local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local DataStore2 = require(ServerScriptService.DataStore2)
local ReplicatedStorage = game.ReplicatedStorage
local func = ReplicatedStorage.RequestPowerup
local bools = {'DoubleJump', 'Spider', 'Slice', 'Lunge', 'Sword', 'BoomerangSword', 'Slam', 'Grapple', 'Fins', 'Ball'}
DataStore2.Combine("Settings", 'reduceMotion')
DataStore2.Combine("Data", "HPUpgrades", "BlockUpgrades")
DataStore2.Combine("Data", unpack(bools))
local totalHP = 7
local totalBlock = 7

Players.PlayerAdded:Connect(function(player)
	local RM = DataStore2('reduceMotion', player)
	local BT = DataStore2('beatTutorial', player)
	local HPU = DataStore2('HPUpgrades', player)
	local BU = DataStore2('BlockUpgrades', player)

	local datafolder = Instance.new('Folder')
	datafolder.Name = "DATA"
	datafolder.Parent = player

	local Settings = Instance.new('Folder')
	Settings.Name = "Settings"
	Settings.Parent = datafolder
	
	for c, i in pairs(bools) do
		local store = DataStore2(i, player)
		local val = Instance.new('BoolValue')
		val.Parent = datafolder
		val.Name = i
		val.Value = store:Get(false)
		store:OnUpdate(function(new)
			val.Value = new
		end)
	end

	local reduceMotion  = Instance.new('BoolValue')
	reduceMotion.Name = "reduceMotion"
	reduceMotion.Parent = Settings
	reduceMotion.Value = RM:Get(false)
	
	local beatTutorial  = Instance.new('BoolValue')
	beatTutorial.Name = "beatTutorial"
	beatTutorial.Parent = Settings
	beatTutorial.Value = BT:Get(false)
	
	local healthUpgrades  = Instance.new('StringValue')
	healthUpgrades.Name = "HPUpgrades"
	healthUpgrades.Parent = datafolder
	healthUpgrades.Value = HPU:Get("")
	
	local blockUpgrades  = Instance.new('StringValue')
	blockUpgrades.Name = "BlockUpgrades"
	blockUpgrades.Parent = datafolder
	blockUpgrades.Value = BU:Get("")
	
	RM:OnUpdate(function(new)
		reduceMotion.Value = new
	end)
	
	HPU:OnUpdate(function(new)
		healthUpgrades.Value = new
	end)
	
	BU:OnUpdate(function(new)
		blockUpgrades.Value = new
	end)
	
end)

-- instance, string, int
-- requests to update datastore2, returns true when successful
function requestPowerup(plr, powerup, identifier)
	if powerup == "HPUpgrades" or powerup == "BlockUpgrades" then
		local selectedVal = powerup == "HPUpgrades" and plr.DATA.HPUpgrades or plr.DATA.healthUpgrades
		local datastore = DataStore2(powerup, plr)
		if identifier ~= nil then
			local currentlyObtained = string.split(selectedVal.Value, "|")
			for c, i in pairs(currentlyObtained) do
				if tonumber(i) == identifier then
					return false -- already collected, refuse to collect a duplicate
				end
			end
			datastore:Set(selectedVal.Value..("|"..tostring(identifier)))
			print('a')
			return true
		end
	else
		for c, i in pairs(bools) do -- implementation of duplicate checking isn't necessary here
			if powerup == i then
				local datastore = DataStore2(i, plr)
				datastore:Set(true)
				return true -- we don't need to query any more since we found it already
			end
		end
	end
	return false -- nothing updated, tell client
end

func.OnServerInvoke = requestPowerup