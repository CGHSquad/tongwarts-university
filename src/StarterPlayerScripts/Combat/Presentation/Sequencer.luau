--!strict
--[[
	Sequencer — the client-side timeline every battle beat plugs into. A sequence is a duration and
	a list of cues (a time and a function); the sequencer runs the cues as its clock passes them,
	on Heartbeat, and reports whether it's busy (a sequence is still playing), which the HUD uses to
	hold the command ring until the stage is done and the tests use to check that no turn opens
	mid-animation.

	Everything a beat creates on the fly (effects, sounds, popups) is registered with `own`, with a
	lifetime when it's meant to clean itself up; `cancel` destroys all of it at once, so leaving a
	fight, a respawn or a new battle never leaves anything behind. Cues of a cancelled or replaced
	sequence never run.
]]

local Sequencer = {}
Sequencer.__index = Sequencer

export type Cue = {
	at: number, -- seconds into the sequence
	run: () -> (),
}

type Owned = {
	instance: Instance,
	until_: number?, -- sequencer time at which it's destroyed on its own
}

type Fields = {
	onBusyChanged: ((busy: boolean) -> ())?,
	time: number,
	busy: boolean,
	serial: number, -- bumped per play/cancel, so stale cues are dropped
	cues: { Cue },
	cueIndex: number,
	endsAt: number,
	owned: { Owned },
	connections: { RBXScriptConnection },
}

export type Sequencer = typeof(setmetatable({} :: Fields, Sequencer))

function Sequencer.new(onBusyChanged: ((busy: boolean) -> ())?): Sequencer
	local fields: Fields = {
		onBusyChanged = onBusyChanged,
		time = 0,
		busy = false,
		serial = 0,
		cues = {},
		cueIndex = 1,
		endsAt = 0,
		owned = {},
		connections = {},
	}
	return setmetatable(fields, Sequencer)
end

function Sequencer._setBusy(self: Sequencer, busy: boolean)
	if self.busy == busy then
		return
	end
	self.busy = busy
	local callback = self.onBusyChanged
	if callback then
		callback(busy)
	end
end

-- Starts a sequence, replacing whatever was playing (its remaining cues are dropped; what it
-- created lives on until its lifetime). Cues may be given in any order. `duration` is how long
-- the sequencer counts as busy; a cue past it still runs when its time comes.
function Sequencer.play(self: Sequencer, duration: number, cues: { Cue })
	self.serial += 1
	local sorted = table.clone(cues)
	table.sort(sorted, function(a, b)
		return a.at < b.at
	end)
	self.cues = sorted
	self.cueIndex = 1
	self.time = 0
	self.endsAt = math.max(0, duration)
	self:_setBusy(self.endsAt > 0 or #sorted > 0)
	self:_runDue()
end

-- Adds a cue to the sequence that's playing, relative to its start.
function Sequencer.addCue(self: Sequencer, at: number, run: () -> ())
	table.insert(self.cues, { at = at, run = run })
	table.sort(self.cues, function(a, b)
		return a.at < b.at
	end)
	self.cueIndex = 1
	for index, cue in self.cues do
		if cue.at > self.time or (cue.at == self.time and cue.run == run) then
			self.cueIndex = index
			break
		end
		self.cueIndex = index + 1
	end
	self:_setBusy(true)
	self:_runDue()
end

-- Stops everything: no more cues, nothing owned left on the stage.
function Sequencer.cancel(self: Sequencer)
	self.serial += 1
	table.clear(self.cues)
	self.cueIndex = 1
	self.endsAt = 0
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	for _, owned in self.owned do
		owned.instance:Destroy()
	end
	table.clear(self.owned)
	self:_setBusy(false)
end

-- Registers something a beat created. With `lifetime`, it's destroyed that many seconds from now
-- on its own; either way `cancel` destroys it.
function Sequencer.own(self: Sequencer, instance: Instance, lifetime: number?)
	table.insert(self.owned, { instance = instance, until_ = if lifetime then self.time + lifetime else nil })
end

function Sequencer.ownConnection(self: Sequencer, connection: RBXScriptConnection)
	table.insert(self.connections, connection)
end

function Sequencer.isBusy(self: Sequencer): boolean
	return self.busy
end

-- How many things it holds right now (for the tests: zero after a fight).
function Sequencer.ownedCount(self: Sequencer): number
	return #self.owned + #self.connections
end

function Sequencer.update(self: Sequencer, dt: number)
	self.time += math.max(0, dt)
	self:_runDue()
	for index = #self.owned, 1, -1 do
		local owned = self.owned[index]
		if owned.until_ ~= nil and self.time >= owned.until_ then
			table.remove(self.owned, index)
			owned.instance:Destroy()
		end
	end
	if self.busy and self.time >= self.endsAt and self.cueIndex > #self.cues then
		self:_setBusy(false)
	end
end

function Sequencer._runDue(self: Sequencer)
	local serial = self.serial
	while self.cueIndex <= #self.cues and self.cues[self.cueIndex].at <= self.time do
		local cue = self.cues[self.cueIndex]
		self.cueIndex += 1
		cue.run()
		if self.serial ~= serial then
			return -- the cue started or cancelled a new sequence
		end
	end
end

return Sequencer
