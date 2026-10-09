--!strict
--[[
	Layout — safe zones, scale and device class, as pure functions of the screen size (handoff
	rule 1, M0 report section 4). Nothing here touches an Instance, so the Lune tests can check the
	same numbers Studio renders.

	Sizes are the ScreenGui's AbsoluteSize: with ScreenInsets = CoreUISafeInsets that already
	excludes Roblox's top bar and device notches. On top of that the UI keeps three regions clear:

		top-left                 Roblox's menu and chat
		bottom-left / -right     the mobile thumbstick and jump button (the bottom 25% at each side)

	Design size is a phone (DESIGN). The root UIScale only ever scales up from there, so body text
	and tap targets never shrink below their design pixels on the smallest screen.
]]

local Layout = {}

export type Rect = { x: number, y: number, w: number, h: number }

Layout.DESIGN = Vector2.new(844, 390) -- a small phone in landscape, in logical pixels
Layout.MIN_SCALE = 1
Layout.MAX_SCALE = 1.6

-- Keep-out regions as fractions of the screen, so SafeZoneDebug can draw them in Scale units.
Layout.KEEP_OUT = {
	topLeft = { w = 0.2, h = 0.15 },
	bottomLeft = { w = 0.22, h = 0.25 },
	bottomRight = { w = 0.22, h = 0.25 },
}
-- Key UI stays inside the middle of the screen (handoff: "the middle ~85%").
Layout.SAFE_MARGIN = { x = 0.025, y = 0.03 }

export type KeepOut = { topLeft: Rect, bottomLeft: Rect, bottomRight: Rect }

function Layout.rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

-- The scale the root UIScale uses for a screen of this size: 1 on the design phone, up to
-- MAX_SCALE on big screens, never below MIN_SCALE.
function Layout.scaleFor(size: Vector2): number
	local ratio = math.min(size.X / Layout.DESIGN.X, size.Y / Layout.DESIGN.Y)
	return math.clamp(ratio, Layout.MIN_SCALE, Layout.MAX_SCALE)
end

export type DeviceClass = "Phone" | "Tablet" | "Desktop"

function Layout.deviceClass(size: Vector2): DeviceClass
	if size.Y < 500 then
		return "Phone"
	elseif size.Y < 900 then
		return "Tablet"
	end
	return "Desktop"
end

-- The three keep-out rects, in pixels, for a screen of this size.
function Layout.keepOut(size: Vector2): KeepOut
	local k = Layout.KEEP_OUT
	return {
		topLeft = Layout.rect(0, 0, size.X * k.topLeft.w, size.Y * k.topLeft.h),
		bottomLeft = Layout.rect(0, size.Y * (1 - k.bottomLeft.h), size.X * k.bottomLeft.w, size.Y * k.bottomLeft.h),
		bottomRight = Layout.rect(size.X * (1 - k.bottomRight.w), size.Y * (1 - k.bottomRight.h), size.X * k.bottomRight.w, size.Y * k.bottomRight.h),
	}
end

-- The area key UI lives in: the screen minus a small margin.
function Layout.safeArea(size: Vector2): Rect
	local mx, my = size.X * Layout.SAFE_MARGIN.x, size.Y * Layout.SAFE_MARGIN.y
	return Layout.rect(mx, my, size.X - 2 * mx, size.Y - 2 * my)
end

function Layout.intersects(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

function Layout.contains(outer: Rect, inner: Rect): boolean
	return inner.x >= outer.x and inner.y >= outer.y and inner.x + inner.w <= outer.x + outer.w and inner.y + inner.h <= outer.y + outer.h
end

-- Whether a rect touches any keep-out region.
function Layout.hitsKeepOut(rect: Rect, keepOut: KeepOut): string?
	if Layout.intersects(rect, keepOut.topLeft) then
		return "topLeft"
	elseif Layout.intersects(rect, keepOut.bottomLeft) then
		return "bottomLeft"
	elseif Layout.intersects(rect, keepOut.bottomRight) then
		return "bottomRight"
	end
	return nil
end

-- Where a GuiObject with this Position / Size / AnchorPoint lands inside `parent`, with `scale`
-- applied to its offsets (a UIScale above it). This is what the tests use in place of
-- AbsolutePosition / AbsoluteSize, which Lune can't compute.
function Layout.resolve(position: UDim2, size: UDim2, anchor: Vector2, parent: Rect, scale: number?): Rect
	local s = scale or 1
	local w = size.X.Scale * parent.w + size.X.Offset * s
	local h = size.Y.Scale * parent.h + size.Y.Offset * s
	local x = parent.x + position.X.Scale * parent.w + position.X.Offset * s - anchor.X * w
	local y = parent.y + position.Y.Scale * parent.h + position.Y.Offset * s - anchor.Y * h
	return Layout.rect(x, y, w, h)
end

-- The screen's own rect.
function Layout.screen(size: Vector2): Rect
	return Layout.rect(0, 0, size.X, size.Y)
end

-- Named anchor positions for the regions screens place their UI in, in whole pixels (UDim2
-- offsets are integers, so every edge that meets a keep-out is rounded away from it). All of them
-- clear the keep-outs by construction; the tests check it anyway.
function Layout.regions(size: Vector2): { [string]: Rect }
	local k = Layout.KEEP_OUT
	local safe = Layout.safeArea(size)
	-- Edges: the first pixel after a keep-out (ceil) and the last before one (floor).
	local topLeftRight = math.ceil(size.X * k.topLeft.w) -- x where the top-left keep-out ends
	local topLeftBottom = math.ceil(size.Y * k.topLeft.h)
	local bottomClear = math.floor(size.Y * (1 - k.bottomLeft.h)) -- y where the bottom keep-outs start
	local bottomLeftRight = math.ceil(size.X * k.bottomLeft.w)
	local bottomRightLeft = math.floor(size.X * (1 - k.bottomRight.w))
	local safeX, safeY = math.ceil(safe.x), math.ceil(safe.y)
	local function span(from: number, to: number): number
		return math.max(0, to - from)
	end
	local rightStart = bottomRightLeft - math.floor(size.X * 0.06) -- the right column reaches past the keep-out's edge
	local gap = 8
	return {
		-- top center strip: turn order, headlines; stops short of the right column
		topCenter = Layout.rect(topLeftRight, safeY, span(topLeftRight, rightStart - gap), math.floor(size.Y * 0.16)),
		-- top right: BACK button, list headers
		topRight = Layout.rect(math.ceil(size.X * 0.78), safeY, span(math.ceil(size.X * 0.78), size.X - safeX), math.floor(size.Y * 0.15)),
		-- left column, between the top-left and bottom-left keep-outs: the command ring
		left = Layout.rect(safeX, topLeftBottom, span(safeX, math.min(topLeftRight, bottomLeftRight)), span(topLeftBottom, bottomClear)),
		-- right column, from the top down to the bottom-right keep-out: party cards, skill list
		right = Layout.rect(rightStart, safeY, span(rightStart, size.X - safeX), span(safeY, bottomClear)),
		-- bottom center, between the two bottom keep-outs: the hero Mana plate
		bottomCenter = Layout.rect(bottomLeftRight, bottomClear, span(bottomLeftRight, bottomRightLeft), span(bottomClear, size.Y - safeY)),
		-- the middle: stamps, result lettering
		center = Layout.rect(math.ceil(size.X * 0.25), math.ceil(size.Y * 0.2), math.floor(size.X * 0.5), math.floor(size.Y * 0.5)),
	}
end

return Layout
