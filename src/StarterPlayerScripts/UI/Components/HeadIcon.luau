--!strict
--[[
	HeadIcon — a player's avatar headshot (handoff section 3): Players:GetUserThumbnailAsync, with
	a drawn fallback (initials on a disc) while it loads, when it fails, or for enemies and bots
	with no user id.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Theme"))
local Core = script.Parent.Parent:WaitForChild("Core")
local Fallbacks = require(Core:WaitForChild("Fallbacks"))
local Gui = require(Core:WaitForChild("Gui"))

export type Props = {
	name: string,
	userId: number?,
	fallbackText: string, -- initials or a short word
	size: number?,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
	ring: Color3?,
}

export type HeadIcon = {
	frame: ImageLabel,
	setUser: (userId: number?, fallbackText: string) -> (),
	setRing: (color: Color3) -> (),
	destroy: () -> (),
}

local HeadIcon = {}

-- Headshots are cached per user so a party of four doesn't fetch the same face per card.
local cache: { [number]: string } = {}

local function fetch(userId: number): string?
	if cache[userId] then
		return cache[userId]
	end
	local ok, content, ready = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	end)
	if ok and ready and type(content) == "string" and content ~= "" then
		cache[userId] = content
		return content
	end
	return nil
end

function HeadIcon.new(parent: Instance, props: Props): HeadIcon
	local size = props.size or 48
	local frame = Fallbacks.image(parent, props.name, "", { fill = Theme.Colors.Navy, fillTransparency = 0, trim = props.ring or Theme.Colors.Gold, trimThickness = 2, corner = 8 })
	Fallbacks.panel(frame, { fill = Theme.Colors.Navy, fillTransparency = 0, trim = props.ring or Theme.Colors.Gold, trimThickness = 2, corner = 8 })
	frame.Size = UDim2.fromOffset(size, size)
	frame.Position = props.position or UDim2.fromScale(0, 0)
	frame.AnchorPoint = props.anchor or Vector2.zero
	frame.LayoutOrder = props.layoutOrder or 0
	frame.ClipsDescendants = true
	frame.ScaleType = Enum.ScaleType.Crop

	local initials = Gui.label(frame, "Initials", { text = props.fallbackText, size = math.floor(size * 0.4), font = Theme.Fonts.Display, stroke = 1 })
	local generation = 0

	local function setUser(userId: number?, fallbackText: string)
		generation += 1
		local myGeneration = generation
		initials.Text = fallbackText
		initials.Visible = true
		frame.Image = ""
		if userId == nil then
			return
		end
		task.spawn(function()
			local content = fetch(userId)
			if content and generation == myGeneration and frame.Parent then
				frame.Image = content
				initials.Visible = false
			end
		end)
	end
	setUser(props.userId, props.fallbackText)

	return {
		frame = frame,
		setUser = setUser,
		setRing = function(color: Color3)
			local stroke = frame:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = color
			end
		end,
		destroy = function()
			frame:Destroy()
		end,
	}
end

return HeadIcon
