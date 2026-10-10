--!strict
--[[
	CombatHUD — S1, the combat screen (docs/ui/UI_HANDOFF.md section 7, reconciled by section 16
	and docs/ui/M0_REPORT.md). The turn-order bar and status line at the top, the command ring on
	the left, party cards on the right, the hero Mana plate at the bottom, plates over the enemies,
	the initiative reveal, a feed of the last few actions, the S6 results screen once the fight is
	over, and the overworld notice while exploring.

	It renders server snapshots and nothing else (handoff rule 2). The only thing it remembers is
	the choice being made right now: which command, which ability, which target. Confirming sends
	that choice to the server (onAction), which decides what happens; the client never computes an
	outcome. Legality (can afford, can target) is a filter from Abilities data and snapshot numbers
	that mirrors the server's rule (R22); the server re-checks every request.

	Sub-states on the local player's turn:
		Ring    the command ribbons: Attack, Spell, Guard (Item and Pass behind their flags)
		List    the S7 skill list, from Spell
		Target  picking an enemy (or an ally, for a heal): tap a plate or a card, then Confirm, or
		        tap the chosen one again
		Sent    the request is away; locked until the server moves on or refuses it (a notice)
	Off the player's turn everything but the status line is hidden (Idle).
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local BattleTypes = require(Combat:WaitForChild("BattleTypes"))
local UI = ReplicatedStorage:WaitForChild("UI")
local Bindings = require(UI:WaitForChild("Bindings"))
local MockData = require(UI:WaitForChild("MockData")) -- the S6 rewards are mock until the server has them (Q3)
local Strings = require(UI:WaitForChild("Strings"))
local Theme = require(UI:WaitForChild("Theme"))
local UITypes = require(UI:WaitForChild("UITypes"))

local Root = script.Parent.Parent
local Core = Root:WaitForChild("Core")
local Gui = require(Core:WaitForChild("Gui"))
local Layout = require(Core:WaitForChild("Layout"))
local ScreenManager = require(Core:WaitForChild("ScreenManager"))
local Components = Root:WaitForChild("Components")
local TapButton = require(Components:WaitForChild("TapButton"))
local Toast = require(Components:WaitForChild("Toast"))
local SkillList = require(script.Parent:WaitForChild("SkillList"))
local Results = require(script.Parent:WaitForChild("Results"))
local CommandRing = require(script:WaitForChild("CommandRing"))
local EnemyOverlay = require(script:WaitForChild("EnemyOverlay"))
local OverworldNotice = require(script:WaitForChild("OverworldNotice"))
local Stamps = require(script:WaitForChild("Stamps"))
local Widgets = require(script:WaitForChild("Widgets"))

type Snapshot = BattleTypes.Snapshot
type HudBattle = UITypes.HudBattle
type HudParticipant = UITypes.HudParticipant
type CommandId = UITypes.CommandId

export type Callbacks = {
	onAction: (abilityId: string, targetId: string) -> (), -- a summon's ability, or Attack or Guard
	onTargetChanged: (targetId: string?, friendly: boolean) -> (), -- friendly = picking an ally
}

export type Options = {
	namePrefix: string?, -- the harness runs a second HUD beside the live one
}

export type Mode = "Idle" | "Ring" | "List" | "Target" | "Sent"
export type StampKind = Stamps.Kind

type TargetPanel = {
	frame: Frame,
	caption: TextLabel,
	confirm: TapButton.TapButton,
	back: TapButton.TapButton,
}

type Fields = {
	localUserId: number,
	callbacks: Callbacks,
	playerGui: PlayerGui,
	manager: ScreenManager.ScreenManager,
	hudName: string,
	listName: string,
	resultsName: string,
	gui: ScreenGui,
	safeArea: Frame,

	dim: Frame,
	overworld: OverworldNotice.OverworldNotice,
	turnBar: Widgets.TurnOrderBar,
	status: Widgets.StatusLine,
	ring: CommandRing.CommandRing,
	targetPanel: TargetPanel,
	party: Widgets.PartyCards,
	manaPlate: Widgets.ManaPlate,
	reveal: Widgets.Reveal,
	log: Widgets.LogFeed,
	stamps: Stamps.Stamps,
	toast: Toast.Toast,
	enemies: EnemyOverlay.EnemyOverlay,
	skillList: SkillList.SkillList,
	results: Results.Results,

	snapshot: Snapshot?,
	hud: HudBattle?,
	mode: Mode,
	commands: { UITypes.CommandView },
	pendingAbilityId: string?,
	targetId: string?,
	submittedTurn: number?,
	turnSeen: number?,
	resultsFor: string?, -- which fight and outcome the results screen is showing
	hint: string?, -- a ribbon's description while it's hovered or held
	overworldBanner: number,
	detailBase: string,
	deadline: number?,
	stageBusy: boolean, -- the stage is still playing a beat (BattleView), so the ring waits
	turnOpenedAt: number?, -- server clock, when the turn being shown opened
	ringHeld: boolean, -- the ring is due but waiting for the stage
	rewardSeenAt: number?, -- server clock, when the fight was decided
	resultsHeld: boolean, -- the results screen is due but waiting for the final blow to play
	connections: { RBXScriptConnection },
}

local CombatHUD = {}
CombatHUD.__index = CombatHUD

export type CombatHUD = typeof(setmetatable({} :: Fields, CombatHUD))

CombatHUD.NAME = "CombatHUD"

-- Keyboard: the numbers Input.keyFor promises for each command (handoff section 10).
local KEY_COMMANDS: { [string]: CommandId } = {
	One = "Attack",
	Two = "Spell",
	Three = "Item",
	Four = "Guard",
	Five = "Pass",
}

local function secondsLeft(at: number, now: number): number
	return math.max(0, math.ceil(at - now))
end

-- The ring waits for the stage to finish its beat, but never longer than this past the turn's
-- start: a slow client must never hold up the fight (the server's turn timer runs regardless).
CombatHUD.RING_WAIT_CAP = 0.6
-- The results screen waits for the final blow (and the fall) to play, but never longer than this
-- (the longest beat, an enemy's critical knockout, runs about 3.5 s).
CombatHUD.RESULTS_WAIT_CAP = 4.5

function CombatHUD.new(playerGui: PlayerGui, localUserId: number, callbacks: Callbacks, options: Options?): CombatHUD
	local prefix = if options and options.namePrefix then options.namePrefix :: string else ""
	local hudName, listName, resultsName = prefix .. CombatHUD.NAME, prefix .. SkillList.NAME, prefix .. Results.NAME
	local manager = ScreenManager.new(playerGui)
	local self: CombatHUD

	local gui: ScreenGui
	local safeArea: Frame
	local dim: Frame
	local overworld: OverworldNotice.OverworldNotice
	local turnBar: Widgets.TurnOrderBar
	local status: Widgets.StatusLine
	local ring: CommandRing.CommandRing
	local targetPanel: TargetPanel
	local party: Widgets.PartyCards
	local manaPlate: Widgets.ManaPlate
	local reveal: Widgets.Reveal
	local log: Widgets.LogFeed
	local stamps: Stamps.Stamps
	local toast: Toast.Toast
	local skillList: SkillList.SkillList
	local results: Results.Results

	manager:register(hudName, ScreenManager.DISPLAY_ORDER.Combat, function(_, screenGui, area)
		gui, safeArea = screenGui, area
		-- First child, so it only dims the scene, never the HUD (Sibling ZIndex order).
		dim = Gui.frame(area, "Dim")
		dim.BackgroundTransparency = 0.45
		dim.BackgroundColor3 = Theme.Colors.Obsidian
		dim.Size = UDim2.fromScale(1, 1)
		dim.Visible = false
		overworld = OverworldNotice.new(area)
		turnBar = Widgets.turnOrderBar(area)
		status = Widgets.statusLine(area)
		ring = CommandRing.new(area, function(id)
			self:_onCommand(id)
		end, function(id)
			self:_setHint(id)
		end)
		local panel = Gui.frame(area, "TargetPanel")
		panel.Visible = false
		local caption = Gui.label(panel, "Caption", { size = Theme.Sizes.TextBody, font = Theme.Fonts.Bold, color = Theme.Colors.Gold, wrap = true, stroke = 1 })
		caption.Size = UDim2.new(1, 0, 0, 40)
		local confirm = TapButton.new(panel, {
			name = "Confirm",
			text = Strings.Confirm,
			keyHint = "Confirm",
			color = Theme.Colors.Gold,
			textColor = Theme.Colors.Obsidian,
			sound = "Confirm",
			position = UDim2.fromOffset(0, 44),
			onTap = function()
				self:_confirm()
			end,
		})
		local back = TapButton.new(panel, {
			name = "Back",
			text = Strings.Back,
			keyHint = "Back",
			color = Theme.Colors.Obsidian,
			assetKey = "Button_BackNormal",
			pressedKey = "Button_BackPressed",
			sound = "Back",
			position = UDim2.fromOffset(0, 108),
			onTap = function()
				self:_back()
			end,
		})
		targetPanel = { frame = panel, caption = caption, confirm = confirm, back = back }
		party = Widgets.partyCards(area)
		party.onPick(function(id)
			self:_pick(id)
		end)
		manaPlate = Widgets.manaPlate(area)
		reveal = Widgets.reveal(area)
		log = Widgets.logFeed(area)
		stamps = Stamps.new(area)
		toast = Toast.new(area)
		return {
			onResize = function(virtual: Vector2)
				if self then
					self:_layout(virtual)
				end
			end,
		}
	end)
	manager:register(listName, ScreenManager.DISPLAY_ORDER.SkillList, function(_, listGui, area)
		skillList = SkillList.build(listGui, area, {
			onConfirm = function(abilityId)
				self:_onAbilityChosen(abilityId)
			end,
			onBack = function()
				self:_back()
			end,
		})
		return skillList.screen
	end)
	manager:register(resultsName, ScreenManager.DISPLAY_ORDER.Results, function(_, resultsGui, area)
		results = Results.build(resultsGui, area, {})
		return results.screen
	end)

	local fields: Fields = {
		localUserId = localUserId,
		callbacks = callbacks,
		playerGui = playerGui,
		manager = manager,
		hudName = hudName,
		listName = listName,
		resultsName = resultsName,
		gui = gui,
		safeArea = safeArea,
		dim = dim,
		overworld = overworld,
		turnBar = turnBar,
		status = status,
		ring = ring,
		targetPanel = targetPanel,
		party = party,
		manaPlate = manaPlate,
		reveal = reveal,
		log = log,
		stamps = stamps,
		toast = toast,
		enemies = EnemyOverlay.new(playerGui, prefix .. "CombatHUDEnemies"),
		skillList = skillList,
		results = results,
		snapshot = nil,
		hud = nil,
		mode = "Idle",
		commands = {},
		pendingAbilityId = nil,
		targetId = nil,
		submittedTurn = nil,
		turnSeen = nil,
		resultsFor = nil,
		hint = nil,
		overworldBanner = 0,
		detailBase = "",
		deadline = nil,
		stageBusy = false,
		turnOpenedAt = nil,
		ringHeld = false,
		rewardSeenAt = nil,
		resultsHeld = false,
		connections = {},
	}
	self = setmetatable(fields, CombatHUD)
	self.enemies.onPick(function(id)
		self:_pick(id)
	end)

	manager:open(hudName) -- always up: it holds the overworld notice too
	self:_leaveBattle()
	self:_layout(ScreenManager.virtualSize(safeArea))

	pcall(function()
		table.insert(self.connections, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed then
				self:_onKey(input.KeyCode.Name)
			end
		end))
	end)
	return self
end

-- Draws a fresh snapshot from the server. The battle screen is only for the players in the fight;
-- everyone else keeps exploring.
function CombatHUD.render(self: CombatHUD, snapshot: Snapshot)
	self.snapshot = snapshot
	local battle = snapshot.battle
	local inBattle = battle ~= nil and Bindings.isInBattle(battle, self.localUserId)
	-- Out of a fight, the notice shows for a moment on arriving (showOverworldBanner), and whenever
	-- a fight you're not in is on, so you're told about it.
	self.overworld.frame.Visible = not inBattle and (self.overworldBanner > 0 or battle ~= nil)
	if battle and inBattle then
		local hud = Bindings.battle(battle, self.localUserId)
		self.hud = hud
		self:_renderBattle(hud)
	else
		self:_leaveBattle()
		self.overworld.update(snapshot.overworld, battle ~= nil, self.localUserId)
		self.callbacks.onTargetChanged(nil, false)
	end
	self:tick(Workspace:GetServerTimeNow())
end

-- The stage started or finished playing a beat (BattleView): the ring waits for it.
function CombatHUD.setStageBusy(self: CombatHUD, busy: boolean)
	if self.stageBusy == busy then
		return
	end
	self.stageBusy = busy
	-- (A held ring is released on the next tick, not here: this can be called from inside a
	-- render, through BattleView.)
end

-- Whether the ring has to wait for the stage right now.
function CombatHUD._ringWaits(self: CombatHUD, now: number): boolean
	local openedAt = self.turnOpenedAt
	return self.stageBusy and openedAt ~= nil and now - openedAt < CombatHUD.RING_WAIT_CAP
end

-- Whether the results screen has to wait for the stage right now.
function CombatHUD._resultsWait(self: CombatHUD, now: number): boolean
	local seenAt = self.rewardSeenAt
	return self.stageBusy and seenAt ~= nil and now - seenAt < CombatHUD.RESULTS_WAIT_CAP
end

-- Updates countdowns; called every frame.
function CombatHUD.tick(self: CombatHUD, now: number)
	local hud = self.hud
	if hud == nil then
		return
	end
	self.enemies.tick()
	if (self.ringHeld and not self:_ringWaits(now)) or (self.resultsHeld and not self:_resultsWait(now)) then
		self:_rerender()
		return
	end
	if hud.phase == "Reward" then
		if self.manager:isOpen(self.resultsName) then
			self.results.tick(now)
		end
	elseif self.hint and self.mode == "Ring" then
		self.status.detail.Text = self.hint :: string
	elseif self.deadline then
		self.status.detail.Text = Strings.format.pair(self.detailBase, Strings.format.secondsLeft(secondsLeft(self.deadline :: number, now)))
	end
end

-- Shows the overworld notice for `seconds`, then hides it. BattleClient calls this when the player
-- walks out onto the grass.
function CombatHUD.showOverworldBanner(self: CombatHUD, seconds: number)
	self.overworldBanner += 1
	local banner = self.overworldBanner
	self:_rerender()
	task.delay(seconds, function()
		if self.overworldBanner == banner then -- not shown again since
			self.overworldBanner = 0
			self:_rerender()
		end
	end)
end

-- Shows why the server refused a request, and lets the player try again.
function CombatHUD.showNotice(self: CombatHUD, message: string)
	self.submittedTurn = nil
	self.toast.show(message)
	self:_rerender()
end

-- A ribbon is hovered or held (nil: no longer): its description takes the status detail's place.
function CombatHUD._setHint(self: CombatHUD, id: CommandId?)
	self.hint = if id then Bindings.commandHint(id) else nil
	if self.hud and self.mode == "Ring" then
		self.status.detail.Text = self.detailBase
		self:tick(Workspace:GetServerTimeNow())
	end
end

-- For the harness only: the stamps have no server source (Flags.DownSystem, R7).
function CombatHUD.showStamp(self: CombatHUD, kind: StampKind)
	self.stamps.show(kind, true)
end

function CombatHUD.destroy(self: CombatHUD)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.manager:closeAll()
	self.enemies.destroy()
	for _, name in { self.hudName, self.listName, self.resultsName } do
		local entry = self.manager:entry(name)
		if entry then
			entry.gui:Destroy()
		end
	end
end

function CombatHUD._rerender(self: CombatHUD)
	local snapshot = self.snapshot
	if snapshot then
		self:render(snapshot)
	end
end

-- The participant this client must act for right now, if any.
function CombatHUD._actor(self: CombatHUD): HudParticipant?
	local hud = self.hud
	return if hud and hud.localActorId then hud.byId[hud.localActorId :: string] else nil
end

--[[ Layout: Layout.regions, in design pixels inside the SafeArea ]]

function CombatHUD._layout(self: CombatHUD, virtual: Vector2)
	local regions = Layout.regions(virtual)
	local top, left, right, bottom, center = regions.topCenter, regions.left, regions.right, regions.bottomCenter, regions.center
	local gap = Theme.Sizes.Gap

	local barHeight = Widgets.TOKEN + 10
	self.turnBar.frame.Position = UDim2.fromOffset(top.x, top.y)
	self.turnBar.frame.Size = UDim2.fromOffset(top.w, barHeight)
	-- The status line sits under the bar and stops short of the party column.
	local statusWidth = math.max(120, right.x - gap - top.x)
	self.status.frame.Position = UDim2.fromOffset(top.x, top.y + barHeight + 4)
	self.status.frame.Size = UDim2.fromOffset(statusWidth, 74)

	self.ring.frame.Position = UDim2.fromOffset(left.x, left.y)
	self.ring.layout(left.w, left.h)
	local panel = self.targetPanel
	panel.frame.Position = UDim2.fromOffset(left.x, left.y)
	panel.frame.Size = UDim2.fromOffset(left.w, left.h)
	panel.confirm.button.Size = UDim2.fromOffset(left.w, Theme.Sizes.TapComfortable)
	panel.back.button.Size = UDim2.fromOffset(left.w, Theme.Sizes.TapMin)

	-- The party column: the cards, with the recent-actions feed under them (out of the middle,
	-- where the battle camera frames the acting character and the enemies).
	local feedHeight = 48
	local cardsHeight = math.max(0, right.h - feedHeight - gap)
	self.party.frame.Position = UDim2.fromOffset(right.x, right.y)
	self.party.frame.Size = UDim2.fromOffset(right.w, cardsHeight)
	self.party.layout(right.w, cardsHeight)
	self.log.frame.Position = UDim2.fromOffset(right.x, right.y + right.h - feedHeight)
	self.log.frame.Size = UDim2.fromOffset(right.w, feedHeight)

	local plateWidth = math.min(bottom.w, 360)
	self.manaPlate.frame.Position = UDim2.fromOffset(bottom.x + math.floor((bottom.w - plateWidth) / 2), bottom.y + 4)
	self.manaPlate.frame.Size = UDim2.fromOffset(plateWidth, 48)

	self.reveal.frame.Position = UDim2.fromOffset(center.x, center.y)
	self.reveal.frame.Size = UDim2.fromOffset(center.w, center.h)
	self.stamps.frame.Position = UDim2.fromOffset(center.x, center.y)
	self.stamps.frame.Size = UDim2.fromOffset(center.w, center.h)

	self.overworld.frame.Position = UDim2.fromOffset(top.x, top.y)
	self.overworld.frame.Size = UDim2.fromOffset(math.min(top.w, 520), 130)

	-- The enemy plates (BillboardGuis, in viewport pixels) keep to the box between the status line
	-- and the bottom of the middle, the ring's column and the party's column.
	local measured = ScreenManager.measure(self.gui)
	local scale = Layout.scaleFor(measured)
	self.enemies.setScale(scale)
	-- (Layout.regions already includes the safe margins; the SafeArea frame sits at the GUI's
	-- origin, which is the inset below Roblox's top bar.)
	local inset = Vector2.zero
	pcall(function()
		inset = GuiService:GetGuiInset()
	end)
	local function toViewport(x: number, y: number): (number, number)
		return inset.X + x * scale, inset.Y + y * scale
	end
	local statusBottom = top.y + barHeight + 4 + 74
	local boxLeft, boxTop = toViewport(left.x + left.w + gap, statusBottom + gap)
	local boxRight, boxBottom = toViewport(right.x - gap, center.y + center.h - gap)
	self.enemies.setBounds({ left = boxLeft, top = boxTop, right = boxRight, bottom = boxBottom })
end

--[[ Battle ]]

function CombatHUD._leaveBattle(self: CombatHUD)
	self.hud = nil
	self.turnSeen = nil
	self.submittedTurn = nil
	self:_setMode("Idle")
	self.turnBar.frame.Visible = false
	self.status.frame.Visible = false
	self.reveal.frame.Visible = false
	self.log.frame.Visible = false
	self.hint = nil
	self.manager:close(self.resultsName)
	self.targetPanel.frame.Visible = false
	self.dim.Visible = false
	self.party.frame.Visible = false
	self.ring.hide()
	self.ringHeld = false
	self.turnOpenedAt = nil
	self.rewardSeenAt = nil
	self.resultsHeld = false
	self.manaPlate.update(nil, self.localUserId)
	self.enemies.hide()
	self.stamps.hide()
	self.deadline = nil
end

function CombatHUD._renderBattle(self: CombatHUD, hud: HudBattle)
	local myTurn = hud.localActorId ~= nil
	-- A new turn starts clean, and "Sending..." only lasts until the server moves on.
	if self.turnSeen ~= hud.turnNumber then
		self.turnSeen = hud.turnNumber
		self.turnOpenedAt = Workspace:GetServerTimeNow()
		self.submittedTurn = nil
		self:_setMode("Idle")
	end
	if not myTurn then
		self:_setMode("Idle")
	elseif self.submittedTurn ~= nil then
		self:_setMode("Sent")
	elseif self.mode == "Idle" or self.mode == "Sent" then
		self:_setMode("Ring")
	end

	local actor = self:_actor()
	local friendly = false
	local pickable: { [string]: boolean } = {}
	if self.mode == "Target" and actor then
		-- Keep the pick legal (R22): the ability still affordable, the target still standing.
		local abilityId = self.pendingAbilityId
		local row = if abilityId then Bindings.abilityRow(abilityId :: string, actor.mana.current) else nil
		if row == nil or not row.canAfford then
			self:_setMode("Ring")
		else
			local legal, best = Bindings.targetsFor(abilityId :: string, actor, hud)
			local stillLegal = false
			for _, p in legal do
				pickable[p.id] = true
				if p.id == self.targetId then
					stillLegal = true
				end
			end
			if not stillLegal then
				self.targetId = if best then best.id else nil
			end
			if self.targetId == nil then
				self:_setMode("Ring")
				table.clear(pickable)
			else
				friendly = row.needsTarget == "Ally"
			end
		end
	elseif self.mode == "List" and actor then
		self.skillList.refresh(Bindings.abilityRows(actor, actor.abilityIds))
	end
	if actor then
		self.commands = Bindings.commands(actor.abilityIds)
	end

	-- Top: the turn bar, the reveal while initiative is shown, the status line otherwise.
	local phase = hud.phase
	local active = if hud.activeId then hud.byId[hud.activeId :: string] else nil
	self.turnBar.frame.Visible = phase ~= "Setup" and phase ~= "Reward"
	self.turnBar.update(hud)
	self.reveal.frame.Visible = phase == "Setup"
	if phase == "Setup" then
		self.reveal.update(hud)
	end
	self.log.frame.Visible = (phase == "Input" or phase == "Resolve") and #hud.recentLog > 0 and self.mode ~= "List" -- the list covers its spot
	self.log.update(hud.recentLog)
	-- The results screen (S6) takes over once the fight is decided and the stage has played the
	-- final blow (it waits while the stage is busy, at most RESULTS_WAIT_CAP); the countdown
	-- follows the snapshot.
	self.resultsHeld = false
	if phase == "Reward" then
		if self.rewardSeenAt == nil then
			self.rewardSeenAt = Workspace:GetServerTimeNow()
		end
		local won = hud.winner == "Party"
		local key = `{hud.rosterKey}:{won}`
		if self.manager:isOpen(self.resultsName) and self.resultsFor == key then
			self.results.setReturnAt(hud.overworldReturnAt)
		elseif self:_resultsWait(Workspace:GetServerTimeNow()) then
			self.resultsHeld = true
		else
			self.resultsFor = key
			local players, members = Bindings.partyShape(hud)
			local size: MockData.PartySize = if members <= 1 then "One" elseif members == 2 then (if players == 1 then "TwoSolo" else "Two") else "Four"
			local props: Results.Props = { won = won, reward = Bindings.reward(hud, won, MockData.reward(size)), returnAt = hud.overworldReturnAt }
			self.manager:open(self.resultsName, props)
		end
	else
		self.manager:close(self.resultsName)
	end

	local title, detail = "", ""
	self.deadline = nil
	if (phase == "Input" or phase == "Resolve") and active then
		local round = Strings.format.round(hud.round)
		if phase == "Resolve" then
			title, detail = round, hud.lastLogLine or ""
		elseif myTurn and actor then
			title = Strings.format.pair(round, Strings.YourTurn)
			if self.mode == "Sent" then
				detail = Strings.Sending
			elseif self.mode == "Target" then
				detail = if friendly then Strings.PickAlly else Strings.PickEnemy
			else
				detail = Strings.format.chooseFor(actor.name)
			end
			self.deadline = if self.mode == "Sent" then nil else hud.turnDeadline
		elseif active.ownerUserId == nil then
			title, detail = Strings.format.pair(round, Strings.EnemyTurn), Strings.format.enemyChoosing(active.name)
		else
			title = Strings.format.pair(round, Strings.format.alliesTurn(active.ownerName or ""))
			detail = Strings.format.waitingFor(active.name)
			self.deadline = hud.turnDeadline
		end
	end
	self.status.frame.Visible = title ~= "" and self.mode ~= "List" -- the list takes its place on a phone
	self.status.title.Text = title
	self.status.title.TextColor3 = if myTurn then Theme.Colors.Cyan else Theme.Colors.TextLight
	self.detailBase = detail
	self.status.detail.Text = detail

	-- Left: the ring (once the stage has finished its beat, or RING_WAIT_CAP after the turn
	-- opened, whichever comes first), or the target panel.
	self.ringHeld = false
	if self.mode == "Ring" then
		if self:_ringWaits(Workspace:GetServerTimeNow()) then
			self.ringHeld = true
			self.ring.hide()
		else
			self.ring.show(self.commands)
		end
	else
		self.ring.hide()
	end
	self.targetPanel.frame.Visible = self.mode == "Target"
	if self.mode == "Target" then
		self.targetPanel.caption.Text = if friendly then Strings.PickAlly else Strings.PickEnemy
		self.targetPanel.confirm.setEnabled(self.targetId ~= nil)
	end
	self.dim.Visible = self.mode == "List"

	-- Right, bottom and over the enemies. The skill list takes the party's column while it's open.
	local shownTarget = if self.mode == "Target" then self.targetId else nil
	self.party.frame.Visible = self.mode ~= "List" and phase ~= "Reward"
	self.party.update(hud, self.localUserId, if friendly then shownTarget else nil, pickable)
	self.manaPlate.update(if myTurn then actor else nil, self.localUserId)
	self.enemies.update(hud, if friendly then nil else shownTarget, pickable)
	self.callbacks.onTargetChanged(shownTarget, friendly)
end

function CombatHUD._setMode(self: CombatHUD, mode: Mode)
	if self.mode == mode then
		return
	end
	local previous = self.mode
	self.mode = mode
	if previous == "List" then
		self.manager:close(self.listName)
	end
	if mode ~= "Target" then
		self.pendingAbilityId = nil
		self.targetId = nil
	end
	if mode == "List" then
		local actor = self:_actor()
		if actor then
			local props: SkillList.Props = { title = Strings.Spell, rows = Bindings.abilityRows(actor, actor.abilityIds) }
			self.manager:open(self.listName, props)
		else
			self.mode = "Ring"
		end
	end
end

--[[ The player's choices ]]

function CombatHUD._onCommand(self: CombatHUD, id: CommandId)
	if self.mode ~= "Ring" then
		return
	end
	local actor = self:_actor()
	if actor == nil then
		return
	end
	if id == "Attack" then
		self:_beginTarget("Attack")
	elseif id == "Spell" then
		self:_setMode("List")
		self:_rerender()
	elseif id == "Guard" then
		self:_submit("Guard", Bindings.selfTarget(actor))
	else
		self.toast.show(Strings.ComingSoon)
	end
end

-- An ability was chosen (Attack from the ring, or a row from the list): pick a target if it needs
-- one, otherwise send it now.
function CombatHUD._beginTarget(self: CombatHUD, abilityId: string)
	local hud, actor = self.hud, self:_actor()
	if hud == nil or actor == nil then
		return
	end
	local row = Bindings.abilityRow(abilityId, actor.mana.current)
	if row == nil then
		return
	elseif not row.canAfford then
		self.toast.show(Strings.NotEnoughMana)
		return
	elseif row.needsTarget == "None" or row.needsTarget == "AllAllies" then
		self:_submit(abilityId, Bindings.selfTarget(actor))
		return
	end
	local _, best = Bindings.targetsFor(abilityId, actor, hud)
	if best == nil then
		return
	end
	self:_setMode("Target")
	self.pendingAbilityId = abilityId
	self.targetId = best.id
	self:_rerender()
end

function CombatHUD._onAbilityChosen(self: CombatHUD, abilityId: string)
	if self.mode ~= "List" then
		return
	end
	self:_beginTarget(abilityId)
end

-- A plate or card was tapped: pick it, or confirm it if it's already the pick.
function CombatHUD._pick(self: CombatHUD, id: string)
	if self.mode ~= "Target" then
		return
	end
	if self.targetId == id then
		self:_confirm()
	else
		self.targetId = id
		self:_rerender()
	end
end

function CombatHUD._confirm(self: CombatHUD)
	local abilityId, targetId = self.pendingAbilityId, self.targetId
	if self.mode == "Target" and abilityId and targetId then
		self:_submit(abilityId, targetId)
	end
end

function CombatHUD._back(self: CombatHUD)
	if self.mode == "Target" or self.mode == "List" then
		self:_setMode("Ring")
		self:_rerender()
	end
end

function CombatHUD._submit(self: CombatHUD, abilityId: string, targetId: string)
	local hud = self.hud
	if hud == nil or hud.localActorId == nil or self.submittedTurn ~= nil then
		return
	end
	-- Optimistic "Sending..." until the server answers; the server's result is what counts.
	self.submittedTurn = hud.turnNumber
	self:_setMode("Sent")
	self.callbacks.onAction(abilityId, targetId)
	self:_rerender()
end

local function isBack(keyName: string): boolean
	return keyName == "Backspace" or keyName == "Escape" or keyName == "ButtonB"
end

function CombatHUD._onKey(self: CombatHUD, keyName: string)
	-- The results screen is up (no actor in the reward phase): Back skips its count-up.
	if self.manager:current() == self.resultsName then
		if isBack(keyName) then
			self.manager:back()
		end
		return
	end
	if self.hud == nil or self:_actor() == nil then
		return
	end
	if self.mode == "Ring" then
		local command = KEY_COMMANDS[keyName]
		if command then
			for _, view in self.commands do
				if view.id == command and view.enabled then
					self:_onCommand(command)
				end
			end
		end
	elseif keyName == "Return" or keyName == "Space" then
		if self.mode == "Target" then
			self:_confirm()
		elseif self.mode == "List" then
			self.skillList.confirm()
		end
	end
	if isBack(keyName) then
		self:_back()
	end
end

return CombatHUD
