--!strict
--[[
	Assets — every UI image, keyed by name, with its asset id and 9-slice settings (handoff
	section 9, M0 report section 5).

	Ids start empty. A component asks `Assets.image(key)`; nil means "no art yet", and the component
	draws its fallback look instead (handoff 5.2). When the artist's cut PNGs land in the Asset
	Manager (named UI_<Screen>_<Part>.png, see docs/ui/ASSET_PROMPTS.md), each id is written here
	and nothing in a screen or component changes. Never hardcode an rbxassetid anywhere else.

	Keys follow the sheets in ASSET_PROMPTS.md. `slice` is the SliceCenter for stretchable parts
	(horizontal 3-slice: a plain middle, decoration in the end caps); set it once the art exists.
]]

export type AssetEntry = {
	id: string?, -- "rbxassetid://..." once uploaded
	slice: Rect?, -- SliceCenter for ScaleType.Slice
	sliceScale: number?, -- 0.5 for parts cut at 2x
	file: string, -- the artist's file name, for looking the upload up
}

local function part(file: string, slice: Rect?): AssetEntry
	return { id = nil, slice = slice, sliceScale = nil, file = file }
end

-- Placeholder slice rects for 3-slice bars/panels; replaced by measured values when the art lands.
local BAR = Rect.new(24, 0, 40, 0)
local PANEL = Rect.new(32, 16, 64, 32)

local Images: { [string]: AssetEntry } = {
	-- Sheet 01: buttons and badges
	Button_BackNormal = part("UI_Button_BackNormal", PANEL),
	Button_BackPressed = part("UI_Button_BackPressed", PANEL),
	Button_PrimaryNormal = part("UI_Button_PrimaryNormal", PANEL),
	Button_PrimaryPressed = part("UI_Button_PrimaryPressed", PANEL),
	Button_PrimaryDisabled = part("UI_Button_PrimaryDisabled", PANEL),
	Badge_TapIcon = part("UI_Badge_TapIcon"),
	Badge_Plus = part("UI_Badge_Plus"),
	Badge_Lock = part("UI_Badge_Lock"),
	Badge_LevelUp = part("UI_Badge_LevelUp", PANEL),
	Divider_Star = part("UI_Divider_Star", BAR),
	Star_Large = part("UI_Star_Large"),
	Sparkle = part("UI_Sparkle"),

	-- Sheet 02: element and ability medallions
	Icon_MedallionEmpty = part("UI_Icon_MedallionEmpty"),
	Icon_MedallionSelected = part("UI_Icon_MedallionSelected"),
	Icon_Physical = part("UI_Icon_Physical"),
	Icon_Fire = part("UI_Icon_Fire"),
	Icon_Ice = part("UI_Icon_Ice"),
	Icon_Wind = part("UI_Icon_Wind"),
	Icon_Nature = part("UI_Icon_Nature"),
	Icon_Lightning = part("UI_Icon_Lightning"),
	Icon_Light = part("UI_Icon_Light"),
	Icon_Dark = part("UI_Icon_Dark"),
	Icon_Heal = part("UI_Icon_Heal"),
	Icon_Guard = part("UI_Icon_Guard"),
	Icon_Item = part("UI_Icon_Item"),
	Icon_Pass = part("UI_Icon_Pass"),

	-- Sheet 03: command ribbons and stamps
	Combat_CommandBlue = part("UI_Combat_CommandBlue", PANEL),
	Combat_CommandPurple = part("UI_Combat_CommandPurple", PANEL),
	Combat_CommandGreen = part("UI_Combat_CommandGreen", PANEL),
	Combat_CommandAmber = part("UI_Combat_CommandAmber", PANEL),
	Combat_CommandSilver = part("UI_Combat_CommandSilver", PANEL),
	Combat_AllOutRibbon = part("UI_Combat_AllOutRibbon", PANEL),
	Combat_OneMoreLettering = part("UI_Combat_OneMoreLettering"),
	Tag_Weak = part("UI_Tag_Weak", PANEL),
	Tag_Resist = part("UI_Tag_Resist", PANEL),
	Tag_Null = part("UI_Tag_Null", PANEL),
	Tag_Down = part("UI_Tag_Down", PANEL),
	Combat_Dizzy = part("UI_Combat_Dizzy"),
	Ribbon_Neutral = part("UI_Ribbon_Neutral", PANEL),

	-- Sheet 04A: turn order and enemy overlay
	Turn_BarFrame = part("UI_Turn_BarFrame", PANEL),
	Turn_TokenNormal = part("UI_Turn_TokenNormal"),
	Turn_TokenActive = part("UI_Turn_TokenActive"),
	Turn_TokenEnemy = part("UI_Turn_TokenEnemy"),
	Enemy_NamePlate = part("UI_Enemy_NamePlate", PANEL),
	Enemy_HpTrack = part("UI_Enemy_HpTrack", BAR),
	Enemy_HpFill = part("UI_Enemy_HpFill", BAR),
	Enemy_Brackets = part("UI_Enemy_Brackets"),
	Enemy_BracketsSelected = part("UI_Enemy_BracketsSelected"),
	Enemy_WeakMarker = part("UI_Enemy_WeakMarker"),

	-- Sheet 04B: party cards and bars
	Party_CardNormal = part("UI_Party_CardNormal", PANEL),
	Party_CardActive = part("UI_Party_CardActive", PANEL),
	Bar_HpTrack = part("UI_Bar_HpTrack", BAR),
	Bar_HpFill = part("UI_Bar_HpFill", BAR),
	Bar_ManaTrack = part("UI_Bar_ManaTrack", BAR),
	Bar_ManaFill = part("UI_Bar_ManaFill", BAR),
	Party_ManaPlate = part("UI_Party_ManaPlate", PANEL),
	Party_Callout = part("UI_Party_Callout", PANEL),

	-- Sheet 05: skill list
	SkillList_Header = part("UI_SkillList_Header", PANEL),
	SkillList_RowNormal = part("UI_SkillList_RowNormal", PANEL),
	SkillList_RowSelected = part("UI_SkillList_RowSelected", PANEL),
	SkillList_RowDimmed = part("UI_SkillList_RowDimmed", PANEL),
	SkillList_RowLocked = part("UI_SkillList_RowLocked", PANEL),
	SkillList_Description = part("UI_SkillList_Description", PANEL),
	SkillList_WeakTag = part("UI_SkillList_WeakTag", PANEL),
	Capsule_Cost = part("UI_Capsule_Cost", BAR),
	Capsule_CostDimmed = part("UI_Capsule_CostDimmed", BAR),
	Capsule_Quantity = part("UI_Capsule_Quantity", BAR),

	-- Sheet 09A: results
	Results_VictoryLettering = part("UI_Results_VictoryLettering"),
	Results_SubtitleRibbon = part("UI_Results_SubtitleRibbon", PANEL),
	Results_TallyNormal = part("UI_Results_TallyNormal", PANEL),
	Results_TallyGold = part("UI_Results_TallyGold", PANEL),
	Results_TallyGreen = part("UI_Results_TallyGreen", PANEL),
	Results_ItemSlot = part("UI_Results_ItemSlot"),
	Results_QuantityTag = part("UI_Results_QuantityTag", PANEL),
	Results_PartyRow = part("UI_Results_PartyRow", PANEL),

	-- Sheet 09B: item icons and particles
	Item_PotionRed = part("UI_Item_PotionRed"),
	Item_PotionBlue = part("UI_Item_PotionBlue"),
	Item_Herb = part("UI_Item_Herb"),
	Item_RuneShard = part("UI_Item_RuneShard"),
	Item_AmberGem = part("UI_Item_AmberGem"),
	Item_Scroll = part("UI_Item_Scroll"),
	Particle_SparkLarge = part("UI_Particle_SparkLarge"),
	Particle_SparkSmall = part("UI_Particle_SparkSmall"),
	Particle_Shard = part("UI_Particle_Shard"),
	Particle_Leaf = part("UI_Particle_Leaf"),

	-- Sheet 10: ink overlays
	Ink_StreaksWhite = part("UI_Ink_StreaksWhite"),
	Ink_StreaksGold = part("UI_Ink_StreaksGold"),
	Ink_StreaksCyan = part("UI_Ink_StreaksCyan"),
	Ink_PanelLarge = part("UI_Ink_PanelLarge"),
	Ink_PanelTall = part("UI_Ink_PanelTall"),
	Ink_Splatter = part("UI_Ink_Splatter"),
}

-- Sounds are named hooks only (handoff Core/Audio); ids filled in when audio exists.
local Sounds: { [string]: string } = {
	-- Tap, Back, Confirm, Tick, Stamp, Victory
}

-- Which images each screen preloads before it opens.
local Screens: { [string]: { string } } = {
	CombatHUD = {
		"Combat_CommandBlue", "Combat_CommandPurple", "Combat_CommandGreen", "Combat_CommandAmber", "Combat_CommandSilver",
		"Turn_BarFrame", "Turn_TokenNormal", "Turn_TokenActive", "Turn_TokenEnemy",
		"Enemy_NamePlate", "Enemy_HpTrack", "Enemy_HpFill", "Enemy_Brackets", "Enemy_BracketsSelected",
		"Party_CardNormal", "Party_CardActive", "Bar_HpTrack", "Bar_HpFill", "Bar_ManaTrack", "Bar_ManaFill", "Party_ManaPlate",
	},
	SkillList = {
		"SkillList_Header", "SkillList_RowNormal", "SkillList_RowSelected", "SkillList_RowDimmed", "SkillList_RowLocked",
		"SkillList_Description", "Capsule_Cost", "Capsule_CostDimmed", "Icon_MedallionEmpty", "Icon_MedallionSelected",
	},
	Results = {
		"Results_VictoryLettering", "Results_SubtitleRibbon", "Results_TallyNormal", "Results_TallyGold", "Results_TallyGreen",
		"Results_ItemSlot", "Results_QuantityTag", "Results_PartyRow", "Badge_LevelUp", "Item_AmberGem",
	},
}

local Assets = {}
Assets.Images = Images
Assets.Sounds = Sounds
Assets.Screens = Screens

-- The image to show for `key`, or nil when there is no art yet (then use the fallback look).
function Assets.image(key: string): string?
	local entry: AssetEntry? = Images[key]
	if entry == nil then
		warn(`Assets: unknown image key "{key}"`)
		return nil
	end
	local id = entry.id
	return if id ~= nil and id ~= "" then id else nil
end

function Assets.entry(key: string): AssetEntry?
	return Images[key]
end

-- Every filled-in id a screen should preload (empty while no art exists).
function Assets.contentFor(screen: string): { string }
	local ids = {}
	local keys: { string } = Screens[screen] or {}
	for _, key in keys do
		local id = Assets.image(key)
		if id then
			table.insert(ids, id)
		end
	end
	return ids
end

return Assets
