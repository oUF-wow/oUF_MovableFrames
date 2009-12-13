local _, ns = ...
local oUF = ns.oUF or oUF

assert(oUF, "oUF_MovableFrames was unable to locate oUF install.")

-- The DB is organized as the following:
-- {
--    Lily = {
--       player = "CENTER\031UIParent\0310\031-621\029",
-- }
--}
local _DB
local _LOCK

local _BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background";
}

local print = function(...)
	return print('|cff33ff99oUF_MovableFrames:|r', ...)
end
local round = function(n)
	return math.floor(n * 1e5 + .5) / 1e5
end

local backdropPool = {}

-- XXX: Should possibly just be replaced with something that steals the points
-- of the anchor, as it does most of the work for us already.
local getPoint = function(obj)
	-- VARIABLE NAMES OF DOOM!
	local L, R = obj:GetLeft(), obj:GetRight()
	local T, B = obj:GetTop(), obj:GetBottom()
	local Cx, Cy = obj:GetCenter()

	local width, height = UIParent:GetRight(), UIParent:GetTop()
	local left = width / 3
	local right = width - left
	local bottom = height / 3
	local top = height - bottom

	local point, x, y
	if(Cx >= left and not(Cx <= right)) then
		point = 'RIGHT'
		x = R - width
	elseif(Cx <= left) then
		point = 'LEFT'
		x = L
	else
		x = Cx - (width / 2)
	end

	if(Cy > bottom and Cy < top) then
		if(not point) then point = 'CENTER' end
		y = Cy - (height / 2)
	elseif(Cy >= bottom and not(Cy <= top)) then
		point = 'TOP' .. (point or '')
		y = T - height
	elseif(Cy <= bottom) then
		y = B
		point = 'BOTTOM' .. (point or '')
	end

	return string.format(
		'%s\031%s\031%d\031%d\029',
		point, 'UIParent', round(x), round(y)
	)
end

local getObjectInformation  = function(obj)
	-- This won't be set if we're dealing with oUF <1.3.22. Due to this we're just
	-- setting it to Unknown. It will only break if the user has multiple layouts
	-- spawning the same unit or change between layouts.
	local style = obj.style or 'Unknown'
	local identifier = obj.unit

	-- Are we dealing with header units?
	local isHeader
	local parent = obj:GetParent()
	-- Check for both as we can hit parents with initialConfigFunction, and
	-- SetManyAttributes alone is kinda up to the authors.
	if(parent and parent.initialConfigFunction and parent.SetManyAttributes) then
		isHeader = true

		-- These always have a name, so we might as well abuse it.
		identifier = parent:GetName()
	end

	return style, identifier, isHeader
end

local function restorePosition(obj)
	local style, identifier, isHeader = getObjectInformation(obj)
	-- We've not saved any custom position for this style.
	if(not _DB[style] or not _DB[style][identifier]) then return end

	local parent = (isHeader and obj:GetParent())
	local SetPoint = getmetatable(parent or obj).__index.SetPoint;

	-- Hah, a spot you have to use semi-colon!
	-- Guess I've never experienced that as these are usually wrapped in do end
	-- statements.
	(parent or obj).SetPoint = restorePosition;
	(parent or obj):ClearAllPoints();

	for point, parentName, x, y in _DB[style][identifier]:gmatch(
		"(%w+)\031(.-)\031([+-]?%d+%.?%d*)\031([+-]?%d+%.?%d*)\029") do
		SetPoint(parent or obj, point, parentName, point, x, y)
	end
end

local savePosition = function(obj, override)
	local style, identifier, isHeader = getObjectInformation(obj)
	if(not _DB[style]) then _DB[style] = {} end

	if(isHeader and not override) then
		_DB[style][identifier] = getPoint(obj:GetParent())
	else
		_DB[style][identifier] = getPoint(override or obj)
	end
end

do
	local frame = CreateFrame"Frame"
	frame:SetScript("OnEvent", function(self)
		return self[event](self)
	end)

	function frame:VARIABLES_LOADED()
		-- I honestly don't trust the load order of SVs.
		_DB = bb08df87101dd7f2161e5b77cf750f753c58ef1b or {}
		bb08df87101dd7f2161e5b77cf750f753c58ef1b = _DB
		-- Got to catch them all!
		for _, obj in next, oUF.objects do
			restorePosition(obj)
		end

		oUF:RegisterInitCallback(restorePosition)
		self:UnregisterEvent"VARIABLES_LOADED"
		self.VARIABLES_LOADED = nil
	end
	frame:RegisterEvent"VARIABLES_LOADED"

	function frame:PLAYER_REGEN_DISABLED()
		print("Anchors hidden due to combat.")
		for k, bdrop in next, backdropPool do
			bdrop:Hide()
		end

		_LOCK = nil
	end
	frame:RegisterEvent"PLAYER_REGEN_DISABLED"
end

local getBackdrop
do
	local OnShow = function(self)
		if(self.header) then
			self.name:SetText(self.header:GetName())
		else
			local desc = self.obj.unit or self.obj:GetName() or '<unknown>'
			self.name:SetText(desc)
		end
	end

	local OnDragStart = function(self)
		self:StartMoving()
	end

	local OnDragStop = function(self)
		self:StopMovingOrSizing()
		savePosition(self.obj, self.header and self)
	end

	getBackdrop = function(obj, isHeader)
		local header = (isHeader and obj:GetParent())
		if(backdropPool[header or obj]) then return backdropPool[header or obj] end

		local backdrop = CreateFrame"Frame"
		backdrop:Hide()

		backdrop:SetBackdrop(_BACKDROP)
		backdrop:SetFrameStrata"TOOLTIP"
		backdrop:SetScale(obj:GetEffectiveScale())
		backdrop:SetAllPoints(header or obj)

		backdrop:EnableMouse(true)
		backdrop:SetMovable(true)
		backdrop:RegisterForDrag"LeftButton"

		backdrop:SetScript("OnShow", OnShow)

		local name = backdrop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		name:SetPoint"LEFT"
		name:SetPoint"RIGHT"
		name:SetJustifyH"CENTER"
		name:SetFont(GameFontNormal:GetFont(), 12)
		name:SetTextColor(1, 1, 1)

		backdrop.name = name
		backdrop.obj = obj
		backdrop.header = header

		backdrop:SetBackdropBorderColor(0, .9, 0)
		backdrop:SetBackdropColor(0, .9, 0)

		-- Reset our anchors.
		backdrop:StartMoving()
		backdrop:StopMovingOrSizing()

		-- Work around the fact that headers with no units displayed are 0 in height.
		if(header and math.floor(header:GetHeight()) == 0) then
			local height = header:GetChildren():GetHeight()
			backdrop:SetHeight(height)
		end

		(header or obj):ClearAllPoints();
		(header or obj):SetAllPoints(backdrop);

		backdrop:SetScript("OnDragStart", OnDragStart)
		backdrop:SetScript("OnDragStop", OnDragStop)

		backdropPool[header or obj] = backdrop

		return backdrop
	end
end

SLASH_OUF_MOVABLEFRAMES1 = '/omf'
SlashCmdList['OUF_MOVABLEFRAMES'] = function(inp)
	if(InCombatLockdown()) then
		return print"Frames cannot be moved while in combat. Bailing out."
	end

	if(not _LOCK) then
		for k, obj in next, oUF.objects do
			local style, identifier, isHeader = getObjectInformation(obj)
			local backdrop = getBackdrop(obj, isHeader)
			backdrop:Show()
		end

		_LOCK = true
	else
		for k, bdrop in next, backdropPool do
			bdrop:Hide()
		end

		_LOCK = nil
	end
end
-- It's not in your best interest to disconnect me. Someone could get hurt.
