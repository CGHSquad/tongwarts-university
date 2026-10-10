--!strict
--[[
	Sequencer — the client-side timeline every battle beat plugs into. A sequence is a duration and
	a list of cues (a time and a function); the sequencer runs the cues as its clock passes them,
	on Heartbeat, and reports whether it's busy (a sequence is still playing, or a cue is still
	due), which the HUD uses to hold the command ring until the stage is done and the tests use to
	check that no turn opens mid-animation.

	Everything a beat creates on the fly (popups, effects, sounds) is registered with `own`, with a
	lifetime when it's meant to clean itself up; `cancel` destroys all of it at once, so leaving a
	fight, a respawn or a new battle never leaves anything behind. Cues of a cancelled or replaced
	sequence never run. Lifetimes run on the sequencer's own clock, which never resets, so a thing
	owned near the end of one beat still lives exactly its lifetime into the next.

	Time can be held (C2): `hold(seconds, scale)` runs the sequencer's clock at `scale` for that many
	real seconds, 0 for a hit-stop, a fraction for a slow-mo, one hold after another. Cues, lifetimes
	and everything timed on the clock stretch with it; `onScaleChanged` tells the stage, so its
	animation tracks follow.
]]

local Sequencer = {}
Sequencer.__index = Sequencer

export type Cue = {
	at: number, -- seconds into the sequence
	run: () -> (),
}

type Scheduled = {
	at: number,
	run: () -> (),
	ran: boolean,
	order: number, -- cues at the same time run in the order they were given
}

type Owned = {
	instance: Instance,
	until_: number?, -- clock time at which it's destroyed on its own
}

type Hold = { seconds: number, scale: number }

type Fields = {
	onBusyChanged: ((busy: boolean) -> ())?,
	onScaleChanged: ((scale: number) -> ())?,
	holds: { Hold }, -- real seconds left at each scale, the first running now
	scale: number, -- the clock's rate right now
	clock: number, -- never resets
	time: number, -- since the current sequence started
	busy: boolean,
	serial: number, -- bumped per play/cancel, so stale cues are dropped
	cues: { Scheduled },
	added: number, -- cues scheduled so far (their order)
	endsAt: number,
	owned: { Owned },
	connections: { RBXScriptConnection },
}

export type Sequencer = typeof(setmetatable({} :: Fields, Sequencer))

function Sequencer.new(onBusyChanged: ((busy: boolean) -> ())?): Sequencer
	local fields: Fields = {
		onBusyChanged = onBusyChanged,
		onScaleChanged = nil,
		holds = {},
		scale = 1,
		clock = 0,
		time = 0,
		busy = false,
		serial = 0,
		cues = {},
		added = 0,
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

local function byTime(a: Scheduled, b: Scheduled): boolean
	if a.at ~= b.at then
		return a.at < b.at
	end
	return a.order < b.order
end

-- Starts a sequence, replacing whatever was playing (its remaining cues are dropped; what it
-- created lives on until its lifetime). Cues may be given in any order. `duration` is how long the
-- sequencer counts as busy; a cue past it keeps it busy until the cue has run.
function Sequencer.play(self: Sequencer, duration: number, cues: { Cue })
	self.serial += 1
	local scheduled: { Scheduled } = {}
	for _, cue in cues do
		self.added += 1
		table.insert(scheduled, { at = cue.at, run = cue.run, ran = false, order = self.added })
	end
	table.sort(scheduled, byTime)
	self.cues = scheduled
	self.time = 0
	self.endsAt = math.max(0, duration)
	self:_settle()
end

-- Adds a cue to the sequence that's playing, relative to its start (a beat that follows on from
-- the current one, like the result camera after the final blow).
function Sequencer.addCue(self: Sequencer, at: number, run: () -> ())
	self.added += 1
	table.insert(self.cues, { at = at, run = run, ran = false, order = self.added })
	table.sort(self.cues, byTime)
	self:_settle()
end

-- Runs the clock at `scale` for `seconds` of real time, after any holds already queued.
function Sequencer.hold(self: Sequencer, seconds: number, scale: number)
	if seconds <= 0 then
		return
	end
	table.insert(self.holds, { seconds = seconds, scale = math.max(0, scale) })
	self:_setScale(self.holds[1].scale)
end

-- The clock's rate right now (1 unless a hold is running).
function Sequencer.timeScale(self: Sequencer): number
	return self.scale
end

-- Real seconds of holds still to run, and how much of the clock they'll cost (for budgets).
function Sequencer.heldSeconds(self: Sequencer): number
	local total = 0
	for _, h in self.holds do
		total += h.seconds
	end
	return total
end

function Sequencer.setOnScaleChanged(self: Sequencer, callback: ((scale: number) -> ())?)
	self.onScaleChanged = callback
end

function Sequencer._setScale(self: Sequencer, scale: number)
	if self.scale == scale then
		return
	end
	self.scale = scale
	local callback = self.onScaleChanged
	if callback then
		callback(scale)
	end
end

-- Stops everything: no more cues, nothing owned left on the stage.
function Sequencer.cancel(self: Sequencer)
	self.serial += 1
	table.clear(self.cues)
	table.clear(self.holds)
	self:_setScale(1)
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
	table.insert(self.owned, { instance = instance, until_ = if lifetime then self.clock + lifetime else nil })
end

function Sequencer.ownConnection(self: Sequencer, connection: RBXScriptConnection)
	table.insert(self.connections, connection)
end

-- Lets go of a connection that has done its job (it's disconnected already).
function Sequencer.releaseConnection(self: Sequencer, connection: RBXScriptConnection)
	local index = table.find(self.connections, connection)
	if index then
		table.remove(self.connections, index)
	end
end

function Sequencer.isBusy(self: Sequencer): boolean
	return self.busy
end

-- Seconds since the current sequence started (where a cue added now would be placed).
function Sequencer.elapsed(self: Sequencer): number
	return self.time
end

-- How many things it holds right now (for the tests: zero after a fight).
function Sequencer.ownedCount(self: Sequencer): number
	return #self.owned + #self.connections
end

function Sequencer.update(self: Sequencer, dt: number)
	-- Advance the clock through any holds: each takes its share of this frame's real time at its
	-- scale, the rest runs at normal speed.
	local real = math.max(0, dt)
	local step = 0
	while real > 0 and #self.holds > 0 do
		local h = self.holds[1]
		local used = math.min(real, h.seconds)
		step += used * h.scale
		h.seconds -= used
		real -= used
		if h.seconds <= 1e-6 then
			table.remove(self.holds, 1)
		end
	end
	step += real
	self:_setScale(if #self.holds > 0 then self.holds[1].scale else 1)
	self.clock += step
	self.time += step
	for index = #self.owned, 1, -1 do
		local owned = self.owned[index]
		if owned.until_ ~= nil and self.clock >= owned.until_ then
			table.remove(self.owned, index)
			owned.instance:Destroy()
		end
	end
	self:_settle()
end

-- Runs every cue that's due, then works out whether anything is still to come.
function Sequencer._settle(self: Sequencer)
	local serial = self.serial
	local pending = false
	-- Each cue that runs restarts the scan: a cue may add cues (and the list is re-sorted), so
	-- the loop never walks a table that changed under it.
	local scanning = true
	while scanning do
		scanning = false
		pending = false
		for _, cue in self.cues do
			if cue.ran then
				continue
			end
			if cue.at <= self.time then
				cue.ran = true
				cue.run()
				if self.serial ~= serial then
					return -- the cue started or cancelled a new sequence, which settled itself
				end
				scanning = true
				break
			else
				pending = true
			end
		end
	end
	self:_setBusy(pending or self.time < self.endsAt)
end

return Sequencer
