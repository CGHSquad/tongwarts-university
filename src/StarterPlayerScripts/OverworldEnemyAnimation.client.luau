--[[
	OverworldEnemyAnimation — makes the wild Tung Tungs (saplings on the grass, sparring partners in
	the university gym) idle and walk.

	The server (Overworld) moves each enemy's invisible body and welds the sapling model to it; this
	script plays the model's own clips on every client, so the animation is smooth for everyone and
	still runs for enemies that stream in later. It works out whether an enemy is walking from how its
	body moves.

	The sapling's walk clip walks forward on its own (root motion): left alone, the model drifts ahead
	of its body and snaps back each loop. That forward drift is taken back out of the hips every frame,
	so it walks in place and the body does the travelling.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Summons = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("Summons"))
local art = Summons.TungTungSapling.art

local HIPS = "mixamorig:Hips"
-- How far the walk clip moves the hips forward over one loop (Hips Z at the end of the clip, in the
-- scaled model's units). This is a starting guess; each enemy measures the real value from its own
-- clip as it walks and settles on that.
local WALK_DRIFT_GUESS = -3.2
local STOPPED_AFTER = 0.2 -- seconds without moving before it counts as standing still

type Animated = {
	body: BasePart,
	hips: Bone?,
	idle: AnimationTrack?,
	walk: AnimationTrack?,
	lastPos: Vector3,
	lastMoved: number,
	walking: boolean,
	drift: number, -- learned Hips Z at the end of one walk loop
}
local animated: { [BasePart]: Animated } = {}

local function load(animator: Animator, id: string?, priority: Enum.AnimationPriority): AnimationTrack?
	if not id then return nil end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
	if not ok then return nil end
	track.Looped = true
	track.Priority = priority
	return track
end

local function add(body: Instance)
	if not body:IsA("BasePart") or animated[body] then return end
	local visual = body:WaitForChild("Visual", 10)
	local controller = visual and visual:WaitForChild("AnimationController", 10)
	local animator = controller and controller:WaitForChild("Animator", 10)
	-- each enemy wears some summon's model (its "Look"): use that summon's clips
	local look = body:GetAttribute("Look")
	local def = look and Summons[look]
	local art = (def and def.art) or art
	if not (animator and animator:IsA("Animator") and art) then return end
	local entry: Animated = {
		body = body,
		hips = visual:FindFirstChild(HIPS, true) :: Bone?,
		idle = load(animator, art.animations.idle, Enum.AnimationPriority.Idle),
		walk = load(animator, art.animations.walk, Enum.AnimationPriority.Movement),
		lastPos = body.Position,
		lastMoved = 0,
		walking = false,
		drift = WALK_DRIFT_GUESS,
	}
	if entry.idle then entry.idle:Play() end
	animated[body] = entry
end

local function watchFolder(folder: Instance)
	for _, b in folder:GetChildren() do task.spawn(add, b) end
	folder.ChildAdded:Connect(function(b) task.spawn(add, b) end)
	folder.ChildRemoved:Connect(function(b)
		-- a beaten enemy leaves, then comes back as the same body and gets added again
		local entry = animated[b :: BasePart]
		if entry then
			if entry.walk then entry.walk:Stop(0) end
			if entry.idle then entry.idle:Stop(0) end
			entry.walking = false
			animated[b :: BasePart] = nil
		end
	end)
end
task.spawn(function()
	watchFolder(workspace:WaitForChild("OverworldEnemies"))
end)

-- Walking or standing, from how the body moved.
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for body, entry in animated do
		if body.Parent == nil then animated[body] = nil continue end
		local pos = body.Position
		if (pos - entry.lastPos).Magnitude > 0.01 then entry.lastMoved = now end
		entry.lastPos = pos
		local walking = now - entry.lastMoved < STOPPED_AFTER
		if walking ~= entry.walking and entry.walk then
			entry.walking = walking
			if walking then entry.walk:Play(0.2) else entry.walk:Stop(0.25) end
		end
	end
end)

-- Take the walk clip's forward drift back out of the hips (runs right after animations are applied).
RunService.PreSimulation:Connect(function()
	for _, entry in animated do
		local walk, hips = entry.walk, entry.hips
		if walk and hips and walk.IsPlaying and walk.WeightCurrent > 0 and walk.Length > 0 then
			local progress = walk.TimePosition / walk.Length
			local rawZ = hips.Transform.Position.Z
			if walk.WeightCurrent > 0.99 and progress > 0.6 then
				-- the clip's drift is close to a straight line through the loop: learn its slope
				entry.drift += (rawZ / progress - entry.drift) * 0.1
			end
			hips.Transform += Vector3.new(0, 0, -entry.drift * progress * walk.WeightCurrent)
		end
	end
end)
