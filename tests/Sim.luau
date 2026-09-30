--[[
	Sim — runs the Rojo-built place headlessly in Lune: one server DataModel plus one DataModel per
	client, each loaded from the real .rbxlx, executing the real Script/LocalScript/ModuleScript
	sources. Roblox services the code touches are faked on a virtual clock:

	- RemoteEvents route between server and clients with latency, and payloads are serialized
	  (deep-copied, rejecting types/tables Roblox can't send).
	- Instance.new creates real Lune instances wrapped in proxies, so every property write is
	  validated against Roblox's reflection database (name AND type), while events (Activated,
	  GetPropertyChangedSignal) are provided by fake signals the test bots can fire.
	- task.delay / TweenService / Debris / RunService.Heartbeat run on the virtual clock.

	Every error thrown inside a handler, timer or script is recorded in sim.errors; every warn()
	in sim.warnings. Nothing visual is modelled: there's no rendering or physics, and a tween just
	lands on its end state when it finishes. The tests in run.luau use this; see there to run them.
]]

local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local fs = require("@lune/fs")

local Sim = {}

-- Lune's CFrame.lookAt flips the look direction's Z component (toward -Z it faces +Z), unlike
-- Roblox's. Game code gets this correct one instead; everything else is Lune's CFrame.
function Sim.lookAt(at, target, up)
	up = up or roblox.Vector3.new(0, 1, 0)
	local look = (target - at).Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(roblox.Vector3.new(0, 0, 1))
	end
	right = right.Unit
	return roblox.CFrame.fromMatrix(at, right, right:Cross(look).Unit, -look)
end
local FixedCFrame = setmetatable({ lookAt = Sim.lookAt }, { __index = roblox.CFrame })
Sim.__index = Sim

local PROXY = newproxy(false) -- private key: proxy -> real instance

local function unwrap(value)
	if type(value) == "table" then
		local inner = rawget(value, PROXY)
		if inner ~= nil then
			return inner
		end
	end
	return value
end
Sim.unwrap = unwrap

--[[ Signals ]]

local Signal = {}
Signal.__index = Signal

function Signal.new(sim, label)
	return setmetatable({ sim = sim, label = label, handlers = {}, queue = nil }, Signal)
end

function Signal:Connect(fn)
	assert(type(fn) == "function", "Connect expects a function")
	local entry = { fn = fn, connected = true }
	table.insert(self.handlers, entry)
	-- Remote client signals queue events fired before anyone listened (like Roblox does).
	if self.queue and #self.queue > 0 then
		local queued = self.queue
		self.queue = {}
		for _, args in queued do
			self.sim:delay(0, function()
				self:Fire(table.unpack(args, 1, args.n))
			end, self.label .. " (queued)")
		end
	end
	local connection = { Connected = true }
	function connection.Disconnect(conn)
		entry.connected = false
		conn.Connected = false
	end
	return connection
end

function Signal:Fire(...)
	local anyone = false
	for _, entry in table.clone(self.handlers) do
		if entry.connected then
			anyone = true
			self.sim:protectedCall(self.label, entry.fn, ...)
		end
	end
	if not anyone and self.queue then
		table.insert(self.queue, table.pack(...))
	end
end

function Signal:Wait()
	error("Signal:Wait() isn't supported in the sim (the prototype shouldn't need to yield)")
end

Sim.Signal = Signal

--[[ Remote payload rules ]]

local IMMUTABLE_DATATYPES = {
	Color3 = true,
	Vector3 = true,
	Vector2 = true,
	UDim = true,
	UDim2 = true,
	CFrame = true,
	EnumItem = true,
}

local function serialize(value, path)
	local kind = typeof(value)
	if kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" then
		return value
	end
	if IMMUTABLE_DATATYPES[kind] then
		return value
	end
	if kind == "table" then
		if rawget(value, PROXY) ~= nil then
			error(`{path}: Instances aren't sent by the prototype's remotes`)
		end
		if getmetatable(value) ~= nil then
			error(`{path}: a table with a metatable (it would arrive without it)`)
		end
		local length = #value
		local count, stringKeys = 0, 0
		for key in value do
			count += 1
			if type(key) == "string" then
				stringKeys += 1
			elseif type(key) ~= "number" then
				error(`{path}: key of type {typeof(key)} can't cross a remote`)
			end
		end
		if stringKeys > 0 and stringKeys ~= count then
			error(`{path}: mixed array/dictionary table (Roblox drops part of it)`)
		end
		if stringKeys == 0 and count ~= length then
			error(`{path}: array with holes or non-sequential number keys`)
		end
		local copy = {}
		for key, item in value do
			copy[key] = serialize(item, `{path}.{key}`)
		end
		return copy
	end
	error(`{path}: {kind} can't cross a remote`)
end
Sim.serialize = serialize

--[[ Clock ]]

function Sim.new(placePath, options)
	options = options or {}
	local self = setmetatable({}, Sim)
	self.placeBytes = fs.readFile(placePath)
	self.now = 1000 -- server time starts somewhere non-zero, like GetServerTimeNow()
	self.seq = 0
	self.timers = {}
	self.latency = options.latency or 0.03
	self.heartbeatInterval = options.heartbeatInterval or 0.2
	self.errors = {}
	self.warnings = {}
	self.tweening = setmetatable({}, { __mode = "k" }) -- instance -> property -> the tween driving it
	self.tweenLog = {} -- every tween played: { instance, goals, info, time }
	self.remotes = {}
	self.clients = {}
	self.clientOrder = {}
	self.serverPlayers = {}
	self.hooks = { serverSend = {}, serverBroadcast = {} }
	self.verbose = options.verbose
	math.randomseed(options.seed or 1)
	self.RandomClass = Sim.makeRandomClass()
	self.server = self:createEnv("server", "server", nil)
	return self
end

function Sim:protectedCall(label, fn, ...)
	local ok, err = xpcall(fn, function(message)
		return debug.traceback(tostring(message), 2)
	end, ...)
	if not ok then
		table.insert(self.errors, { label = label, message = err, time = self.now })
		if self.verbose then
			print(`[error] {label}: {err}`)
		end
	end
	return ok
end

function Sim:delay(seconds, fn, label)
	self.seq += 1
	table.insert(self.timers, {
		time = self.now + math.max(0, seconds or 0),
		seq = self.seq,
		fn = fn,
		label = label or "timer",
	})
end

function Sim:nextTimerIndex()
	local bestIndex = nil
	local best = nil
	for index, timer in self.timers do
		if best == nil or timer.time < best.time or (timer.time == best.time and timer.seq < best.seq) then
			bestIndex, best = index, timer
		end
	end
	return bestIndex, best
end

-- Runs every timer due in the next `seconds` of virtual time.
function Sim:run(seconds)
	local target = self.now + seconds
	while true do
		local index, timer = self:nextTimerIndex()
		if index == nil or timer.time > target then
			break
		end
		table.remove(self.timers, index)
		self.now = math.max(self.now, timer.time)
		self:protectedCall(timer.label, timer.fn)
	end
	self.now = target
end

-- Runs until predicate() is true (checked after every timer). Returns true if it became true.
function Sim:runUntil(predicate, maxSeconds)
	local deadline = self.now + maxSeconds
	if predicate() then
		return true
	end
	while true do
		local index, timer = self:nextTimerIndex()
		if index == nil or timer.time > deadline then
			self.now = deadline
			return predicate()
		end
		table.remove(self.timers, index)
		self.now = math.max(self.now, timer.time)
		self:protectedCall(timer.label, timer.fn)
		if predicate() then
			return true
		end
	end
end

--[[ Random, TweenInfo ]]

function Sim.makeRandomClass()
	local Random = {}
	Random.__index = Random
	function Random.new(_seed)
		return setmetatable({}, Random)
	end
	function Random:NextInteger(min, max)
		assert(type(min) == "number" and type(max) == "number", "NextInteger expects numbers")
		assert(math.floor(min) == min and math.floor(max) == max, `NextInteger expects whole numbers, got {min}, {max}`)
		assert(min <= max, `NextInteger min {min} > max {max}`)
		return math.random(min, max)
	end
	function Random:NextNumber(min, max)
		local f = math.random()
		if min == nil then
			return f
		end
		return min + (max - min) * f
	end
	return Random
end

local TweenInfo = {}
function TweenInfo.new(time, style, direction, repeatCount, reverses, delayTime)
	assert(type(time) == "number", "TweenInfo.new: time must be a number")
	assert(style == nil or typeof(style) == "EnumItem", "TweenInfo.new: easingStyle must be an EnumItem")
	assert(direction == nil or typeof(direction) == "EnumItem", "TweenInfo.new: easingDirection must be an EnumItem")
	assert(repeatCount == nil or type(repeatCount) == "number", "TweenInfo.new: repeatCount must be a number")
	assert(reverses == nil or type(reverses) == "boolean", "TweenInfo.new: reverses must be a boolean")
	assert(delayTime == nil or type(delayTime) == "number", "TweenInfo.new: delayTime must be a number")
	return {
		__tweenInfo = true,
		Time = time,
		RepeatCount = repeatCount or 0,
		Reverses = reverses == true,
		DelayTime = delayTime or 0,
	}
end

--[[ Environments (one per DataModel) ]]

function Sim:remoteRecord(fullName)
	local record = self.remotes[fullName]
	if record == nil then
		record = { serverSignal = Signal.new(self, "OnServerEvent " .. fullName), clientSignals = {} }
		self.remotes[fullName] = record
	end
	return record
end

function Sim:clientSignal(fullName, userId)
	local record = self:remoteRecord(fullName)
	local signal = record.clientSignals[userId]
	if signal == nil then
		signal = Signal.new(self, `OnClientEvent {fullName} ({userId})`)
		signal.queue = {}
		record.clientSignals[userId] = signal
	end
	return signal
end

function Sim:sendToClient(fullName, userId, ...)
	local payload = table.pack(...)
	for i = 1, payload.n do
		payload[i] = serialize(payload[i], `{fullName} -> client arg {i}`)
	end
	for _, hook in self.hooks.serverSend do
		hook(fullName, userId, payload)
	end
	self:delay(self.latency, function()
		if self.clients[userId] == nil then
			return
		end
		self:clientSignal(fullName, userId):Fire(table.unpack(payload, 1, payload.n))
	end, `deliver {fullName} -> {userId}`)
end

function Sim:sendToServer(fullName, userId, ...)
	local payload = table.pack(...)
	for i = 1, payload.n do
		payload[i] = serialize(payload[i], `{fullName} -> server arg {i}`)
	end
	self:delay(self.latency, function()
		local player = self.serverPlayers[userId]
		if player == nil then
			return
		end
		self:remoteRecord(fullName).serverSignal:Fire(player, table.unpack(payload, 1, payload.n))
	end, `deliver {fullName} -> server`)
end

function Sim:createEnv(name, side, client)
	local sim = self
	local env = {
		name = name,
		side = side,
		client = client,
		dm = roblox.deserializePlace(self.placeBytes),
		modules = {},
		signals = {}, -- [instance][eventName] = Signal
		characters = {}, -- clients: [userId] = this client's copy of that player's character
	}

	local function instanceSignal(instance, eventName)
		local set = env.signals[instance]
		if set == nil then
			set = {}
			env.signals[instance] = set
		end
		local signal = set[eventName]
		if signal == nil then
			signal = Signal.new(sim, `{name} {instance:GetFullName()}.{eventName}`)
			set[eventName] = signal
		end
		return signal
	end
	env.instanceSignal = instanceSignal

	local services = {}
	local wrap

	local function remoteMember(instance, key)
		local fullName = instance:GetFullName()
		if side == "server" then
			if key == "OnServerEvent" then
				return sim:remoteRecord(fullName).serverSignal
			elseif key == "FireClient" then
				return function(_, player, ...)
					assert(type(player) == "table" and player.UserId, "FireClient needs a Player")
					sim:sendToClient(fullName, player.UserId, ...)
				end
			elseif key == "FireAllClients" then
				return function(_, ...)
					local payload = table.pack(...)
					for i = 1, payload.n do
						payload[i] = serialize(payload[i], `{fullName} -> all clients arg {i}`)
					end
					for _, hook in sim.hooks.serverBroadcast do
						hook(fullName, payload)
					end
					for _, userId in sim.clientOrder do
						sim:sendToClient(fullName, userId, ...)
					end
				end
			elseif key == "OnClientEvent" or key == "FireServer" then
				error(`server code used client-only member {key} on {fullName}`, 3)
			end
		else
			local userId = client.userId
			if key == "OnClientEvent" then
				return sim:clientSignal(fullName, userId)
			elseif key == "FireServer" then
				return function(_, ...)
					sim:sendToServer(fullName, userId, ...)
				end
			elseif key == "OnServerEvent" or key == "FireClient" or key == "FireAllClients" then
				error(`client code used server-only member {key} on {fullName}`, 3)
			end
		end
		return nil
	end

	local EVENTS = { Activated = true, MouseButton1Click = true, Changed = true }

	wrap = function(instance)
		if instance == nil then
			return nil
		end
		assert(typeof(instance) == "Instance", "wrap expects an Instance")
		local proxy = { [PROXY] = instance }
		return setmetatable(proxy, {
			__index = function(_, key)
				local className = instance.ClassName
				if className == "RemoteEvent" then
					local member = remoteMember(instance, key)
					if member ~= nil then
						return member
					end
				elseif className == "DataModel" and key == "GetService" then
					return function(_, serviceName)
						return env.getService(serviceName)
					end
				elseif className == "Workspace" and key == "GetServerTimeNow" then
					return function()
						return sim.now
					end
				elseif className == "Camera" and key == "ViewportSize" then
					return env.viewportSize or roblox.Vector2.new(1280, 720)
				end

				if EVENTS[key] then
					return instanceSignal(instance, key)
				elseif key == "GetPropertyChangedSignal" then
					return function(_, property)
						assert(type(property) == "string", "GetPropertyChangedSignal expects a property name")
						local ok, err = pcall(function()
							return instance[property]
						end)
						-- Lune can't read some engine-computed properties (Camera.ViewportSize), but an
						-- unknown member is a real bug.
						if not ok and string.find(tostring(err), "not a valid member", 1, true) then
							error(err, 2)
						end
						return instanceSignal(instance, "Changed:" .. property)
					end
				elseif key == "WaitForChild" then
					return function(_, childName)
						local child = instance:FindFirstChild(childName)
						if child == nil then
							error(`WaitForChild would wait forever: {instance:GetFullName()}.{childName}`, 2)
						end
						return wrap(child)
					end
				end

				local value = instance[key] -- errors for anything that isn't a real member
				if typeof(value) == "Instance" then
					return wrap(value)
				elseif type(value) == "function" then
					return function(_, ...)
						local args = table.pack(...)
						for i = 1, args.n do
							args[i] = unwrap(args[i])
						end
						local results = table.pack(value(instance, table.unpack(args, 1, args.n)))
						for i = 1, results.n do
							if typeof(results[i]) == "Instance" then
								results[i] = wrap(results[i])
							elseif type(results[i]) == "table" then
								for j, item in results[i] do
									if typeof(item) == "Instance" then
										results[i][j] = wrap(item)
									end
								end
							end
						end
						return table.unpack(results, 1, results.n)
					end
				end
				return value
			end,
			__newindex = function(_, key, value)
				instance[key] = unwrap(value) -- Lune validates the member and the value type
			end,
			__tostring = function()
				return `Proxy<{instance:GetFullName()}>`
			end,
		})
	end
	env.wrap = wrap

	-- Services the prototype uses; anything else comes straight from the DataModel.
	local heartbeat = Signal.new(sim, name .. " Heartbeat")
	env.heartbeat = heartbeat
	services.RunService = { Heartbeat = heartbeat }
	services.TweenService = {
		Create = function(_, target, tweenInfo, goals)
			assert(type(tweenInfo) == "table" and tweenInfo.__tweenInfo, "TweenService:Create needs a TweenInfo")
			local instance = unwrap(target)
			for property, goal in goals do
				-- Validate the goal like the engine would: the property must exist and take this type.
				local old = instance[property]
				instance[property] = goal
				instance[property] = old
			end
			-- A tween lands on its goals when it finishes (a reversing one, back where it started);
			-- nothing in between is modelled. As in the engine, a newer tween on a property takes it
			-- over from an older one, which then never lands there, and a tween on an instance that
			-- has been destroyed just stops.
			local tween
			local function release()
				local owned = sim.tweening[instance]
				for property in goals do
					if owned and owned[property] == tween then
						owned[property] = nil
					end
				end
			end
			tween = {
				Completed = Signal.new(sim, "Tween.Completed"),
				Cancel = release,
				Play = function()
					local owned = sim.tweening[instance] or {}
					sim.tweening[instance] = owned
					local starts = {}
					for property in goals do
						starts[property] = instance[property]
						owned[property] = tween
					end
					table.insert(sim.tweenLog, { instance = instance, goals = goals, info = tweenInfo, time = sim.now })
					local cycles = (tweenInfo.RepeatCount + 1) * (if tweenInfo.Reverses then 2 else 1)
					sim:delay(tweenInfo.DelayTime + tweenInfo.Time * cycles, function()
						for property, goal in goals do
							if owned[property] == tween then
								local final = if tweenInfo.Reverses then starts[property] else goal
								pcall(function() -- Lune refuses to touch a destroyed instance
									instance[property] = final
								end)
							end
						end
						release()
						tween.Completed:Fire()
					end, "Tween")
				end,
			}
			return tween
		end,
	}
	services.Debris = {
		AddItem = function(_, target, lifetime)
			assert(type(lifetime) == "number", "Debris:AddItem needs a lifetime")
			sim:delay(lifetime, function()
				unwrap(target):Destroy()
			end, "Debris")
		end,
	}
	if side == "server" then
		local players = {
			PlayerAdded = Signal.new(sim, "Players.PlayerAdded"),
			PlayerRemoving = Signal.new(sim, "Players.PlayerRemoving"),
		}
		function players.GetPlayers()
			local list = {}
			for _, userId in sim.clientOrder do
				table.insert(list, sim.serverPlayers[userId])
			end
			return list
		end
		function players.GetPlayerByUserId(_, userId)
			return sim.serverPlayers[userId]
		end
		services.Players = players
	else
		local playerGui = roblox.Instance.new("PlayerGui")
		env.playerGui = playerGui
		services.Players = {
			LocalPlayer = {
				UserId = client.userId,
				DisplayName = client.name,
				Name = client.name,
				WaitForChild = function(_, childName)
					assert(childName == "PlayerGui", "the sim's LocalPlayer only has a PlayerGui")
					return wrap(playerGui)
				end,
			},
			-- Anyone in the server, with this client's copy of their character (nil if it hasn't
			-- replicated here).
			GetPlayerByUserId = function(_, userId)
				local player = sim.serverPlayers[userId]
				if player == nil then
					return nil
				end
				local model = env.characters[userId]
				return {
					UserId = userId,
					Name = player.Name,
					DisplayName = player.DisplayName,
					Character = if model then wrap(model) else nil,
				}
			end,
		}
	end

	function env.getService(serviceName)
		local fake = services[serviceName]
		if fake then
			return fake
		end
		return wrap(env.dm:GetService(serviceName))
	end

	local InstanceLib = {
		new = function(className, parent)
			assert(parent == nil, "don't use Instance.new's parent argument")
			return wrap(roblox.Instance.new(className))
		end,
	}

	local function globalsFor(scriptInstance)
		return {
			game = wrap(env.dm),
			workspace = env.getService("Workspace"),
			script = wrap(scriptInstance),
			require = env.require,
			Instance = InstanceLib,
			Color3 = roblox.Color3,
			UDim2 = roblox.UDim2,
			UDim = roblox.UDim,
			Vector2 = roblox.Vector2,
			Vector3 = roblox.Vector3,
			CFrame = FixedCFrame,
			Enum = roblox.Enum,
			TweenInfo = TweenInfo,
			Random = sim.RandomClass,
			task = {
				delay = function(seconds, fn, ...)
					local args = table.pack(...)
					sim:delay(seconds, function()
						fn(table.unpack(args, 1, args.n))
					end, name .. " task.delay")
				end,
				spawn = function(fn, ...)
					fn(...)
				end,
				wait = function()
					error("task.wait isn't supported in the sim")
				end,
			},
			warn = function(...)
				local parts = table.pack(...)
				for i = 1, parts.n do
					parts[i] = tostring(parts[i])
				end
				table.insert(sim.warnings, { env = name, message = table.concat(parts, " "), time = sim.now })
				if sim.verbose then
					print(`[warn] {name}: {table.concat(parts, " ")}`)
				end
			end,
			print = function(...)
				if sim.verbose then
					print(name, ...)
				end
			end,
		}
	end

	function env.require(target)
		local instance = unwrap(target)
		assert(typeof(instance) == "Instance" and instance.ClassName == "ModuleScript", "require expects a ModuleScript")
		local key = instance:GetFullName()
		local record = env.modules[key]
		if record then
			assert(not record.loading, "circular require: " .. key)
			return record.value
		end
		record = { loading = true }
		env.modules[key] = record
		local chunk = luau.load(instance.Source, { debugName = `{name}:{key}`, environment = globalsFor(instance) })
		local results = table.pack(chunk())
		assert(results.n == 1, `module {key} must return exactly one value`)
		record.value = results[1]
		record.loading = false
		return record.value
	end

	function env.runScript(scriptInstance)
		local chunk = luau.load(scriptInstance.Source, {
			debugName = `{name}:{scriptInstance:GetFullName()}`,
			environment = globalsFor(scriptInstance),
		})
		return sim:protectedCall(name .. " " .. scriptInstance.Name, chunk)
	end

	return env
end

--[[ Players ]]

function Sim:startServer()
	local script = self.server.dm:GetService("ServerScriptService"):FindFirstChild("BattleServer")
	assert(script and script.ClassName == "Script", "BattleServer Script missing from the place")
	assert(self.server.runScript(script), "BattleServer failed to start")
	local function beat()
		self.server.heartbeat:Fire(self.heartbeatInterval)
		self:delay(self.heartbeatInterval, beat, "server heartbeat")
	end
	self:delay(self.heartbeatInterval, beat, "server heartbeat")
end

-- (Re)spawns a player's character on the server: a Model with a HumanoidRootPart and a Humanoid,
-- standing on the spawn point facing -Z, like Roblox's default rig as far as the game code cares.
function Sim:spawnCharacter(userId)
	local player = self.serverPlayers[userId]
	assert(player, "not connected")
	if player._model then
		player._model:Destroy()
	end
	local model = roblox.Instance.new("Model")
	model.Name = player.Name
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = roblox.Vector3.new(2, 2, 1)
	root.CFrame = roblox.CFrame.new(0, 3, 0)
	root.Parent = model
	local humanoid = roblox.Instance.new("Humanoid")
	humanoid.Parent = model
	model.Parent = self.server.dm:GetService("Workspace")
	player._model = model
	player.Character = self.server.wrap(model)
	player.CharacterAdded:Fire(player.Character)
	self.characterSpawns = (self.characterSpawns or 0) + 1
	for _, client in self.clients do
		self:replicateCharacter(client, userId)
	end
end

-- Gives one client its copy of a player's character, like Roblox replicating it: a Model with a
-- HumanoidRootPart, a Torso, a Head, a Humanoid and an Animate script, not Archivable (as Roblox
-- characters aren't). Clients that shouldn't see it (say, it hasn't streamed in) can drop it.
function Sim:replicateCharacter(client, userId)
	local characters = client.env.characters
	if characters[userId] then
		characters[userId]:Destroy()
		characters[userId] = nil
	end
	local player = self.serverPlayers[userId]
	if player == nil or player._model == nil then
		return
	end
	local model = roblox.Instance.new("Model")
	model.Name = player.Name
	for _, spec in { { "HumanoidRootPart", roblox.Vector3.new(2, 2, 1) }, { "Torso", roblox.Vector3.new(2, 2, 1) }, { "Head", roblox.Vector3.new(2, 1, 1) } } do
		local part = roblox.Instance.new("Part")
		part.Name = spec[1]
		part.Size = spec[2]
		part.Anchored = spec[1] == "HumanoidRootPart"
		part.Parent = model
	end
	local humanoid = roblox.Instance.new("Humanoid")
	humanoid.MaxHealth = 100 -- Roblox's defaults (Lune has none for these)
	humanoid.Health = 100
	humanoid.Parent = model
	local animate = roblox.Instance.new("LocalScript")
	animate.Name = "Animate"
	animate.Parent = model
	model.Archivable = false
	model.Parent = client.env.dm:GetService("Workspace")
	characters[userId] = model
end

-- The server-side HumanoidRootPart of a player's character: what a bot "walks" by moving.
function Sim:rootPart(userId)
	local player = self.serverPlayers[userId]
	local model = player and player._model
	return if model then model:FindFirstChild("HumanoidRootPart") else nil
end

function Sim:humanoid(userId)
	local player = self.serverPlayers[userId]
	local model = player and player._model
	return if model then model:FindFirstChildOfClass("Humanoid") else nil
end

-- The overworld enemies standing in the server's Workspace right now, by id.
function Sim:overworldEnemies()
	local folder = self.server.dm:GetService("Workspace"):FindFirstChild("OverworldEnemies")
	local enemies = {}
	for _, part in (if folder then folder:GetChildren() else {}) do
		enemies[part.Name] = part
	end
	return enemies
end

-- Moves a player's character into touching range of an enemy (2 studs from its center, so a
-- patrol that walks on before the server looks is still in range), facing the way a front, back
-- or side touch needs. Like a real player walking up;
-- a character the server has anchored can't move.
function Sim:touchEnemy(userId, enemyPart, how)
	local root = self:rootPart(userId)
	if root == nil or root.Anchored then
		return false
	end
	local enemyPosition = enemyPart.CFrame.Position
	local offset = root.CFrame.Position - enemyPosition
	local direction = roblox.Vector3.new(offset.X, 0, offset.Z)
	direction = if direction.Magnitude > 0.1 then direction.Unit else roblox.Vector3.new(1, 0, 0)
	local position = roblox.Vector3.new(enemyPosition.X, 3, enemyPosition.Z) + direction * 2
	local toEnemy = -direction
	local look = if how == "front" then toEnemy
		elseif how == "back" then direction
		else roblox.Vector3.new(-toEnemy.Z, 0, toEnemy.X) -- side: at right angles
	root.CFrame = Sim.lookAt(position, position + look)
	return true
end

-- A player joins: the server sees PlayerAdded now, their LocalScripts start a moment later.
function Sim:connectClient(userId, name)
	assert(self.clients[userId] == nil, "already connected")
	local client = { userId = userId, name = name }
	client.env = self:createEnv("client:" .. name, "client", client)
	client.playerGui = client.env.playerGui
	self.clients[userId] = client
	table.insert(self.clientOrder, userId)
	for otherId in self.serverPlayers do
		self:replicateCharacter(client, otherId) -- characters already in the game
	end

	local sim = self
	local player = {
		UserId = userId,
		DisplayName = name,
		Name = name,
		Character = nil,
		CharacterAdded = Signal.new(self, name .. " CharacterAdded"),
		LoadCharacterAsync = function()
			sim:spawnCharacter(userId)
		end,
	}
	self.serverPlayers[userId] = player
	self.server.getService("Players").PlayerAdded:Fire(player)
	self:delay(0.3, function()
		if self.serverPlayers[userId] == player then
			self:spawnCharacter(userId)
		end
	end, name .. " character spawns")

	self:delay(0.5, function()
		if self.clients[userId] ~= client then
			return
		end
		local starterScripts = client.env.dm:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
		local localScript = starterScripts:FindFirstChild("BattleClient")
		assert(localScript and localScript.ClassName == "LocalScript", "BattleClient LocalScript missing")
		client.env.runScript(localScript)
		client.started = true
	end, name .. " scripts start")

	local function beat()
		if self.clients[userId] ~= client then
			return
		end
		client.env.heartbeat:Fire(self.heartbeatInterval)
		self:delay(self.heartbeatInterval, beat, name .. " heartbeat")
	end
	self:delay(self.heartbeatInterval, beat, name .. " heartbeat")
	return client
end

function Sim:disconnectClient(userId)
	local player = self.serverPlayers[userId]
	assert(player, "not connected")
	self.server.getService("Players").PlayerRemoving:Fire(player)
	if player._model then
		player._model:Destroy()
		player._model = nil
		player.Character = nil
	end
	for _, other in self.clients do
		if other.env.characters[userId] then
			other.env.characters[userId]:Destroy()
			other.env.characters[userId] = nil
		end
	end
	self.serverPlayers[userId] = nil
	self.clients[userId] = nil
	local index = table.find(self.clientOrder, userId)
	if index then
		table.remove(self.clientOrder, index)
	end
end

--[[ UI helpers for bots ]]

-- Would a real player be able to click this? (visible all the way up, interactable)
function Sim.isClickable(instance)
	if instance == nil or not instance:IsA("GuiButton") or not instance.Interactable then
		return false
	end
	local node = instance
	while node ~= nil and not node:IsA("LayerCollector") do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return node ~= nil and node.Enabled
end

function Sim:click(client, button)
	assert(Sim.isClickable(button), "tried to click something a player couldn't click: " .. button:GetFullName())
	client.env.instanceSignal(button, "Activated"):Fire(nil, 1)
end

-- A client's GUI by path, e.g. sim:gui(client, "Battle", "Actions", "AttackButton")
function Sim:gui(client, ...)
	local node = client.playerGui:FindFirstChild("BattleUI")
	for _, childName in { ... } do
		if node == nil then
			return nil
		end
		node = node:FindFirstChild(childName)
	end
	return node
end

return Sim
