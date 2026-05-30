local MacLib = { 
	Options = {}, 
	Toggles = {},
	Folder = "TiRex",
	Name = "TiRex",
	GetService = function(service)
		return cloneref and cloneref(game:GetService(service)) or game:GetService(service)
	end
}

--// Services
local TweenService = MacLib.GetService("TweenService")
local RunService = MacLib.GetService("RunService")
local HttpService = MacLib.GetService("HttpService")
local ContentProvider = MacLib.GetService("ContentProvider")
local UserInputService = MacLib.GetService("UserInputService")
local Lighting = MacLib.GetService("Lighting")
local Players = MacLib.GetService("Players")

--// Variables
local isStudio = RunService:IsStudio()
local LocalPlayer = Players.LocalPlayer

local windowState
local acrylicBlur
local hasGlobalSetting
local activeLoadingGuis = 0

local DEFAULT_WINDOW_SIZE = UDim2.fromOffset(920, 680)
local MIN_WINDOW_SIZE = Vector2.new(760, 520)

local tabs = {}
local currentTabInstance = nil
local tabIndex = 0
local unloaded = false

local function optionFirstNonNil(...)
	local values = { ... }
	for i = 1, #values do
		if values[i] ~= nil then
			return values[i]
		end
	end
	return nil
end

local function optionText(settings, flag, fallback)
	settings = settings or {}
	return tostring(optionFirstNonNil(settings.Text, settings.Name, flag, fallback or "Option"))
end

local function optionArgs(settings, flag)
	if type(settings) == "string" and type(flag) == "function" then
		return { Name = settings, Callback = flag }, nil
	end
	if type(settings) == "string" and (type(flag) == "table" or flag == nil) then
		return flag or {}, settings
	end
	if settings ~= nil and type(settings) ~= "table" then
		return { Text = tostring(settings) }, flag
	end
	return settings or {}, flag
end

local optionUnpack = table.unpack or unpack

local function optionCall(callback, ...)
	if type(callback) ~= "function" then
		return
	end

	local args = { ... }
	local function invoke()
		local ok, err = pcall(callback, optionUnpack(args))
		if not ok then
			warn("[MacLib] callback error: " .. tostring(err))
		end
	end
	if task and type(task.spawn) == "function" then
		task.spawn(invoke)
	else
		coroutine.wrap(invoke)()
	end
end

local function optionRound(value, precision)
	value = tonumber(value) or 0
	precision = tonumber(precision)
	if not precision or precision <= 0 then
		return math.floor(value + 0.5)
	end
	local scale = 10 ^ precision
	return math.floor(value * scale + 0.5) / scale
end

local function optionClampNumber(value, minValue, maxValue)
	value = tonumber(value)
	minValue = tonumber(minValue) or 0
	maxValue = tonumber(maxValue) or minValue
	if maxValue < minValue then
		minValue, maxValue = maxValue, minValue
	end
	return math.clamp(value or minValue, minValue, maxValue)
end

local function optionExtractNumber(text)
	if typeof(text) == "number" then
		return text, false
	end

	text = tostring(text or "")
	text = text:gsub(",", "")
	local numberText, percent = text:match("([%-]?%d+%.?%d*)%s*(%%?)")
	if not numberText then
		return nil, false
	end
	return tonumber(numberText), percent == "%"
end

local function optionResolveInput(input)
	if typeof(input) == "EnumItem" then
		return input
	end

	local name = tostring(input or "")
	name = name:gsub("^Enum%.KeyCode%.", "")
	name = name:gsub("^KeyCode%.", "")
	name = name:gsub("^Enum%.UserInputType%.", "")
	name = name:gsub("^UserInputType%.", "")
	if name == "" or name == "None" or name == "nil" then
		return nil
	end

	local okKey, keyCode = pcall(function()
		return Enum.KeyCode[name]
	end)
	if not okKey then
		keyCode = nil
	end
	if keyCode then
		return keyCode
	end
	local okInput, inputType = pcall(function()
		return Enum.UserInputType[name]
	end)
	return okInput and inputType or nil
end

local assets = {
	interFont = "rbxasset://fonts/families/SourceSansPro.json",
	tirexIcon = "rbxassetid://91835354225469",
	userInfoBlurred = "rbxassetid://18824089198",
	toggleBackground = "rbxassetid://18772190202",
	togglerHead = "rbxassetid://18772309008",
	buttonImage = "rbxassetid://10709791437",
	searchIcon = "rbxassetid://86737463322606",
	colorWheel = "rbxassetid://2849458409",
	colorTarget = "rbxassetid://73265255323268",
	grid = "rbxassetid://121484455191370",
	globe = "rbxassetid://108952102602834",
	transform = "rbxassetid://90336395745819",
	dropdown = "rbxassetid://18865373378",
	sliderbar = "rbxassetid://18772615246",
	sliderhead = "rbxassetid://18772834246",
}

--// Functions
local function GetGui()
	local newGui = Instance.new("ScreenGui")
	pcall(function()
		newGui.ScreenInsets = Enum.ScreenInsets.None
	end)
	pcall(function()
		newGui.ResetOnSpawn = false
	end)
	pcall(function()
		newGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	end)
	pcall(function()
		newGui.DisplayOrder = 2147483647
	end)

	local parentCandidates = {}
	local seenParents = {}
	local function addParentCandidate(candidate)
		if typeof(candidate) == "Instance" and not seenParents[candidate] then
			seenParents[candidate] = true
			parentCandidates[#parentCandidates + 1] = candidate
		end
	end

	if LocalPlayer then
		addParentCandidate(LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:FindFirstChild("PlayerGui"))
	end
	local okCoreGui, coreGui = pcall(function()
		return cloneref and cloneref(MacLib.GetService("CoreGui")) or MacLib.GetService("CoreGui")
	end)
	if okCoreGui then
		addParentCandidate(coreGui)
	end
	if type(gethui) == "function" and task and type(task.spawn) == "function" then
		local okHui, hui
		local finished = false
		task.spawn(function()
			okHui, hui = pcall(gethui)
			finished = true
			if okHui and typeof(hui) == "Instance" and not newGui.Parent then
				pcall(function()
					newGui.Parent = hui
				end)
			end
		end)
		local started = os.clock()
		while not finished and os.clock() - started < 0.05 do
			task.wait()
		end
		if finished and okHui then
			addParentCandidate(hui)
		end
	end

	for _, parent in ipairs(parentCandidates) do
		local okParent = pcall(function()
			newGui.Parent = parent
		end)
		if okParent and newGui.Parent == parent then
			return newGui
		end
	end

	warn("[MacLib] Failed to parent ScreenGui; UI may not be visible.")
	return newGui
end

local function SafeFont(font, weight, style)
	local ok, fontFace = pcall(function()
		return Font.new(
			font or assets.interFont,
			weight or Enum.FontWeight.Regular,
			style or Enum.FontStyle.Normal
		)
	end)
	if ok and fontFace then
		return fontFace
	end

	local okFallback, fallback = pcall(function()
		return Font.new(
			"rbxasset://fonts/families/SourceSansPro.json",
			weight or Enum.FontWeight.Regular,
			style or Enum.FontStyle.Normal
		)
	end)
	if okFallback and fallback then
		return fallback
	end

	return Font.fromEnum(Enum.Font.SourceSans)
end

local function Tween(instance, tweeninfo, propertytable)
	return TweenService:Create(instance, tweeninfo, propertytable)
end

local function ResolveImageAsset(value, fallback)
	if type(value) == "number" then
		return "rbxassetid://" .. tostring(value)
	end
	if type(value) == "string" then
		if value:match("^%d+$") then
			return "rbxassetid://" .. value
		end
		return value
	end
	return fallback or assets.tirexIcon
end

local lucideState = {
	BaseUrl = "https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/%s.svg",
	DirectModuleUrl = "https://raw.githubusercontent.com/deividcomsono/lucide-roblox-direct/refs/heads/main/source.lua",
	DirectModuleCache = "TiRex/lucide/lucide-roblox-direct.lua",
	SvgCacheFolder = "TiRex/lucide/svg",
	SvgCache = {},
	SegmentCache = {},
	Waiters = {},
	PendingSvg = {},
	DirectModule = nil,
	DirectLoading = false,
	DirectLoaded = false,
	DirectFailed = false,
	FastIcons = true,
	Aliases = {
		["check-circle"] = "circle-check",
		["alert-triangle"] = "triangle-alert",
		["swords"] = "sword",
		["activity"] = "chart-no-axes-column-increasing",
		["clapperboard"] = "clapperboard",
	}
}

local function ensureCachePath(path, isFile)
	if type(isfolder) ~= "function" or type(makefolder) ~= "function" then
		return false
	end

	local folderPath = isFile and tostring(path or ""):match("^(.*)/[^/]+$") or tostring(path or "")
	if not folderPath or folderPath == "" then
		return true
	end

	local current = ""
	for segment in folderPath:gmatch("[^/]+") do
		current = current == "" and segment or (current .. "/" .. segment)
		local okExists, exists = pcall(isfolder, current)
		if not okExists or not exists then
			pcall(makefolder, current)
		end
	end

	return true
end

local function readCacheFile(path)
	if type(isfile) ~= "function" or type(readfile) ~= "function" then
		return nil
	end

	local okExists, exists = pcall(isfile, path)
	if not okExists or not exists then
		return nil
	end

	local okRead, body = pcall(readfile, path)
	if okRead and type(body) == "string" and body ~= "" then
		return body
	end

	return nil
end

local function writeCacheFile(path, body)
	if type(writefile) ~= "function" or type(body) ~= "string" or body == "" then
		return false
	end

	ensureCachePath(path, true)
	local okWrite = pcall(writefile, path, body)
	return okWrite == true
end

local function normalizeLucideIconName(value)
	if type(value) ~= "string" then
		return nil
	end

	local name = value
	name = name:gsub("^lucide:", "")
	name = name:gsub("^lucide://", "")
	name = name:match("lucide%.dev/icons/([^%?#]+)") or name
	name = name:match("/icons/([^%?#]+)") or name
	name = name:gsub("%?.*$", ""):gsub("#.*$", ""):gsub("%.svg$", "")
	name = name:gsub("_", "-"):gsub("%s+", "-"):lower()
	name = name:gsub("[^%w%-]", "")
	if name == "" or name:find("^rbxasset") or name:find("^http") then
		return nil
	end

	return lucideState.Aliases[name] or name
end

local function fetchLucideSvg(iconName)
	if lucideState.SvgCache[iconName] ~= nil then
		return lucideState.SvgCache[iconName]
	end

	local cachePath = lucideState.SvgCacheFolder .. "/" .. tostring(iconName) .. ".svg"
	local cachedBody = readCacheFile(cachePath)
	if type(cachedBody) == "string" and cachedBody:find("<svg", 1, true) then
		lucideState.SvgCache[iconName] = cachedBody
		return cachedBody
	end

	local url = string.format(lucideState.BaseUrl, iconName)
	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if not ok or type(body) ~= "string" or not body:find("<svg", 1, true) then
		lucideState.SvgCache[iconName] = false
		return nil
	end

	lucideState.SvgCache[iconName] = body
	writeCacheFile(cachePath, body)
	return body
end

local function loadLucideDirectModule()
	if lucideState.DirectLoaded then
		return lucideState.DirectModule
	end
	if lucideState.DirectFailed then
		return nil
	end

	local source = readCacheFile(lucideState.DirectModuleCache)
	if type(source) ~= "string" or source == "" then
		local okFetch, body = pcall(function()
			return game:HttpGet(lucideState.DirectModuleUrl)
		end)
		if not okFetch or type(body) ~= "string" or body == "" then
			lucideState.DirectFailed = true
			return nil
		end
		source = body
		writeCacheFile(lucideState.DirectModuleCache, source)
	end

	local loadFn = loadstring or load
	if type(loadFn) ~= "function" then
		lucideState.DirectFailed = true
		return nil
	end

	local okModule, module = pcall(function()
		local loader, loadErr = loadFn(source)
		if type(loader) ~= "function" then
			error(loadErr or "failed to compile lucide direct module", 0)
		end
		return loader()
	end)

	if not okModule or type(module) ~= "table" or type(module.GetAsset) ~= "function" then
		lucideState.DirectFailed = true
		return nil
	end

	lucideState.DirectModule = module
	lucideState.DirectLoaded = true
	lucideState.DirectFailed = false
	return module
end

local function getDirectLucideAsset(iconName)
	if not lucideState.DirectLoaded or type(lucideState.DirectModule) ~= "table" then
		return nil
	end

	local okAsset, asset = pcall(lucideState.DirectModule.GetAsset, iconName)
	if okAsset and type(asset) == "table" and type(asset.Url) == "string" then
		return asset
	end

	return nil
end

local function parseSvgAttributes(tag)
	local attributes = {}
	for key, value in tag:gmatch("([%w%-]+)%s*=%s*\"([^\"]*)\"") do
		attributes[key] = value
	end
	for key, value in tag:gmatch("([%w%-]+)%s*=%s*'([^']*)'") do
		attributes[key] = value
	end
	return attributes
end

local function toNumber(value, fallback)
	local number = tonumber(value)
	if number == nil then
		return fallback or 0
	end
	return number
end

local function addSegment(segments, x1, y1, x2, y2)
	x1, y1, x2, y2 = tonumber(x1), tonumber(y1), tonumber(x2), tonumber(y2)
	if not (x1 and y1 and x2 and y2) then
		return
	end
	if math.abs(x1 - x2) < 0.001 and math.abs(y1 - y2) < 0.001 then
		return
	end
	segments[#segments + 1] = { x1, y1, x2, y2 }
end

local function addCircleSegments(segments, cx, cy, radius, steps)
	cx, cy, radius = tonumber(cx), tonumber(cy), tonumber(radius)
	if not (cx and cy and radius) or radius <= 0 then
		return
	end

	steps = steps or 18
	local previousX = cx + radius
	local previousY = cy
	for index = 1, steps do
		local angle = (math.pi * 2) * (index / steps)
		local x = cx + math.cos(angle) * radius
		local y = cy + math.sin(angle) * radius
		addSegment(segments, previousX, previousY, x, y)
		previousX, previousY = x, y
	end
end

local function parsePointList(points)
	local values = {}
	for number in tostring(points or ""):gmatch("[%-]?%d+%.?%d*") do
		values[#values + 1] = tonumber(number)
	end
	return values
end

local function addPolylineSegments(segments, points, closeShape)
	local values = parsePointList(points)
	if #values < 4 then
		return
	end

	for index = 1, #values - 3, 2 do
		addSegment(segments, values[index], values[index + 1], values[index + 2], values[index + 3])
	end
	if closeShape then
		addSegment(segments, values[#values - 1], values[#values], values[1], values[2])
	end
end

local function tokenizeSvgPath(pathData)
	local tokens = {}
	local data = tostring(pathData or "")
	local index = 1

	while index <= #data do
		local char = data:sub(index, index)
		if char:match("[AaCcHhLlMmQqSsTtVvZz]") then
			tokens[#tokens + 1] = char
			index += 1
		else
			local number = data:match("^%-?%d*%.?%d+", index)
			if number and number ~= "" and number ~= "-" and number ~= "." then
				tokens[#tokens + 1] = number
				index += #number
			else
				index += 1
			end
		end
	end

	return tokens
end

local function isPathCommand(token)
	return type(token) == "string" and token:match("^[AaCcHhLlMmQqSsTtVvZz]$") ~= nil
end

local pathArity = {
	M = 2, L = 2, H = 1, V = 1, C = 6, S = 4, Q = 4, T = 2, A = 7
}

local function parsePathSegments(pathData)
	local tokens = tokenizeSvgPath(pathData)
	local segments = {}
	local index = 1
	local command = nil
	local currentX, currentY = 0, 0
	local startX, startY = 0, 0

	local function hasNumbers(count)
		for offset = 0, count - 1 do
			if index + offset > #tokens or isPathCommand(tokens[index + offset]) then
				return false
			end
		end
		return true
	end

	while index <= #tokens do
		if isPathCommand(tokens[index]) then
			command = tokens[index]
			index = index + 1
		end

		if not command then
			break
		end

		local upper = command:upper()
		local relative = command ~= upper

		if upper == "Z" then
			addSegment(segments, currentX, currentY, startX, startY)
			currentX, currentY = startX, startY
			command = nil
		elseif upper == "M" then
			if not hasNumbers(2) then
				break
			end
			local x = tonumber(tokens[index])
			local y = tonumber(tokens[index + 1])
			index = index + 2
			if relative then
				x, y = currentX + x, currentY + y
			end
			currentX, currentY = x, y
			startX, startY = x, y
			command = relative and "l" or "L"
		else
			local arity = pathArity[upper]
			if not arity or not hasNumbers(arity) then
				if isPathCommand(tokens[index]) then
					command = tokens[index]
					index = index + 1
				else
					break
				end
			else
				local oldX, oldY = currentX, currentY
				if upper == "L" then
					local x = tonumber(tokens[index])
					local y = tonumber(tokens[index + 1])
					index = index + 2
					if relative then
						x, y = currentX + x, currentY + y
					end
					currentX, currentY = x, y
				elseif upper == "H" then
					local x = tonumber(tokens[index])
					index = index + 1
					currentX = relative and currentX + x or x
				elseif upper == "V" then
					local y = tonumber(tokens[index])
					index = index + 1
					currentY = relative and currentY + y or y
				elseif upper == "C" then
					local x = tonumber(tokens[index + 4])
					local y = tonumber(tokens[index + 5])
					index = index + 6
					if relative then
						x, y = currentX + x, currentY + y
					end
					currentX, currentY = x, y
				elseif upper == "S" or upper == "Q" then
					local x = tonumber(tokens[index + 2])
					local y = tonumber(tokens[index + 3])
					index = index + 4
					if relative then
						x, y = currentX + x, currentY + y
					end
					currentX, currentY = x, y
				elseif upper == "T" then
					local x = tonumber(tokens[index])
					local y = tonumber(tokens[index + 1])
					index = index + 2
					if relative then
						x, y = currentX + x, currentY + y
					end
					currentX, currentY = x, y
				elseif upper == "A" then
					local x = tonumber(tokens[index + 5])
					local y = tonumber(tokens[index + 6])
					index = index + 7
					if relative then
						x, y = currentX + x, currentY + y
					end
					currentX, currentY = x, y
				end
				addSegment(segments, oldX, oldY, currentX, currentY)
			end
		end
	end

	return segments
end

local function parseLucideSvgSegments(iconName)
	if lucideState.SegmentCache[iconName] ~= nil then
		return lucideState.SegmentCache[iconName]
	end

	local svg = fetchLucideSvg(iconName)
	if not svg then
		lucideState.SegmentCache[iconName] = false
		return nil
	end

	local segments = {}
	for tag in svg:gmatch("<line%s+([^>/]-)/?>") do
		local attr = parseSvgAttributes(tag)
		addSegment(segments, attr.x1, attr.y1, attr.x2, attr.y2)
	end
	for tag in svg:gmatch("<polyline%s+([^>/]-)/?>") do
		local attr = parseSvgAttributes(tag)
		addPolylineSegments(segments, attr.points, false)
	end
	for tag in svg:gmatch("<polygon%s+([^>/]-)/?>") do
		local attr = parseSvgAttributes(tag)
		addPolylineSegments(segments, attr.points, true)
	end
	for tag in svg:gmatch("<rect%s+([^>/]-)/?>") do
		local attr = parseSvgAttributes(tag)
		local x = toNumber(attr.x, 0)
		local y = toNumber(attr.y, 0)
		local width = toNumber(attr.width, 0)
		local height = toNumber(attr.height, 0)
		addSegment(segments, x, y, x + width, y)
		addSegment(segments, x + width, y, x + width, y + height)
		addSegment(segments, x + width, y + height, x, y + height)
		addSegment(segments, x, y + height, x, y)
	end
	for tag in svg:gmatch("<circle%s+([^>/]-)/?>") do
		local attr = parseSvgAttributes(tag)
		addCircleSegments(segments, attr.cx, attr.cy, attr.r, 20)
	end
	for tag in svg:gmatch("<path%s+([^>/]-)/?>") do
		local attr = parseSvgAttributes(tag)
		for _, segment in ipairs(parsePathSegments(attr.d)) do
			segments[#segments + 1] = segment
		end
	end

	lucideState.SegmentCache[iconName] = segments
	return segments
end

local function drawIconLine(parent, segment, size, color, transparency)
	local scale = size / 24
	local x1, y1, x2, y2 = segment[1] * scale, segment[2] * scale, segment[3] * scale, segment[4] * scale
	local dx, dy = x2 - x1, y2 - y1
	local length = math.sqrt(dx * dx + dy * dy)
	if length <= 0.01 then
		return
	end

	local line = Instance.new("Frame")
	line.Name = "Line"
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.BackgroundColor3 = color
	line.BackgroundTransparency = transparency or 0
	line.BorderSizePixel = 0
	line.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
	line.Rotation = math.deg(math.atan2(dy, dx))
	line.Size = UDim2.fromOffset(length, math.max(1, math.floor(size / 12)))
	line.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 0)
	corner.Parent = line
end

local function clearLucideContainer(container)
	for _, child in ipairs(container:GetChildren()) do
		child:Destroy()
	end
end

local function renderLucideFallback(container, iconName, icon, size, color)
	clearLucideContainer(container)

	local fallback = Instance.new("TextLabel")
	fallback.Name = "Fallback"
	fallback.BackgroundTransparency = 1
	fallback.FontFace = SafeFont(assets.interFont, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
	fallback.Size = UDim2.fromScale(1, 1)
	fallback.Text = string.upper(tostring(iconName or icon or "?"):sub(1, 1))
	fallback.TextColor3 = color
	fallback.TextSize = math.max(10, size - 4)
	fallback.TextTransparency = 0.35
	fallback.Parent = container
end

local function renderLucideSegments(container, segments, size, color)
	clearLucideContainer(container)
	for _, segment in ipairs(segments) do
		drawIconLine(container, segment, size, color, 0)
	end
end

local function renderLucideSprite(container, asset, size, color)
	clearLucideContainer(container)

	local image = Instance.new("ImageLabel")
	image.Name = "LucideSprite"
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Image = asset.Url
	image.ImageColor3 = color
	image.ImageTransparency = 0
	image.ImageRectOffset = asset.ImageRectOffset or Vector2.zero
	image.ImageRectSize = asset.ImageRectSize or Vector2.zero
	image.Size = UDim2.fromOffset(size, size)
	image.Parent = container
end

local function resolveLucideWaiters(iconName)
	local waiters = lucideState.Waiters[iconName]
	if not waiters then
		return true
	end

	local asset = getDirectLucideAsset(iconName)
	local segments = nil
	if not asset and type(lucideState.SegmentCache[iconName]) == "table" then
		segments = lucideState.SegmentCache[iconName]
	end

	if not asset and not segments then
		return false
	end

	lucideState.Waiters[iconName] = nil
	for _, waiter in ipairs(waiters) do
		local container = waiter.Container
		if typeof(container) == "Instance" and container.Parent then
			if asset then
				renderLucideSprite(container, asset, waiter.Size, waiter.Color)
			else
				renderLucideSegments(container, segments, waiter.Size, waiter.Color)
			end
		end
	end

	return true
end

local function startLucideSvgLoad(iconName)
	if lucideState.PendingSvg[iconName] then
		return
	end

	lucideState.PendingSvg[iconName] = true
	task.spawn(function()
		local segments = parseLucideSvgSegments(iconName)
		lucideState.PendingSvg[iconName] = nil

		if type(segments) == "table" then
			resolveLucideWaiters(iconName)
		elseif lucideState.Waiters[iconName] then
			lucideState.Waiters[iconName] = nil
		end
	end)
end

local function startLucideDirectLoad()
	if lucideState.DirectLoaded or lucideState.DirectLoading or lucideState.DirectFailed then
		return
	end

	lucideState.DirectLoading = true
	task.spawn(function()
		loadLucideDirectModule()
		lucideState.DirectLoading = false

		local queuedIcons = {}
		for iconName in pairs(lucideState.Waiters) do
			queuedIcons[#queuedIcons + 1] = iconName
		end

		for _, iconName in ipairs(queuedIcons) do
			if not resolveLucideWaiters(iconName) then
				startLucideSvgLoad(iconName)
			end
		end
	end)
end

local function queueLucideIconRender(iconName, container, size, color)
	local asset = getDirectLucideAsset(iconName)
	if asset then
		renderLucideSprite(container, asset, size, color)
		return
	end

	if type(lucideState.SegmentCache[iconName]) == "table" then
		renderLucideSegments(container, lucideState.SegmentCache[iconName], size, color)
		return
	end

	lucideState.Waiters[iconName] = lucideState.Waiters[iconName] or {}
	table.insert(lucideState.Waiters[iconName], {
		Container = container,
		Size = size,
		Color = color
	})

	if lucideState.DirectLoaded or lucideState.DirectFailed then
		startLucideSvgLoad(iconName)
	else
		startLucideDirectLoad()
	end
end

local function createLucideIcon(icon, size, color, transparency)
	size = size or 18
	color = color or Color3.fromRGB(255, 255, 255)
	local iconName = normalizeLucideIconName(icon)

	local container = Instance.new("CanvasGroup")
	container.Name = "LucideIcon"
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.GroupTransparency = transparency or 0
	container.Size = UDim2.fromOffset(size, size)

	if iconName and getDirectLucideAsset(iconName) then
		renderLucideSprite(container, getDirectLucideAsset(iconName), size, color)
	elseif iconName and type(lucideState.SegmentCache[iconName]) == "table" then
		renderLucideSegments(container, lucideState.SegmentCache[iconName], size, color)
	else
		renderLucideFallback(container, iconName, icon, size, color)
		if iconName then
			queueLucideIconRender(iconName, container, size, color)
		end
	end

	return container
end

local function createIconInstance(icon, size, color, transparency)
	icon = ResolveImageAsset(icon, icon)

	if type(icon) ~= "string" then
		icon = assets.tirexIcon
	end

	if normalizeLucideIconName(icon) then
		return createLucideIcon(icon, size, color, transparency)
	end

	if type(icon) == "string" and (icon:find("^rbxasset") or icon:find("^http")) then
		local image = Instance.new("ImageLabel")
		image.Name = "IconImage"
		image.BackgroundTransparency = 1
		image.BorderSizePixel = 0
		image.Image = icon
		image.ImageColor3 = color or Color3.fromRGB(255, 255, 255)
		image.ImageTransparency = transparency or 0
		image.Size = UDim2.fromOffset(size or 18, size or 18)
		return image
	end

	return createLucideIcon(icon, size, color, transparency)
end

local function setIconTransparency(icon, transparency)
	if not icon then
		return
	end
	if icon:IsA("ImageLabel") or icon:IsA("ImageButton") then
		icon.ImageTransparency = transparency
	elseif icon:IsA("CanvasGroup") then
		icon.GroupTransparency = transparency
	else
		for _, child in ipairs(icon:GetDescendants()) do
			if child:IsA("GuiObject") then
				child.BackgroundTransparency = transparency
			end
		end
	end
end

local function tweenIconTransparency(icon, transparency, tweenInfo)
	if not icon then
		return
	end
	if icon:IsA("ImageLabel") or icon:IsA("ImageButton") then
		Tween(icon, tweenInfo, { ImageTransparency = transparency }):Play()
	elseif icon:IsA("CanvasGroup") then
		Tween(icon, tweenInfo, { GroupTransparency = transparency }):Play()
	else
		setIconTransparency(icon, transparency)
	end
end

--// Library Functions
function MacLib:Window(Settings)
	Settings = Settings or {}
	Settings.Title = tostring(Settings.Title or self.Name or "TiRex")
	Settings.Subtitle = tostring(Settings.Subtitle or Settings.Footer or "")
	Settings.DisabledWindowControls = type(Settings.DisabledWindowControls) == "table" and Settings.DisabledWindowControls or {}
	if typeof(Settings.Size) ~= "UDim2" then
		Settings.Size = DEFAULT_WINDOW_SIZE
	end
	if typeof(Settings.MinimumSize) ~= "Vector2" then
		Settings.MinimumSize = typeof(Settings.MinSize) == "Vector2" and Settings.MinSize or MIN_WINDOW_SIZE
	end
	unloaded = false
	hasGlobalSetting = false
	tabs = {}
	currentTabInstance = nil
	tabIndex = 0

	local WindowFunctions = {Settings = Settings}
	if Settings.AcrylicBlur ~= nil then
		acrylicBlur = Settings.AcrylicBlur == true
	else
		acrylicBlur = false
	end

	local macLib = GetGui()

	local notifications = Instance.new("Frame")
	notifications.Name = "Notifications"
	notifications.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	notifications.BackgroundTransparency = 1
	notifications.BorderColor3 = Color3.fromRGB(0, 0, 0)
	notifications.BorderSizePixel = 0
	notifications.Size = UDim2.fromScale(1, 1)
	notifications.Parent = macLib
	notifications.ZIndex = 2

	local notificationsUIListLayout = Instance.new("UIListLayout")
	notificationsUIListLayout.Name = "NotificationsUIListLayout"
	notificationsUIListLayout.Padding = UDim.new(0, 10)
	notificationsUIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	notificationsUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	notificationsUIListLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	notificationsUIListLayout.Parent = notifications

	local notificationsUIPadding = Instance.new("UIPadding")
	notificationsUIPadding.Name = "NotificationsUIPadding"
	notificationsUIPadding.PaddingBottom = UDim.new(0, 10)
	notificationsUIPadding.PaddingLeft = UDim.new(0, 10)
	notificationsUIPadding.PaddingRight = UDim.new(0, 10)
	notificationsUIPadding.PaddingTop = UDim.new(0, 10)
	notificationsUIPadding.Parent = notifications

	local base = Instance.new("Frame")
	base.Name = "Base"
	base.AnchorPoint = Vector2.new(0.5, 0.5)
	base.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
	base.BackgroundTransparency = acrylicBlur and 0.02 or 0
	base.BorderColor3 = Color3.fromRGB(0, 0, 0)
	base.BorderSizePixel = 0
	base.Position = UDim2.fromScale(0.5, 0.5)
	base.Size = Settings.Size or DEFAULT_WINDOW_SIZE

	local baseUIScale = Instance.new("UIScale")
	baseUIScale.Name = "BaseUIScale"
	baseUIScale.Parent = base

	local baseUISizeConstraint = Instance.new("UISizeConstraint")
	baseUISizeConstraint.Name = "BaseUISizeConstraint"
	baseUISizeConstraint.MinSize = Settings.MinimumSize or Settings.MinSize or MIN_WINDOW_SIZE
	baseUISizeConstraint.Parent = base
	
	local baseUICorner = Instance.new("UICorner")
	baseUICorner.Name = "BaseUICorner"
	baseUICorner.CornerRadius = UDim.new(0, 0)
	baseUICorner.Parent = base

	local baseUIStroke = Instance.new("UIStroke")
	baseUIStroke.Name = "BaseUIStroke"
	baseUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	baseUIStroke.Color = Color3.fromRGB(255, 255, 255)
	baseUIStroke.Transparency = 0.9
	baseUIStroke.Parent = base

	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	sidebar.BackgroundTransparency = 1
	sidebar.BorderColor3 = Color3.fromRGB(0, 0, 0)
	sidebar.BorderSizePixel = 0
	sidebar.Position = UDim2.fromScale(-3.52e-08, 4.69e-08)
	sidebar.Size = UDim2.fromScale(0.325, 1)

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.AnchorPoint = Vector2.new(1, 0)
	divider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	divider.BackgroundTransparency = 0.9
	divider.BorderColor3 = Color3.fromRGB(0, 0, 0)
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromScale(1, 0)
	divider.Size = UDim2.new(0, 1, 1, 0)
	divider.Parent = sidebar

	local dividerInteract = Instance.new("TextButton")
	dividerInteract.Name = "DividerInteract"
	dividerInteract.AnchorPoint = Vector2.new(0.5, 0)
	dividerInteract.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	dividerInteract.BackgroundTransparency = 1
	dividerInteract.BorderColor3 = Color3.fromRGB(0, 0, 0)
	dividerInteract.BorderSizePixel = 0
	dividerInteract.FontFace = SafeFont("rbxasset://fonts/families/SourceSansPro.json")
	dividerInteract.Position = UDim2.fromScale(0.5, 0)
	dividerInteract.Size = UDim2.new(1, 6, 1, 0)
	dividerInteract.Text = ""
	dividerInteract.TextColor3 = Color3.fromRGB(0, 0, 0)
	dividerInteract.TextSize = 14
	dividerInteract.Parent = divider

	local windowControls = Instance.new("Frame")
	windowControls.Name = "WindowControls"
	windowControls.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	windowControls.BackgroundTransparency = 1
	windowControls.BorderColor3 = Color3.fromRGB(0, 0, 0)
	windowControls.BorderSizePixel = 0
	windowControls.Size = UDim2.new(1, 0, 0, 31)

	local controls = Instance.new("Frame")
	controls.Name = "Controls"
	controls.BackgroundColor3 = Color3.fromRGB(119, 174, 94)
	controls.BackgroundTransparency = 1
	controls.BorderColor3 = Color3.fromRGB(0, 0, 0)
	controls.BorderSizePixel = 0
	controls.Size = UDim2.fromScale(1, 1)

	local uIListLayout = Instance.new("UIListLayout")
	uIListLayout.Name = "UIListLayout"
	uIListLayout.Padding = UDim.new(0, 5)
	uIListLayout.FillDirection = Enum.FillDirection.Horizontal
	uIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	uIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	uIListLayout.Parent = controls

	local uIPadding = Instance.new("UIPadding")
	uIPadding.Name = "UIPadding"
	uIPadding.PaddingLeft = UDim.new(0, 11)
	uIPadding.Parent = controls

	local windowControlSettings = {
		sizes = { enabled = UDim2.fromOffset(8, 8), disabled = UDim2.fromOffset(7, 7) },
		transparencies = { enabled = 0, disabled = 1 },
		strokeTransparency = 0.9,
	}

	local stroke = Instance.new("UIStroke")
	stroke.Name = "BaseUIStroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = windowControlSettings.strokeTransparency

	local exit = Instance.new("TextButton")
	exit.Name = "Exit"
	exit.FontFace = SafeFont("rbxasset://fonts/families/SourceSansPro.json")
	exit.Text = ""
	exit.TextColor3 = Color3.fromRGB(0, 0, 0)
	exit.TextSize = 14
	exit.AutoButtonColor = false
	exit.BackgroundColor3 = Color3.fromRGB(250, 93, 86)
	exit.BorderColor3 = Color3.fromRGB(0, 0, 0)
	exit.BorderSizePixel = 0

	local uICorner = Instance.new("UICorner")
	uICorner.Name = "UICorner"
	uICorner.CornerRadius = UDim.new(0, 0)
	uICorner.Parent = exit

	exit.Parent = controls

	local minimize = Instance.new("TextButton")
	minimize.Name = "Minimize"
	minimize.FontFace = SafeFont("rbxasset://fonts/families/SourceSansPro.json")
	minimize.Text = ""
	minimize.TextColor3 = Color3.fromRGB(0, 0, 0)
	minimize.TextSize = 14
	minimize.AutoButtonColor = false
	minimize.BackgroundColor3 = Color3.fromRGB(252, 190, 57)
	minimize.BorderColor3 = Color3.fromRGB(0, 0, 0)
	minimize.BorderSizePixel = 0
	minimize.LayoutOrder = 1

	local uICorner1 = Instance.new("UICorner")
	uICorner1.Name = "UICorner"
	uICorner1.CornerRadius = UDim.new(0, 0)
	uICorner1.Parent = minimize

	minimize.Parent = controls

	local maximize = Instance.new("TextButton")
	maximize.Name = "Maximize"
	maximize.FontFace = SafeFont("rbxasset://fonts/families/SourceSansPro.json")
	maximize.Text = ""
	maximize.TextColor3 = Color3.fromRGB(0, 0, 0)
	maximize.TextSize = 14
	maximize.AutoButtonColor = false
	maximize.BackgroundColor3 = Color3.fromRGB(119, 174, 94)
	maximize.BorderColor3 = Color3.fromRGB(0, 0, 0)
	maximize.BorderSizePixel = 0
	maximize.LayoutOrder = 1

	local uICorner2 = Instance.new("UICorner")
	uICorner2.Name = "UICorner"
	uICorner2.CornerRadius = UDim.new(0, 0)
	uICorner2.Parent = maximize

	maximize.Parent = controls

	local function applyState(button, enabled)
		local size = enabled and windowControlSettings.sizes.enabled or windowControlSettings.sizes.disabled
		local transparency = enabled and windowControlSettings.transparencies.enabled or windowControlSettings.transparencies.disabled

		button.Size = size
		button.BackgroundTransparency = transparency
		button.Active = enabled
		button.Interactable = enabled

		for _, child in ipairs(button:GetChildren()) do
			if child:IsA("UIStroke") then
				child.Transparency = transparency
			end
		end
		if not enabled then
			stroke:Clone().Parent = button
		end
	end

	applyState(maximize, false)

	local controlsList = {exit, minimize}
	for _, button in pairs(controlsList) do
		local buttonName = button.Name
		local isEnabled = true

		if Settings.DisabledWindowControls and table.find(Settings.DisabledWindowControls, buttonName) then
			isEnabled = false
		end

		applyState(button, isEnabled)
	end

	controls.Parent = windowControls

	local divider1 = Instance.new("Frame")
	divider1.Name = "Divider"
	divider1.AnchorPoint = Vector2.new(0, 1)
	divider1.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	divider1.BackgroundTransparency = 0.9
	divider1.BorderColor3 = Color3.fromRGB(0, 0, 0)
	divider1.BorderSizePixel = 0
	divider1.Position = UDim2.fromScale(0, 1)
	divider1.Size = UDim2.new(1, 0, 0, 1)
	divider1.Parent = windowControls

	windowControls.Parent = sidebar

	local information = Instance.new("Frame")
	information.Name = "Information"
	information.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	information.BackgroundTransparency = 1
	information.BorderColor3 = Color3.fromRGB(0, 0, 0)
	information.BorderSizePixel = 0
	information.Position = UDim2.fromOffset(0, 31)
	information.Size = UDim2.new(1, 0, 0, 60)

	local divider2 = Instance.new("Frame")
	divider2.Name = "Divider"
	divider2.AnchorPoint = Vector2.new(0, 1)
	divider2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	divider2.BackgroundTransparency = 0.9
	divider2.BorderColor3 = Color3.fromRGB(0, 0, 0)
	divider2.BorderSizePixel = 0
	divider2.Position = UDim2.fromScale(0, 1)
	divider2.Size = UDim2.new(1, 0, 0, 1)
	divider2.Parent = information

	local informationHolder = Instance.new("Frame")
	informationHolder.Name = "InformationHolder"
	informationHolder.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	informationHolder.BackgroundTransparency = 1
	informationHolder.BorderColor3 = Color3.fromRGB(0, 0, 0)
	informationHolder.BorderSizePixel = 0
	informationHolder.Size = UDim2.fromScale(1, 1)

	local informationHolderUIPadding = Instance.new("UIPadding")
	informationHolderUIPadding.Name = "InformationHolderUIPadding"
	informationHolderUIPadding.PaddingBottom = UDim.new(0, 10)
	informationHolderUIPadding.PaddingLeft = UDim.new(0, 23)
	informationHolderUIPadding.PaddingRight = UDim.new(0, 22)
	informationHolderUIPadding.PaddingTop = UDim.new(0, 10)
	informationHolderUIPadding.Parent = informationHolder

	local globalSettingsButton = Instance.new("ImageButton")
	globalSettingsButton.Name = "GlobalSettingsButton"
	globalSettingsButton.Image = assets.globe
	globalSettingsButton.ImageTransparency = 0.5
	globalSettingsButton.AnchorPoint = Vector2.new(1, 0.5)
	globalSettingsButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	globalSettingsButton.BackgroundTransparency = 1
	globalSettingsButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	globalSettingsButton.BorderSizePixel = 0
	globalSettingsButton.Position = UDim2.fromScale(1, 0.5)
	globalSettingsButton.Size = UDim2.fromOffset(16,16)
	globalSettingsButton.Parent = informationHolder

	local function ChangeGlobalSettingsButtonState(State)
		if State == "Default" then
			Tween(globalSettingsButton, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {
				ImageTransparency = 0.5
			}):Play()
		elseif State == "Hover" then
			Tween(globalSettingsButton, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {
				ImageTransparency = 0.3
			}):Play()
		end
	end

	globalSettingsButton.MouseEnter:Connect(function()
		ChangeGlobalSettingsButtonState("Hover")
	end)
	globalSettingsButton.MouseLeave:Connect(function()
		ChangeGlobalSettingsButtonState("Default")
	end)

	local titleFrame = Instance.new("Frame")
	titleFrame.Name = "TitleFrame"
	titleFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	titleFrame.BackgroundTransparency = 1
	titleFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	titleFrame.BorderSizePixel = 0
	titleFrame.Size = UDim2.fromScale(1, 1)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.FontFace = SafeFont(
		assets.interFont,
		Enum.FontWeight.SemiBold,
		Enum.FontStyle.Normal
	)
	title.Text = Settings.Title
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.RichText = true
	title.TextSize = 18
	title.TextTransparency = 0.1
	title.TextTruncate = Enum.TextTruncate.SplitWord
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Top
	title.AutomaticSize = Enum.AutomaticSize.Y
	title.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	title.BackgroundTransparency = 1
	title.BorderColor3 = Color3.fromRGB(0, 0, 0)
	title.BorderSizePixel = 0
	title.Size = UDim2.new(1, -20, 0, 0)
	title.Parent = titleFrame

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.FontFace = SafeFont(
		assets.interFont,
		Enum.FontWeight.Medium,
		Enum.FontStyle.Normal
	)
	subtitle.RichText = true
	subtitle.Text = Settings.Subtitle
	subtitle.RichText = true
	subtitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	subtitle.TextSize = 12
	subtitle.TextTransparency = 0.7
	subtitle.TextTruncate = Enum.TextTruncate.SplitWord
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextYAlignment = Enum.TextYAlignment.Top
	subtitle.AutomaticSize = Enum.AutomaticSize.Y
	subtitle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	subtitle.BackgroundTransparency = 1
	subtitle.BorderColor3 = Color3.fromRGB(0, 0, 0)
	subtitle.BorderSizePixel = 0
	subtitle.LayoutOrder = 1
	subtitle.Size = UDim2.new(1, -20, 0, 0)
	subtitle.Parent = titleFrame

	local titleFrameUIListLayout = Instance.new("UIListLayout")
	titleFrameUIListLayout.Name = "TitleFrameUIListLayout"
	titleFrameUIListLayout.Padding = UDim.new(0, 3)
	titleFrameUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	titleFrameUIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	titleFrameUIListLayout.Parent = titleFrame

	titleFrame.Parent = informationHolder

	informationHolder.Parent = information

	information.Parent = sidebar

	local sidebarGroup = Instance.new("Frame")
	sidebarGroup.Name = "SidebarGroup"
	sidebarGroup.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	sidebarGroup.BackgroundTransparency = 1
	sidebarGroup.BorderColor3 = Color3.fromRGB(0, 0, 0)
	sidebarGroup.BorderSizePixel = 0
	sidebarGroup.Position = UDim2.fromOffset(0, 91)
	sidebarGroup.Size = UDim2.new(1, 0, 1, -91)

	local userInfo = Instance.new("Frame")
	userInfo.Name = "UserInfo"
	userInfo.AnchorPoint = Vector2.new(0, 1)
	userInfo.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	userInfo.BackgroundTransparency = 1
	userInfo.BorderColor3 = Color3.fromRGB(0, 0, 0)
	userInfo.BorderSizePixel = 0
	userInfo.Position = UDim2.fromScale(0, 1)
	userInfo.Size = UDim2.new(1, 0, 0, 107)

	local informationGroup = Instance.new("Frame")
	informationGroup.Name = "InformationGroup"
	informationGroup.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	informationGroup.BackgroundTransparency = 1
	informationGroup.BorderColor3 = Color3.fromRGB(0, 0, 0)
	informationGroup.BorderSizePixel = 0
	informationGroup.Size = UDim2.fromScale(1, 1)

	local informationGroupUIPadding = Instance.new("UIPadding")
	informationGroupUIPadding.Name = "InformationGroupUIPadding"
	informationGroupUIPadding.PaddingBottom = UDim.new(0, 17)
	informationGroupUIPadding.PaddingLeft = UDim.new(0, 25)
	informationGroupUIPadding.Parent = informationGroup

	local informationGroupUIListLayout = Instance.new("UIListLayout")
	informationGroupUIListLayout.Name = "InformationGroupUIListLayout"
	informationGroupUIListLayout.FillDirection = Enum.FillDirection.Horizontal
	informationGroupUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	informationGroupUIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	informationGroupUIListLayout.Parent = informationGroup

	local userId = LocalPlayer.UserId
	local thumbType = Enum.ThumbnailType.AvatarBust
	local thumbSize = Enum.ThumbnailSize.Size48x48
	local headshotImage, isReady = Players:GetUserThumbnailAsync(userId, thumbType, thumbSize)

	local headshot = Instance.new("ImageLabel")
	headshot.Name = "Headshot"
	headshot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	headshot.BackgroundTransparency = 1
	headshot.BorderColor3 = Color3.fromRGB(0, 0, 0)
	headshot.BorderSizePixel = 0
	headshot.Size = UDim2.fromOffset(32, 32)
	headshot.Image = (isReady and headshotImage) or "rbxassetid://0"

	local uICorner3 = Instance.new("UICorner")
	uICorner3.Name = "UICorner"
	uICorner3.CornerRadius = UDim.new(0, 0)
	uICorner3.Parent = headshot

	local baseUIStroke2 = Instance.new("UIStroke")
	baseUIStroke2.Name = "BaseUIStroke"
	baseUIStroke2.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	baseUIStroke2.Color = Color3.fromRGB(255, 255, 255)
	baseUIStroke2.Transparency = 0.9
	baseUIStroke2.Parent = headshot

	headshot.Parent = informationGroup

	local userAndDisplayFrame = Instance.new("Frame")
	userAndDisplayFrame.Name = "UserAndDisplayFrame"
	userAndDisplayFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	userAndDisplayFrame.BackgroundTransparency = 1
	userAndDisplayFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	userAndDisplayFrame.BorderSizePixel = 0
	userAndDisplayFrame.LayoutOrder = 1
	userAndDisplayFrame.Size = UDim2.new(1, -42, 0, 32)

	local displayName = Instance.new("TextLabel")
	displayName.Name = "DisplayName"
	displayName.FontFace = SafeFont(
		assets.interFont,
		Enum.FontWeight.SemiBold,
		Enum.FontStyle.Normal
	)
	displayName.Text = LocalPlayer.DisplayName
	displayName.TextColor3 = Color3.fromRGB(255, 255, 255)
	displayName.TextSize = 13
	displayName.TextTransparency = 0.1
	displayName.TextTruncate = Enum.TextTruncate.SplitWord
	displayName.TextXAlignment = Enum.TextXAlignment.Left
	displayName.TextYAlignment = Enum.TextYAlignment.Top
	displayName.AutomaticSize = Enum.AutomaticSize.XY
	displayName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	displayName.BackgroundTransparency = 1
	displayName.BorderColor3 = Color3.fromRGB(0, 0, 0)
	displayName.BorderSizePixel = 0
	displayName.Parent = userAndDisplayFrame
	displayName.Size = UDim2.fromScale(1,0)

	local userAndDisplayFrameUIPadding = Instance.new("UIPadding")
	userAndDisplayFrameUIPadding.Name = "UserAndDisplayFrameUIPadding"
	userAndDisplayFrameUIPadding.PaddingLeft = UDim.new(0, 8)
	userAndDisplayFrameUIPadding.PaddingTop = UDim.new(0, 3)
	userAndDisplayFrameUIPadding.Parent = userAndDisplayFrame

	local userAndDisplayFrameUIListLayout = Instance.new("UIListLayout")
	userAndDisplayFrameUIListLayout.Name = "UserAndDisplayFrameUIListLayout"
	userAndDisplayFrameUIListLayout.Padding = UDim.new(0, 1)
	userAndDisplayFrameUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	userAndDisplayFrameUIListLayout.Parent = userAndDisplayFrame

	local username = Instance.new("TextLabel")
	username.Name = "Username"
	username.FontFace = SafeFont(
		assets.interFont,
		Enum.FontWeight.SemiBold,
		Enum.FontStyle.Normal
	)
	username.Text = "@" .. LocalPlayer.Name
	username.TextColor3 = Color3.fromRGB(255, 255, 255)
	username.TextSize = 12
	username.TextTransparency = 0.7
	username.TextTruncate = Enum.TextTruncate.SplitWord
	username.TextXAlignment = Enum.TextXAlignment.Left
	username.TextYAlignment = Enum.TextYAlignment.Top
	username.AutomaticSize = Enum.AutomaticSize.XY
	username.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	username.BackgroundTransparency = 1
	username.BorderColor3 = Color3.fromRGB(0, 0, 0)
	username.BorderSizePixel = 0
	username.LayoutOrder = 1
	username.Parent = userAndDisplayFrame
	username.Size = UDim2.fromScale(1,0)

	userAndDisplayFrame.Parent = informationGroup

	informationGroup.Parent = userInfo

	local userInfoUIPadding = Instance.new("UIPadding")
	userInfoUIPadding.Name = "UserInfoUIPadding"
	userInfoUIPadding.PaddingLeft = UDim.new(0, 10)
	userInfoUIPadding.PaddingRight = UDim.new(0, 10)
	userInfoUIPadding.Parent = userInfo

	userInfo.Parent = sidebarGroup

	local sidebarGroupUIPadding = Instance.new("UIPadding")
	sidebarGroupUIPadding.Name = "SidebarGroupUIPadding"
	sidebarGroupUIPadding.PaddingLeft = UDim.new(0, 10)
	sidebarGroupUIPadding.PaddingRight = UDim.new(0, 10)
	sidebarGroupUIPadding.PaddingTop = UDim.new(0, 31)
	sidebarGroupUIPadding.Parent = sidebarGroup

	local tabSwitchers = Instance.new("Frame")
	tabSwitchers.Name = "TabSwitchers"
	tabSwitchers.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	tabSwitchers.BackgroundTransparency = 1
	tabSwitchers.BorderColor3 = Color3.fromRGB(0, 0, 0)
	tabSwitchers.BorderSizePixel = 0
	tabSwitchers.Size = UDim2.new(1, 0, 1, -107)

	local tabSwitchersScrollingFrame = Instance.new("ScrollingFrame")
	tabSwitchersScrollingFrame.Name = "TabSwitchersScrollingFrame"
	tabSwitchersScrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	tabSwitchersScrollingFrame.BottomImage = ""
	tabSwitchersScrollingFrame.CanvasSize = UDim2.new()
	tabSwitchersScrollingFrame.ScrollBarImageTransparency = 0.8
	tabSwitchersScrollingFrame.ScrollBarThickness = 1
	tabSwitchersScrollingFrame.TopImage = ""
	tabSwitchersScrollingFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	tabSwitchersScrollingFrame.BackgroundTransparency = 1
	tabSwitchersScrollingFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	tabSwitchersScrollingFrame.BorderSizePixel = 0
	tabSwitchersScrollingFrame.Size = UDim2.fromScale(1, 1)

	local tabSwitchersScrollingFrameUIListLayout = Instance.new("UIListLayout")
	tabSwitchersScrollingFrameUIListLayout.Name = "TabSwitchersScrollingFrameUIListLayout"
	tabSwitchersScrollingFrameUIListLayout.Padding = UDim.new(0, 17)
	tabSwitchersScrollingFrameUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabSwitchersScrollingFrameUIListLayout.Parent = tabSwitchersScrollingFrame

	local tabSwitchersScrollingFrameUIPadding = Instance.new("UIPadding")
	tabSwitchersScrollingFrameUIPadding.Name = "TabSwitchersScrollingFrameUIPadding"
	tabSwitchersScrollingFrameUIPadding.PaddingTop = UDim.new(0, 2)
	tabSwitchersScrollingFrameUIPadding.Parent = tabSwitchersScrollingFrame

	tabSwitchersScrollingFrame.Parent = tabSwitchers

	tabSwitchers.Parent = sidebarGroup

	sidebarGroup.Parent = sidebar

	sidebar.Parent = base

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.AnchorPoint = Vector2.new(1, 0)
	content.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	content.BackgroundTransparency = 1
	content.BorderColor3 = Color3.fromRGB(0, 0, 0)
	content.BorderSizePixel = 0
	content.Position = UDim2.fromScale(1, 4.69e-08)
	content.Size = UDim2.new(0, (base.AbsoluteSize.X - sidebar.AbsoluteSize.X), 1, 0)

	local resizingContent = false
	local defaultSidebarWidth = sidebar.AbsoluteSize.X
	local initialMouseX, initialSidebarWidth
	local snapRange = 20
	local minSidebarWidth = 107
	local maxSidebarWidth = base.AbsoluteSize.X - minSidebarWidth

	local TweenSettings = {
		DefaultTransparency = 0.9,
		HoverTransparency = 0.85,

		EasingStyle = Enum.EasingStyle.Sine
	}

	local function ChangeState(State)
		Tween(divider, TweenInfo.new(0.2, TweenSettings.EasingStyle), {
			BackgroundTransparency = State == "Idle" and TweenSettings.DefaultTransparency or TweenSettings.HoverTransparency
		}):Play()  
	end

	dividerInteract.MouseEnter:Connect(function()
		ChangeState("Hover")
	end)
	dividerInteract.MouseLeave:Connect(function()
		ChangeState("Idle")
	end)

	dividerInteract.MouseButton1Down:Connect(function()
		resizingContent = true
		initialMouseX = UserInputService:GetMouseLocation().X
		initialSidebarWidth = sidebar.AbsoluteSize.X
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			resizingContent = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if resizingContent and input.UserInputType == Enum.UserInputType.MouseMovement then
			local deltaX = UserInputService:GetMouseLocation().X - initialMouseX
			local newSidebarWidth = initialSidebarWidth + deltaX

			if math.abs(newSidebarWidth - defaultSidebarWidth) < snapRange then
				newSidebarWidth = defaultSidebarWidth
			else
				newSidebarWidth = math.clamp(newSidebarWidth, minSidebarWidth, maxSidebarWidth)
			end

			sidebar.Size = UDim2.new(0, newSidebarWidth, 1, 0)
			content.Size = UDim2.new(0, base.AbsoluteSize.X - newSidebarWidth, 1, 0)
		end
	end)

	local topbar = Instance.new("Frame")
	topbar.Name = "Topbar"
	topbar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	topbar.BackgroundTransparency = 1
	topbar.BorderColor3 = Color3.fromRGB(0, 0, 0)
	topbar.BorderSizePixel = 0
	topbar.Size = UDim2.new(1, 0, 0, 63)

	local divider4 = Instance.new("Frame")
	divider4.Name = "Divider"
	divider4.AnchorPoint = Vector2.new(0, 1)
	divider4.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	divider4.BackgroundTransparency = 0.9
	divider4.BorderColor3 = Color3.fromRGB(0, 0, 0)
	divider4.BorderSizePixel = 0
	divider4.Position = UDim2.fromScale(0, 1)
	divider4.Size = UDim2.new(1, 0, 0, 1)
	divider4.Parent = topbar

	local elements = Instance.new("Frame")
	elements.Name = "Elements"
	elements.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	elements.BackgroundTransparency = 1
	elements.BorderColor3 = Color3.fromRGB(0, 0, 0)
	elements.BorderSizePixel = 0
	elements.Size = UDim2.fromScale(1, 1)

	local uIPadding2 = Instance.new("UIPadding")
	uIPadding2.Name = "UIPadding"
	uIPadding2.PaddingLeft = UDim.new(0, 20)
	uIPadding2.PaddingRight = UDim.new(0, 20)
	uIPadding2.Parent = elements

	local moveIcon = Instance.new("ImageButton")
	moveIcon.Name = "MoveIcon"
	moveIcon.Image = assets.transform
	moveIcon.ImageTransparency = 0.7
	moveIcon.AnchorPoint = Vector2.new(1, 0.5)
	moveIcon.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	moveIcon.BackgroundTransparency = 1
	moveIcon.BorderColor3 = Color3.fromRGB(0, 0, 0)
	moveIcon.BorderSizePixel = 0
	moveIcon.Position = UDim2.fromScale(1, 0.5)
	moveIcon.Size = UDim2.fromOffset(15, 15)
	moveIcon.Parent = elements
	moveIcon.Visible = not Settings.DragStyle or Settings.DragStyle == 1

	local interact = Instance.new("TextButton")
	interact.Name = "Interact"
	interact.FontFace = SafeFont("rbxasset://fonts/families/SourceSansPro.json")
	interact.Text = ""
	interact.TextColor3 = Color3.fromRGB(0, 0, 0)
	interact.TextSize = 14
	interact.AnchorPoint = Vector2.new(0.5, 0.5)
	interact.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	interact.BackgroundTransparency = 1
	interact.BorderColor3 = Color3.fromRGB(0, 0, 0)
	interact.BorderSizePixel = 0
	interact.Position = UDim2.fromScale(0.5, 0.5)
	interact.Size = UDim2.fromOffset(40, 40)
	interact.Parent = moveIcon

	local function ChangemoveIconState(State)
		if State == "Default" then
			Tween(moveIcon, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {
				ImageTransparency = 0.7
			}):Play()
		elseif State == "Hover" then
			Tween(moveIcon, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {
				ImageTransparency = 0.4
			}):Play()
		end
	end

	interact.MouseEnter:Connect(function()
		ChangemoveIconState("Hover")
	end)
	interact.MouseLeave:Connect(function()
		ChangemoveIconState("Default")
	end)

	local dragging_ = false
	local dragInput
	local dragStart
	local startPos

	local function update(input)
		local delta = input.Position - dragStart
		base.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end

	local function onDragStart(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging_ = true
			dragStart = input.Position
			startPos = base.Position

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging_ = false
				end
			end)
		end
	end

	local function onDragUpdate(input)
		if dragging_ and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			dragInput = input
		end
	end

	if not Settings.DragStyle or Settings.DragStyle == 1 then
		interact.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				onDragStart(input)
			end
		end)

		interact.InputChanged:Connect(onDragUpdate)

		UserInputService.InputChanged:Connect(function(input)
			if input == dragInput and dragging_ then
				update(input)
			end
		end)

		interact.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging_ = false
			end
		end)
	elseif Settings.DragStyle == 2 then
		base.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				onDragStart(input)
			end
		end)

		base.InputChanged:Connect(onDragUpdate)

		UserInputService.InputChanged:Connect(function(input)
			if input == dragInput and dragging_ then
				update(input)
			end
		end)

		base.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging_ = false
			end
		end)
	end

	local currentTab = Instance.new("TextLabel")
	currentTab.Name = "CurrentTab"
	currentTab.FontFace = SafeFont(assets.interFont)
	currentTab.RichText = true
	currentTab.Text = ""
	currentTab.RichText = true
	currentTab.TextColor3 = Color3.fromRGB(255, 255, 255)
	currentTab.TextSize = 15
	currentTab.TextTransparency = 0.5
	currentTab.TextTruncate = Enum.TextTruncate.SplitWord
	currentTab.TextXAlignment = Enum.TextXAlignment.Left
	currentTab.TextYAlignment = Enum.TextYAlignment.Top
	currentTab.AnchorPoint = Vector2.new(0, 0.5)
	currentTab.AutomaticSize = Enum.AutomaticSize.Y
	currentTab.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	currentTab.BackgroundTransparency = 1
	currentTab.BorderColor3 = Color3.fromRGB(0, 0, 0)
	currentTab.BorderSizePixel = 0
	currentTab.Position = UDim2.fromScale(0, 0.5)
	currentTab.Size = UDim2.fromScale(0.9, 0)
	currentTab.Parent = elements

	elements.Parent = topbar

	topbar.Parent = content

	content.Parent = base

	local globalSettings = Instance.new("Frame")
	globalSettings.Name = "GlobalSettings"
	globalSettings.AutomaticSize = Enum.AutomaticSize.XY
	globalSettings.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
	globalSettings.BorderColor3 = Color3.fromRGB(0, 0, 0)
	globalSettings.BorderSizePixel = 0
	globalSettings.Position = UDim2.fromScale(0.298, 0.104)

	local globalSettingsUIStroke = Instance.new("UIStroke")
	globalSettingsUIStroke.Name = "GlobalSettingsUIStroke"
	globalSettingsUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	globalSettingsUIStroke.Color = Color3.fromRGB(255, 255, 255)
	globalSettingsUIStroke.Transparency = 0.9
	globalSettingsUIStroke.Parent = globalSettings

	local globalSettingsUICorner = Instance.new("UICorner")
	globalSettingsUICorner.Name = "GlobalSettingsUICorner"
	globalSettingsUICorner.CornerRadius = UDim.new(0, 0)
	globalSettingsUICorner.Parent = globalSettings

	local globalSettingsUIPadding = Instance.new("UIPadding")
	globalSettingsUIPadding.Name = "GlobalSettingsUIPadding"
	globalSettingsUIPadding.PaddingBottom = UDim.new(0, 10)
	globalSettingsUIPadding.PaddingTop = UDim.new(0, 10)
	globalSettingsUIPadding.Parent = globalSettings

	local globalSettingsUIListLayout = Instance.new("UIListLayout")
	globalSettingsUIListLayout.Name = "GlobalSettingsUIListLayout"
	globalSettingsUIListLayout.Padding = UDim.new(0, 5)
	globalSettingsUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	globalSettingsUIListLayout.Parent = globalSettings

	local globalSettingsUIScale = Instance.new("UIScale")
	globalSettingsUIScale.Name = "GlobalSettingsUIScale"
	globalSettingsUIScale.Scale = 1e-07
	globalSettingsUIScale.Parent = globalSettings
	globalSettings.Parent = base
	base.Parent = macLib
	WindowFunctions.Gui = macLib
	WindowFunctions.Base = base
	WindowFunctions.Notifications = notifications
	WindowFunctions.GlobalSettings = globalSettings
	WindowFunctions.Content = content
	WindowFunctions.Sidebar = sidebar

	function WindowFunctions:UpdateTitle(NewTitle)
		title.Text = NewTitle
	end

	function WindowFunctions:UpdateSubtitle(NewSubtitle)
		subtitle.Text = NewSubtitle
	end

	function WindowFunctions:AddProfile(Settings)
		Settings = Settings or {}
		if self._Profile and type(self._Profile.Destroy) == "function" then
			self._Profile:Destroy()
		end

		informationGroup.Visible = false

		local profileIcon = ResolveImageAsset(Settings.Icon or Settings.Avatar or Settings.Image, assets.tirexIcon)
		local profile = {}

		local profileButton = Instance.new("ImageButton")
		profileButton.Name = "ProfileButton"
		profileButton.AutoButtonColor = false
		profileButton.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
		profileButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
		profileButton.BorderSizePixel = 0
		profileButton.AnchorPoint = Vector2.new(0, 1)
		profileButton.Position = UDim2.new(0, 15, 1, -25)
		profileButton.Size = UDim2.fromOffset(42, 42)
		profileButton.Image = profileIcon
		profileButton.ScaleType = Enum.ScaleType.Fit
		profileButton.Parent = userInfo

		local profileButtonCorner = Instance.new("UICorner")
		profileButtonCorner.CornerRadius = UDim.new(0, 0)
		profileButtonCorner.Parent = profileButton

		local profileButtonStroke = Instance.new("UIStroke")
		profileButtonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		profileButtonStroke.Color = Color3.fromRGB(255, 255, 255)
		profileButtonStroke.Transparency = 0.88
		profileButtonStroke.Parent = profileButton

		local profileModal = Instance.new("Frame")
		profileModal.Name = "ProfileModal"
		profileModal.AnchorPoint = Vector2.new(0, 1)
		profileModal.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
		profileModal.BorderColor3 = Color3.fromRGB(0, 0, 0)
		profileModal.BorderSizePixel = 0
		profileModal.Position = UDim2.new(0, 18, 1, -18)
		profileModal.Size = UDim2.fromOffset(342, 246)
		profileModal.Visible = false
		profileModal.ZIndex = 10
		profileModal.Parent = base

		local profileModalCorner = Instance.new("UICorner")
		profileModalCorner.CornerRadius = UDim.new(0, 0)
		profileModalCorner.Parent = profileModal

		local profileModalStroke = Instance.new("UIStroke")
		profileModalStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		profileModalStroke.Color = Color3.fromRGB(255, 255, 255)
		profileModalStroke.Transparency = 0.86
		profileModalStroke.Parent = profileModal

		local header = Instance.new("Frame")
		header.Name = "ProfileHeader"
		header.BackgroundTransparency = 1
		header.BorderSizePixel = 0
		header.Size = UDim2.new(1, 0, 0, 56)
		header.ZIndex = 11
		header.Parent = profileModal

		local headerText = Instance.new("TextLabel")
		headerText.Name = "HeaderText"
		headerText.BackgroundTransparency = 1
		headerText.FontFace = SafeFont(assets.interFont, Enum.FontWeight.Medium, Enum.FontStyle.Normal)
		headerText.Text = Settings.Title or "Profile"
		headerText.TextColor3 = Color3.fromRGB(255, 255, 255)
		headerText.TextSize = 15
		headerText.TextXAlignment = Enum.TextXAlignment.Left
		headerText.Position = UDim2.fromOffset(16, 0)
		headerText.Size = UDim2.new(1, -58, 1, 0)
		headerText.ZIndex = 11
		headerText.Parent = header

		local close = Instance.new("TextButton")
		close.Name = "Close"
		close.AutoButtonColor = false
		close.BackgroundTransparency = 1
		close.BorderSizePixel = 0
		close.FontFace = SafeFont(assets.interFont, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
		close.Text = "x"
		close.TextColor3 = Color3.fromRGB(220, 220, 220)
		close.TextSize = 18
		close.AnchorPoint = Vector2.new(1, 0.5)
		close.Position = UDim2.new(1, -17, 0.5, 0)
		close.Size = UDim2.fromOffset(24, 24)
		close.ZIndex = 11
		close.Parent = header

		local card = Instance.new("Frame")
		card.Name = "ProfileCard"
		card.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
		card.BorderSizePixel = 0
		card.Position = UDim2.fromOffset(16, 64)
		card.Size = UDim2.new(1, -32, 0, 124)
		card.ZIndex = 11
		card.Parent = profileModal

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 0)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		cardStroke.Color = Color3.fromRGB(255, 255, 255)
		cardStroke.Transparency = 0.94
		cardStroke.Parent = card

		local avatar = Instance.new("ImageLabel")
		avatar.Name = "ProfileAvatar"
		avatar.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
		avatar.BorderSizePixel = 0
		avatar.Position = UDim2.fromOffset(14, 15)
		avatar.Size = UDim2.fromOffset(58, 58)
		avatar.Image = profileIcon
		avatar.ScaleType = Enum.ScaleType.Fit
		avatar.ZIndex = 12
		avatar.Parent = card

		local avatarCorner = Instance.new("UICorner")
		avatarCorner.CornerRadius = UDim.new(0, 0)
		avatarCorner.Parent = avatar

		local tier = Instance.new("TextLabel")
		tier.Name = "ProfileTier"
		tier.BackgroundColor3 = Color3.fromRGB(218, 218, 218)
		tier.BorderSizePixel = 0
		tier.FontFace = SafeFont(assets.interFont, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
		tier.Text = Settings.Plan or Settings.Tier or "Free"
		tier.TextColor3 = Color3.fromRGB(0, 0, 0)
		tier.TextSize = 10
		tier.Position = UDim2.fromOffset(14, 80)
		tier.Size = UDim2.fromOffset(58, 19)
		tier.ZIndex = 12
		tier.Parent = card

		local tierCorner = Instance.new("UICorner")
		tierCorner.CornerRadius = UDim.new(0, 0)
		tierCorner.Parent = tier

		local rows = Instance.new("Frame")
		rows.Name = "ProfileRows"
		rows.BackgroundTransparency = 1
		rows.BorderSizePixel = 0
		rows.Position = UDim2.fromOffset(84, 16)
		rows.Size = UDim2.new(1, -100, 1, -26)
		rows.ZIndex = 12
		rows.Parent = card

		local rowsLayout = Instance.new("UIListLayout")
		rowsLayout.Padding = UDim.new(0, 9)
		rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowsLayout.Parent = rows

		local valueLabels = {}
		local function addProfileRow(rowName, rowValue)
			local row = Instance.new("Frame")
			row.Name = rowName:gsub("%s+", "") .. "Row"
			row.BackgroundTransparency = 1
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, 0, 0, 16)
			row.ZIndex = 12
			row.Parent = rows

			local label = Instance.new("TextLabel")
			label.Name = "Label"
			label.BackgroundTransparency = 1
			label.FontFace = SafeFont(assets.interFont, Enum.FontWeight.Medium, Enum.FontStyle.Normal)
			label.Text = rowName
			label.TextColor3 = Color3.fromRGB(170, 170, 170)
			label.TextSize = 11
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.Size = UDim2.fromOffset(92, 16)
			label.ZIndex = 13
			label.Parent = row

			local value = Instance.new("TextLabel")
			value.Name = "Value"
			value.BackgroundTransparency = 1
			value.FontFace = SafeFont(assets.interFont, Enum.FontWeight.Medium, Enum.FontStyle.Normal)
			value.Text = tostring(rowValue or "-")
			value.TextColor3 = Color3.fromRGB(245, 245, 245)
			value.TextSize = 11
			value.TextXAlignment = Enum.TextXAlignment.Right
			value.TextTruncate = Enum.TextTruncate.AtEnd
			value.Position = UDim2.fromOffset(94, 0)
			value.Size = UDim2.new(1, -94, 0, 16)
			value.ZIndex = 13
			value.Parent = row

			valueLabels[rowName] = value
			return value
		end

		addProfileRow("Username", Settings.Username or Settings.User or (LocalPlayer and LocalPlayer.Name) or "Player")
		addProfileRow("Expires In", Settings.ExpiresIn or Settings.Expires or Settings.Expiry or "Lifetime")
		addProfileRow("Game", Settings.Game or "Violence District")

		local actions = Instance.new("Frame")
		actions.Name = "ProfileActions"
		actions.BackgroundTransparency = 1
		actions.BorderSizePixel = 0
		actions.Position = UDim2.new(0, 68, 1, -39)
		actions.Size = UDim2.new(1, -84, 0, 29)
		actions.ZIndex = 11
		actions.Parent = profileModal

		local actionsLayout = Instance.new("UIListLayout")
		actionsLayout.Padding = UDim.new(0, 8)
		actionsLayout.FillDirection = Enum.FillDirection.Horizontal
		actionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		actionsLayout.Parent = actions

		local function runProfileAction(action, fallbackClose)
			if type(action) == "function" then
				task.spawn(action)
				return
			end
			if type(action) == "string" and action ~= "" and type(setclipboard) == "function" then
				setclipboard(action)
				WindowFunctions:Notify({
					Title = "TiRex",
					Description = "Copied to clipboard.",
					Lifetime = 2
				})
				return
			end
			if fallbackClose then
				profile:Hide()
			end
		end

		local function addActionButton(text, action, fallbackClose)
			local button = Instance.new("TextButton")
			button.Name = text:gsub("%s+", "") .. "Button"
			button.AutoButtonColor = false
			button.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
			button.BorderSizePixel = 0
			button.FontFace = SafeFont(assets.interFont, Enum.FontWeight.Medium, Enum.FontStyle.Normal)
			button.Text = text
			button.TextColor3 = Color3.fromRGB(255, 255, 255)
			button.TextSize = 11
			button.Size = UDim2.fromOffset(82, 29)
			button.ZIndex = 12
			button.Parent = actions

			local buttonCorner = Instance.new("UICorner")
			buttonCorner.CornerRadius = UDim.new(0, 0)
			buttonCorner.Parent = button

			local buttonStroke = Instance.new("UIStroke")
			buttonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			buttonStroke.Color = Color3.fromRGB(255, 255, 255)
			buttonStroke.Transparency = 0.92
			buttonStroke.Parent = button

			button.MouseEnter:Connect(function()
				Tween(button, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {
					BackgroundColor3 = Color3.fromRGB(42, 42, 42)
				}):Play()
			end)
			button.MouseLeave:Connect(function()
				Tween(button, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {
					BackgroundColor3 = Color3.fromRGB(26, 26, 26)
				}):Play()
			end)
			button.MouseButton1Click:Connect(function()
				runProfileAction(action, fallbackClose)
			end)
		end

		addActionButton("Discord", Settings.Discord or Settings.DiscordCallback, false)
		addActionButton("Website", Settings.Website or Settings.WebsiteCallback, false)
		addActionButton("Logout", Settings.Logout or Settings.LogoutCallback or Settings.OnLogout, true)

		profileButton.MouseEnter:Connect(function()
			Tween(profileButtonStroke, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {
				Transparency = 0.55
			}):Play()
		end)
		profileButton.MouseLeave:Connect(function()
			Tween(profileButtonStroke, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {
				Transparency = 0.88
			}):Play()
		end)
		profileButton.MouseButton1Click:Connect(function()
			profileModal.Visible = not profileModal.Visible
		end)
		close.MouseButton1Click:Connect(function()
			profile:Hide()
		end)

		function profile:Show()
			profileModal.Visible = true
		end
		function profile:Hide()
			profileModal.Visible = false
		end
		function profile:SetIcon(newIcon)
			profileIcon = ResolveImageAsset(newIcon, assets.tirexIcon)
			profileButton.Image = profileIcon
			avatar.Image = profileIcon
		end
		function profile:SetUsername(value)
			valueLabels.Username.Text = tostring(value or "-")
		end
		function profile:SetExpires(value)
			valueLabels["Expires In"].Text = tostring(value or "-")
		end
		function profile:SetGame(value)
			valueLabels.Game.Text = tostring(value or "-")
		end
		function profile:SetPlan(value)
			tier.Text = tostring(value or "Free")
		end
		function profile:Destroy()
			profileButton:Destroy()
			profileModal:Destroy()
			if self == WindowFunctions._Profile then
				WindowFunctions._Profile = nil
			end
		end

		self._Profile = profile
		return profile
	end

	local hovering
	local toggled = globalSettingsUIScale.Scale == 1 and true or false
	local function toggle()
		if not toggled then
			local intween = Tween(globalSettingsUIScale, TweenInfo.new(0.2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Scale = 1
			})
			intween:Play()
			intween.Completed:Wait()
			toggled = true
		elseif toggled then
			local outtween = Tween(globalSettingsUIScale, TweenInfo.new(0.2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Scale = 0
			})
			outtween:Play()
			outtween.Completed:Wait()
			toggled = false
		end
	end
	globalSettingsButton.MouseButton1Click:Connect(function()
		if not hasGlobalSetting then return end
		toggle()
	end)
	globalSettings.MouseEnter:Connect(function()
		hovering = true
	end)
	globalSettings.MouseLeave:Connect(function()
		hovering = false
	end)
	UserInputService.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 and toggled and not hovering then
			toggle()
		end
	end)

	if acrylicBlur then
		local blurOk, blurErr = pcall(function()
			local BlurTarget = base

			local HS = HttpService
			local camera = workspace.CurrentCamera
			if not camera then
				error("CurrentCamera is not available", 0)
			end
			local MTREL = "Glass"
			local binds = {}
			local wedgeguid = HS:GenerateGUID(true)

			local DepthOfField

			for _,v in pairs(Lighting:GetChildren()) do
				local hasBlurTag = false
				pcall(function()
					hasBlurTag = v:HasTag(".")
				end)
				if not v:IsA("DepthOfFieldEffect") and hasBlurTag then
					DepthOfField = Instance.new('DepthOfFieldEffect')
					DepthOfField.FarIntensity = 0
					DepthOfField.FocusDistance = 51.6
					DepthOfField.InFocusRadius = 50
					DepthOfField.NearIntensity = 1
					DepthOfField.Name = HS:GenerateGUID(true)
					pcall(function()
						DepthOfField:AddTag(".")
					end)
				elseif v:IsA("DepthOfFieldEffect") and hasBlurTag then
					DepthOfField = v
				end
			end

			if not DepthOfField then
				DepthOfField = Instance.new('DepthOfFieldEffect')
				DepthOfField.FarIntensity = 0
				DepthOfField.FocusDistance = 51.6
				DepthOfField.InFocusRadius = 50
				DepthOfField.NearIntensity = 1
				DepthOfField.Name = HS:GenerateGUID(true)
				pcall(function()
					DepthOfField:AddTag(".")
				end)
			end

			local frame = Instance.new('Frame')
			frame.Parent = BlurTarget
			frame.Size = UDim2.new(0.97, 0, 0.97, 0)
			frame.Position = UDim2.new(0.5, 0, 0.5, 0)
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.BackgroundTransparency = 1
			frame.Name = HS:GenerateGUID(true)

			do
				local function IsNotNaN(x)
					return x == x
				end
				local continue = IsNotNaN(camera:ScreenPointToRay(0,0).Origin.x)
				while not continue do
					RunService.RenderStepped:Wait()
					continue = IsNotNaN(camera:ScreenPointToRay(0,0).Origin.x)
				end
			end

			local DrawQuad; do
				local acos, max, pi, sqrt = math.acos, math.max, math.pi, math.sqrt
				local sz = 0.2

				local function DrawTriangle(v1, v2, v3, p0, p1)
					local s1 = (v1 - v2).magnitude
					local s2 = (v2 - v3).magnitude
					local s3 = (v3 - v1).magnitude
					local smax = max(s1, s2, s3)
					local A, B, C
					if s1 == smax then
						A, B, C = v1, v2, v3
					elseif s2 == smax then
						A, B, C = v2, v3, v1
					elseif s3 == smax then
						A, B, C = v3, v1, v2
					end

					local para = ( (B-A).x*(C-A).x + (B-A).y*(C-A).y + (B-A).z*(C-A).z ) / (A-B).magnitude
					local perp = sqrt((C-A).magnitude^2 - para*para)
					local dif_para = (A - B).magnitude - para

					local st = CFrame.new(B, A)
					local za = CFrame.Angles(pi/2,0,0)

					local cf0 = st

					local Top_Look = (cf0 * za).lookVector
					local Mid_Point = A + CFrame.new(A, B).lookVector * para
					local Needed_Look = CFrame.new(Mid_Point, C).lookVector
					local dot = Top_Look.x*Needed_Look.x + Top_Look.y*Needed_Look.y + Top_Look.z*Needed_Look.z

					local ac = CFrame.Angles(0, 0, acos(dot))

					cf0 = cf0 * ac
					if ((cf0 * za).lookVector - Needed_Look).magnitude > 0.01 then
						cf0 = cf0 * CFrame.Angles(0, 0, -2*acos(dot))
					end
					cf0 = cf0 * CFrame.new(0, perp/2, -(dif_para + para/2))

					local cf1 = st * ac * CFrame.Angles(0, pi, 0)
					if ((cf1 * za).lookVector - Needed_Look).magnitude > 0.01 then
						cf1 = cf1 * CFrame.Angles(0, 0, 2*acos(dot))
					end
					cf1 = cf1 * CFrame.new(0, perp/2, dif_para/2)

					if not p0 then
						p0 = Instance.new('Part')
						p0.FormFactor = 'Custom'
						p0.TopSurface = 0
						p0.BottomSurface = 0
						p0.Anchored = true
						p0.CanCollide = false
						p0.CastShadow = false
						p0.Material = MTREL
						p0.Size = Vector3.new(sz, sz, sz)
						p0.Name = HS:GenerateGUID(true)
						local mesh = Instance.new('SpecialMesh', p0)
						mesh.MeshType = 2
						mesh.Name = wedgeguid
					end
					local mesh0 = p0:FindFirstChild(wedgeguid)
					if not mesh0 then
						mesh0 = Instance.new('SpecialMesh')
						mesh0.MeshType = 2
						mesh0.Name = wedgeguid
						mesh0.Parent = p0
					end
					mesh0.Scale = Vector3.new(0, perp/sz, para/sz)
					p0.CFrame = cf0

					if not p1 then
						p1 = p0:clone()
					end
					local mesh1 = p1:FindFirstChild(wedgeguid)
					if not mesh1 then
						mesh1 = Instance.new('SpecialMesh')
						mesh1.MeshType = 2
						mesh1.Name = wedgeguid
						mesh1.Parent = p1
					end
					mesh1.Scale = Vector3.new(0, perp/sz, dif_para/sz)
					p1.CFrame = cf1

					return p0, p1
				end

				function DrawQuad(v1, v2, v3, v4, parts)
					parts[1], parts[2] = DrawTriangle(v1, v2, v3, parts[1], parts[2])
					parts[3], parts[4] = DrawTriangle(v3, v2, v4, parts[3], parts[4])
				end
			end

			if binds[frame] then
				return binds[frame].parts
			end

			local parts = {}

			local parents = {}
			do
				local function add(child)
					if child and child:IsA'GuiObject' then
						parents[#parents + 1] = child
						add(child.Parent)
					end
				end
				add(frame)
			end

			local function IsVisible(instance)
				while instance do
					if instance:IsA("GuiObject") then
						if not instance.Visible then
							return false
						end
					elseif instance:IsA("ScreenGui") then
						if not instance.Enabled then
							return false
						end
						break
					end
					instance = instance.Parent
				end
				return true
			end

			local function UpdateOrientation(fetchProps)
				if not IsVisible(frame) or not acrylicBlur or unloaded then
					for _, pt in pairs(parts) do
						pt.Parent = nil
						DepthOfField.Enabled = false
						DepthOfField.Parent = nil
					end
					return
				end
				if not DepthOfField.Parent then
					DepthOfField.Parent = Lighting
				end
				DepthOfField.Enabled = true
				local properties = {
					Transparency = 0.98;
					BrickColor = BrickColor.new('Institutional white');
				}
				local zIndex = 1 - 0.05*frame.ZIndex

				local tl, br = frame.AbsolutePosition, frame.AbsolutePosition + frame.AbsoluteSize
				local tr, bl = Vector2.new(br.x, tl.y), Vector2.new(tl.x, br.y)
				do
					local rot = 0;
					for _, v in ipairs(parents) do
						rot = rot + v.Rotation
					end
					if rot ~= 0 and rot%180 ~= 0 then
						local mid = tl:lerp(br, 0.5)
						local s, c = math.sin(math.rad(rot)), math.cos(math.rad(rot))
						tl = Vector2.new(c*(tl.x - mid.x) - s*(tl.y - mid.y), s*(tl.x - mid.x) + c*(tl.y - mid.y)) + mid
						tr = Vector2.new(c*(tr.x - mid.x) - s*(tr.y - mid.y), s*(tr.x - mid.x) + c*(tr.y - mid.y)) + mid
						bl = Vector2.new(c*(bl.x - mid.x) - s*(bl.y - mid.y), s*(bl.x - mid.x) + c*(bl.y - mid.y)) + mid
						br = Vector2.new(c*(br.x - mid.x) - s*(br.y - mid.y), s*(br.x - mid.x) + c*(br.y - mid.y)) + mid
					end
				end
				DrawQuad(
					camera:ScreenPointToRay(tl.x, tl.y, zIndex).Origin,
					camera:ScreenPointToRay(tr.x, tr.y, zIndex).Origin,
					camera:ScreenPointToRay(bl.x, bl.y, zIndex).Origin,
					camera:ScreenPointToRay(br.x, br.y, zIndex).Origin,
					parts
				)
				if fetchProps then
					for _, pt in pairs(parts) do
						pt.Parent = camera
					end
					for propName, propValue in pairs(properties) do
						for _, pt in pairs(parts) do
							pt[propName] = propValue
						end
					end
				end
			end

			UpdateOrientation(true)

			RunService.RenderStepped:Connect(UpdateOrientation)
		end)
		if not blurOk then
			acrylicBlur = false
			warn("[MacLib] Acrylic blur disabled: " .. tostring(blurErr))
		end
	end

	function WindowFunctions:GlobalSetting(Settings)
		hasGlobalSetting = true
		local GlobalSettingFunctions = {}
		local globalSetting = Instance.new("TextButton")
		globalSetting.Name = "GlobalSetting"
		globalSetting.FontFace = SafeFont("rbxasset://fonts/families/SourceSansPro.json")
		globalSetting.Text = ""
		globalSetting.TextColor3 = Color3.fromRGB(0, 0, 0)
		globalSetting.TextSize = 14
		globalSetting.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		globalSetting.BackgroundTransparency = 1
		globalSetting.BorderColor3 = Color3.fromRGB(0, 0, 0)
		globalSetting.BorderSizePixel = 0
		globalSetting.Size = UDim2.fromOffset(200, 30)

		local globalSettingToggleUIPadding = Instance.new("UIPadding")
		globalSettingToggleUIPadding.Name = "GlobalSettingToggleUIPadding"
		globalSettingToggleUIPadding.PaddingLeft = UDim.new(0, 15)
		globalSettingToggleUIPadding.Parent = globalSetting

		local settingName = Instance.new("TextLabel")
		settingName.Name = "SettingName"
		settingName.FontFace = SafeFont(assets.interFont)
		settingName.Text = Settings.Name
		settingName.RichText = true
		settingName.TextColor3 = Color3.fromRGB(255, 255, 255)
		settingName.TextSize = 13
		settingName.TextTransparency = 0.5
		settingName.TextTruncate = Enum.TextTruncate.SplitWord
		settingName.TextXAlignment = Enum.TextXAlignment.Left
		settingName.TextYAlignment = Enum.TextYAlignment.Top
		settingName.AnchorPoint = Vector2.new(0, 0.5)
		settingName.AutomaticSize = Enum.AutomaticSize.Y
		settingName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		settingName.BackgroundTransparency = 1
		settingName.BorderColor3 = Color3.fromRGB(0, 0, 0)
		settingName.BorderSizePixel = 0
		settingName.Position = UDim2.fromScale(1.3e-07, 0.5)
		settingName.Size = UDim2.new(1,-40,0,0)
		settingName.Parent = globalSetting

		local globalSettingToggleUIListLayout = Instance.new("UIListLayout")
		globalSettingToggleUIListLayout.Name = "GlobalSettingToggleUIListLayout"
		globalSettingToggleUIListLayout.Padding = UDim.new(0, 10)
		globalSettingToggleUIListLayout.FillDirection = Enum.FillDirection.Horizontal
		globalSettingToggleUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		globalSettingToggleUIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		globalSettingToggleUIListLayout.Parent = globalSetting

		local checkmark = Instance.new("TextLabel")
		checkmark.Name = "Checkmark"
		checkmark.FontFace = SafeFont(
			assets.interFont,
			Enum.FontWeight.Medium,
			Enum.FontStyle.Normal
		)
		checkmark.Text = "✓"
		checkmark.TextColor3 = Color3.fromRGB(255, 255, 255)
		checkmark.TextSize = 13
		checkmark.TextTransparency = 1
		checkmark.TextXAlignment = Enum.TextXAlignment.Left
		checkmark.TextYAlignment = Enum.TextYAlignment.Top
		checkmark.AnchorPoint = Vector2.new(0, 0.5)
		checkmark.AutomaticSize = Enum.AutomaticSize.Y
		checkmark.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		checkmark.BackgroundTransparency = 1
		checkmark.BorderColor3 = Color3.fromRGB(0, 0, 0)
		checkmark.BorderSizePixel = 0
		checkmark.LayoutOrder = -1
		checkmark.Position = UDim2.fromScale(1.3e-07, 0.5)
		checkmark.Size = UDim2.fromOffset(-10, 0)
		checkmark.Parent = globalSetting

		globalSetting.Parent = globalSettings

		local tweensettings = {
			duration = 0.2,
			easingStyle = Enum.EasingStyle.Quint,
			transparencyIn = 0.2,
			transparencyOut = 0.5,
			checkSizeIncrease = 12,
			checkSizeDecrease = -globalSettingToggleUIListLayout.Padding.Offset,
			waitTime = 1
		}

		local tweens = {
			checkIn = Tween(checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
				Size = UDim2.new(checkmark.Size.X.Scale, tweensettings.checkSizeIncrease, checkmark.Size.Y.Scale, checkmark.Size.Y.Offset)
			}),
			checkOut = Tween(checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle),{
				Size = UDim2.new(checkmark.Size.X.Scale, tweensettings.checkSizeDecrease, checkmark.Size.Y.Scale, checkmark.Size.Y.Offset)
			}),
			nameIn = Tween(settingName, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle),{
				TextTransparency = tweensettings.transparencyIn
			}),
			nameOut = Tween(settingName, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle),{
				TextTransparency = tweensettings.transparencyOut
			})
		}

		local function Toggle(State)
			if not State then
				tweens.checkOut:Play()
				tweens.nameOut:Play()
				checkmark:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					if checkmark.AbsoluteSize.X <= 0 then
						checkmark.TextTransparency = 1
					end
				end)
			else
				tweens.checkIn:Play()
				tweens.nameIn:Play()
				checkmark:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					if checkmark.AbsoluteSize.X > 0 then
						checkmark.TextTransparency = 0
					end
				end)
			end
		end

		local toggled = Settings.Default
		Toggle(toggled)

		globalSetting.MouseButton1Click:Connect(function()
			toggled = not toggled
			Toggle(toggled)
			optionCall(Settings.Callback, toggled)
		end)

		function GlobalSettingFunctions:UpdateName(NewName)
			settingName.Text = NewName
		end

		function GlobalSettingFunctions:UpdateState(NewState)
			Toggle(NewState)
			toggled = NewState
		end

		return GlobalSettingFunctions
	end

	function WindowFunctions:TabGroup()
		local SectionFunctions = {}

		local tabGroup = Instance.new("Frame")
		tabGroup.Name = "Section"
		tabGroup.AutomaticSize = Enum.AutomaticSize.Y
		tabGroup.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		tabGroup.BackgroundTransparency = 1
		tabGroup.BorderColor3 = Color3.fromRGB(0, 0, 0)
		tabGroup.BorderSizePixel = 0
		tabGroup.Size = UDim2.fromScale(1, 0)

		local divider3 = Instance.new("Frame")
		divider3.Name = "Divider"
		divider3.AnchorPoint = Vector2.new(0.5, 1)
		divider3.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		divider3.BackgroundTransparency = 0.9
		divider3.BorderColor3 = Color3.fromRGB(0, 0, 0)
		divider3.BorderSizePixel = 0
		divider3.Position = UDim2.fromScale(0.5, 1)
		divider3.Size = UDim2.new(1, -21, 0, 1)
		divider3.Parent = tabGroup

		local sectionTabSwitchers = Instance.new("Frame")
		sectionTabSwitchers.Name = "SectionTabSwitchers"
		sectionTabSwitchers.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		sectionTabSwitchers.BackgroundTransparency = 1
		sectionTabSwitchers.BorderColor3 = Color3.fromRGB(0, 0, 0)
		sectionTabSwitchers.BorderSizePixel = 0
		sectionTabSwitchers.Size = UDim2.fromScale(1, 1)

		local uIListLayout1 = Instance.new("UIListLayout")
		uIListLayout1.Name = "UIListLayout"
		uIListLayout1.Padding = UDim.new(0, 15)
		uIListLayout1.HorizontalAlignment = Enum.HorizontalAlignment.Center
		uIListLayout1.SortOrder = Enum.SortOrder.LayoutOrder
		uIListLayout1.Parent = sectionTabSwitchers

		local uIPadding1 = Instance.new("UIPadding")
		uIPadding1.Name = "UIPadding"
		uIPadding1.PaddingBottom = UDim.new(0, 15)
		uIPadding1.Parent = sectionTabSwitchers

		sectionTabSwitchers.Parent = tabGroup
		tabGroup.Parent = tabSwitchersScrollingFrame

		function SectionFunctions:Tab(Settings)
			local TabFunctions = {Settings = Settings}
			local tabSwitcher = Instance.new("TextButton")
			tabSwitcher.Name = "TabSwitcher"
			tabSwitcher.FontFace = SafeFont("rbxasset://fonts/families/SourceSansPro.json")
			tabSwitcher.Text = ""
			tabSwitcher.TextColor3 = Color3.fromRGB(0, 0, 0)
			tabSwitcher.TextSize = 14
			tabSwitcher.AutoButtonColor = false
			tabSwitcher.AnchorPoint = Vector2.new(0.5, 0)
			tabSwitcher.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			tabSwitcher.BackgroundTransparency = 1
			tabSwitcher.BorderColor3 = Color3.fromRGB(0, 0, 0)
			tabSwitcher.BorderSizePixel = 0
			tabSwitcher.Position = UDim2.fromScale(0.5, 0)
			tabSwitcher.Size = UDim2.new(1, -21, 0, 40)

			tabIndex += 1
			tabSwitcher.LayoutOrder = tabIndex

			local tabSwitcherUICorner = Instance.new("UICorner")
			tabSwitcherUICorner.Name = "TabSwitcherUICorner"
			tabSwitcherUICorner.Parent = tabSwitcher

			local tabSwitcherUIStroke = Instance.new("UIStroke")
			tabSwitcherUIStroke.Name = "TabSwitcherUIStroke"
			tabSwitcherUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			tabSwitcherUIStroke.Color = Color3.fromRGB(255, 255, 255)
			tabSwitcherUIStroke.Transparency = 1
			tabSwitcherUIStroke.Parent = tabSwitcher

			local tabSwitcherUIListLayout = Instance.new("UIListLayout")
			tabSwitcherUIListLayout.Name = "TabSwitcherUIListLayout"
			tabSwitcherUIListLayout.Padding = UDim.new(0, 9)
			tabSwitcherUIListLayout.FillDirection = Enum.FillDirection.Horizontal
			tabSwitcherUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
			tabSwitcherUIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			tabSwitcherUIListLayout.Parent = tabSwitcher

			local tabImage

			if Settings.Image then
				tabImage = createIconInstance(Settings.Image, 18, Color3.fromRGB(255, 255, 255), 0.5)
				tabImage.Name = "TabImage"
				tabImage.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				tabImage.BackgroundTransparency = 1
				tabImage.BorderColor3 = Color3.fromRGB(0, 0, 0)
				tabImage.BorderSizePixel = 0
				tabImage.Size = UDim2.fromOffset(18, 18)
				tabImage.Parent = tabSwitcher
			end

			local tabSwitcherName = Instance.new("TextLabel")
			tabSwitcherName.Name = "TabSwitcherName"
			tabSwitcherName.FontFace = SafeFont(
				assets.interFont,
				Enum.FontWeight.Medium,
				Enum.FontStyle.Normal
			)
			tabSwitcherName.Text = Settings.Name
			tabSwitcherName.RichText = true
			tabSwitcherName.TextColor3 = Color3.fromRGB(255, 255, 255)
			tabSwitcherName.TextSize = 16
			tabSwitcherName.TextTransparency = 0.5
			tabSwitcherName.TextTruncate = Enum.TextTruncate.SplitWord
			tabSwitcherName.TextXAlignment = Enum.TextXAlignment.Left
			tabSwitcherName.TextYAlignment = Enum.TextYAlignment.Top
			tabSwitcherName.AutomaticSize = Enum.AutomaticSize.Y
			tabSwitcherName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			tabSwitcherName.BackgroundTransparency = 1
			tabSwitcherName.BorderColor3 = Color3.fromRGB(0, 0, 0)
			tabSwitcherName.BorderSizePixel = 0
			tabSwitcherName.Size = UDim2.fromScale(1, 0)
			tabSwitcherName.Parent = tabSwitcher
			tabSwitcherName.LayoutOrder = 1

			local tabSwitcherUIPadding = Instance.new("UIPadding")
			tabSwitcherUIPadding.Name = "TabSwitcherUIPadding"
			tabSwitcherUIPadding.PaddingLeft = UDim.new(0, 24)
			tabSwitcherUIPadding.PaddingRight = UDim.new(0, 35)
			tabSwitcherUIPadding.PaddingTop = UDim.new(0, 1)
			tabSwitcherUIPadding.Parent = tabSwitcher

			tabSwitcher.Parent = sectionTabSwitchers

			local elements1 = Instance.new("Frame")
			elements1.Name = "Elements"
			elements1.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			elements1.BackgroundTransparency = 1
			elements1.BorderColor3 = Color3.fromRGB(0, 0, 0)
			elements1.BorderSizePixel = 0
			elements1.Position = UDim2.fromOffset(0, 63)
			elements1.Size = UDim2.new(1, 0, 1, -63)
			elements1.ClipsDescendants = true

			local elementsUIPadding = Instance.new("UIPadding")
			elementsUIPadding.Name = "ElementsUIPadding"
			elementsUIPadding.PaddingRight = UDim.new(0, 5)
			elementsUIPadding.PaddingTop = UDim.new(0, 10)
			elementsUIPadding.PaddingBottom = UDim.new(0, 10)
			elementsUIPadding.Parent = elements1

			local elementsScrolling = Instance.new("ScrollingFrame")
			elementsScrolling.Name = "ElementsScrolling"
			elementsScrolling.AutomaticCanvasSize = Enum.AutomaticSize.Y
			elementsScrolling.BottomImage = ""
			elementsScrolling.CanvasSize = UDim2.new()
			elementsScrolling.ScrollBarImageTransparency = 0.5
			elementsScrolling.ScrollBarThickness = 1
			elementsScrolling.TopImage = ""
			elementsScrolling.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			elementsScrolling.BackgroundTransparency = 1
			elementsScrolling.BorderColor3 = Color3.fromRGB(0, 0, 0)
			elementsScrolling.BorderSizePixel = 0
			elementsScrolling.Size = UDim2.fromScale(1, 1)
			elementsScrolling.ClipsDescendants = false

			local elementsScrollingUIPadding = Instance.new("UIPadding")
			elementsScrollingUIPadding.Name = "ElementsScrollingUIPadding"
			elementsScrollingUIPadding.PaddingBottom = UDim.new(0, 5)
			elementsScrollingUIPadding.PaddingLeft = UDim.new(0, 11)
			elementsScrollingUIPadding.PaddingRight = UDim.new(0, 3)
			elementsScrollingUIPadding.PaddingTop = UDim.new(0, 5)
			elementsScrollingUIPadding.Parent = elementsScrolling

			local elementsScrollingUIListLayout = Instance.new("UIListLayout")
			elementsScrollingUIListLayout.Name = "ElementsScrollingUIListLayout"
			elementsScrollingUIListLayout.Padding = UDim.new(0, 12)
			elementsScrollingUIListLayout.FillDirection = Enum.FillDirection.Horizontal
			elementsScrollingUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
			elementsScrollingUIListLayout.Parent = elementsScrolling

			local left = Instance.new("Frame")
			left.Name = "Left"
			left.AutomaticSize = Enum.AutomaticSize.Y
			left.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			left.BackgroundTransparency = 1
			left.BorderColor3 = Color3.fromRGB(0, 0, 0)
			left.BorderSizePixel = 0
			left.Position = UDim2.fromScale(0.512, 0)
			left.Size = UDim2.new(0.5, -10, 0, 0)

			local leftUIListLayout = Instance.new("UIListLayout")
			leftUIListLayout.Name = "LeftUIListLayout"
			leftUIListLayout.Padding = UDim.new(0, 10)
			leftUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
			leftUIListLayout.Parent = left

			left.Parent = elementsScrolling

			local right = Instance.new("Frame")
			right.Name = "Right"
			right.AutomaticSize = Enum.AutomaticSize.Y
			right.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			right.BackgroundTransparency = 1
			right.BorderColor3 = Color3.fromRGB(0, 0, 0)
			right.BorderSizePixel = 0
			right.LayoutOrder = 1
			right.Position = UDim2.fromScale(0.512, 0)
			right.Size = UDim2.new(0.5, -10, 0, 0)

			local rightUIListLayout = Instance.new("UIListLayout")
			rightUIListLayout.Name = "RightUIListLayout"
			rightUIListLayout.Padding = UDim.new(0, 10)
			rightUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
			rightUIListLayout.Parent = right

			right.Parent = elementsScrolling

			elementsScrolling.Parent = elements1

			function TabFunctions:Section(Settings)
				local SectionFunctions = {}
				local section = Instance.new("Frame")
				section.Name = "Section"
				section.AutomaticSize = Enum.AutomaticSize.Y
				section.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				section.BackgroundTransparency = 0.10
				section.BorderColor3 = Color3.fromRGB(0, 0, 0)
				section.BorderSizePixel = 0
				section.Position = UDim2.fromScale(0, 6.78e-08)
				section.Size = UDim2.fromScale(1, 0)
				section.ClipsDescendants = true
				section.Parent = Settings.Side == "Left" and left or right

				local sectionUICorner = Instance.new("UICorner")
				sectionUICorner.Name = "SectionUICorner"
				sectionUICorner.Parent = section

				local sectionUIStroke = Instance.new("UIStroke")
				sectionUIStroke.Name = "SectionUIStroke"
				sectionUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				sectionUIStroke.Color = Color3.fromRGB(255, 255, 255)
				sectionUIStroke.Transparency = 0.58
				sectionUIStroke.Parent = section

				local sectionUIListLayout = Instance.new("UIListLayout")
				sectionUIListLayout.Name = "SectionUIListLayout"
				sectionUIListLayout.Padding = UDim.new(0, 6)
				sectionUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
				sectionUIListLayout.Parent = section

				local sectionUIPadding = Instance.new("UIPadding")
				sectionUIPadding.Name = "SectionUIPadding"
				sectionUIPadding.PaddingBottom = UDim.new(0, 14)
				sectionUIPadding.PaddingLeft = UDim.new(0, 16)
				sectionUIPadding.PaddingRight = UDim.new(0, 16)
				sectionUIPadding.PaddingTop = UDim.new(0, 15)
				sectionUIPadding.Parent = section

				function SectionFunctions:Button(Settings, Flag)
					Settings, Flag = optionArgs(Settings, Flag)
					Settings.Name = optionText(Settings, Flag, "Button")
					local ButtonFunctions = {Settings = Settings}
					local button = Instance.new("Frame")
					button.Name = "Button"
					button.AutomaticSize = Enum.AutomaticSize.Y
					button.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					button.BackgroundTransparency = 1
					button.BorderColor3 = Color3.fromRGB(0, 0, 0)
					button.BorderSizePixel = 0
					button.Size = UDim2.new(1, 0, 0, 32)
					button.Parent = section

					local buttonInteract = Instance.new("TextButton")
					buttonInteract.Name = "ButtonInteract"
					buttonInteract.FontFace = SafeFont(assets.interFont)
					buttonInteract.RichText = true
					buttonInteract.TextColor3 = Color3.fromRGB(255, 255, 255)
					buttonInteract.TextSize = 13
					buttonInteract.TextTransparency = 0.5
					buttonInteract.TextTruncate = Enum.TextTruncate.AtEnd
					buttonInteract.TextXAlignment = Enum.TextXAlignment.Left
					buttonInteract.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					buttonInteract.BackgroundTransparency = 1
					buttonInteract.BorderColor3 = Color3.fromRGB(0, 0, 0)
					buttonInteract.BorderSizePixel = 0
					buttonInteract.Size = UDim2.fromScale(1, 1)
					buttonInteract.Parent = button
					buttonInteract.Text = ButtonFunctions.Settings.Name

					local buttonImage = Instance.new("ImageLabel")
					buttonImage.Name = "ButtonImage"
					buttonImage.Image = assets.buttonImage
					buttonImage.ImageTransparency = 0.5
					buttonImage.AnchorPoint = Vector2.new(1, 0.5)
					buttonImage.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					buttonImage.BackgroundTransparency = 1
					buttonImage.BorderColor3 = Color3.fromRGB(0, 0, 0)
					buttonImage.BorderSizePixel = 0
					buttonImage.Position = UDim2.fromScale(1, 0.5)
					buttonImage.Size = UDim2.fromOffset(15, 15)
					buttonImage.Parent = button

					local TweenSettings = {
						DefaultTransparency = 0.5,
						HoverTransparency = 0.3,

						EasingStyle = Enum.EasingStyle.Sine
					}

					local function ChangeState(State)
						if State == "Idle" then
							Tween(buttonInteract, TweenInfo.new(0.2, TweenSettings.EasingStyle), {
								TextTransparency = TweenSettings.DefaultTransparency
							}):Play()
							Tween(buttonImage, TweenInfo.new(0.2, TweenSettings.EasingStyle), {
								ImageTransparency = TweenSettings.DefaultTransparency
							}):Play()
						elseif State == "Hover" then
							Tween(buttonInteract, TweenInfo.new(0.2, TweenSettings.EasingStyle), {
								TextTransparency = TweenSettings.HoverTransparency
							}):Play()
							Tween(buttonImage, TweenInfo.new(0.2, TweenSettings.EasingStyle), {
								ImageTransparency = TweenSettings.HoverTransparency
							}):Play()
						end
					end

					local function Callback()
						optionCall(ButtonFunctions.Settings.Callback)
					end

					buttonInteract.MouseEnter:Connect(function()
						ChangeState("Hover")
					end)
					buttonInteract.MouseLeave:Connect(function()
						ChangeState("Idle")
					end)

					buttonInteract.MouseButton1Click:Connect(Callback)
					function ButtonFunctions:UpdateName(Name)
						buttonInteract.Text = Name
					end
					function ButtonFunctions:SetVisibility(State)
						button.Visible = State
					end

					if Flag then
						MacLib.Options[Flag] = ButtonFunctions
					end
					return ButtonFunctions
				end

				function SectionFunctions:Toggle(Settings, Flag)
					Settings, Flag = optionArgs(Settings, Flag)
					Settings.Name = optionText(Settings, Flag, "Toggle")
					Settings.Default = Settings.Default == true
					local ToggleFunctions = { Settings = Settings, IgnoreConfig = false, Class = "Toggle" }
					local toggle = Instance.new("Frame")
					toggle.Name = "Toggle"
					toggle.AutomaticSize = Enum.AutomaticSize.Y
					toggle.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					toggle.BackgroundTransparency = 1
					toggle.BorderColor3 = Color3.fromRGB(0, 0, 0)
					toggle.BorderSizePixel = 0
					toggle.Size = UDim2.new(1, 0, 0, 32)
					toggle.Parent = section

					local toggleName = Instance.new("TextLabel")
					toggleName.Name = "ToggleName"
					toggleName.FontFace = SafeFont(assets.interFont)
					toggleName.Text = ToggleFunctions.Settings.Name
					toggleName.RichText = true
					toggleName.TextColor3 = Color3.fromRGB(255, 255, 255)
					toggleName.TextSize = 13
					toggleName.TextTransparency = 0.5
					toggleName.TextTruncate = Enum.TextTruncate.AtEnd
					toggleName.TextXAlignment = Enum.TextXAlignment.Left
					toggleName.TextYAlignment = Enum.TextYAlignment.Top
					toggleName.AnchorPoint = Vector2.new(0, 0.5)
					toggleName.AutomaticSize = Enum.AutomaticSize.Y
					toggleName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					toggleName.BackgroundTransparency = 1
					toggleName.BorderColor3 = Color3.fromRGB(0, 0, 0)
					toggleName.BorderSizePixel = 0
					toggleName.Position = UDim2.fromScale(0, 0.5)
					toggleName.Size = UDim2.new(1, -50, 0, 0)
					toggleName.Parent = toggle

					local toggle1 = Instance.new("ImageButton")
					toggle1.Name = "Toggle"
					toggle1.Image = assets.toggleBackground
					toggle1.ImageColor3 = Color3.fromRGB(125, 125, 125)
					toggle1.AutoButtonColor = false
					toggle1.AnchorPoint = Vector2.new(1, 0.5)
					toggle1.BackgroundColor3 = Color3.fromRGB(48, 49, 53)
					toggle1.BackgroundTransparency = 0.08
					toggle1.BorderColor3 = Color3.fromRGB(0, 0, 0)
					toggle1.BorderSizePixel = 0
					toggle1.Position = UDim2.fromScale(1, 0.5)
					toggle1.Size = UDim2.fromOffset(41, 21)
					toggle1.ImageTransparency = 1

					local toggleUIPadding = Instance.new("UIPadding")
					toggleUIPadding.Name = "ToggleUIPadding"
					toggleUIPadding.PaddingBottom = UDim.new(0, 1)
					toggleUIPadding.PaddingLeft = UDim.new(0, -2)
					toggleUIPadding.PaddingRight = UDim.new(0, 3)
					toggleUIPadding.PaddingTop = UDim.new(0, 1)
					toggleUIPadding.Parent = toggle1

					local togglerHead = Instance.new("ImageLabel")
					togglerHead.Name = "TogglerHead"
					togglerHead.Image = assets.togglerHead
					togglerHead.ImageColor3 = Color3.fromRGB(255, 255, 255)
					togglerHead.AnchorPoint = Vector2.new(1, 0.5)
					togglerHead.BackgroundColor3 = Color3.fromRGB(230, 231, 234)
					togglerHead.BackgroundTransparency = 0
					togglerHead.BorderColor3 = Color3.fromRGB(0, 0, 0)
					togglerHead.BorderSizePixel = 0
					togglerHead.Position = UDim2.fromScale(0.5, 0.5)
					togglerHead.Size = UDim2.fromOffset(15, 15)
					togglerHead.ZIndex = 2
					togglerHead.Parent = toggle1
					togglerHead.ImageTransparency = 1

					toggle1.Parent = toggle

					local toggle1Transparency = {Enabled = 0.08, Disabled = 0.08}
					local togglerHeadTransparency = {Enabled = 0, Disabled = 0}

					local TweenSettings = {
						Info = TweenInfo.new(0.15, Enum.EasingStyle.Quad),

						EnabledPosition = UDim2.new(1, 0, 0.5, 0),
						DisabledPosition = UDim2.new(0.5, 0, 0.5, 0),
					}

					local togglebool = ToggleFunctions.Settings.Default

					local function NewState(State, callback)
						local transparencyValues = State and {toggle1Transparency.Enabled, togglerHeadTransparency.Enabled}
							or {toggle1Transparency.Disabled, togglerHeadTransparency.Disabled}
						local position = State and TweenSettings.EnabledPosition or TweenSettings.DisabledPosition

						Tween(toggle1, TweenSettings.Info, {
							ImageTransparency = 1,
							BackgroundColor3 = State and Color3.fromRGB(126, 128, 135) or Color3.fromRGB(48, 49, 53),
							BackgroundTransparency = transparencyValues[1]
						}):Play()

						Tween(togglerHead, TweenSettings.Info, {
							ImageTransparency = 1,
							BackgroundTransparency = transparencyValues[2]
						}):Play()

						Tween(togglerHead, TweenSettings.Info, {
							Position = position
						}):Play()

						ToggleFunctions.State = State
						ToggleFunctions.Value = State
						optionCall(callback, togglebool)
					end

					NewState(togglebool)

					local function Toggle()
						togglebool = not togglebool
						NewState(togglebool, ToggleFunctions.Settings.Callback)
					end

					toggle1.MouseButton1Click:Connect(Toggle)

					function ToggleFunctions:Toggle()
						Toggle()
					end
					function ToggleFunctions:UpdateState(State)
						togglebool = State == true
						NewState(togglebool, ToggleFunctions.Settings.Callback)
					end
					function ToggleFunctions:SetValue(State)
						self:UpdateState(State)
					end
					function ToggleFunctions:GetState()
						return togglebool
					end
					function ToggleFunctions:GetValue()
						return togglebool
					end
					function ToggleFunctions:UpdateName(Name)
						toggleName.Text = Name
					end
					function ToggleFunctions:SetVisibility(State)
						toggle.Visible = State
					end

					if Flag then
						MacLib.Options[Flag] = ToggleFunctions
					end
					return ToggleFunctions
				end

				function SectionFunctions:Checkbox(Settings, Flag)
					Settings, Flag = optionArgs(Settings, Flag)
					Settings.Name = optionText(Settings, Flag, "Checkbox")
					Settings.Default = Settings.Default == true
					local CheckboxFunctions = { Settings = Settings, IgnoreConfig = false, Class = "Toggle" }
					local checkbox = Instance.new("Frame")
					checkbox.Name = "Checkbox"
					checkbox.AutomaticSize = Enum.AutomaticSize.Y
					checkbox.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					checkbox.BackgroundTransparency = 1
					checkbox.BorderColor3 = Color3.fromRGB(0, 0, 0)
					checkbox.BorderSizePixel = 0
					checkbox.Size = UDim2.new(1, 0, 0, 32)
					checkbox.Parent = section

					local checkboxName = Instance.new("TextLabel")
					checkboxName.Name = "CheckboxName"
					checkboxName.FontFace = SafeFont(assets.interFont)
					checkboxName.Text = CheckboxFunctions.Settings.Name
					checkboxName.RichText = true
					checkboxName.TextColor3 = Color3.fromRGB(255, 255, 255)
					checkboxName.TextSize = 13
					checkboxName.TextTransparency = 0.5
					checkboxName.TextTruncate = Enum.TextTruncate.AtEnd
					checkboxName.TextXAlignment = Enum.TextXAlignment.Left
					checkboxName.TextYAlignment = Enum.TextYAlignment.Top
					checkboxName.AnchorPoint = Vector2.new(0, 0.5)
					checkboxName.AutomaticSize = Enum.AutomaticSize.Y
					checkboxName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					checkboxName.BackgroundTransparency = 1
					checkboxName.BorderColor3 = Color3.fromRGB(0, 0, 0)
					checkboxName.BorderSizePixel = 0
					checkboxName.Position = UDim2.fromScale(0, 0.5)
					checkboxName.Size = UDim2.new(1, -36, 0, 0)
					checkboxName.Parent = checkbox

					local checkboxButton = Instance.new("TextButton")
					checkboxButton.Name = "CheckboxButton"
					checkboxButton.Text = ""
					checkboxButton.AutoButtonColor = false
					checkboxButton.AnchorPoint = Vector2.new(1, 0.5)
					checkboxButton.BackgroundColor3 = Color3.fromRGB(42, 43, 47)
					checkboxButton.BackgroundTransparency = 0.08
					checkboxButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
					checkboxButton.BorderSizePixel = 0
					checkboxButton.Position = UDim2.fromScale(1, 0.5)
					checkboxButton.Size = UDim2.fromOffset(21, 21)
					checkboxButton.Parent = checkbox

					local checkboxCorner = Instance.new("UICorner")
					checkboxCorner.Name = "CheckboxCorner"
					checkboxCorner.CornerRadius = UDim.new(0, 0)
					checkboxCorner.Parent = checkboxButton

					local checkboxStroke = Instance.new("UIStroke")
					checkboxStroke.Name = "CheckboxStroke"
					checkboxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					checkboxStroke.Color = Color3.fromRGB(150, 150, 150)
					checkboxStroke.Transparency = 0.55
					checkboxStroke.Parent = checkboxButton

					local checkmark = Instance.new("TextLabel")
					checkmark.Name = "Checkmark"
					checkmark.FontFace = SafeFont(assets.interFont, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
					checkmark.Text = "✓"
					checkmark.TextColor3 = Color3.fromRGB(14, 15, 17)
					checkmark.TextSize = 14
					checkmark.TextTransparency = 1
					checkmark.TextXAlignment = Enum.TextXAlignment.Center
					checkmark.TextYAlignment = Enum.TextYAlignment.Center
					checkmark.BackgroundTransparency = 1
					checkmark.BorderSizePixel = 0
					checkmark.Size = UDim2.fromScale(1, 1)
					checkmark.Parent = checkboxButton

					local checkboxHitbox = Instance.new("TextButton")
					checkboxHitbox.Name = "CheckboxHitbox"
					checkboxHitbox.Text = ""
					checkboxHitbox.AutoButtonColor = false
					checkboxHitbox.BackgroundTransparency = 1
					checkboxHitbox.BorderSizePixel = 0
					checkboxHitbox.Size = UDim2.fromScale(1, 1)
					checkboxHitbox.ZIndex = 3
					checkboxHitbox.Parent = checkbox

					local TweenSettings = {
						Info = TweenInfo.new(0.15, Enum.EasingStyle.Quad),
						EnabledBackgroundColor = Color3.fromRGB(218, 219, 224),
						DisabledBackgroundColor = Color3.fromRGB(42, 43, 47),
						EnabledStrokeColor = Color3.fromRGB(232, 233, 236),
						DisabledStrokeColor = Color3.fromRGB(88, 90, 96),
						EnabledBackgroundTransparency = 0.02,
						DisabledBackgroundTransparency = 0.08,
						EnabledStrokeTransparency = 0.08,
						DisabledStrokeTransparency = 0.22,
						EnabledCheckTransparency = 0,
						DisabledCheckTransparency = 1
					}

					local checkboxBool = CheckboxFunctions.Settings.Default == true

					local function NewState(State, callback)
						local enabled = State == true

						Tween(checkboxButton, TweenSettings.Info, {
							BackgroundColor3 = enabled and TweenSettings.EnabledBackgroundColor
								or TweenSettings.DisabledBackgroundColor,
							BackgroundTransparency = enabled and TweenSettings.EnabledBackgroundTransparency
								or TweenSettings.DisabledBackgroundTransparency
						}):Play()

						Tween(checkboxStroke, TweenSettings.Info, {
							Color = enabled and TweenSettings.EnabledStrokeColor
								or TweenSettings.DisabledStrokeColor,
							Transparency = enabled and TweenSettings.EnabledStrokeTransparency
								or TweenSettings.DisabledStrokeTransparency
						}):Play()

						Tween(checkmark, TweenSettings.Info, {
							TextTransparency = enabled and TweenSettings.EnabledCheckTransparency
								or TweenSettings.DisabledCheckTransparency
						}):Play()

						CheckboxFunctions.State = enabled
						CheckboxFunctions.Value = enabled
						optionCall(callback, enabled)
					end

					NewState(checkboxBool)

					local function Toggle()
						checkboxBool = not checkboxBool
						NewState(checkboxBool, CheckboxFunctions.Settings.Callback)
					end

					checkboxButton.MouseButton1Click:Connect(Toggle)
					checkboxHitbox.MouseButton1Click:Connect(Toggle)

					function CheckboxFunctions:Toggle()
						Toggle()
					end
					function CheckboxFunctions:UpdateState(State)
						checkboxBool = State == true
						NewState(checkboxBool, CheckboxFunctions.Settings.Callback)
					end
					function CheckboxFunctions:SetValue(State)
						self:UpdateState(State)
					end
					function CheckboxFunctions:GetState()
						return checkboxBool
					end
					function CheckboxFunctions:GetValue()
						return checkboxBool
					end
					function CheckboxFunctions:UpdateName(Name)
						checkboxName.Text = Name
					end
					function CheckboxFunctions:SetVisibility(State)
						checkbox.Visible = State
					end

					if Flag then
						MacLib.Options[Flag] = CheckboxFunctions
					end
					return CheckboxFunctions
				end

				function SectionFunctions:Slider(Settings, Flag)
					Settings, Flag = optionArgs(Settings, Flag)
					Settings.Name = optionText(Settings, Flag, "Slider")
					Settings.Minimum = tonumber(optionFirstNonNil(Settings.Minimum, Settings.Min)) or 0
					Settings.Maximum = tonumber(optionFirstNonNil(Settings.Maximum, Settings.Max)) or 100
					if Settings.Maximum < Settings.Minimum then
						Settings.Minimum, Settings.Maximum = Settings.Maximum, Settings.Minimum
					end
					Settings.Precision = tonumber(optionFirstNonNil(Settings.Precision, Settings.Rounding)) or 0
					Settings.Default = optionClampNumber(optionFirstNonNil(Settings.Default, Settings.Value, Settings.Minimum), Settings.Minimum, Settings.Maximum)
					local SliderFunctions = { Settings = Settings, IgnoreConfig = false, Class = "Slider" }
					local slider = Instance.new("Frame")
					slider.Name = "Slider"
					slider.AutomaticSize = Enum.AutomaticSize.Y
					slider.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					slider.BackgroundTransparency = 1
					slider.BorderColor3 = Color3.fromRGB(0, 0, 0)
					slider.BorderSizePixel = 0
					slider.Size = UDim2.new(1, 0, 0, 32)
					slider.Parent = section

					local sliderName = Instance.new("TextLabel")
					sliderName.Name = "SliderName"
					sliderName.FontFace = SafeFont(assets.interFont)
					sliderName.Text = SliderFunctions.Settings.Name
					sliderName.RichText = true
					sliderName.TextColor3 = Color3.fromRGB(255, 255, 255)
					sliderName.TextSize = 13
					sliderName.TextTransparency = 0.5
					sliderName.TextTruncate = Enum.TextTruncate.AtEnd
					sliderName.TextXAlignment = Enum.TextXAlignment.Left
					sliderName.TextYAlignment = Enum.TextYAlignment.Top
					sliderName.AnchorPoint = Vector2.new(0, 0.5)
					sliderName.AutomaticSize = Enum.AutomaticSize.XY
					sliderName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					sliderName.BackgroundTransparency = 1
					sliderName.BorderColor3 = Color3.fromRGB(0, 0, 0)
					sliderName.BorderSizePixel = 0
					sliderName.Position = UDim2.fromScale(1.3e-07, 0.5)
					sliderName.Parent = slider

					local sliderElements = Instance.new("Frame")
					sliderElements.Name = "SliderElements"
					sliderElements.AnchorPoint = Vector2.new(1, 0)
					sliderElements.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					sliderElements.BackgroundTransparency = 1
					sliderElements.BorderColor3 = Color3.fromRGB(0, 0, 0)
					sliderElements.BorderSizePixel = 0
					sliderElements.Position = UDim2.fromScale(1, 0)
					sliderElements.Size = UDim2.fromScale(1, 1)

					local sliderValue = Instance.new("TextLabel")
					sliderValue.Name = "SliderValue"
					sliderValue.Active = false
					sliderValue.FontFace = SafeFont(assets.interFont)
					sliderValue.TextColor3 = Color3.fromRGB(255, 255, 255)
					sliderValue.TextSize = 11
					sliderValue.TextScaled = false
					sliderValue.TextTransparency = 0
					sliderValue.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
					sliderValue.TextStrokeTransparency = 0.18
					sliderValue.TextXAlignment = Enum.TextXAlignment.Center
					sliderValue.TextYAlignment = Enum.TextYAlignment.Center
					sliderValue.TextTruncate = Enum.TextTruncate.AtEnd
					sliderValue.AnchorPoint = Vector2.new(0.5, 0.5)
					sliderValue.AutomaticSize = Enum.AutomaticSize.X
					sliderValue.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
					sliderValue.BackgroundTransparency = 1
					sliderValue.BorderColor3 = Color3.fromRGB(0, 0, 0)
					sliderValue.BorderSizePixel = 0
					sliderValue.LayoutOrder = 1
					sliderValue.Position = UDim2.fromScale(0.5, 0.5)
					sliderValue.Size = UDim2.fromOffset(70, 16)
					sliderValue.ClipsDescendants = true
					sliderValue.ZIndex = 20

					local sliderValueUICorner = Instance.new("UICorner")
					sliderValueUICorner.Name = "SliderValueUICorner"
					sliderValueUICorner.CornerRadius = UDim.new(0, 0)
					sliderValueUICorner.Parent = sliderValue

					local sliderValueUIStroke = Instance.new("UIStroke")
					sliderValueUIStroke.Name = "SliderValueUIStroke"
					sliderValueUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					sliderValueUIStroke.Color = Color3.fromRGB(255, 255, 255)
					sliderValueUIStroke.Transparency = 1
					sliderValueUIStroke.Parent = sliderValue

					local sliderValueUIPadding = Instance.new("UIPadding")
					sliderValueUIPadding.Name = "SliderValueUIPadding"
					sliderValueUIPadding.PaddingLeft = UDim.new(0, 4)
					sliderValueUIPadding.PaddingRight = UDim.new(0, 4)
					sliderValueUIPadding.Parent = sliderValue

					local sliderValueTextSize = Instance.new("UITextSizeConstraint")
					sliderValueTextSize.Name = "SliderValueTextSizeConstraint"
					sliderValueTextSize.MaxTextSize = 11
					sliderValueTextSize.MinTextSize = 9
					sliderValueTextSize.Parent = sliderValue

					local sliderValueSizeConstraint = Instance.new("UISizeConstraint")
					sliderValueSizeConstraint.Name = "SliderValueSizeConstraint"
					sliderValueSizeConstraint.MinSize = Vector2.new(42, 16)
					sliderValueSizeConstraint.MaxSize = Vector2.new(126, 16)
					sliderValueSizeConstraint.Parent = sliderValue

					local sliderElementsUIListLayout = Instance.new("UIListLayout")
					sliderElementsUIListLayout.Name = "SliderElementsUIListLayout"
					sliderElementsUIListLayout.Padding = UDim.new(0, 20)
					sliderElementsUIListLayout.FillDirection = Enum.FillDirection.Horizontal
					sliderElementsUIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
					sliderElementsUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
					sliderElementsUIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
					sliderElementsUIListLayout.Parent = sliderElements

					local sliderBar = Instance.new("ImageButton")
					sliderBar.Name = "SliderBar"
					sliderBar.Active = true
					sliderBar.AutoButtonColor = false
					sliderBar.Image = assets.sliderbar
					sliderBar.ImageTransparency = 1
					sliderBar.ImageColor3 = Color3.fromRGB(87, 86, 86)
					sliderBar.BackgroundColor3 = Color3.fromRGB(38, 39, 42)
					sliderBar.BackgroundTransparency = 0.06
					sliderBar.BorderColor3 = Color3.fromRGB(0, 0, 0)
					sliderBar.BorderSizePixel = 0
					sliderBar.LayoutOrder = 1
					sliderBar.Position = UDim2.fromScale(0.219, 0.457)
					sliderBar.Size = UDim2.fromOffset(123, 14)
					sliderBar.ZIndex = 2

					local sliderBarCorner = Instance.new("UICorner")
					sliderBarCorner.Name = "SliderBarCorner"
					sliderBarCorner.CornerRadius = UDim.new(0, 0)
					sliderBarCorner.Parent = sliderBar

					local sliderFill = Instance.new("Frame")
					sliderFill.Name = "SliderFill"
					sliderFill.BackgroundColor3 = Color3.fromRGB(168, 170, 176)
					sliderFill.BackgroundTransparency = 0
					sliderFill.BorderSizePixel = 0
					sliderFill.Size = UDim2.fromScale(0, 1)
					sliderFill.ZIndex = sliderBar.ZIndex + 1
					sliderFill.Parent = sliderBar

					local sliderFillCorner = Instance.new("UICorner")
					sliderFillCorner.Name = "SliderFillCorner"
					sliderFillCorner.CornerRadius = UDim.new(0, 0)
					sliderFillCorner.Parent = sliderFill

					local sliderHitbox = Instance.new("TextButton")
					sliderHitbox.Name = "SliderHitbox"
					sliderHitbox.Text = ""
					sliderHitbox.AutoButtonColor = false
					sliderHitbox.Active = true
					sliderHitbox.AnchorPoint = Vector2.new(0.5, 0.5)
					sliderHitbox.BackgroundTransparency = 1
					sliderHitbox.BorderSizePixel = 0
					sliderHitbox.Position = UDim2.fromScale(0.5, 0.5)
					sliderHitbox.Size = UDim2.new(1, 18, 0, 28)
					sliderHitbox.ZIndex = 30
					sliderHitbox.Parent = sliderBar

					local sliderHead = Instance.new("ImageButton")
					sliderHead.Name = "SliderHead"
					sliderHead.Image = assets.sliderhead
					sliderHead.ImageTransparency = 1
					sliderHead.AutoButtonColor = false
					sliderHead.AnchorPoint = Vector2.new(0.5, 0.5)
					sliderHead.BackgroundColor3 = Color3.fromRGB(245, 245, 246)
					sliderHead.BackgroundTransparency = 0
					sliderHead.BorderColor3 = Color3.fromRGB(0, 0, 0)
					sliderHead.BorderSizePixel = 0
					sliderHead.Position = UDim2.fromScale(1, 0.5)
					sliderHead.Size = UDim2.fromOffset(8, 14)
					sliderHead.ZIndex = sliderBar.ZIndex + 2
					sliderHead.Parent = sliderBar

					sliderValue.Parent = sliderBar

					sliderBar.Parent = sliderElements

					local sliderElementsUIPadding = Instance.new("UIPadding")
					sliderElementsUIPadding.Name = "SliderElementsUIPadding"
					sliderElementsUIPadding.PaddingTop = UDim.new(0, 3)
					sliderElementsUIPadding.Parent = sliderElements

					sliderElements.Parent = slider

					local dragging = false

					local function getSliderBounds()
						local runtimeSettings = SliderFunctions.Settings or Settings or {}
						local minValue = tonumber(optionFirstNonNil(runtimeSettings.Minimum, runtimeSettings.Min, Settings.Minimum, Settings.Min)) or 0
						local maxValue = tonumber(optionFirstNonNil(runtimeSettings.Maximum, runtimeSettings.Max, Settings.Maximum, Settings.Max)) or 100
						if maxValue < minValue then
							minValue, maxValue = maxValue, minValue
						end

						local precision = tonumber(optionFirstNonNil(runtimeSettings.Precision, runtimeSettings.Rounding, Settings.Precision, Settings.Rounding)) or 0
						runtimeSettings.Minimum = minValue
						runtimeSettings.Maximum = maxValue
						runtimeSettings.Precision = precision
						runtimeSettings.Default = optionClampNumber(optionFirstNonNil(runtimeSettings.Default, runtimeSettings.Value, Settings.Default, minValue), minValue, maxValue)
						SliderFunctions.Settings = runtimeSettings
						return minValue, maxValue, precision
					end

					local DisplayMethods = {
						Hundredths = function(sliderValue) -- Deprecated use Settings.Precision
							return string.format("%.2f", sliderValue)
						end,
						Tenths = function(sliderValue) -- Deprecated use Settings.Precision
							return string.format("%.1f", sliderValue)
						end,
						Round = function(sliderValue, precision)
							if precision then
								return string.format("%." .. precision .. "f", sliderValue)
							else
								return tostring(math.round(sliderValue))
							end
						end,
						Degrees = function(sliderValue, precision)
							local formattedValue = precision and string.format("%." .. precision .. "f", sliderValue) or tostring(sliderValue)
							return formattedValue .. "°"
						end,
						Percent = function(sliderValue, precision)
							local minValue, maxValue = getSliderBounds()
							local range = maxValue - minValue
							local percentage = range == 0 and 0 or ((sliderValue - minValue) / range) * 100
							return precision and string.format("%." .. precision .. "f", percentage) .. "%" or tostring(math.round(percentage)) .. "%"
						end,
						Value = function(sliderValue, precision)
							return precision and string.format("%." .. precision .. "f", sliderValue) or tostring(sliderValue)
						end
					}

					local ValueDisplayMethod = DisplayMethods[SliderFunctions.Settings.DisplayMethod] or DisplayMethods.Value
					local finalValue

					local function formatSliderValue(value)
						local _, maxValue, precision = getSliderBounds()
						local prefix = tostring(optionFirstNonNil(SliderFunctions.Settings.Prefix, Settings.Prefix, ""))
						local suffix = tostring(optionFirstNonNil(SliderFunctions.Settings.Suffix, Settings.Suffix, ""))
						return prefix
							.. ValueDisplayMethod(value, precision)
							.. "/"
							.. ValueDisplayMethod(maxValue, precision)
							.. suffix
					end

					local function setSliderDisplayText(value)
						sliderValue.Text = formatSliderValue(value)
					end

					local function applySliderVisual(posXScale)
						posXScale = math.clamp(tonumber(posXScale) or 0, 0, 1)
						local headWidth = sliderHead.AbsoluteSize.X
						if headWidth <= 0 then
							headWidth = sliderHead.Size.X.Offset
						end
						local headHalf = math.max(0, headWidth / 2)
						sliderHead.Position = UDim2.new(posXScale, headHalf - (posXScale * headHalf * 2), 0.5, 0)
						sliderFill.Size = UDim2.fromScale(posXScale, 1)
					end

					local function getPointerX(input)
						if input and input.UserInputType == Enum.UserInputType.Touch and input.Position then
							return input.Position.X
						end

						local mouse = LocalPlayer and LocalPlayer:GetMouse()
						if mouse then
							return mouse.X
						end

						local ok, mouseLocation = pcall(function()
							return UserInputService:GetMouseLocation()
						end)
						if ok and mouseLocation then
							return mouseLocation.X
						end

						if input and input.Position then
							return input.Position.X
						end

						return sliderBar.AbsolutePosition.X
					end

					local function setValueFromX(x, ignorecallback)
						local minValue, maxValue, precision = getSliderBounds()
						local range = maxValue - minValue
						local width = math.max(sliderBar.AbsoluteSize.X, 1)
						local posXScale = math.clamp((tonumber(x) or sliderBar.AbsolutePosition.X) - sliderBar.AbsolutePosition.X, 0, width) / width
						local previousValue = finalValue

						applySliderVisual(posXScale)
						finalValue = optionClampNumber(optionRound(posXScale * range + minValue, precision), minValue, maxValue)
						SliderFunctions.Value = finalValue
						SliderFunctions.State = finalValue
						setSliderDisplayText(finalValue)

						if not ignorecallback and previousValue ~= finalValue then
							optionCall(SliderFunctions.Settings.Callback, finalValue)
							optionCall(SliderFunctions.Settings.Changed, finalValue)
						end
					end

					local function SetValue(val, ignorecallback)
						local posXScale
						local minValue, maxValue, precision = getSliderBounds()
						local range = maxValue - minValue

						if (typeof(val) == "InputObject" or type(val) == "table") and val.Position then
							setValueFromX(getPointerX(val), ignorecallback)
							return
						else
							local value, isPercent = optionExtractNumber(val)
							if value == nil then
								value = finalValue or SliderFunctions.Settings.Default or minValue
							elseif isPercent then
								value = minValue + (value / 100) * range
							end
							value = optionClampNumber(optionRound(value, precision), minValue, maxValue)
							posXScale = range == 0 and 0 or math.clamp(((value - minValue) / range), 0, 1)
						end

						local previousValue = finalValue
						applySliderVisual(posXScale)

						finalValue = optionClampNumber(optionRound(posXScale * range + minValue, precision), minValue, maxValue)
						SliderFunctions.Value = finalValue
						SliderFunctions.State = finalValue

						setSliderDisplayText(finalValue)

						if not ignorecallback and previousValue ~= finalValue then
							optionCall(SliderFunctions.Settings.Callback, finalValue)
							optionCall(SliderFunctions.Settings.Changed, finalValue)
						end
					end

					SetValue(SliderFunctions.Settings.Default, true)

					local dragRenderConnection

					local function beginSliderInput(input)
						if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
							return
						end

						dragging = true
						setValueFromX(getPointerX(input))

						if dragRenderConnection then
							dragRenderConnection:Disconnect()
						end
						dragRenderConnection = RunService.RenderStepped:Connect(function()
							if dragging then
								setValueFromX(getPointerX())
							end
						end)
					end

					sliderHead.InputBegan:Connect(function(input)
						beginSliderInput(input)
					end)

					sliderBar.InputBegan:Connect(function(input)
						beginSliderInput(input)
					end)

					sliderHitbox.InputBegan:Connect(function(input)
						beginSliderInput(input)
					end)

					local function finishSliderInput()
						if not dragging then return end
						dragging = false
						if dragRenderConnection then
							dragRenderConnection:Disconnect()
							dragRenderConnection = nil
						end
						optionCall(SliderFunctions.Settings.onInputComplete, finalValue)
					end

					sliderHead.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							finishSliderInput()
						end
					end)

					UserInputService.InputChanged:Connect(function(input)
						if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
							setValueFromX(getPointerX(input))
						end
					end)

					UserInputService.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							finishSliderInput()
						end
					end)

					local function updateSliderBarSize()
						local sliderNameWidth = sliderName.AbsoluteSize.X
						local totalWidth = sliderElements.AbsoluteSize.X

						local newBarWidth = math.max(92, (totalWidth - (sliderNameWidth + 24)) / math.max(baseUIScale.Scale, 0.001))
						sliderBar.Size = UDim2.new(sliderBar.Size.X.Scale, newBarWidth, sliderBar.Size.Y.Scale, sliderBar.Size.Y.Offset)
					end

					updateSliderBarSize()

					sliderName:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateSliderBarSize)
					section:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateSliderBarSize)

					function SliderFunctions:UpdateName(Name)
						sliderName.Text = Name
					end
					function SliderFunctions:SetVisibility(State)
						slider.Visible = State
					end
					function SliderFunctions:SetValue(Value, ignorecallback)
						SetValue(Value, ignorecallback)
					end
					function SliderFunctions:UpdateValue(Value, ignorecallback)
						SetValue(Value, ignorecallback ~= false)
					end
					function SliderFunctions:GetValue()
						return finalValue
					end
					function SliderFunctions:GetState()
						return finalValue
					end

					if Flag then
						MacLib.Options[Flag] = SliderFunctions
					end
					return SliderFunctions
				end

				function SectionFunctions:Input(Settings, Flag)
					Settings, Flag = optionArgs(Settings, Flag)
					Settings.Name = optionText(Settings, Flag, "Input")
					Settings.Default = tostring(optionFirstNonNil(Settings.Default, Settings.Value, ""))
					Settings.Placeholder = tostring(optionFirstNonNil(Settings.Placeholder, Settings.PlaceholderText, ""))
					Settings.AcceptedCharacters = Settings.Numeric and "Numeric" or (Settings.AcceptedCharacters or "All")
					Settings.ClearTextOnFocus = Settings.ClearTextOnFocus == true
					local InputFunctions = { Settings = Settings, IgnoreConfig = false, Class = "Input" }
					local input = Instance.new("Frame")
					input.Name = "Input"
					input.AutomaticSize = Enum.AutomaticSize.Y
					input.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					input.BackgroundTransparency = 1
					input.BorderColor3 = Color3.fromRGB(0, 0, 0)
					input.BorderSizePixel = 0
					input.Size = UDim2.new(1, 0, 0, 32)
					input.Parent = section

					local inputName = Instance.new("TextLabel")
					inputName.Name = "InputName"
					inputName.FontFace = SafeFont(assets.interFont)
					inputName.Text = InputFunctions.Settings.Name
					inputName.RichText = true
					inputName.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputName.TextSize = 13
					inputName.TextTransparency = 0.5
					inputName.TextTruncate = Enum.TextTruncate.AtEnd
					inputName.TextXAlignment = Enum.TextXAlignment.Left
					inputName.TextYAlignment = Enum.TextYAlignment.Top
					inputName.AnchorPoint = Vector2.new(0, 0.5)
					inputName.AutomaticSize = Enum.AutomaticSize.XY
					inputName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputName.BackgroundTransparency = 1
					inputName.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputName.BorderSizePixel = 0
					inputName.Position = UDim2.fromScale(0, 0.5)
					inputName.Parent = input

					local inputBox = Instance.new("TextBox")
					inputBox.Name = "InputBox"
					inputBox.ClearTextOnFocus = InputFunctions.Settings.ClearTextOnFocus
					inputBox.FontFace = SafeFont(assets.interFont)
					inputBox.Text = ""
					inputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputBox.TextSize = 12
					inputBox.TextTransparency = 0.1
					inputBox.AnchorPoint = Vector2.new(1, 0.5)
					inputBox.AutomaticSize = Enum.AutomaticSize.X
					inputBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputBox.BackgroundTransparency = 0.95
					inputBox.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputBox.BorderSizePixel = 0
					inputBox.ClipsDescendants = true
					inputBox.LayoutOrder = 1
					inputBox.Position = UDim2.fromScale(1, 0.5)
					inputBox.Size = UDim2.fromOffset(21, 21)
					inputBox.TextXAlignment = Enum.TextXAlignment.Right

					local inputBoxUICorner = Instance.new("UICorner")
					inputBoxUICorner.Name = "InputBoxUICorner"
					inputBoxUICorner.CornerRadius = UDim.new(0, 0)
					inputBoxUICorner.Parent = inputBox

					local inputBoxUIStroke = Instance.new("UIStroke")
					inputBoxUIStroke.Name = "InputBoxUIStroke"
					inputBoxUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					inputBoxUIStroke.Color = Color3.fromRGB(255, 255, 255)
					inputBoxUIStroke.Transparency = 0.9
					inputBoxUIStroke.Parent = inputBox

					local inputBoxUIPadding = Instance.new("UIPadding")
					inputBoxUIPadding.Name = "InputBoxUIPadding"
					inputBoxUIPadding.PaddingLeft = UDim.new(0, 5)
					inputBoxUIPadding.PaddingRight = UDim.new(0, 5)
					inputBoxUIPadding.Parent = inputBox

					local inputBoxUISizeConstraint = Instance.new("UISizeConstraint")
					inputBoxUISizeConstraint.Name = "InputBoxUISizeConstraint"
					inputBoxUISizeConstraint.Parent = inputBox

					inputBox.Parent = input

					local Input = input
					local InputBox = inputBox
					local InputName = inputName
					local Constraint = inputBoxUISizeConstraint

					local function applyCharacterLimit(value)
						if InputFunctions.Settings.CharacterLimit then
							return value:sub(1, InputFunctions.Settings.CharacterLimit)
						end
						return value
					end

					local CharacterSubs = {
						All = function(value)
							return applyCharacterLimit(value)
						end,
						Numeric = function(value)
							local text = tostring(value or "")
							local sign = text:sub(1, 1) == "-" and "-" or ""
							text = text:gsub("[^%d%.]", "")
							local dotUsed = false
							text = text:gsub("%.", function()
								if dotUsed then
									return ""
								end
								dotUsed = true
								return "."
							end)
							local result = sign .. text
							return applyCharacterLimit(result)
						end,
						Alphabetic = function(value)
							return applyCharacterLimit(value:gsub("[^a-zA-Z ]", ""))
						end,
						AlphaNumeric = function(value)
							return applyCharacterLimit(value:gsub("[^a-zA-Z0-9]", ""))
						end,
					}

					local AcceptedCharacters

					if type(InputFunctions.Settings.AcceptedCharacters) == "function" then
						AcceptedCharacters = InputFunctions.Settings.AcceptedCharacters
					else
						AcceptedCharacters = CharacterSubs[InputFunctions.Settings.AcceptedCharacters] or CharacterSubs.All
					end

					InputBox.AutomaticSize = Enum.AutomaticSize.X

					local function checkSize()
						local nameWidth = InputName.AbsoluteSize.X
						local totalWidth = Input.AbsoluteSize.X

						local maxWidth = (totalWidth - nameWidth - 20) / baseUIScale.Scale
						Constraint.MaxSize = Vector2.new(maxWidth, 9e9)
					end

					checkSize()
					InputName:GetPropertyChangedSignal("AbsoluteSize"):Connect(checkSize)

					local updatingText = false

					local function setInputText(text, callback)
						local filteredText = AcceptedCharacters(tostring(text or ""))
						if filteredText == "" and InputFunctions.Settings.AllowEmpty == false then
							filteredText = tostring(optionFirstNonNil(InputFunctions.Settings.EmptyReset, InputFunctions.Settings.Default, ""))
						end

						updatingText = true
						InputBox.Text = filteredText
						updatingText = false

						InputFunctions.Text = filteredText
						InputFunctions.Value = filteredText

						if callback then
							optionCall(InputFunctions.Settings.Callback, filteredText)
							optionCall(InputFunctions.Settings.Changed, filteredText)
						end
						return filteredText
					end

					InputBox.FocusLost:Connect(function()
						local inputText = InputBox.Text
						setInputText(inputText, true)
					end)
					InputBox.Text = InputFunctions.Settings.Default
					InputBox.PlaceholderText = InputFunctions.Settings.Placeholder

					InputBox:GetPropertyChangedSignal("Text"):Connect(function()
						if updatingText then
							return
						end

						local filteredText = AcceptedCharacters(InputBox.Text)
						if filteredText ~= InputBox.Text then
							updatingText = true
							InputBox.Text = filteredText
							updatingText = false
						end
						InputFunctions.Text = filteredText
						InputFunctions.Value = filteredText
						optionCall(InputFunctions.Settings.onChanged or InputFunctions.Settings.ChangedCallback, filteredText)
					end)

					function InputFunctions:UpdateName(Name)
						inputName.Text = Name
					end
					function InputFunctions:SetVisibility(State)
						input.Visible = State
					end
					function InputFunctions:GetInput()
						return InputBox.Text
					end
					function InputFunctions:GetValue()
						return InputBox.Text
					end
					function InputFunctions:GetState()
						return InputBox.Text
					end
					function InputFunctions:UpdatePlaceholder(Placeholder)
						inputBox.PlaceholderText = Placeholder
					end
					function InputFunctions:UpdateText(Text)
						setInputText(Text, true)
					end
					function InputFunctions:SetValue(Text)
						setInputText(Text, true)
					end

					setInputText(InputFunctions.Settings.Default, false)

					if Flag then
						MacLib.Options[Flag] = InputFunctions
					end
					return InputFunctions
				end

				function SectionFunctions:Keybind(Settings, Flag)
					Settings, Flag = optionArgs(Settings, Flag)
					Settings.Name = optionText(Settings, Flag, "Keybind")
					local KeybindFunctions = { Settings = Settings, IgnoreConfig = false, Class = "Keybind" }
					local keybind = Instance.new("Frame")
					keybind.Name = "Keybind"
					keybind.AutomaticSize = Enum.AutomaticSize.Y
					keybind.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					keybind.BackgroundTransparency = 1
					keybind.BorderColor3 = Color3.fromRGB(0, 0, 0)
					keybind.BorderSizePixel = 0
					keybind.Size = UDim2.new(1, 0, 0, 32)
					keybind.Parent = section

					local keybindName = Instance.new("TextLabel")
					keybindName.Name = "KeybindName"
					keybindName.FontFace = SafeFont(assets.interFont)
					keybindName.Text = KeybindFunctions.Settings.Name
					keybindName.RichText = true
					keybindName.TextColor3 = Color3.fromRGB(255, 255, 255)
					keybindName.TextSize = 13
					keybindName.TextTransparency = 0.35
					keybindName.TextTruncate = Enum.TextTruncate.AtEnd
					keybindName.TextXAlignment = Enum.TextXAlignment.Left
					keybindName.TextYAlignment = Enum.TextYAlignment.Top
					keybindName.AnchorPoint = Vector2.new(0, 0.5)
					keybindName.AutomaticSize = Enum.AutomaticSize.Y
					keybindName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					keybindName.BackgroundTransparency = 1
					keybindName.BorderColor3 = Color3.fromRGB(0, 0, 0)
					keybindName.BorderSizePixel = 0
					keybindName.Position = UDim2.fromScale(0, 0.5)
					keybindName.Size = UDim2.new(1, -100, 0, 0)
					keybindName.Parent = keybind

					local binderBox = Instance.new("TextButton")
					binderBox.Name = "BinderBox"
					binderBox.FontFace = SafeFont(assets.interFont)
					binderBox.Text = ""
					binderBox.TextColor3 = Color3.fromRGB(255, 255, 255)
					binderBox.TextSize = 12
					binderBox.TextScaled = false
					binderBox.TextTransparency = 0
					binderBox.TextTruncate = Enum.TextTruncate.AtEnd
					binderBox.AnchorPoint = Vector2.new(1, 0.5)
					binderBox.AutomaticSize = Enum.AutomaticSize.X
					binderBox.AutoButtonColor = false
					binderBox.BackgroundColor3 = Color3.fromRGB(130, 130, 130)
					binderBox.BackgroundTransparency = 0.76
					binderBox.BorderColor3 = Color3.fromRGB(0, 0, 0)
					binderBox.BorderSizePixel = 0
					binderBox.ClipsDescendants = true
					binderBox.LayoutOrder = 1
					binderBox.Position = UDim2.fromScale(1, 0.5)
					binderBox.Size = UDim2.fromOffset(21, 21)
					binderBox.ZIndex = 10

					local binderBoxUICorner = Instance.new("UICorner")
					binderBoxUICorner.Name = "BinderBoxUICorner"
					binderBoxUICorner.CornerRadius = UDim.new(0, 0)
					binderBoxUICorner.Parent = binderBox

					local binderBoxUIStroke = Instance.new("UIStroke")
					binderBoxUIStroke.Name = "BinderBoxUIStroke"
					binderBoxUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					binderBoxUIStroke.Color = Color3.fromRGB(150, 150, 150)
					binderBoxUIStroke.Transparency = 0.35
					binderBoxUIStroke.Parent = binderBox

					local binderBoxTextSize = Instance.new("UITextSizeConstraint")
					binderBoxTextSize.Name = "BinderBoxTextSizeConstraint"
					binderBoxTextSize.MaxTextSize = 12
					binderBoxTextSize.MinTextSize = 9
					binderBoxTextSize.Parent = binderBox

					local binderBoxUIPadding = Instance.new("UIPadding")
					binderBoxUIPadding.Name = "BinderBoxUIPadding"
					binderBoxUIPadding.PaddingLeft = UDim.new(0, 6)
					binderBoxUIPadding.PaddingRight = UDim.new(0, 6)
					binderBoxUIPadding.Parent = binderBox

					local binderBoxUISizeConstraint = Instance.new("UISizeConstraint")
					binderBoxUISizeConstraint.Name = "BinderBoxUISizeConstraint"
					binderBoxUISizeConstraint.MinSize = Vector2.new(21, 21)
					binderBoxUISizeConstraint.MaxSize = Vector2.new(96, 21)
					binderBoxUISizeConstraint.Parent = binderBox

					binderBox.Parent = keybind

					local isBinding = false
					local reset = false
					local binded = optionResolveInput(optionFirstNonNil(
						KeybindFunctions.Settings.Default,
						KeybindFunctions.Settings.Value,
						KeybindFunctions.Settings.Key,
						KeybindFunctions.Settings.Bind,
						KeybindFunctions.Settings.Keybind
					))
					local suppressBinderClickUntil = 0

					local function getBindText(bind)
						local name
						if typeof(bind) == "EnumItem" then
							name = bind.Name
						else
							name = tostring(bind or "")
						end

						if name == "" or name == "None" or name == "nil" then
							return "-"
						end

						local shortNames = {
							MouseButton1 = "M1",
							MouseButton2 = "M2",
							MouseButton3 = "M3",
							LeftShift = "LS",
							RightShift = "RS",
							LeftControl = "LC",
							RightControl = "RC",
							LeftAlt = "LA",
							RightAlt = "RA",
							Space = "Space",
							Return = "EN",
							Backspace = "BK"
						}

						return shortNames[name] or (#name <= 6 and name or string.sub(name, 1, 6))
					end

					local function updateBindVisual(binding)
						if binding then
							binderBox.Text = "..."
							binderBox.TextColor3 = Color3.fromRGB(255, 255, 255)
							Tween(binderBox, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
								BackgroundColor3 = Color3.fromRGB(24, 24, 24),
								BackgroundTransparency = 0.08
							}):Play()
							Tween(binderBoxUIStroke, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
								Color = Color3.fromRGB(255, 255, 255),
								Transparency = 0.12
							}):Play()
						else
							binderBox.Text = getBindText(binded)
							binderBox.TextColor3 = Color3.fromRGB(255, 255, 255)
							Tween(binderBox, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
								BackgroundColor3 = binded and Color3.fromRGB(24, 24, 24) or Color3.fromRGB(130, 130, 130),
								BackgroundTransparency = binded and 0.08 or 0.76
							}):Play()
							Tween(binderBoxUIStroke, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
								Color = binded and Color3.fromRGB(224, 224, 224) or Color3.fromRGB(150, 150, 150),
								Transparency = binded and 0.12 or 0.35
							}):Play()
						end
					end

					local function resetBindingState()
						isBinding = false
						updateBindVisual(false)
					end

					local function canBindInput(input)
						return input.UserInputType == Enum.UserInputType.Keyboard
							or input.UserInputType == Enum.UserInputType.MouseButton1
							or input.UserInputType == Enum.UserInputType.MouseButton2
							or input.UserInputType == Enum.UserInputType.MouseButton3
					end

					local function setBind(newBind)
						binded = optionResolveInput(newBind)
						updateBindVisual(false)
						optionCall(KeybindFunctions.Settings.onBinded, binded)
						optionCall(KeybindFunctions.Settings.Changed, binded)
					end

					binderBox.MouseButton1Click:Connect(function()
						if tick() < suppressBinderClickUntil then
							return
						end

						if isBinding then
							resetBindingState()
							return
						end

						isBinding = true
						updateBindVisual(true)
					end)

					UserInputService.InputBegan:Connect(function(inp)
						if isBinding then
							if not canBindInput(inp) then
								return
							end

							if KeybindFunctions.Settings.Blacklist and (table.find(KeybindFunctions.Settings.Blacklist, inp.KeyCode) or table.find(KeybindFunctions.Settings.Blacklist, inp.UserInputType)) then
								resetBindingState()
								return
							end

							if inp.UserInputType == Enum.UserInputType.Keyboard then
								if inp.KeyCode == Enum.KeyCode.Escape or inp.KeyCode == Enum.KeyCode.Backspace or inp.KeyCode == Enum.KeyCode.Delete then
									binded = nil
									resetBindingState()
									optionCall(KeybindFunctions.Settings.onBinded, binded)
									optionCall(KeybindFunctions.Settings.Changed, binded)
									return
								end
								setBind(inp.KeyCode)
							else
								if inp.UserInputType == Enum.UserInputType.MouseButton1 then
									suppressBinderClickUntil = tick() + 0.2
								end
								setBind(inp.UserInputType)
							end
							reset = true
							isBinding = false
							return
						end

						if not reset and binded and (inp.KeyCode == binded or inp.UserInputType == binded) then
								optionCall(KeybindFunctions.Settings.Callback, binded)
								optionCall(KeybindFunctions.Settings.onBindHeld, true, binded)
						else
							reset = false
						end
					end)

					UserInputService.InputEnded:Connect(function(inp)
						if reset then
							reset = false
							return
						end

						if not isBinding then
							if inp.KeyCode == binded or inp.UserInputType == binded then
								optionCall(KeybindFunctions.Settings.onBindHeld, false, binded)
							end
						end
					end)

					function KeybindFunctions:Bind(Key)
						setBind(Key)
					end

					function KeybindFunctions:Unbind()
						binded = nil
						updateBindVisual(false)
					end

					function KeybindFunctions:GetBind()
						return binded
					end

					function KeybindFunctions:SetValue(Key)
						setBind(Key)
					end

					function KeybindFunctions:GetValue()
						return binded
					end

					function KeybindFunctions:GetState()
						return binded
					end

					function KeybindFunctions:UpdateName(Name)
						keybindName.Text = Name
					end

					function KeybindFunctions:SetVisibility(State)
						keybind.Visible = State
					end

					updateBindVisual(false)

					if Flag then
						MacLib.Options[Flag] = KeybindFunctions
					end

					return KeybindFunctions
				end

				function SectionFunctions:KeyPicker(Settings, Flag)
					return self:Keybind(Settings, Flag)
				end
				function SectionFunctions:keyPicker(Settings, Flag)
					return self:Keybind(Settings, Flag)
				end
				function SectionFunctions:KeyPicket(Settings, Flag)
					return self:Keybind(Settings, Flag)
				end
				function SectionFunctions:AddKeyPicker(Settings, Flag)
					return self:Keybind(Settings, Flag)
				end
				function SectionFunctions:addKeyPicker(Settings, Flag)
					return self:Keybind(Settings, Flag)
				end
				function SectionFunctions:AddKeyPicket(Settings, Flag)
					return self:Keybind(Settings, Flag)
				end
				function SectionFunctions:addKeyPicket(Settings, Flag)
					return self:Keybind(Settings, Flag)
				end
				function SectionFunctions:AddKeybind(Settings, Flag)
					return self:Keybind(Settings, Flag)
				end
				function SectionFunctions:addKeybind(Settings, Flag)
					return self:Keybind(Settings, Flag)
				end

				function SectionFunctions:Dropdown(Settings, Flag)
					Settings, Flag = optionArgs(Settings, Flag)
					Settings.Name = optionText(Settings, Flag, "Dropdown")
					Settings.Options = Settings.Options or Settings.Values or {}
					Settings.Multi = Settings.Multi == true
					Settings.Required = Settings.Required == true or Settings.AllowNull == false
					Settings.Search = Settings.Search == true or Settings.Searchable == true
					local DropdownFunctions = { Settings = Settings, IgnoreConfig = false, Class = "Dropdown" }
					local Selected = {}
					local OptionObjs = {}

					local dropdown = Instance.new("Frame")
					dropdown.Name = "Dropdown"
					dropdown.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					dropdown.BackgroundTransparency = 0.985
					dropdown.BorderColor3 = Color3.fromRGB(0, 0, 0)
					dropdown.BorderSizePixel = 0
					dropdown.Size = UDim2.new(1, 0, 0, 32)
					dropdown.Parent = section
					dropdown.ClipsDescendants = true

					local dropdownUIPadding = Instance.new("UIPadding")
					dropdownUIPadding.Name = "DropdownUIPadding"
					dropdownUIPadding.PaddingLeft = UDim.new(0, 15)
					dropdownUIPadding.PaddingRight = UDim.new(0, 15)
					dropdownUIPadding.Parent = dropdown

					local interact = Instance.new("TextButton")
					interact.Name = "Interact"
					interact.FontFace = SafeFont("rbxasset://fonts/families/SourceSansPro.json")
					interact.Text = ""
					interact.TextColor3 = Color3.fromRGB(0, 0, 0)
					interact.TextSize = 14
					interact.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					interact.BackgroundTransparency = 1
					interact.BorderColor3 = Color3.fromRGB(0, 0, 0)
					interact.BorderSizePixel = 0
					interact.Size = UDim2.new(1, 0, 0, 32)
					interact.Parent = dropdown

					local dropdownName = Instance.new("TextLabel")
					dropdownName.Name = "DropdownName"
					dropdownName.FontFace = SafeFont(assets.interFont)
					dropdownName.Text = DropdownFunctions.Settings.Name .. "..."
					dropdownName.RichText = true
					dropdownName.TextColor3 = Color3.fromRGB(255, 255, 255)
					dropdownName.TextSize = 13
					dropdownName.TextTransparency = 0.5
					dropdownName.TextTruncate = Enum.TextTruncate.SplitWord
					dropdownName.TextXAlignment = Enum.TextXAlignment.Left
					dropdownName.AutomaticSize = Enum.AutomaticSize.Y
					dropdownName.Text = DropdownFunctions.Settings.Name .. "..."
					dropdownName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					dropdownName.BackgroundTransparency = 1
					dropdownName.BorderColor3 = Color3.fromRGB(0, 0, 0)
					dropdownName.BorderSizePixel = 0
					dropdownName.Size = UDim2.new(1, -20, 0, 38)
					dropdownName.Parent = dropdown

					local dropdownUIStroke = Instance.new("UIStroke")
					dropdownUIStroke.Name = "DropdownUIStroke"
					dropdownUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					dropdownUIStroke.Color = Color3.fromRGB(255, 255, 255)
					dropdownUIStroke.Transparency = 0.95
					dropdownUIStroke.Parent = dropdown

					local dropdownUICorner = Instance.new("UICorner")
					dropdownUICorner.Name = "DropdownUICorner"
					dropdownUICorner.CornerRadius = UDim.new(0, 0)
					dropdownUICorner.Parent = dropdown

					local dropdownImage = Instance.new("ImageLabel")
					dropdownImage.Name = "DropdownImage"
					dropdownImage.Image = assets.dropdown
					dropdownImage.ImageTransparency = 0.5
					dropdownImage.AnchorPoint = Vector2.new(1, 0)
					dropdownImage.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					dropdownImage.BackgroundTransparency = 1
					dropdownImage.BorderColor3 = Color3.fromRGB(0, 0, 0)
					dropdownImage.BorderSizePixel = 0
					dropdownImage.Position = UDim2.new(1, 0, 0, 12)
					dropdownImage.Size = UDim2.fromOffset(14, 14)
					dropdownImage.Parent = dropdown

					local dropdownFrame = Instance.new("Frame")
					dropdownFrame.Name = "DropdownFrame"
					dropdownFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					dropdownFrame.BackgroundTransparency = 1
					dropdownFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
					dropdownFrame.BorderSizePixel = 0
					dropdownFrame.ClipsDescendants = true
					dropdownFrame.Size = UDim2.fromScale(1, 1)
					dropdownFrame.Visible = false
					dropdownFrame.AutomaticSize = Enum.AutomaticSize.Y

					local dropdownFrameUIPadding = Instance.new("UIPadding")
					dropdownFrameUIPadding.Name = "DropdownFrameUIPadding"
					dropdownFrameUIPadding.PaddingTop = UDim.new(0, 38)
					dropdownFrameUIPadding.PaddingBottom = UDim.new(0, 10)
					dropdownFrameUIPadding.Parent = dropdownFrame

					local dropdownFrameUIListLayout = Instance.new("UIListLayout")
					dropdownFrameUIListLayout.Name = "DropdownFrameUIListLayout"
					dropdownFrameUIListLayout.Padding = UDim.new(0, 5)
					dropdownFrameUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
					dropdownFrameUIListLayout.Parent = dropdownFrame

					local search = Instance.new("Frame")
					search.Name = "Search"
					search.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					search.BackgroundTransparency = 0.95
					search.BorderColor3 = Color3.fromRGB(0, 0, 0)
					search.BorderSizePixel = 0
					search.LayoutOrder = -1
					search.Size = UDim2.new(1, 0, 0, 30)
					search.Parent = dropdownFrame
					search.Visible = DropdownFunctions.Settings.Search

					local sectionUICorner = Instance.new("UICorner")
					sectionUICorner.Name = "SectionUICorner"
					sectionUICorner.Parent = search

					local searchIcon = Instance.new("ImageLabel")
					searchIcon.Name = "SearchIcon"
					searchIcon.Image = assets.searchIcon
					searchIcon.ImageColor3 = Color3.fromRGB(180, 180, 180)
					searchIcon.AnchorPoint = Vector2.new(0, 0.5)
					searchIcon.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					searchIcon.BackgroundTransparency = 1
					searchIcon.BorderColor3 = Color3.fromRGB(0, 0, 0)
					searchIcon.BorderSizePixel = 0
					searchIcon.Position = UDim2.fromScale(0, 0.5)
					searchIcon.Size = UDim2.fromOffset(12, 12)
					searchIcon.Parent = search

					local uIPadding = Instance.new("UIPadding")
					uIPadding.Name = "UIPadding"
					uIPadding.PaddingLeft = UDim.new(0, 15)
					uIPadding.Parent = search

					local searchBox = Instance.new("TextBox")
					searchBox.Name = "SearchBox"
					searchBox.CursorPosition = -1
					searchBox.FontFace = SafeFont(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					searchBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
					searchBox.PlaceholderText = "Search..."
					searchBox.Text = ""
					searchBox.TextColor3 = Color3.fromRGB(200, 200, 200)
					searchBox.TextSize = 14
					searchBox.TextXAlignment = Enum.TextXAlignment.Left
					searchBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					searchBox.BackgroundTransparency = 1
					searchBox.BorderColor3 = Color3.fromRGB(0, 0, 0)
					searchBox.BorderSizePixel = 0
					searchBox.Size = UDim2.fromScale(1, 1)

					local function CalculateDropdownSize()
						local totalHeight = 0
						local visibleChildrenCount = 0
						local padding = dropdownFrameUIPadding.PaddingTop.Offset + dropdownFrameUIPadding.PaddingBottom.Offset

						for _, v in pairs(dropdownFrame:GetChildren()) do
							if not v:IsA("UIComponent") and v.Visible then
								totalHeight += v.AbsoluteSize.Y
								visibleChildrenCount += 1
							end
						end

						local spacing = dropdownFrameUIListLayout.Padding.Offset * math.max(visibleChildrenCount - 1, 0)

						return totalHeight + spacing + padding
					end

					local function findOption()
						local searchTerm = searchBox.Text:lower()

						for _, v in pairs(OptionObjs) do
							local optionText = tostring(v.NameLabel.Text):lower()
							local isVisible = string.find(optionText, searchTerm) ~= nil

							if v.Button.Visible ~= isVisible then
								v.Button.Visible = isVisible
							end
						end

						dropdown.Size = UDim2.new(1, 0, 0, CalculateDropdownSize())
					end

					searchBox:GetPropertyChangedSignal("Text"):Connect(findOption)

					local uIPadding1 = Instance.new("UIPadding")
					uIPadding1.Name = "UIPadding"
					uIPadding1.PaddingLeft = UDim.new(0, 23)
					uIPadding1.Parent = searchBox

					searchBox.Parent = search

					local tweensettings = {
						duration = 0.2,
						easingStyle = Enum.EasingStyle.Quint,
						transparencyIn = 0.2,
						transparencyOut = 0.5,
						checkSizeIncrease = 12,
						checkSizeDecrease = -13,
						waitTime = 1
					}

					local function Toggle(optionName, State)
						local option = OptionObjs[optionName]

						if not option then return end
						if not State and DropdownFunctions.Settings.Required and #Selected <= 1 and table.find(Selected, optionName) then
							return
						end

						local checkmark = option.Checkmark
						local optionNameLabel = option.NameLabel

						if State then
							if DropdownFunctions.Settings.Multi then
								if not table.find(Selected, optionName) then
									table.insert(Selected, optionName)
								end
							else
								for name, opt in pairs(OptionObjs) do
									if name ~= optionName then
										Tween(opt.Checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
											Size = UDim2.new(opt.Checkmark.Size.X.Scale, tweensettings.checkSizeDecrease, opt.Checkmark.Size.Y.Scale, opt.Checkmark.Size.Y.Offset)
										}):Play()
										Tween(opt.NameLabel, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
											TextTransparency = tweensettings.transparencyOut
										}):Play()
										opt.Checkmark.TextTransparency = 1
									end
								end
								Selected = {optionName}
							end
							Tween(checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
								Size = UDim2.new(checkmark.Size.X.Scale, tweensettings.checkSizeIncrease, checkmark.Size.Y.Scale, checkmark.Size.Y.Offset)
							}):Play()
							Tween(optionNameLabel, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
								TextTransparency = tweensettings.transparencyIn
							}):Play()
							checkmark.TextTransparency = 0
						else
							if DropdownFunctions.Settings.Multi then
								local idx = table.find(Selected, optionName)
								if idx then
									table.remove(Selected, idx)
								end
							else
								Selected = {}
							end
							Tween(checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
								Size = UDim2.new(checkmark.Size.X.Scale, tweensettings.checkSizeDecrease, checkmark.Size.Y.Scale, checkmark.Size.Y.Offset)
							}):Play()
							Tween(optionNameLabel, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
								TextTransparency = tweensettings.transparencyOut
							}):Play()
							checkmark.TextTransparency = 1
						end

						if DropdownFunctions.Settings.Multi then
							local mapped = {}
							for _, selected in ipairs(Selected) do
								mapped[selected] = true
							end
							DropdownFunctions.Value = mapped
						else
							DropdownFunctions.Value = Selected[1]
						end

						if #Selected > 0 then
							local parts = {}
							for _, selected in ipairs(Selected) do
								table.insert(parts, tostring(selected))
							end
							dropdownName.Text = DropdownFunctions.Settings.Name .. " • " .. table.concat(parts, ", ")
						else
							dropdownName.Text = DropdownFunctions.Settings.Name .. "..."
						end
					end

					local dropped = false
					local db = false

					local function ToggleDropdown()
						if db then return end
						db = true
						local defaultDropdownSize = 38
						local isDropdownOpen = not dropped
						local targetSize = isDropdownOpen and UDim2.new(1, 0, 0, CalculateDropdownSize()) or UDim2.new(1, 0, 0, defaultDropdownSize)

						local dropTween = Tween(dropdown, TweenInfo.new(0.2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
							Size = targetSize
						})
						local iconTween = Tween(dropdownImage, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							Rotation = isDropdownOpen and -90 or 0
						})

						dropTween:Play()
						iconTween:Play()

						if isDropdownOpen then
							dropdownFrame.Visible = true
							dropTween.Completed:Connect(function()
								db = false
							end)
						else
							dropTween.Completed:Connect(function()
								dropdownFrame.Visible = false
								db = false
							end)
						end

						dropped = isDropdownOpen
					end

					interact.MouseButton1Click:Connect(ToggleDropdown)

					local function addOption(i, v)
						local optionValue = v
						local optionDisplay = tostring(v)
						local option = Instance.new("TextButton")
						option.Name = "Option"
						option.FontFace = SafeFont("rbxasset://fonts/families/SourceSansPro.json")
						option.Text = ""
						option.TextColor3 = Color3.fromRGB(0, 0, 0)
						option.TextSize = 14
						option.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
						option.BackgroundTransparency = 1
						option.BorderColor3 = Color3.fromRGB(0, 0, 0)
						option.BorderSizePixel = 0
						option.Size = UDim2.new(1, 0, 0, 30)

						local optionUIPadding = Instance.new("UIPadding")
						optionUIPadding.Name = "OptionUIPadding"
						optionUIPadding.PaddingLeft = UDim.new(0, 15)
						optionUIPadding.Parent = option

						local optionName = Instance.new("TextLabel")
						optionName.Name = "OptionName"
						optionName.FontFace = SafeFont(assets.interFont)
						optionName.Text = optionDisplay
						optionName.RichText = true
						optionName.TextColor3 = Color3.fromRGB(255, 255, 255)
						optionName.TextSize = 13
						optionName.TextTransparency = 0.5
						optionName.TextTruncate = Enum.TextTruncate.AtEnd
						optionName.TextXAlignment = Enum.TextXAlignment.Left
						optionName.TextYAlignment = Enum.TextYAlignment.Top
						optionName.AnchorPoint = Vector2.new(0, 0.5)
						optionName.AutomaticSize = Enum.AutomaticSize.XY
						optionName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
						optionName.BackgroundTransparency = 1
						optionName.BorderColor3 = Color3.fromRGB(0, 0, 0)
						optionName.BorderSizePixel = 0
						optionName.Position = UDim2.fromScale(1.3e-07, 0.5)
						optionName.Parent = option

						local optionUIListLayout = Instance.new("UIListLayout")
						optionUIListLayout.Name = "OptionUIListLayout"
						optionUIListLayout.Padding = UDim.new(0, 10)
						optionUIListLayout.FillDirection = Enum.FillDirection.Horizontal
						optionUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
						optionUIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
						optionUIListLayout.Parent = option

						local checkmark = Instance.new("TextLabel")
						checkmark.Name = "Checkmark"
						checkmark.FontFace = SafeFont(assets.interFont)
						checkmark.Text = "✓"
						checkmark.TextColor3 = Color3.fromRGB(255, 255, 255)
						checkmark.TextSize = 13
						checkmark.TextTransparency = 1
						checkmark.TextXAlignment = Enum.TextXAlignment.Left
						checkmark.TextYAlignment = Enum.TextYAlignment.Top
						checkmark.AnchorPoint = Vector2.new(0, 0.5)
						checkmark.AutomaticSize = Enum.AutomaticSize.Y
						checkmark.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
						checkmark.BackgroundTransparency = 1
						checkmark.BorderColor3 = Color3.fromRGB(0, 0, 0)
						checkmark.BorderSizePixel = 0
						checkmark.LayoutOrder = -1
						checkmark.Position = UDim2.fromScale(1.3e-07, 0.5)
						checkmark.Size = UDim2.fromOffset(-10, 0)
						checkmark.Parent = option

						option.Parent = dropdownFrame

						dropdownFrame.Parent = dropdown
						OptionObjs[optionValue] = {
							Index = i,
							Button = option,
							NameLabel = optionName,
							Checkmark = checkmark
						}

						local tweensettings = {
							duration = 0.2,
							easingStyle = Enum.EasingStyle.Quint,
							transparencyIn = 0.2,
							transparencyOut = 0.5,
							checkSizeIncrease = 12,
							checkSizeDecrease = -optionUIListLayout.Padding.Offset,
							waitTime = 1
						}
						local tweens = {
							checkIn = Tween(checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle), {
								Size = UDim2.new(checkmark.Size.X.Scale, tweensettings.checkSizeIncrease, checkmark.Size.Y.Scale, checkmark.Size.Y.Offset)
							}),
							checkOut = Tween(checkmark, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle),{
								Size = UDim2.new(checkmark.Size.X.Scale, tweensettings.checkSizeDecrease, checkmark.Size.Y.Scale, checkmark.Size.Y.Offset)
							}),
							nameIn = Tween(optionName, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle),{
								TextTransparency = tweensettings.transparencyIn
							}),
							nameOut = Tween(optionName, TweenInfo.new(tweensettings.duration, tweensettings.easingStyle),{
								TextTransparency = tweensettings.transparencyOut
							})
						}

						local isSelected = false
						if DropdownFunctions.Settings.Default then
							if DropdownFunctions.Settings.Multi then
								if type(DropdownFunctions.Settings.Default) == "table" then
									isSelected = table.find(DropdownFunctions.Settings.Default, optionValue) ~= nil
										or DropdownFunctions.Settings.Default[optionValue] == true
										or DropdownFunctions.Settings.Default[optionDisplay] == true
								end
							else
								isSelected = DropdownFunctions.Settings.Default == i
									or DropdownFunctions.Settings.Default == optionValue
									or tostring(DropdownFunctions.Settings.Default) == optionDisplay
							end
						end
						Toggle(optionValue, isSelected)

						local option = OptionObjs[optionValue].Button

						option.MouseButton1Click:Connect(function()
							local isSelected = table.find(Selected, optionValue) and true or false
							local newSelected = not isSelected

							if DropdownFunctions.Settings.Required and not newSelected and #Selected <= 1 then
								return
							end

							Toggle(optionValue, newSelected)

							if DropdownFunctions.Settings.Multi then
								local Return = {}
								for _, opt in ipairs(Selected) do
									Return[opt] = true
								end
								DropdownFunctions.Value = Return
								optionCall(DropdownFunctions.Settings.Callback, Return)
								optionCall(DropdownFunctions.Settings.Changed, Return)
							else
								DropdownFunctions.Value = Selected[1]
								if newSelected or not DropdownFunctions.Settings.Required then
									optionCall(DropdownFunctions.Settings.Callback, DropdownFunctions.Value)
									optionCall(DropdownFunctions.Settings.Changed, DropdownFunctions.Value)
								end
							end
						end)

						if dropped then
							dropdown.Size = UDim2.new(1, 0, 0, CalculateDropdownSize())
						end
					end

					if DropdownFunctions.Settings.Options then
						for i, v in pairs(DropdownFunctions.Settings.Options) do
							addOption(i, v)
						end
					end

					function DropdownFunctions:UpdateName(New)
						dropdownName.Text = New
					end
					function DropdownFunctions:SetVisibility(State)
						dropdown.Visible = State
					end
					function DropdownFunctions:UpdateSelection(newSelection)
						if not newSelection and DropdownFunctions.Settings.Required then return end

						for option, _ in pairs(OptionObjs) do
							Toggle(option, false)
						end

						local selectedOptions = {}
						if type(newSelection) == "number" then
							for option, data in pairs(OptionObjs) do
								local isSelected = data.Index == newSelection
								Toggle(option, isSelected)
								if isSelected then
									table.insert(selectedOptions, option)
								end
							end
						elseif type(newSelection) == "string" then
							for option, data in pairs(OptionObjs) do
								local isSelected = option == newSelection
								Toggle(option, isSelected)
								if isSelected then
									table.insert(selectedOptions, option)
								end
							end
						elseif type(newSelection) == "table" then
							for option, _ in pairs(OptionObjs) do
								local isSelected = table.find(newSelection, option) ~= nil or newSelection[option] == true or newSelection[tostring(option)] == true
								Toggle(option, isSelected)
								if isSelected then
									table.insert(selectedOptions, option)
								end
							end
						end

						if DropdownFunctions.Settings.Multi then
							local Return = {}
							for _, opt in ipairs(selectedOptions) do
								Return[opt] = true
							end
							DropdownFunctions.Value = Return
							optionCall(DropdownFunctions.Settings.Callback, Return)
							optionCall(DropdownFunctions.Settings.Changed, Return)
						else
							DropdownFunctions.Value = selectedOptions[1]
							optionCall(DropdownFunctions.Settings.Callback, DropdownFunctions.Value)
							optionCall(DropdownFunctions.Settings.Changed, DropdownFunctions.Value)
						end
					end
					function DropdownFunctions:SetValue(newSelection)
						self:UpdateSelection(newSelection)
					end
					function DropdownFunctions:GetValue()
						return self.Value
					end
					function DropdownFunctions:GetState()
						return self.Value
					end
					function DropdownFunctions:InsertOptions(newOptions)
						if not newOptions then return end
						DropdownFunctions:ClearOptions()
						DropdownFunctions.Settings.Options = newOptions
						for i, v in pairs(newOptions) do
							addOption(i, v)
						end
					end
					function DropdownFunctions:ClearOptions()
						for _, optionData in pairs(OptionObjs) do
							optionData.Button:Destroy()
						end
						OptionObjs = {}
						Selected = {}
						DropdownFunctions.Value = DropdownFunctions.Settings.Multi and {} or nil
						dropdownName.Text = DropdownFunctions.Settings.Name .. "..."

						if dropped then
							dropdown.Size = UDim2.new(1, 0, 0, CalculateDropdownSize())
						end
					end
					function DropdownFunctions:GetOptions()
						local optionsStatus = {}

						for option, data in pairs(OptionObjs) do
							local isSelected = table.find(Selected, option) and true or false
							optionsStatus[option] = isSelected
						end

						return optionsStatus
					end

					function DropdownFunctions:RemoveOptions(remove)
						if not remove then return end
						for _, optionName in ipairs(remove) do
							local optionData = OptionObjs[optionName]

							if optionData then
								for i = #Selected, 1, -1 do
									if Selected[i] == optionName then
										table.remove(Selected, i)
									end
								end

								optionData.Button:Destroy()

								OptionObjs[optionName] = nil
							end
						end

						if dropped then
							dropdown.Size = UDim2.new(1, 0, 0, CalculateDropdownSize())
						end
					end
					function DropdownFunctions:IsOption(optionName)
						if not optionName then return end
						return OptionObjs[optionName] ~= nil
					end

					if Flag then
						MacLib.Options[Flag] = DropdownFunctions
					end

					return DropdownFunctions
				end

				function SectionFunctions:Colorpicker(Settings, Flag)
					Settings, Flag = optionArgs(Settings, Flag)
					Settings.Name = optionText(Settings, Flag, "Color")
					local ColorpickerFunctions = { Settings = Settings, IgnoreConfig = false, Class = "Colorpicker" }

					local alphaDefault = optionFirstNonNil(ColorpickerFunctions.Settings.Alpha, ColorpickerFunctions.Settings.Transparency)
					local isAlpha = alphaDefault ~= nil
					local defaultColor = optionFirstNonNil(ColorpickerFunctions.Settings.Default, ColorpickerFunctions.Settings.Color, ColorpickerFunctions.Settings.Value)
					if typeof(defaultColor) ~= "Color3" then
						defaultColor = Color3.fromRGB(255, 255, 255)
					end
					ColorpickerFunctions.Color = defaultColor
					ColorpickerFunctions.Value = ColorpickerFunctions.Color
					ColorpickerFunctions.Alpha = isAlpha and optionClampNumber(alphaDefault, 0, 1) or 0

					local colorpicker = Instance.new("Frame")
					colorpicker.Name = "Colorpicker"
					colorpicker.AutomaticSize = Enum.AutomaticSize.Y
					colorpicker.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					colorpicker.BackgroundTransparency = 1
					colorpicker.BorderColor3 = Color3.fromRGB(0, 0, 0)
					colorpicker.BorderSizePixel = 0
					colorpicker.Size = UDim2.new(1, 0, 0, 32)
					colorpicker.Parent = section

					local colorpickerName = Instance.new("TextLabel")
					colorpickerName.Name = "KeybindName"
					colorpickerName.FontFace = SafeFont(assets.interFont)
					colorpickerName.Text = Settings.Name
					colorpickerName.TextColor3 = Color3.fromRGB(255, 255, 255)
					colorpickerName.TextSize = 13
					colorpickerName.TextTransparency = 0.5
					colorpickerName.RichText = true
					colorpickerName.TextTruncate = Enum.TextTruncate.AtEnd
					colorpickerName.TextXAlignment = Enum.TextXAlignment.Left
					colorpickerName.TextYAlignment = Enum.TextYAlignment.Top
					colorpickerName.AnchorPoint = Vector2.new(0, 0.5)
					colorpickerName.AutomaticSize = Enum.AutomaticSize.XY
					colorpickerName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					colorpickerName.BackgroundTransparency = 1
					colorpickerName.BorderColor3 = Color3.fromRGB(0, 0, 0)
					colorpickerName.BorderSizePixel = 0
					colorpickerName.Position = UDim2.fromScale(0, 0.5)
					colorpickerName.Parent = colorpicker

					local colorCbg = Instance.new("ImageLabel")
					colorCbg.Name = "NewColor"
					colorCbg.Image = assets.grid
					colorCbg.ScaleType = Enum.ScaleType.Tile
					colorCbg.TileSize = UDim2.fromOffset(500, 500)
					colorCbg.AnchorPoint = Vector2.new(1, 0.5)
					colorCbg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					colorCbg.BackgroundTransparency = 1
					colorCbg.BorderColor3 = Color3.fromRGB(0, 0, 0)
					colorCbg.BorderSizePixel = 0
					colorCbg.Position = UDim2.fromScale(1, 0.5)
					colorCbg.Size = UDim2.fromOffset(21, 21)

					local colorC = Instance.new("Frame")
					colorC.Name = "Color"
					colorC.AnchorPoint = Vector2.new(0.5, 0.5)
					colorC.BackgroundColor3 = ColorpickerFunctions.Color
					colorC.BorderSizePixel = 0
					colorC.Position = UDim2.fromScale(0.5, 0.5)
					colorC.Size = UDim2.fromScale(1, 1)
					colorC.BackgroundTransparency = ColorpickerFunctions.Alpha or 0

					local uICorner = Instance.new("UICorner")
					uICorner.Name = "UICorner"
					uICorner.CornerRadius = UDim.new(0, 0)
					uICorner.Parent = colorC

					local interact = Instance.new("TextButton")
					interact.Name = "Interact"
					interact.FontFace = SafeFont("rbxasset://fonts/families/SourceSansPro.json")
					interact.Text = ""
					interact.TextColor3 = Color3.fromRGB(0, 0, 0)
					interact.TextSize = 14
					interact.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					interact.BackgroundTransparency = 1
					interact.BorderColor3 = Color3.fromRGB(0, 0, 0)
					interact.BorderSizePixel = 0
					interact.Size = UDim2.fromScale(1, 1)
					interact.Parent = colorC

					colorC.Parent = colorCbg

					local uICorner1 = Instance.new("UICorner")
					uICorner1.Name = "UICorner"
					uICorner1.CornerRadius = UDim.new(0, 0)
					uICorner1.Parent = colorCbg

					colorCbg.Parent = colorpicker

					local colorPicker = Instance.new("Frame")
					colorPicker.Name = "ColorPicker"
					colorPicker.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					colorPicker.BackgroundTransparency = 0.5
					colorPicker.BorderColor3 = Color3.fromRGB(0, 0, 0)
					colorPicker.BorderSizePixel = 0
					colorPicker.Size = UDim2.fromScale(1, 1)
					colorPicker.Visible = false

					local baseUICorner = Instance.new("UICorner")
					baseUICorner.Name = "BaseUICorner"
					baseUICorner.CornerRadius = UDim.new(0, 0)
					baseUICorner.Parent = colorPicker

					local prompt = Instance.new("Frame")
					prompt.Name = "Prompt"
					prompt.AnchorPoint = Vector2.new(0.5, 0.5)
					prompt.AutomaticSize = Enum.AutomaticSize.Y
					prompt.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
					prompt.BorderColor3 = Color3.fromRGB(0, 0, 0)
					prompt.BorderSizePixel = 0
					prompt.Position = UDim2.fromScale(0.5, 0.5)
					prompt.Size = UDim2.fromOffset(420, 0)

					local promptUIScale = Instance.new("UIScale")
					promptUIScale.Name = "BaseUIScale"
					promptUIScale.Parent = prompt
					promptUIScale.Scale = 0.95

					local globalSettingsUIStroke = Instance.new("UIStroke")
					globalSettingsUIStroke.Name = "GlobalSettingsUIStroke"
					globalSettingsUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					globalSettingsUIStroke.Color = Color3.fromRGB(255, 255, 255)
					globalSettingsUIStroke.Transparency = 0.9
					globalSettingsUIStroke.Parent = prompt

					local globalSettingsUICorner = Instance.new("UICorner")
					globalSettingsUICorner.Name = "GlobalSettingsUICorner"
					globalSettingsUICorner.CornerRadius = UDim.new(0, 0)
					globalSettingsUICorner.Parent = prompt

					local uIListLayout = Instance.new("UIListLayout")
					uIListLayout.Name = "UIListLayout"
					uIListLayout.Padding = UDim.new(0, 10)
					uIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
					uIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout.Parent = prompt

					local colorOptions = Instance.new("Frame")
					colorOptions.Name = "ColorOptions"
					colorOptions.AutomaticSize = Enum.AutomaticSize.XY
					colorOptions.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					colorOptions.BackgroundTransparency = 1
					colorOptions.BorderColor3 = Color3.fromRGB(0, 0, 0)
					colorOptions.BorderSizePixel = 0
					colorOptions.LayoutOrder = 1
					colorOptions.Size = UDim2.fromScale(1, 0)

					local value = Instance.new("TextButton")
					value.Name = "Value"
					value.FontFace = SafeFont("rbxasset://fonts/families/SourceSansPro.json")
					value.Text = ""
					value.TextColor3 = Color3.fromRGB(0, 0, 0)
					value.TextSize = 14
					value.AutoButtonColor = false
					value.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					value.BorderColor3 = Color3.fromRGB(0, 0, 0)
					value.BorderSizePixel = 0
					value.LayoutOrder = 1
					value.Position = UDim2.fromScale(0.092, 0.886)
					value.Size = UDim2.new(1, 0, 0, 15)

					local uIGradient = Instance.new("UIGradient")
					uIGradient.Name = "UIGradient"
					uIGradient.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
						ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
						ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
						ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
						ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
						ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0))
					})
					uIGradient.Parent = value

					local slide = Instance.new("Frame")
					slide.Name = "Slide"
					slide.AnchorPoint = Vector2.new(0, 0.5)
					slide.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					slide.BorderColor3 = Color3.fromRGB(27, 42, 53)
					slide.BorderSizePixel = 0
					slide.Position = UDim2.fromScale(0, 0.5)
					slide.Size = UDim2.new(0, 13, 1, 8)

					local uICorner = Instance.new("UICorner")
					uICorner.Name = "UICorner"
					uICorner.CornerRadius = UDim.new(0, 0)
					uICorner.Parent = slide

					local uIStroke = Instance.new("UIStroke")
					uIStroke.Name = "UIStroke"
					uIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					uIStroke.Transparency = 0.5
					uIStroke.Parent = slide

					slide.Parent = value

					local uICorner1 = Instance.new("UICorner")
					uICorner1.Name = "UICorner"
					uICorner1.CornerRadius = UDim.new(0, 0)
					uICorner1.Parent = value

					local uIStroke1 = Instance.new("UIStroke")
					uIStroke1.Name = "UIStroke"
					uIStroke1.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					uIStroke1.Color = Color3.fromRGB(255, 255, 255)
					uIStroke1.Transparency = 0.9

					local uIGradient1 = Instance.new("UIGradient")
					uIGradient1.Name = "UIGradient"
					uIGradient1.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
					})
					uIGradient1.Rotation = 180
					uIGradient1.Parent = uIStroke1

					uIStroke1.Parent = value

					value.Parent = colorOptions

					local uIListLayout1 = Instance.new("UIListLayout")
					uIListLayout1.Name = "UIListLayout"
					uIListLayout1.Padding = UDim.new(0, 25)
					uIListLayout1.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout1.Parent = colorOptions

					local wheel = Instance.new("Frame")
					wheel.Name = "Wheel"
					wheel.AutomaticSize = Enum.AutomaticSize.Y
					wheel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					wheel.BackgroundTransparency = 1
					wheel.BorderColor3 = Color3.fromRGB(0, 0, 0)
					wheel.BorderSizePixel = 0
					wheel.Size = UDim2.new(1, 0, 0, 100)

					local wheel1 = Instance.new("ImageButton")
					wheel1.Name = "Wheel"
					wheel1.Image = ""
					wheel1.AutoButtonColor = false
					wheel1.Active = true
					wheel1.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
					wheel1.BackgroundTransparency = 0
					wheel1.BorderColor3 = Color3.fromRGB(27, 42, 53)
					wheel1.Selectable = false
					wheel1.Size = UDim2.fromOffset(220, 220)
					wheel1.SizeConstraint = Enum.SizeConstraint.RelativeYY
					wheel1.ClipsDescendants = true

					local wheelCorner = Instance.new("UICorner")
					wheelCorner.Name = "WheelCorner"
					wheelCorner.CornerRadius = UDim.new(0, 0)
					wheelCorner.Parent = wheel1

					local wheelStroke = Instance.new("UIStroke")
					wheelStroke.Name = "WheelStroke"
					wheelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					wheelStroke.Color = Color3.fromRGB(255, 255, 255)
					wheelStroke.Transparency = 0.85
					wheelStroke.Parent = wheel1

					local wheelHueGradient = Instance.new("Folder")
					wheelHueGradient.Name = "WheelHueGradient"
					wheelHueGradient.Parent = wheel1

					local saturationOverlay = Instance.new("Frame")
					saturationOverlay.Name = "SaturationOverlay"
					saturationOverlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					saturationOverlay.BorderSizePixel = 0
					saturationOverlay.Size = UDim2.fromScale(1, 1)
					saturationOverlay.ZIndex = wheel1.ZIndex + 1
					saturationOverlay.Parent = wheel1

					local saturationGradient = Instance.new("UIGradient")
					saturationGradient.Name = "SaturationGradient"
					saturationGradient.Rotation = 0
					saturationGradient.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(1, 1)
					})
					saturationGradient.Parent = saturationOverlay

					local valueOverlay = Instance.new("Frame")
					valueOverlay.Name = "ValueOverlay"
					valueOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					valueOverlay.BorderSizePixel = 0
					valueOverlay.Size = UDim2.fromScale(1, 1)
					valueOverlay.ZIndex = wheel1.ZIndex + 2
					valueOverlay.Parent = wheel1

					local valueGradient = Instance.new("UIGradient")
					valueGradient.Name = "ValueGradient"
					valueGradient.Rotation = 90
					valueGradient.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(1, 0)
					})
					valueGradient.Parent = valueOverlay

					local target = Instance.new("ImageLabel")
					target.Name = "Target"
					target.Image = assets.colorTarget
					target.ImageColor3 = Color3.fromRGB(255, 255, 255)
					target.AnchorPoint = Vector2.new(0.5, 0.5)
					target.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					target.BackgroundTransparency = 1
					target.BorderColor3 = Color3.fromRGB(27, 42, 53)
					target.Position = UDim2.fromScale(0.5, 0.5)
					target.Size = UDim2.fromOffset(22, 22)
					target.SizeConstraint = Enum.SizeConstraint.RelativeYY
					target.ZIndex = wheel1.ZIndex + 3
					target.Parent = wheel1

					wheel1.Parent = wheel

					local inputs = Instance.new("Frame")
					inputs.Name = "Inputs"
					inputs.AnchorPoint = Vector2.new(1, 0.5)
					inputs.AutomaticSize = Enum.AutomaticSize.XY
					inputs.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputs.BackgroundTransparency = 1
					inputs.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputs.BorderSizePixel = 0
					inputs.LayoutOrder = 1
					inputs.Position = UDim2.fromScale(1, 0.5)

					local uIListLayout2 = Instance.new("UIListLayout")
					uIListLayout2.Name = "UIListLayout"
					uIListLayout2.Padding = UDim.new(0, 5)
					uIListLayout2.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout2.Parent = inputs

					local red = Instance.new("Frame")
					red.Name = "Red"
					red.AutomaticSize = Enum.AutomaticSize.XY
					red.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					red.BackgroundTransparency = 1
					red.BorderColor3 = Color3.fromRGB(0, 0, 0)
					red.BorderSizePixel = 0
					red.LayoutOrder = 1
					red.Size = UDim2.fromOffset(0, 38)

					local inputName = Instance.new("TextLabel")
					inputName.Name = "InputName"
					inputName.FontFace = SafeFont(assets.interFont)
					inputName.Text = "Red"
					inputName.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputName.TextSize = 13
					inputName.TextTransparency = 0.5
					inputName.TextTruncate = Enum.TextTruncate.AtEnd
					inputName.TextXAlignment = Enum.TextXAlignment.Left
					inputName.TextYAlignment = Enum.TextYAlignment.Top
					inputName.AnchorPoint = Vector2.new(0, 0.5)
					inputName.AutomaticSize = Enum.AutomaticSize.XY
					inputName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputName.BackgroundTransparency = 1
					inputName.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputName.BorderSizePixel = 0
					inputName.LayoutOrder = 2
					inputName.Position = UDim2.fromScale(0, 0.5)
					inputName.Parent = red

					local uIListLayout3 = Instance.new("UIListLayout")
					uIListLayout3.Name = "UIListLayout"
					uIListLayout3.Padding = UDim.new(0, 15)
					uIListLayout3.FillDirection = Enum.FillDirection.Horizontal
					uIListLayout3.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout3.VerticalAlignment = Enum.VerticalAlignment.Center
					uIListLayout3.Parent = red

					local inputBox = Instance.new("TextBox")
					inputBox.Name = "InputBox"
					inputBox.ClearTextOnFocus = false
					inputBox.CursorPosition = -1
					inputBox.FontFace = SafeFont(assets.interFont)
					inputBox.Text = "255"
					inputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputBox.TextSize = 12
					inputBox.TextTransparency = 0.1
					inputBox.TextXAlignment = Enum.TextXAlignment.Left
					inputBox.AnchorPoint = Vector2.new(1, 0.5)
					inputBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputBox.BackgroundTransparency = 0.95
					inputBox.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputBox.BorderSizePixel = 0
					inputBox.ClipsDescendants = true
					inputBox.LayoutOrder = 1
					inputBox.Position = UDim2.fromScale(1, 0.5)
					inputBox.Size = UDim2.fromOffset(75, 25)

					local inputBoxUICorner = Instance.new("UICorner")
					inputBoxUICorner.Name = "InputBoxUICorner"
					inputBoxUICorner.CornerRadius = UDim.new(0, 0)
					inputBoxUICorner.Parent = inputBox

					local inputBoxUIStroke = Instance.new("UIStroke")
					inputBoxUIStroke.Name = "InputBoxUIStroke"
					inputBoxUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					inputBoxUIStroke.Color = Color3.fromRGB(255, 255, 255)
					inputBoxUIStroke.Transparency = 0.9
					inputBoxUIStroke.Parent = inputBox

					local inputBoxUISizeConstraint = Instance.new("UISizeConstraint")
					inputBoxUISizeConstraint.Name = "InputBoxUISizeConstraint"
					inputBoxUISizeConstraint.Parent = inputBox

					local inputBoxUIPadding = Instance.new("UIPadding")
					inputBoxUIPadding.Name = "InputBoxUIPadding"
					inputBoxUIPadding.PaddingLeft = UDim.new(0, 8)
					inputBoxUIPadding.PaddingRight = UDim.new(0, 10)
					inputBoxUIPadding.Parent = inputBox

					inputBox.Parent = red

					red.Parent = inputs

					local green = Instance.new("Frame")
					green.Name = "Green"
					green.AutomaticSize = Enum.AutomaticSize.XY
					green.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					green.BackgroundTransparency = 1
					green.BorderColor3 = Color3.fromRGB(0, 0, 0)
					green.BorderSizePixel = 0
					green.LayoutOrder = 2
					green.Size = UDim2.fromOffset(0, 38)

					local inputName1 = Instance.new("TextLabel")
					inputName1.Name = "InputName"
					inputName1.FontFace = SafeFont(assets.interFont)
					inputName1.Text = "Green"
					inputName1.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputName1.TextSize = 13
					inputName1.TextTransparency = 0.5
					inputName1.TextTruncate = Enum.TextTruncate.AtEnd
					inputName1.TextXAlignment = Enum.TextXAlignment.Left
					inputName1.TextYAlignment = Enum.TextYAlignment.Top
					inputName1.AnchorPoint = Vector2.new(0, 0.5)
					inputName1.AutomaticSize = Enum.AutomaticSize.XY
					inputName1.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputName1.BackgroundTransparency = 1
					inputName1.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputName1.BorderSizePixel = 0
					inputName1.LayoutOrder = 2
					inputName1.Position = UDim2.fromScale(0, 0.5)
					inputName1.Parent = green

					local uIListLayout4 = Instance.new("UIListLayout")
					uIListLayout4.Name = "UIListLayout"
					uIListLayout4.Padding = UDim.new(0, 15)
					uIListLayout4.FillDirection = Enum.FillDirection.Horizontal
					uIListLayout4.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout4.VerticalAlignment = Enum.VerticalAlignment.Center
					uIListLayout4.Parent = green

					local inputBox1 = Instance.new("TextBox")
					inputBox1.Name = "InputBox"
					inputBox1.ClearTextOnFocus = false
					inputBox1.FontFace = SafeFont(assets.interFont)
					inputBox1.Text = "255"
					inputBox1.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputBox1.TextSize = 12
					inputBox1.TextTransparency = 0.1
					inputBox1.TextXAlignment = Enum.TextXAlignment.Left
					inputBox1.AnchorPoint = Vector2.new(1, 0.5)
					inputBox1.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputBox1.BackgroundTransparency = 0.95
					inputBox1.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputBox1.BorderSizePixel = 0
					inputBox1.ClipsDescendants = true
					inputBox1.LayoutOrder = 1
					inputBox1.Position = UDim2.fromScale(1, 0.5)
					inputBox1.Size = UDim2.fromOffset(75, 25)

					local inputBoxUICorner1 = Instance.new("UICorner")
					inputBoxUICorner1.Name = "InputBoxUICorner"
					inputBoxUICorner1.CornerRadius = UDim.new(0, 0)
					inputBoxUICorner1.Parent = inputBox1

					local inputBoxUIStroke1 = Instance.new("UIStroke")
					inputBoxUIStroke1.Name = "InputBoxUIStroke"
					inputBoxUIStroke1.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					inputBoxUIStroke1.Color = Color3.fromRGB(255, 255, 255)
					inputBoxUIStroke1.Transparency = 0.9
					inputBoxUIStroke1.Parent = inputBox1

					local inputBoxUISizeConstraint1 = Instance.new("UISizeConstraint")
					inputBoxUISizeConstraint1.Name = "InputBoxUISizeConstraint"
					inputBoxUISizeConstraint1.Parent = inputBox1

					local inputBoxUIPadding1 = Instance.new("UIPadding")
					inputBoxUIPadding1.Name = "InputBoxUIPadding"
					inputBoxUIPadding1.PaddingLeft = UDim.new(0, 8)
					inputBoxUIPadding1.PaddingRight = UDim.new(0, 10)
					inputBoxUIPadding1.Parent = inputBox1

					inputBox1.Parent = green

					green.Parent = inputs

					local blue = Instance.new("Frame")
					blue.Name = "Blue"
					blue.AutomaticSize = Enum.AutomaticSize.XY
					blue.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					blue.BackgroundTransparency = 1
					blue.BorderColor3 = Color3.fromRGB(0, 0, 0)
					blue.BorderSizePixel = 0
					blue.LayoutOrder = 3
					blue.Size = UDim2.fromOffset(0, 38)

					local inputName2 = Instance.new("TextLabel")
					inputName2.Name = "InputName"
					inputName2.FontFace = SafeFont(assets.interFont)
					inputName2.Text = "Blue"
					inputName2.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputName2.TextSize = 13
					inputName2.TextTransparency = 0.5
					inputName2.TextTruncate = Enum.TextTruncate.AtEnd
					inputName2.TextXAlignment = Enum.TextXAlignment.Left
					inputName2.TextYAlignment = Enum.TextYAlignment.Top
					inputName2.AnchorPoint = Vector2.new(0, 0.5)
					inputName2.AutomaticSize = Enum.AutomaticSize.XY
					inputName2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputName2.BackgroundTransparency = 1
					inputName2.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputName2.BorderSizePixel = 0
					inputName2.LayoutOrder = 2
					inputName2.Position = UDim2.fromScale(0, 0.5)
					inputName2.Parent = blue

					local uIListLayout5 = Instance.new("UIListLayout")
					uIListLayout5.Name = "UIListLayout"
					uIListLayout5.Padding = UDim.new(0, 15)
					uIListLayout5.FillDirection = Enum.FillDirection.Horizontal
					uIListLayout5.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout5.VerticalAlignment = Enum.VerticalAlignment.Center
					uIListLayout5.Parent = blue

					local inputBox2 = Instance.new("TextBox")
					inputBox2.Name = "InputBox"
					inputBox2.ClearTextOnFocus = false
					inputBox2.FontFace = SafeFont(assets.interFont)
					inputBox2.Text = "255"
					inputBox2.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputBox2.TextSize = 12
					inputBox2.TextTransparency = 0.1
					inputBox2.TextXAlignment = Enum.TextXAlignment.Left
					inputBox2.AnchorPoint = Vector2.new(1, 0.5)
					inputBox2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputBox2.BackgroundTransparency = 0.95
					inputBox2.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputBox2.BorderSizePixel = 0
					inputBox2.ClipsDescendants = true
					inputBox2.LayoutOrder = 1
					inputBox2.Position = UDim2.fromScale(1, 0.5)
					inputBox2.Size = UDim2.fromOffset(75, 25)

					local inputBoxUICorner2 = Instance.new("UICorner")
					inputBoxUICorner2.Name = "InputBoxUICorner"
					inputBoxUICorner2.CornerRadius = UDim.new(0, 0)
					inputBoxUICorner2.Parent = inputBox2

					local inputBoxUIStroke2 = Instance.new("UIStroke")
					inputBoxUIStroke2.Name = "InputBoxUIStroke"
					inputBoxUIStroke2.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					inputBoxUIStroke2.Color = Color3.fromRGB(255, 255, 255)
					inputBoxUIStroke2.Transparency = 0.9
					inputBoxUIStroke2.Parent = inputBox2

					local inputBoxUISizeConstraint2 = Instance.new("UISizeConstraint")
					inputBoxUISizeConstraint2.Name = "InputBoxUISizeConstraint"
					inputBoxUISizeConstraint2.Parent = inputBox2

					local inputBoxUIPadding2 = Instance.new("UIPadding")
					inputBoxUIPadding2.Name = "InputBoxUIPadding"
					inputBoxUIPadding2.PaddingLeft = UDim.new(0, 8)
					inputBoxUIPadding2.PaddingRight = UDim.new(0, 10)
					inputBoxUIPadding2.Parent = inputBox2

					inputBox2.Parent = blue

					blue.Parent = inputs

					local alpha = Instance.new("Frame")
					alpha.Name = "Alpha"
					alpha.AutomaticSize = Enum.AutomaticSize.XY
					alpha.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					alpha.BackgroundTransparency = 1
					alpha.BorderColor3 = Color3.fromRGB(0, 0, 0)
					alpha.BorderSizePixel = 0
					alpha.LayoutOrder = 4
					alpha.Size = UDim2.fromOffset(0, 38)
					alpha.Visible = isAlpha

					local inputName3 = Instance.new("TextLabel")
					inputName3.Name = "InputName"
					inputName3.FontFace = SafeFont(assets.interFont)
					inputName3.Text = "Alpha"
					inputName3.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputName3.TextSize = 13
					inputName3.TextTransparency = 0.5
					inputName3.TextTruncate = Enum.TextTruncate.AtEnd
					inputName3.TextXAlignment = Enum.TextXAlignment.Left
					inputName3.TextYAlignment = Enum.TextYAlignment.Top
					inputName3.AnchorPoint = Vector2.new(0, 0.5)
					inputName3.AutomaticSize = Enum.AutomaticSize.XY
					inputName3.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputName3.BackgroundTransparency = 1
					inputName3.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputName3.BorderSizePixel = 0
					inputName3.LayoutOrder = 2
					inputName3.Position = UDim2.fromScale(0, 0.5)
					inputName3.Parent = alpha

					local uIListLayout6 = Instance.new("UIListLayout")
					uIListLayout6.Name = "UIListLayout"
					uIListLayout6.Padding = UDim.new(0, 15)
					uIListLayout6.FillDirection = Enum.FillDirection.Horizontal
					uIListLayout6.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout6.VerticalAlignment = Enum.VerticalAlignment.Center
					uIListLayout6.Parent = alpha

					local inputBox3 = Instance.new("TextBox")
					inputBox3.Name = "InputBox"
					inputBox3.ClearTextOnFocus = false
					inputBox3.FontFace = SafeFont(assets.interFont)
					inputBox3.Text = "0"
					inputBox3.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputBox3.TextSize = 12
					inputBox3.TextTransparency = 0.1
					inputBox3.TextXAlignment = Enum.TextXAlignment.Left
					inputBox3.AnchorPoint = Vector2.new(1, 0.5)
					inputBox3.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputBox3.BackgroundTransparency = 0.95
					inputBox3.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputBox3.BorderSizePixel = 0
					inputBox3.ClipsDescendants = true
					inputBox3.LayoutOrder = 1
					inputBox3.Position = UDim2.fromScale(1, 0.5)
					inputBox3.Size = UDim2.fromOffset(75, 25)

					local inputBoxUICorner3 = Instance.new("UICorner")
					inputBoxUICorner3.Name = "InputBoxUICorner"
					inputBoxUICorner3.CornerRadius = UDim.new(0, 0)
					inputBoxUICorner3.Parent = inputBox3

					local inputBoxUIStroke3 = Instance.new("UIStroke")
					inputBoxUIStroke3.Name = "InputBoxUIStroke"
					inputBoxUIStroke3.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					inputBoxUIStroke3.Color = Color3.fromRGB(255, 255, 255)
					inputBoxUIStroke3.Transparency = 0.9
					inputBoxUIStroke3.Parent = inputBox3

					local inputBoxUISizeConstraint3 = Instance.new("UISizeConstraint")
					inputBoxUISizeConstraint3.Name = "InputBoxUISizeConstraint"
					inputBoxUISizeConstraint3.Parent = inputBox3

					local inputBoxUIPadding3 = Instance.new("UIPadding")
					inputBoxUIPadding3.Name = "InputBoxUIPadding"
					inputBoxUIPadding3.PaddingLeft = UDim.new(0, 8)
					inputBoxUIPadding3.PaddingRight = UDim.new(0, 10)
					inputBoxUIPadding3.Parent = inputBox3

					inputBox3.Parent = alpha

					alpha.Parent = inputs

					local hex = Instance.new("Frame")
					hex.Name = "Hex"
					hex.AutomaticSize = Enum.AutomaticSize.XY
					hex.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					hex.BackgroundTransparency = 1
					hex.BorderColor3 = Color3.fromRGB(0, 0, 0)
					hex.BorderSizePixel = 0
					hex.Size = UDim2.fromOffset(0, 38)

					local inputName4 = Instance.new("TextLabel")
					inputName4.Name = "InputName"
					inputName4.FontFace = SafeFont(assets.interFont)
					inputName4.Text = "Hex"
					inputName4.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputName4.TextSize = 13
					inputName4.TextTransparency = 0.5
					inputName4.TextTruncate = Enum.TextTruncate.AtEnd
					inputName4.TextXAlignment = Enum.TextXAlignment.Left
					inputName4.TextYAlignment = Enum.TextYAlignment.Top
					inputName4.AnchorPoint = Vector2.new(0, 0.5)
					inputName4.AutomaticSize = Enum.AutomaticSize.XY
					inputName4.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputName4.BackgroundTransparency = 1
					inputName4.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputName4.BorderSizePixel = 0
					inputName4.LayoutOrder = 2
					inputName4.Position = UDim2.fromScale(0, 0.5)
					inputName4.Parent = hex

					local uIListLayout7 = Instance.new("UIListLayout")
					uIListLayout7.Name = "UIListLayout"
					uIListLayout7.Padding = UDim.new(0, 15)
					uIListLayout7.FillDirection = Enum.FillDirection.Horizontal
					uIListLayout7.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout7.VerticalAlignment = Enum.VerticalAlignment.Center
					uIListLayout7.Parent = hex

					local inputBox4 = Instance.new("TextBox")
					inputBox4.Name = "InputBox"
					inputBox4.ClearTextOnFocus = false
					inputBox4.CursorPosition = -1
					inputBox4.FontFace = SafeFont(assets.interFont)
					inputBox4.Text = "255"
					inputBox4.TextColor3 = Color3.fromRGB(255, 255, 255)
					inputBox4.TextSize = 12
					inputBox4.TextTransparency = 0.1
					inputBox4.TextXAlignment = Enum.TextXAlignment.Left
					inputBox4.AnchorPoint = Vector2.new(1, 0.5)
					inputBox4.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					inputBox4.BackgroundTransparency = 0.95
					inputBox4.BorderColor3 = Color3.fromRGB(0, 0, 0)
					inputBox4.BorderSizePixel = 0
					inputBox4.ClipsDescendants = true
					inputBox4.LayoutOrder = 1
					inputBox4.Position = UDim2.fromScale(1, 0.5)
					inputBox4.Size = UDim2.fromOffset(75, 25)

					local inputBoxUICorner4 = Instance.new("UICorner")
					inputBoxUICorner4.Name = "InputBoxUICorner"
					inputBoxUICorner4.CornerRadius = UDim.new(0, 0)
					inputBoxUICorner4.Parent = inputBox4

					local inputBoxUIStroke4 = Instance.new("UIStroke")
					inputBoxUIStroke4.Name = "InputBoxUIStroke"
					inputBoxUIStroke4.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					inputBoxUIStroke4.Color = Color3.fromRGB(255, 255, 255)
					inputBoxUIStroke4.Transparency = 0.9
					inputBoxUIStroke4.Parent = inputBox4

					local inputBoxUISizeConstraint4 = Instance.new("UISizeConstraint")
					inputBoxUISizeConstraint4.Name = "InputBoxUISizeConstraint"
					inputBoxUISizeConstraint4.Parent = inputBox4

					local inputBoxUIPadding4 = Instance.new("UIPadding")
					inputBoxUIPadding4.Name = "InputBoxUIPadding"
					inputBoxUIPadding4.PaddingLeft = UDim.new(0, 8)
					inputBoxUIPadding4.PaddingRight = UDim.new(0, 10)
					inputBoxUIPadding4.Parent = inputBox4

					inputBox4.Parent = hex

					hex.Parent = inputs

					inputs.Parent = wheel

					local uIPadding = Instance.new("UIPadding")
					uIPadding.Name = "UIPadding"
					uIPadding.PaddingRight = UDim.new(0, 5)
					uIPadding.Parent = wheel

					wheel.Parent = colorOptions

					local colorWells = Instance.new("Frame")
					colorWells.Name = "ColorWells"
					colorWells.AutomaticSize = Enum.AutomaticSize.Y
					colorWells.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					colorWells.BackgroundTransparency = 1
					colorWells.BorderColor3 = Color3.fromRGB(0, 0, 0)
					colorWells.BorderSizePixel = 0
					colorWells.LayoutOrder = 2
					colorWells.Size = UDim2.fromScale(1, 0)

					local uIGridLayout = Instance.new("UIGridLayout")
					uIGridLayout.Name = "UIGridLayout"
					uIGridLayout.CellPadding = UDim2.fromOffset(10, 0)
					uIGridLayout.CellSize = UDim2.new(0.5, -5, 0, 30)
					uIGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
					uIGridLayout.Parent = colorWells

					local newColor = Instance.new("ImageLabel")
					newColor.Name = "NewColor"
					newColor.Image = assets.grid
					newColor.ScaleType = Enum.ScaleType.Tile
					newColor.TileSize = UDim2.fromOffset(500, 500)
					newColor.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					newColor.BackgroundTransparency = 1
					newColor.BorderColor3 = Color3.fromRGB(0, 0, 0)
					newColor.BorderSizePixel = 0
					newColor.Size = UDim2.fromOffset(100, 100)

					local uICorner2 = Instance.new("UICorner")
					uICorner2.Name = "UICorner"
					uICorner2.Parent = newColor

					local color = Instance.new("Frame")
					color.Name = "Color"
					color.AnchorPoint = Vector2.new(0.5, 0.5)
					color.BorderColor3 = Color3.fromRGB(27, 42, 53)
					color.BorderSizePixel = 0
					color.Position = UDim2.fromScale(0.5, 0.5)
					color.Size = UDim2.new(1, 1, 1, 1)

					local uICorner3 = Instance.new("UICorner")
					uICorner3.Name = "UICorner"
					uICorner3.Parent = color

					color.Parent = newColor

					newColor.Parent = colorWells

					local oldColor = Instance.new("ImageLabel")
					oldColor.Name = "OldColor"
					oldColor.Image = assets.grid
					oldColor.ScaleType = Enum.ScaleType.Tile
					oldColor.TileSize = UDim2.fromOffset(500, 500)
					oldColor.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					oldColor.BackgroundTransparency = 1
					oldColor.BorderColor3 = Color3.fromRGB(0, 0, 0)
					oldColor.BorderSizePixel = 0
					oldColor.LayoutOrder = 1
					oldColor.Size = UDim2.fromOffset(100, 100)

					local uICorner4 = Instance.new("UICorner")
					uICorner4.Name = "UICorner"
					uICorner4.Parent = oldColor

					local color1 = Instance.new("Frame")
					color1.Name = "Color"
					color1.AnchorPoint = Vector2.new(0.5, 0.5)
					color1.BorderColor3 = Color3.fromRGB(27, 42, 53)
					color1.BorderSizePixel = 0
					color1.Position = UDim2.fromScale(0.5, 0.5)
					color1.Size = UDim2.new(1, 1, 1, 1)

					local uICorner5 = Instance.new("UICorner")
					uICorner5.Name = "UICorner"
					uICorner5.Parent = color1

					color1.Parent = oldColor

					oldColor.Parent = colorWells

					colorWells.Parent = colorOptions

					colorOptions.Parent = prompt

					local interactions = Instance.new("Frame")
					interactions.Name = "Interactions"
					interactions.AutomaticSize = Enum.AutomaticSize.Y
					interactions.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					interactions.BackgroundTransparency = 1
					interactions.BorderColor3 = Color3.fromRGB(0, 0, 0)
					interactions.BorderSizePixel = 0
					interactions.LayoutOrder = 2
					interactions.Size = UDim2.fromScale(1, 0)

					local uIListLayout8 = Instance.new("UIListLayout")
					uIListLayout8.Name = "UIListLayout"
					uIListLayout8.Padding = UDim.new(0, 10)
					uIListLayout8.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout8.Parent = interactions

					local confirm = Instance.new("TextButton")
					confirm.Name = "Confirm"
					confirm.FontFace = SafeFont(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					confirm.Text = "Confirm"
					confirm.TextColor3 = Color3.fromRGB(255, 255, 255)
					confirm.TextSize = 15
					confirm.TextTransparency = 0.5
					confirm.TextTruncate = Enum.TextTruncate.AtEnd
					confirm.AutoButtonColor = false
					confirm.AutomaticSize = Enum.AutomaticSize.Y
					confirm.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
					confirm.BorderColor3 = Color3.fromRGB(0, 0, 0)
					confirm.BorderSizePixel = 0
					confirm.Size = UDim2.fromScale(1, 0)

					local uIPadding1 = Instance.new("UIPadding")
					uIPadding1.Name = "UIPadding"
					uIPadding1.PaddingBottom = UDim.new(0, 9)
					uIPadding1.PaddingLeft = UDim.new(0, 10)
					uIPadding1.PaddingRight = UDim.new(0, 10)
					uIPadding1.PaddingTop = UDim.new(0, 9)
					uIPadding1.Parent = confirm

					local baseUICorner = Instance.new("UICorner")
					baseUICorner.Name = "BaseUICorner"
					baseUICorner.CornerRadius = UDim.new(0, 0)
					baseUICorner.Parent = confirm

					confirm.Parent = interactions

					local cancel = Instance.new("TextButton")
					cancel.Name = "Cancel"
					cancel.FontFace = SafeFont(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					cancel.Text = "Cancel"
					cancel.TextColor3 = Color3.fromRGB(255, 255, 255)
					cancel.TextSize = 15
					cancel.TextTransparency = 0.5
					cancel.TextTruncate = Enum.TextTruncate.AtEnd
					cancel.AutoButtonColor = false
					cancel.AutomaticSize = Enum.AutomaticSize.Y
					cancel.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
					cancel.BorderColor3 = Color3.fromRGB(0, 0, 0)
					cancel.BorderSizePixel = 0
					cancel.Size = UDim2.fromScale(1, 0)

					local baseUICorner1 = Instance.new("UICorner")
					baseUICorner1.Name = "BaseUICorner"
					baseUICorner1.CornerRadius = UDim.new(0, 0)
					baseUICorner1.Parent = cancel

					local uIPadding2 = Instance.new("UIPadding")
					uIPadding2.Name = "UIPadding"
					uIPadding2.PaddingBottom = UDim.new(0, 9)
					uIPadding2.PaddingLeft = UDim.new(0, 10)
					uIPadding2.PaddingRight = UDim.new(0, 10)
					uIPadding2.PaddingTop = UDim.new(0, 9)
					uIPadding2.Parent = cancel

					cancel.Parent = interactions

					local uIPadding3 = Instance.new("UIPadding")
					uIPadding3.Name = "UIPadding"
					uIPadding3.PaddingTop = UDim.new(0, 10)
					uIPadding3.Parent = interactions

					interactions.Parent = prompt

					local globalSettingsUIPadding = Instance.new("UIPadding")
					globalSettingsUIPadding.Name = "GlobalSettingsUIPadding"
					globalSettingsUIPadding.PaddingBottom = UDim.new(0, 20)
					globalSettingsUIPadding.PaddingLeft = UDim.new(0, 20)
					globalSettingsUIPadding.PaddingRight = UDim.new(0, 20)
					globalSettingsUIPadding.PaddingTop = UDim.new(0, 20)
					globalSettingsUIPadding.Parent = prompt

					local paragraph = Instance.new("Frame")
					paragraph.Name = "Paragraph"
					paragraph.AutomaticSize = Enum.AutomaticSize.Y
					paragraph.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					paragraph.BackgroundTransparency = 1
					paragraph.BorderColor3 = Color3.fromRGB(0, 0, 0)
					paragraph.BorderSizePixel = 0
					paragraph.Size = UDim2.fromScale(1, 0)

					local paragraphHeader = Instance.new("TextLabel")
					paragraphHeader.Name = "ParagraphHeader"
					paragraphHeader.FontFace = SafeFont(
						assets.interFont,
						Enum.FontWeight.SemiBold,
						Enum.FontStyle.Normal
					)
					paragraphHeader.RichText = true
					paragraphHeader.Text = ColorpickerFunctions.Settings.Name or ColorpickerFunctions.Settings.Text or tostring(Flag or "Color")
					paragraphHeader.TextColor3 = Color3.fromRGB(255, 255, 255)
					paragraphHeader.TextSize = 18
					paragraphHeader.TextTransparency = 0.4
					paragraphHeader.TextWrapped = true
					paragraphHeader.TextYAlignment = Enum.TextYAlignment.Top
					paragraphHeader.AutomaticSize = Enum.AutomaticSize.XY
					paragraphHeader.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					paragraphHeader.BackgroundTransparency = 1
					paragraphHeader.BorderColor3 = Color3.fromRGB(0, 0, 0)
					paragraphHeader.BorderSizePixel = 0
					paragraphHeader.Size = UDim2.fromScale(1, 0)
					paragraphHeader.Parent = paragraph

					local uIListLayout9 = Instance.new("UIListLayout")
					uIListLayout9.Name = "UIListLayout"
					uIListLayout9.Padding = UDim.new(0, 15)
					uIListLayout9.HorizontalAlignment = Enum.HorizontalAlignment.Center
					uIListLayout9.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout9.Parent = paragraph

					local uIPadding4 = Instance.new("UIPadding")
					uIPadding4.Name = "UIPadding"
					uIPadding4.PaddingBottom = UDim.new(0, 15)
					uIPadding4.Parent = paragraph

					local line = Instance.new("Frame")
					line.Name = "Line"
					line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					line.BackgroundTransparency = 0.9
					line.BorderColor3 = Color3.fromRGB(0, 0, 0)
					line.BorderSizePixel = 0
					line.LayoutOrder = 1
					line.Size = UDim2.new(1, 0, 0, 1)
					line.Parent = paragraph

					paragraph.Parent = prompt

					prompt.Parent = colorPicker

					colorPicker.Parent = base

					local fromHSV, fromRGB, v2, udim2 = Color3.fromHSV, Color3.fromRGB, Vector2.new, UDim2.new

					local wheel = wheel1
					local ring = target
					local slider = value
					local colour = color

					local modifierInputs = {
						Hex = hex.InputBox,
						Red = red.InputBox,
						Green = green.InputBox,
						Blue = blue.InputBox,
						Alpha = alpha.InputBox
					}

					local Mouse = LocalPlayer:GetMouse()

					local WheelDown, SlideDown = false, false
					local hue, saturation, value = 0, 0, 1

					local function toPolar(v)
						return math.atan2(v.y, v.x), v.magnitude
					end

					local function radToDeg(x)
						return ((x + math.pi) / (2 * math.pi)) * 360
					end

					local function degToRad(degrees)
						return degrees * (math.pi / 180)
					end

					local function hexToRGB(hex)
						hex = hex:gsub("#","")
						if #hex ~= 6 or not hex:match("^[%da-fA-F]+$") then return nil end
						local r = tonumber(hex:sub(1, 2), 16) or 0
						local g = tonumber(hex:sub(3, 4), 16) or 0
						local b = tonumber(hex:sub(5, 6), 16) or 0
						return r, g, b
					end

					local function clampInput(value, min, max)
						local num = tonumber(value)
						if num then
							return math.clamp(num, min, max)
						end
						return min
					end

					local function update()
						local c = fromHSV(hue, saturation, value)
						colour.BackgroundColor3 = c
						colour.BackgroundTransparency = isAlpha and clampInput(modifierInputs.Alpha.Text, 0, 1) or 0

						modifierInputs.Red.Text = tostring(math.floor(c.R * 255 + 0.5))
						modifierInputs.Green.Text = tostring(math.floor(c.G * 255 + 0.5))
						modifierInputs.Blue.Text = tostring(math.floor(c.B * 255 + 0.5))
						modifierInputs.Alpha.Text = tostring(clampInput(modifierInputs.Alpha.Text, 0, 1))

						local hexColor = string.format("#%02X%02X%02X", 
							math.floor(c.R * 255 + 0.5),
							math.floor(c.G * 255 + 0.5),
							math.floor(c.B * 255 + 0.5))
						modifierInputs.Hex.Text = hexColor
					end

					local function UpdateSlide(iX)
						local width = math.max(slider.AbsoluteSize.X, 1)
						local relX = math.clamp(iX - slider.AbsolutePosition.X, 0, width)
						local ratio = relX / width
						slide.Position = udim2(ratio, 0, 0.5, 0)
						hue = ratio
						wheel.BackgroundColor3 = fromHSV(hue, 1, 1)
						update()
					end

					local function UpdateRing(iX, iY)
						local width = math.max(wheel.AbsoluteSize.X, 1)
						local height = math.max(wheel.AbsoluteSize.Y, 1)
						local relX = math.clamp(iX - wheel.AbsolutePosition.X, 0, width)
						local relY = math.clamp(iY - wheel.AbsolutePosition.Y, 0, height)

						saturation = relX / width
						value = 1 - (relY / height)
						ring.Position = udim2(saturation, 0, 1 - value, 0)
						update()
					end

					local function UpdateSlideFromValue(newHue)
						slide.Position = UDim2.new(math.clamp(newHue, 0, 1), 0, 0.5, 0)
					end

					local function UpdateRingFromHSV(hue, saturation)
						wheel.BackgroundColor3 = fromHSV(hue, 1, 1)
						ring.Position = UDim2.new(math.clamp(saturation, 0, 1), 0, math.clamp(1 - value, 0, 1), 0)
					end

					local updateFromSettings

					local function updateFromRGB()
						local r = clampInput(modifierInputs.Red.Text, 0, 255)
						local g = clampInput(modifierInputs.Green.Text, 0, 255)
						local b = clampInput(modifierInputs.Blue.Text, 0, 255)
						modifierInputs.Red.Text = tostring(r)
						modifierInputs.Green.Text = tostring(g)
						modifierInputs.Blue.Text = tostring(b)

						hue, saturation, value = Color3.fromRGB(r, g, b):ToHSV()

						UpdateSlideFromValue(hue)
						UpdateRingFromHSV(hue, saturation)
						update()
					end

					local function updateFromHex()
						local hex = modifierInputs.Hex.Text
						local r, g, b = hexToRGB(hex)
						if not r then
							updateFromSettings()
							return
						end

						r = clampInput(r, 0, 255)
						g = clampInput(g, 0, 255)
						b = clampInput(b, 0, 255)

						modifierInputs.Red.Text = tostring(r)
						modifierInputs.Green.Text = tostring(g)
						modifierInputs.Blue.Text = tostring(b)

						hue, saturation, value = Color3.fromRGB(r, g, b):ToHSV()
						UpdateSlideFromValue(hue)
						UpdateRingFromHSV(hue, saturation)
						update()
					end

					updateFromSettings = function()
						local r = math.floor(ColorpickerFunctions.Color.R * 255 + 0.5)
						local g = math.floor(ColorpickerFunctions.Color.G * 255 + 0.5)
						local b = math.floor(ColorpickerFunctions.Color.B * 255 + 0.5)
						modifierInputs.Red.Text = tostring(r)
						modifierInputs.Green.Text = tostring(g)
						modifierInputs.Blue.Text = tostring(b)
						modifierInputs.Alpha.Text = tostring(isAlpha and ColorpickerFunctions.Alpha or 0)

						local hexColor = string.format("#%02X%02X%02X", r,g,b)
						modifierInputs.Hex.Text = hexColor

						hue, saturation, value = Color3.fromRGB(r, g, b):ToHSV()

						color1.BackgroundColor3 = ColorpickerFunctions.Color
						color1.BackgroundTransparency = isAlpha and ColorpickerFunctions.Alpha or 0

						colour.BackgroundColor3 = Color3.fromRGB(r,g,b)
						colour.BackgroundTransparency = isAlpha and ColorpickerFunctions.Alpha or 0

						UpdateSlideFromValue(hue)
						UpdateRingFromHSV(hue, saturation)
					end

					wheel.InputBegan:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							WheelDown = true
							UpdateRing(Mouse.X, Mouse.Y)
						end
					end)

					slider.InputBegan:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							SlideDown = true
							UpdateSlide(Mouse.X)
						end
					end)

					slider.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							SlideDown = false
						end
					end)

					wheel.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							WheelDown = false
						end
					end)

					UserInputService.InputChanged:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
							if SlideDown then
								UpdateSlide(Mouse.X)
							elseif WheelDown then
								UpdateRing(Mouse.X, Mouse.Y)
							end
						end
					end)

					local function onFocusEnter(instance)
						instance.PlaceholderText = instance.Text
					end

					modifierInputs.Hex.FocusLost:Connect(updateFromHex)
					modifierInputs.Red.FocusLost:Connect(updateFromRGB)
					modifierInputs.Green.FocusLost:Connect(updateFromRGB)
					modifierInputs.Blue.FocusLost:Connect(updateFromRGB)
					modifierInputs.Alpha.FocusLost:Connect(update)

					modifierInputs.Hex.Focused:Connect(function()
						onFocusEnter(modifierInputs.Hex)
					end)
					modifierInputs.Red.Focused:Connect(function()
						onFocusEnter(modifierInputs.Red)
					end)
					modifierInputs.Green.Focused:Connect(function()
						onFocusEnter(modifierInputs.Green)
					end)
					modifierInputs.Blue.Focused:Connect(function()
						onFocusEnter(modifierInputs.Blue)
					end)
					modifierInputs.Alpha.Focused:Connect(function()
						onFocusEnter(modifierInputs.Alpha)
					end)

					local function makeCanvas()
						local ColorPickerCanvas = Instance.new("CanvasGroup")
						ColorPickerCanvas.Name = "ColorPickerCanvas"
						ColorPickerCanvas.BackgroundTransparency = 1
						ColorPickerCanvas.BorderSizePixel = 0
						ColorPickerCanvas.Size = UDim2.fromScale(1, 1)
						ColorPickerCanvas.ZIndex = 5
						ColorPickerCanvas.GroupTransparency = 1
						ColorPickerCanvas.Parent = base
						ColorPickerCanvas.Visible = false
						return ColorPickerCanvas
					end

					local function transition(isIn)
						local canvas = makeCanvas()
						local tweenTransparency = isIn and 0 or 1
						local tweenScale = isIn and 1 or 0.95
						local stateTransparency = isIn and 1 or 0
						local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Sine)
						local canvasTween = Tween(canvas, tweenInfo, { GroupTransparency = tweenTransparency })
						local scaleTween = Tween(promptUIScale, tweenInfo, { Scale = tweenScale })

						colorPicker.Visible = true
						colorPicker.Parent = canvas
						canvas.Visible = true
						canvas.GroupTransparency = stateTransparency
						canvasTween:Play()
						scaleTween:Play()
						canvasTween.Completed:Wait()

						if not isIn then
							colorPicker.Visible = false
							canvas.Visible = false
						end

						colorPicker.Parent = base
						canvas:Destroy()
					end

					local function colorpickerIn()
						transition(true)
					end

					local function colorpickerOut()
						transition(false)
					end

					interact.MouseButton1Click:Connect(colorpickerIn)

					cancel.MouseButton1Click:Connect(colorpickerOut)
					confirm.MouseButton1Click:Connect(function()
						colorpickerOut()
						local c = fromHSV(hue, saturation, value)
						ColorpickerFunctions.Color = Color3.fromRGB(c.R * 255, c.G * 255, c.B * 255)
						ColorpickerFunctions.Value = ColorpickerFunctions.Color
						ColorpickerFunctions.Alpha = isAlpha and clampInput(modifierInputs.Alpha.Text, 0, 1) or 0

						color1.BackgroundColor3 = ColorpickerFunctions.Color
						color1.BackgroundTransparency = isAlpha and ColorpickerFunctions.Alpha or 0

						colorC.BackgroundColor3 = ColorpickerFunctions.Color
						colorC.BackgroundTransparency = isAlpha and ColorpickerFunctions.Alpha or 0

						optionCall(ColorpickerFunctions.Settings.Callback, ColorpickerFunctions.Color, isAlpha and ColorpickerFunctions.Alpha)
						optionCall(ColorpickerFunctions.Settings.Changed, ColorpickerFunctions.Color, isAlpha and ColorpickerFunctions.Alpha)
					end)

					updateFromSettings()

					function ColorpickerFunctions:UpdateName(New)
						colorpickerName.Text = New
					end
					function ColorpickerFunctions:SetVisibility(State)
						colorpicker.Visible = State
					end

					function ColorpickerFunctions:SetColor(color3)
						if typeof(color3) ~= "Color3" then
							return
						end
						ColorpickerFunctions.Color = color3
						ColorpickerFunctions.Value = color3
						colorC.BackgroundColor3 = color3

						local r = math.floor(ColorpickerFunctions.Color.R * 255 + 0.5)
						local g = math.floor(ColorpickerFunctions.Color.G * 255 + 0.5)
						local b = math.floor(ColorpickerFunctions.Color.B * 255 + 0.5)
						modifierInputs.Red.Text = tostring(r)
						modifierInputs.Green.Text = tostring(g)
						modifierInputs.Blue.Text = tostring(b)

						local hexColor = string.format("#%02X%02X%02X", r,g,b)
						modifierInputs.Hex.Text = hexColor

						hue, saturation, value = Color3.fromRGB(r, g, b):ToHSV()

						color1.BackgroundColor3 = ColorpickerFunctions.Color
						colour.BackgroundColor3 = Color3.fromRGB(r,g,b)

						UpdateSlideFromValue(hue)
						UpdateRingFromHSV(hue, saturation)

						optionCall(ColorpickerFunctions.Settings.Callback, ColorpickerFunctions.Color, isAlpha and ColorpickerFunctions.Alpha)
						optionCall(ColorpickerFunctions.Settings.Changed, ColorpickerFunctions.Color, isAlpha and ColorpickerFunctions.Alpha)
					end

					function ColorpickerFunctions:SetAlpha(alpha)
						ColorpickerFunctions.Alpha = optionClampNumber(alpha, 0, 1)
						colorC.BackgroundTransparency = ColorpickerFunctions.Alpha
						color1.BackgroundTransparency = ColorpickerFunctions.Alpha
						colour.BackgroundTransparency = ColorpickerFunctions.Alpha
						updateFromSettings()
					end

					function ColorpickerFunctions:GetValue()
						return ColorpickerFunctions.Color, isAlpha and ColorpickerFunctions.Alpha
					end

					function ColorpickerFunctions:GetState()
						return ColorpickerFunctions:GetValue()
					end

					if Flag then
						MacLib.Options[Flag] = ColorpickerFunctions
					end
					return ColorpickerFunctions
				end

				function SectionFunctions:ColorPicker(Settings, Flag)
					return self:Colorpicker(Settings, Flag)
				end
				function SectionFunctions:AddColorPicker(Settings, Flag)
					return self:Colorpicker(Settings, Flag)
				end
				function SectionFunctions:addColorPicker(Settings, Flag)
					return self:Colorpicker(Settings, Flag)
				end
				function SectionFunctions:AddColorpicker(Settings, Flag)
					return self:Colorpicker(Settings, Flag)
				end
				function SectionFunctions:addColorpicker(Settings, Flag)
					return self:Colorpicker(Settings, Flag)
				end
				function SectionFunctions:Colourpicker(Settings, Flag)
					return self:Colorpicker(Settings, Flag)
				end
				function SectionFunctions:ColourPicker(Settings, Flag)
					return self:Colorpicker(Settings, Flag)
				end
				function SectionFunctions:AddColourPicker(Settings, Flag)
					return self:Colorpicker(Settings, Flag)
				end
				function SectionFunctions:addColourPicker(Settings, Flag)
					return self:Colorpicker(Settings, Flag)
				end
				function SectionFunctions:AddColourpicker(Settings, Flag)
					return self:Colorpicker(Settings, Flag)
				end
				function SectionFunctions:addColourpicker(Settings, Flag)
					return self:Colorpicker(Settings, Flag)
				end

				function SectionFunctions:Header(Settings, Flag)
					Settings, Flag = optionArgs(Settings, Flag)
					local HeaderFunctions = {Settings = Settings}

					local header = Instance.new("Frame")
					header.Name = "Header"
					header.AutomaticSize = Enum.AutomaticSize.Y
					header.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					header.BackgroundTransparency = 1
					header.BorderColor3 = Color3.fromRGB(0, 0, 0)
					header.BorderSizePixel = 0
					header.LayoutOrder = 0
					header.Size = UDim2.fromScale(1, 0)
					header.Parent = section

					local uIPadding = Instance.new("UIPadding")
					uIPadding.Name = "UIPadding"
					uIPadding.PaddingBottom = UDim.new(0, 5)
					uIPadding.Parent = header

					local headerText = Instance.new("TextLabel")
					headerText.Name = "HeaderText"
					headerText.FontFace = SafeFont(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					headerText.RichText = true
					headerText.Text = optionText(HeaderFunctions.Settings, Flag, "Header")
					headerText.TextColor3 = Color3.fromRGB(255, 255, 255)
					headerText.TextSize = 16
					headerText.TextTransparency = 0.3
					headerText.TextWrapped = true
					headerText.TextXAlignment = Enum.TextXAlignment.Left
					headerText.AutomaticSize = Enum.AutomaticSize.Y
					headerText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					headerText.BackgroundTransparency = 1
					headerText.BorderColor3 = Color3.fromRGB(0, 0, 0)
					headerText.BorderSizePixel = 0
					headerText.Size = UDim2.fromScale(1, 0)
					headerText.Parent = header

					function HeaderFunctions:UpdateName(New)
						headerText.Text = New
					end
					function HeaderFunctions:SetVisibility(State)
						header.Visible = State
					end

					if Flag then
						MacLib.Options[Flag] = HeaderFunctions
					end
					return HeaderFunctions
				end

				function SectionFunctions:Label(Settings, Flag)
					Settings, Flag = optionArgs(Settings, Flag)
					local LabelFunctions = {Settings = Settings}

					local label = Instance.new("Frame")
					label.Name = "Label"
					label.AutomaticSize = Enum.AutomaticSize.Y
					label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					label.BackgroundTransparency = 1
					label.BorderColor3 = Color3.fromRGB(0, 0, 0)
					label.BorderSizePixel = 0
					label.Size = UDim2.new(1, 0, 0, 28)
					label.Parent = section

					local labelText = Instance.new("TextLabel")
					labelText.Name = "LabelText"
					labelText.FontFace = SafeFont(assets.interFont)
					labelText.RichText = true
					labelText.Text = optionText(LabelFunctions.Settings, Flag, "Label") -- Settings.Name Deprecated use Settings.Text
					labelText.TextColor3 = Color3.fromRGB(255, 255, 255)
					labelText.TextSize = 13
					labelText.TextTransparency = 0.5
					labelText.TextWrapped = true
					labelText.TextXAlignment = Enum.TextXAlignment.Left
					labelText.AutomaticSize = Enum.AutomaticSize.Y
					labelText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					labelText.BackgroundTransparency = 1
					labelText.BorderColor3 = Color3.fromRGB(0, 0, 0)
					labelText.BorderSizePixel = 0
					labelText.Size = UDim2.fromScale(1, 1)
					labelText.Parent = label

					function LabelFunctions:UpdateName(New)
						labelText.Text = New
					end
					function LabelFunctions:SetVisibility(State)
						label.Visible = State
					end
					function LabelFunctions:GetFrame()
						return label, labelText
					end

					if Flag then
						MacLib.Options[Flag] = LabelFunctions
					end
					return LabelFunctions
				end

				function SectionFunctions:SubLabel(Settings, Flag)
					Settings, Flag = optionArgs(Settings, Flag)
					local SubLabelFunctions = {Settings = Settings}

					local subLabel = Instance.new("Frame")
					subLabel.Name = "SubLabel"
					subLabel.AutomaticSize = Enum.AutomaticSize.Y
					subLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					subLabel.BackgroundTransparency = 1
					subLabel.BorderColor3 = Color3.fromRGB(0, 0, 0)
					subLabel.BorderSizePixel = 0
					subLabel.Size = UDim2.new(1, 0, 0, 0)
					subLabel.Parent = section

					local subLabelText = Instance.new("TextLabel")
					subLabelText.Name = "SubLabelText"
					subLabelText.FontFace = SafeFont(assets.interFont)
					subLabelText.RichText = true
					subLabelText.Text = optionText(SubLabelFunctions.Settings, Flag, "SubLabel") -- Settings.Name Deprecated use Settings.Text
					subLabelText.TextColor3 = Color3.fromRGB(255, 255, 255)
					subLabelText.TextSize = 12
					subLabelText.TextTransparency = 0.7
					subLabelText.TextWrapped = true
					subLabelText.TextXAlignment = Enum.TextXAlignment.Left
					subLabelText.AutomaticSize = Enum.AutomaticSize.Y
					subLabelText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					subLabelText.BackgroundTransparency = 1
					subLabelText.BorderColor3 = Color3.fromRGB(0, 0, 0)
					subLabelText.BorderSizePixel = 0
					subLabelText.Size = UDim2.fromScale(1, 1)
					subLabelText.Parent = subLabel

					function SubLabelFunctions:UpdateName(New)
						subLabelText.Text = New
					end
					function SubLabelFunctions:SetVisibility(State)
						subLabel.Visible = State
					end

					if Flag then
						MacLib.Options[Flag] = SubLabelFunctions
					end
					return SubLabelFunctions
				end

				function SectionFunctions:Paragraph(Settings, Flag)
					Settings, Flag = optionArgs(Settings, Flag)
					local ParagraphFunctions = {Settings = Settings}

					local paragraph = Instance.new("Frame")
					paragraph.Name = "Paragraph"
					paragraph.AutomaticSize = Enum.AutomaticSize.Y
					paragraph.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					paragraph.BackgroundTransparency = 1
					paragraph.BorderColor3 = Color3.fromRGB(0, 0, 0)
					paragraph.BorderSizePixel = 0
					paragraph.Size = UDim2.new(1, 0, 0, 32)
					paragraph.Parent = section

					local paragraphHeader = Instance.new("TextLabel")
					paragraphHeader.Name = "ParagraphHeader"
					paragraphHeader.FontFace = SafeFont(
						assets.interFont,
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					)
					paragraphHeader.RichText = true
					paragraphHeader.Text = tostring(optionFirstNonNil(ParagraphFunctions.Settings.Header, ParagraphFunctions.Settings.Title, ParagraphFunctions.Settings.Name, Flag, ""))
					paragraphHeader.TextColor3 = Color3.fromRGB(255, 255, 255)
					paragraphHeader.TextSize = 15
					paragraphHeader.TextTransparency = 0.4
					paragraphHeader.TextWrapped = true
					paragraphHeader.TextXAlignment = Enum.TextXAlignment.Left
					paragraphHeader.AutomaticSize = Enum.AutomaticSize.Y
					paragraphHeader.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					paragraphHeader.BackgroundTransparency = 1
					paragraphHeader.BorderColor3 = Color3.fromRGB(0, 0, 0)
					paragraphHeader.BorderSizePixel = 0
					paragraphHeader.Size = UDim2.fromScale(1, 0)
					paragraphHeader.Parent = paragraph

					local uIListLayout = Instance.new("UIListLayout")
					uIListLayout.Name = "UIListLayout"
					uIListLayout.Padding = UDim.new(0, 5)
					uIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout.Parent = paragraph

					local paragraphBody = Instance.new("TextLabel")
					paragraphBody.Name = "ParagraphBody"
					paragraphBody.FontFace = SafeFont(assets.interFont)
					paragraphBody.RichText = true
					paragraphBody.Text = tostring(optionFirstNonNil(ParagraphFunctions.Settings.Body, ParagraphFunctions.Settings.Content, ParagraphFunctions.Settings.Text, ""))
					paragraphBody.TextColor3 = Color3.fromRGB(255, 255, 255)
					paragraphBody.TextSize = 13
					paragraphBody.TextTransparency = 0.5
					paragraphBody.TextWrapped = true
					paragraphBody.TextXAlignment = Enum.TextXAlignment.Left
					paragraphBody.AutomaticSize = Enum.AutomaticSize.Y
					paragraphBody.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					paragraphBody.BackgroundTransparency = 1
					paragraphBody.BorderColor3 = Color3.fromRGB(0, 0, 0)
					paragraphBody.BorderSizePixel = 0
					paragraphBody.LayoutOrder = 1
					paragraphBody.Size = UDim2.fromScale(1, 0)
					paragraphBody.Parent = paragraph

					function ParagraphFunctions:UpdateHeader(New)
						paragraphHeader.Text = New
					end
					function ParagraphFunctions:UpdateBody(New)
						paragraphBody.Text = New
					end
					function ParagraphFunctions:SetVisibility(State)
						paragraph.Visible = State
					end

					if Flag then
						MacLib.Options[Flag] = ParagraphFunctions
					end
					return ParagraphFunctions
				end

				function SectionFunctions:Divider()
					local DividerFunctions = {}

					local divider = Instance.new("Frame")
					divider.Name = "Divider"
					divider.AnchorPoint = Vector2.new(0, 1)
					divider.AutomaticSize = Enum.AutomaticSize.Y
					divider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					divider.BackgroundTransparency = 1
					divider.BorderColor3 = Color3.fromRGB(0, 0, 0)
					divider.BorderSizePixel = 0
					divider.Position = UDim2.fromScale(0, 1)
					divider.Size = UDim2.new(1, 0, 0, 1)
					divider.Parent = section

					local uIPadding = Instance.new("UIPadding")
					uIPadding.Name = "UIPadding"
					uIPadding.PaddingBottom = UDim.new(0, 8)
					uIPadding.PaddingTop = UDim.new(0, 8)
					uIPadding.Parent = divider

					local uIListLayout = Instance.new("UIListLayout")
					uIListLayout.Name = "UIListLayout"
					uIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
					uIListLayout.Parent = divider

					local line = Instance.new("Frame")
					line.Name = "Line"
					line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					line.BackgroundTransparency = 0.9
					line.BorderColor3 = Color3.fromRGB(0, 0, 0)
					line.BorderSizePixel = 0
					line.Size = UDim2.new(1, 0, 0, 1)
					line.Parent = divider

					function DividerFunctions:Remove()
						divider:Destroy()
					end
					function DividerFunctions:SetVisibility(State)
						divider.Visible = State
					end

					return DividerFunctions
				end

				function SectionFunctions:Spacer()
					local SpacerFunctions = {}

					local spacer = Instance.new("Frame")
					spacer.Name = "Spacer"
					spacer.AnchorPoint = Vector2.new(0, 1)
					spacer.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					spacer.BackgroundTransparency = 1
					spacer.BorderColor3 = Color3.fromRGB(0, 0, 0)
					spacer.BorderSizePixel = 0
					spacer.Position = UDim2.fromScale(0, 1)
					spacer.Parent = section

					function SpacerFunctions:Remove()
						spacer:Destroy()
					end
					function SpacerFunctions:SetVisibility(State)
						spacer.Visible = State
					end

					return SpacerFunctions
				end

				function SectionFunctions:Custom(Settings, Flag)
					Settings, Flag = optionArgs(Settings, Flag)
					local CustomFunctions = { Settings = Settings }

					local custom = Instance.new("Frame")
					custom.Name = Settings.Name or "Custom"
					custom.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					custom.BackgroundTransparency = 1
					custom.BorderColor3 = Color3.fromRGB(0, 0, 0)
					custom.BorderSizePixel = 0
					custom.ClipsDescendants = Settings.ClipsDescendants ~= false
					custom.Size = UDim2.new(1, 0, 0, Settings.Height or 32)
					custom.Visible = Settings.Visible ~= false
					custom.Parent = section

					local instance = Settings.Instance
					if typeof(instance) == "Instance" then
						instance.Parent = custom
						if instance:IsA("GuiObject") then
							instance.AnchorPoint = Vector2.new(0, 0)
							instance.Position = UDim2.fromOffset(0, 0)
							instance.Size = UDim2.fromScale(1, 1)
						end
					end

					function CustomFunctions:SetHeight(Height)
						custom.Size = UDim2.new(1, 0, 0, tonumber(Height) or custom.Size.Y.Offset)
					end
					function CustomFunctions:SetVisibility(State)
						custom.Visible = State
					end
					function CustomFunctions:SetInstance(NewInstance)
						if typeof(instance) == "Instance" and instance.Parent == custom then
							instance.Parent = nil
						end
						instance = NewInstance
						if typeof(instance) == "Instance" then
							instance.Parent = custom
							if instance:IsA("GuiObject") then
								instance.AnchorPoint = Vector2.new(0, 0)
								instance.Position = UDim2.fromOffset(0, 0)
								instance.Size = UDim2.fromScale(1, 1)
							end
						end
					end
					function CustomFunctions:GetFrame()
						return custom
					end
					function CustomFunctions:Remove()
						custom:Destroy()
					end

					if Flag then
						MacLib.Options[Flag] = CustomFunctions
					end
					return CustomFunctions
				end

				return SectionFunctions
			end

			local function SelectCurrentTab()
				local easetime = 0.15

				if currentTabInstance then
					currentTabInstance.Parent = nil
				end

				for i, tabInfo in pairs(tabs) do
					Tween(i, TweenInfo.new(easetime, Enum.EasingStyle.Sine), {
						BackgroundTransparency = (i == tabSwitcher and 0.98 or 1)
					}):Play()

					if tabInfo.tabStroke then
						Tween(tabInfo.tabStroke, TweenInfo.new(easetime, Enum.EasingStyle.Sine), {
							Transparency = (i == tabSwitcher and 0.95 or 1)
						}):Play()
					end
					if tabInfo.switcherImage then
						tweenIconTransparency(tabInfo.switcherImage, (i == tabSwitcher and 0.1 or 0.5), TweenInfo.new(easetime, Enum.EasingStyle.Sine))
					end
					if tabInfo.switcherName then
						Tween(tabInfo.switcherName, TweenInfo.new(easetime, Enum.EasingStyle.Sine), {
							TextTransparency = (i == tabSwitcher and 0.1 or 0.5)
						}):Play()
					end
				end

				tabs[tabSwitcher].tabContent.Parent = content
				currentTabInstance = tabs[tabSwitcher].tabContent
				currentTab.Text = Settings.Name
			end

			tabSwitcher.MouseButton1Click:Connect(function()
				SelectCurrentTab()
			end)

			function TabFunctions:Select()
				SelectCurrentTab()
			end

			function TabFunctions:InsertConfigSection(Side)
				local configSection = TabFunctions:Section({ Side = "Left" })

				if isStudio then
					configSection:Label({Text = "Config system unavailable. (Environment isStudio)"})
					return "Config system unavailable." 
				end

				local inputPath = nil
				local selectedConfig = nil

				configSection:Input({
					Name = "Config Name",
					Placeholder = "Name",
					AcceptedCharacters = "All",
					Callback = function(input)
						inputPath = input
					end,
				})

				local configSelection = configSection:Dropdown({
					Name = "Select Config",
					Multi = false,
					Required = false,
					Options = MacLib:RefreshConfigList(),
					Callback = function(Value)
						selectedConfig = Value
					end,
				})

				configSection:Button({
					Name = "Create Config",
					Callback = function()
						if not inputPath or string.gsub(inputPath, " ", "") == "" then
							WindowFunctions:Notify({
								Title = "Interface",
								Description = "Config name cannot be empty."
							})
							return
						end

						local success, returned = MacLib:SaveConfig(inputPath)
						if not success then
							WindowFunctions:Notify({
								Title = "Interface",
								Description = "Unable to save config, return error: " .. returned
							})
						end

						WindowFunctions:Notify({
							Title = "Interface",
							Description = string.format("Created config %q", inputPath),
						})

						configSelection:ClearOptions()
						configSelection:InsertOptions(MacLib:RefreshConfigList())
					end,
				})

				configSection:Button({
					Name = "Load Config",
					Callback = function()
						local success, returned = MacLib:LoadConfig(configSelection.Value)
						if not success then
							WindowFunctions:Notify({
								Title = "Interface",
								Description = "Unable to load config, return error: " .. returned
							})
							return
						end

						WindowFunctions:Notify({
							Title = "Interface",
							Description = string.format("Loaded config %q", configSelection.Value),
						})
					end,
				})

				configSection:Button({
					Name = "Overwrite Config",
					Callback = function()
						local success, returned = MacLib:SaveConfig(configSelection.Value)
						if not success then
							WindowFunctions:Notify({
								Title = "Interface",
								Description = "Unable to overwrite config, return error: " .. returned
							})
							return
						end

						WindowFunctions:Notify({
							Title = "Interface",
							Description = string.format("Overwrote config %q", configSelection.Value),
						})
					end,
				})

				configSection:Button({
					Name = "Refresh Config List",
					Callback = function()
						configSelection:ClearOptions()
						configSelection:InsertOptions(MacLib:RefreshConfigList())
					end,
				})

				local autoloadLabel

				configSection:Button({
					Name = "Set as autoload",
					Callback = function()
						local name = configSelection.Value
						writefile(MacLib.Folder .. "/settings/autoload.txt", name)
						autoloadLabel:UpdateName("Autoload config: " .. name)
						WindowFunctions:Notify({
							Title = "Interface",
							Description = string.format("Set %q as autoload", name),
						})
					end,
				})

				autoloadLabel = configSection:Label({Text = "Autoload config: None"})

				if isfile(MacLib.Folder .. "/settings/autoload.txt") then
					local name = readfile(MacLib.Folder .. "/settings/autoload.txt")
					autoloadLabel:UpdateName("Autoload config: " .. name)
				end
			end

			tabs[tabSwitcher] = {
				tabContent = elements1,
				tabStroke = tabSwitcherUIStroke,
				switcherImage = tabImage,
				switcherName = tabSwitcherName,
			}

			return TabFunctions
		end

		return SectionFunctions
	end

	function WindowFunctions:Notify(Settings)
		local NotificationFunctions = {}

		local notification = Instance.new("Frame")
		notification.Name = "Notification"
		notification.AnchorPoint = Vector2.new(0.5, 0.5)
		notification.AutomaticSize = Enum.AutomaticSize.Y
		notification.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
		notification.BorderColor3 = Color3.fromRGB(0, 0, 0)
		notification.BorderSizePixel = 0
		notification.Position = UDim2.fromScale(0.5, 0.5)
		notification.Size = UDim2.fromOffset(Settings.SizeX or 250, 0)

		notification.Parent = notifications

		local notificationUIStroke = Instance.new("UIStroke")
		notificationUIStroke.Name = "NotificationUIStroke"
		notificationUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		notificationUIStroke.Color = Color3.fromRGB(255, 255, 255)
		notificationUIStroke.Transparency = 0.9
		notificationUIStroke.Parent = notification

		local notificationUICorner = Instance.new("UICorner")
		notificationUICorner.Name = "NotificationUICorner"
		notificationUICorner.CornerRadius = UDim.new(0, 0)
		notificationUICorner.Parent = notification

		local notificationUIScale = Instance.new("UIScale")
		notificationUIScale.Name = "NotificationUIScale"
		notificationUIScale.Parent = notification
		notificationUIScale.Scale = 0

		local notificationInformation = Instance.new("Frame")
		notificationInformation.Name = "NotificationInformation"
		notificationInformation.AutomaticSize = Enum.AutomaticSize.Y
		notificationInformation.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		notificationInformation.BackgroundTransparency = 1
		notificationInformation.BorderColor3 = Color3.fromRGB(0, 0, 0)
		notificationInformation.BorderSizePixel = 0
		notificationInformation.Size = UDim2.fromScale(1, 1)

		local notificationTitle = Instance.new("TextLabel")
		notificationTitle.Name = "NotificationTitle"
		notificationTitle.FontFace = SafeFont(
			assets.interFont,
			Enum.FontWeight.SemiBold,
			Enum.FontStyle.Normal
		)
		notificationTitle.RichText = true
		notificationTitle.Text = Settings.Title
		notificationTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
		notificationTitle.TextSize = 13
		notificationTitle.TextTransparency = 0.2
		notificationTitle.TextTruncate = Enum.TextTruncate.SplitWord
		notificationTitle.TextXAlignment = Enum.TextXAlignment.Left
		notificationTitle.TextYAlignment = Enum.TextYAlignment.Top
		notificationTitle.AutomaticSize = Enum.AutomaticSize.XY
		notificationTitle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		notificationTitle.BackgroundTransparency = 1
		notificationTitle.BorderColor3 = Color3.fromRGB(0, 0, 0)
		notificationTitle.BorderSizePixel = 0
		notificationTitle.Size = UDim2.new(1, -12, 0, 0)

		local notificationTitleUIPadding = Instance.new("UIPadding")
		notificationTitleUIPadding.Name = "NotificationTitleUIPadding"
		notificationTitleUIPadding.PaddingRight = UDim.new(0, 25)
		notificationTitleUIPadding.Parent = notificationTitle

		notificationTitle.Parent = notificationInformation

		local notificationDescription = Instance.new("TextLabel")
		notificationDescription.Name = "NotificationDescription"
		notificationDescription.FontFace = SafeFont(
			assets.interFont,
			Enum.FontWeight.Medium,
			Enum.FontStyle.Normal
		)
		notificationDescription.Text = Settings.Description
		notificationDescription.TextColor3 = Color3.fromRGB(255, 255, 255)
		notificationDescription.TextSize = 11
		notificationDescription.TextTransparency = 0.5
		notificationDescription.TextWrapped = true
		notificationDescription.RichText = true
		notificationDescription.TextXAlignment = Enum.TextXAlignment.Left
		notificationDescription.TextYAlignment = Enum.TextYAlignment.Top
		notificationDescription.AutomaticSize = Enum.AutomaticSize.XY
		notificationDescription.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		notificationDescription.BackgroundTransparency = 1
		notificationDescription.BorderColor3 = Color3.fromRGB(0, 0, 0)
		notificationDescription.BorderSizePixel = 0
		notificationDescription.Size = UDim2.new(1, -12, 0, 0)

		local notificationDescriptionUIPadding = Instance.new("UIPadding")
		notificationDescriptionUIPadding.Name = "NotificationDescriptionUIPadding"
		notificationDescriptionUIPadding.PaddingRight = UDim.new(0, 25)
		notificationDescriptionUIPadding.PaddingTop = UDim.new(0, 17)
		notificationDescriptionUIPadding.Parent = notificationDescription

		notificationDescription.Parent = notificationInformation

		local notificationUIPadding = Instance.new("UIPadding")
		notificationUIPadding.Name = "NotificationUIPadding"
		notificationUIPadding.PaddingBottom = UDim.new(0, 12)
		notificationUIPadding.PaddingLeft = UDim.new(0, 10)
		notificationUIPadding.PaddingRight = UDim.new(0, 10)
		notificationUIPadding.PaddingTop = UDim.new(0, 10)
		notificationUIPadding.Parent = notificationInformation

		notificationInformation.Parent = notification

		local notificationControls = Instance.new("Frame")
		notificationControls.Name = "NotificationControls"
		notificationControls.AutomaticSize = Enum.AutomaticSize.Y
		notificationControls.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		notificationControls.BackgroundTransparency = 1
		notificationControls.BorderColor3 = Color3.fromRGB(0, 0, 0)
		notificationControls.BorderSizePixel = 0
		notificationControls.Size = UDim2.fromScale(1, 1)

		local interactable = Instance.new("TextButton")
		interactable.Name = "Interactable"
		interactable.FontFace = SafeFont(assets.interFont)
		interactable.Text = "✓"
		interactable.TextColor3 = Color3.fromRGB(255, 255, 255)
		interactable.TextSize = 17
		interactable.TextTransparency = 0.2
		interactable.AnchorPoint = Vector2.new(1, 0.5)
		interactable.AutomaticSize = Enum.AutomaticSize.XY
		interactable.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		interactable.BackgroundTransparency = 1
		interactable.BorderColor3 = Color3.fromRGB(0, 0, 0)
		interactable.BorderSizePixel = 0
		interactable.LayoutOrder = 1
		interactable.Position = UDim2.fromScale(1, 0.5)
		interactable.Parent = notificationControls

		local uIPadding = Instance.new("UIPadding")
		uIPadding.Name = "UIPadding"
		uIPadding.PaddingBottom = UDim.new(0, 6)
		uIPadding.PaddingRight = UDim.new(0, 13)
		uIPadding.PaddingTop = UDim.new(0, 6)
		uIPadding.Parent = notificationControls

		notificationControls.Parent = notification

		local tweens = {
			In = Tween(notificationUIScale, TweenInfo.new(0.2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Scale = Settings.Scale or 1
			}),
			Out = Tween(notificationUIScale, TweenInfo.new(0.2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Scale = 0
			}),
		}

		local styles = {
			None = function() interactable:Destroy() end,
			Confirm = function() interactable.Text = "✓" end,
			Cancel = function() interactable.Text = "✗" end
		}

		local style = styles[Settings.Style] or function() interactable:Destroy() end
		style()

		if interactable then
			interactable.MouseButton1Click:Connect(function()
				NotificationFunctions:Cancel()
				if Settings.Callback then
					task.spawn(Settings.Callback)
				end
			end)
		end

		local AnimateNotification = task.spawn(function()
			tweens.In:Play()

			Settings.Lifetime = Settings.Lifetime or 3

			if Settings.Lifetime ~= 0 then
				task.wait(Settings.Lifetime)

				local out = tweens.Out
				out:Play()
				out.Completed:Wait()
				notification:Destroy()
			end
		end)

		function NotificationFunctions:UpdateTitle(New)
			notificationTitle.Text = New
		end

		function NotificationFunctions:UpdateDescription(New)
			notificationDescription.Text = New
		end

		function NotificationFunctions:Resize(X)
			local targ = X or 250
			notification.Size = UDim2.fromOffset(targ, 0)
		end

		function NotificationFunctions:Cancel()
			task.cancel(AnimateNotification)

			local out = tweens.Out
			out:Play()
			out.Completed:Wait()
			notification:Destroy()
		end

		return NotificationFunctions
	end

	function WindowFunctions:Dialog(Settings)
		local DialogFunctions = {}

		local dialogCanvas = Instance.new("CanvasGroup")
		dialogCanvas.Name = "DialogCanvas"
		dialogCanvas.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		dialogCanvas.BackgroundTransparency = 1
		dialogCanvas.BorderColor3 = Color3.fromRGB(0, 0, 0)
		dialogCanvas.BorderSizePixel = 0
		dialogCanvas.Size = UDim2.fromScale(1, 1)
		dialogCanvas.GroupTransparency = 1
		dialogCanvas.Parent = base

		local dialog = Instance.new("Frame")
		dialog.Name = "Dialog"
		dialog.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		dialog.BackgroundTransparency = 0.5
		dialog.BorderColor3 = Color3.fromRGB(0, 0, 0)
		dialog.BorderSizePixel = 0
		dialog.Size = UDim2.fromScale(1, 1)

		local dialogUICorner = Instance.new("UICorner")
		dialogUICorner.Name = "BaseUICorner"
		dialogUICorner.CornerRadius = UDim.new(0, 0)
		dialogUICorner.Parent = dialog

		local prompt = Instance.new("Frame")
		prompt.Name = "Prompt"
		prompt.AnchorPoint = Vector2.new(0.5, 0.5)
		prompt.AutomaticSize = Enum.AutomaticSize.Y
		prompt.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
		prompt.BorderColor3 = Color3.fromRGB(0, 0, 0)
		prompt.BorderSizePixel = 0
		prompt.Position = UDim2.fromScale(0.5, 0.5)
		prompt.Size = UDim2.fromOffset(280, 0)

		local promptUIScale = Instance.new("UIScale")
		promptUIScale.Name = "BaseUIScale"
		promptUIScale.Parent = prompt
		promptUIScale.Scale = 0.95

		local globalSettingsUIStroke = Instance.new("UIStroke")
		globalSettingsUIStroke.Name = "GlobalSettingsUIStroke"
		globalSettingsUIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		globalSettingsUIStroke.Color = Color3.fromRGB(255, 255, 255)
		globalSettingsUIStroke.Transparency = 0.9
		globalSettingsUIStroke.Parent = prompt

		local globalSettingsUICorner = Instance.new("UICorner")
		globalSettingsUICorner.Name = "GlobalSettingsUICorner"
		globalSettingsUICorner.CornerRadius = UDim.new(0, 0)
		globalSettingsUICorner.Parent = prompt

		local globalSettingsUIPadding = Instance.new("UIPadding")
		globalSettingsUIPadding.Name = "GlobalSettingsUIPadding"
		globalSettingsUIPadding.PaddingBottom = UDim.new(0, 20)
		globalSettingsUIPadding.PaddingLeft = UDim.new(0, 20)
		globalSettingsUIPadding.PaddingRight = UDim.new(0, 20)
		globalSettingsUIPadding.PaddingTop = UDim.new(0, 20)
		globalSettingsUIPadding.Parent = prompt

		local paragraph = Instance.new("Frame")
		paragraph.Name = "Paragraph"
		paragraph.AutomaticSize = Enum.AutomaticSize.Y
		paragraph.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		paragraph.BackgroundTransparency = 1
		paragraph.BorderColor3 = Color3.fromRGB(0, 0, 0)
		paragraph.BorderSizePixel = 0
		paragraph.Size = UDim2.new(1, 0, 0, 38)

		local paragraphHeader = Instance.new("TextLabel")
		paragraphHeader.Name = "ParagraphHeader"
		paragraphHeader.FontFace = SafeFont(
			assets.interFont,
			Enum.FontWeight.Medium,
			Enum.FontStyle.Normal
		)
		paragraphHeader.RichText = true
		paragraphHeader.Text = Settings.Title
		paragraphHeader.TextColor3 = Color3.fromRGB(255, 255, 255)
		paragraphHeader.TextSize = 18
		paragraphHeader.TextTransparency = 0.4
		paragraphHeader.TextWrapped = true
		paragraphHeader.AutomaticSize = Enum.AutomaticSize.Y
		paragraphHeader.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		paragraphHeader.BackgroundTransparency = 1
		paragraphHeader.BorderColor3 = Color3.fromRGB(0, 0, 0)
		paragraphHeader.BorderSizePixel = 0
		paragraphHeader.Size = UDim2.fromScale(1, 0)
		paragraphHeader.Parent = paragraph

		local uIListLayout = Instance.new("UIListLayout")
		uIListLayout.Name = "UIListLayout"
		uIListLayout.Padding = UDim.new(0, 15)
		uIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		uIListLayout.Parent = paragraph

		local paragraphBody = Instance.new("TextLabel")
		paragraphBody.Name = "ParagraphBody"
		paragraphBody.FontFace = SafeFont(assets.interFont)
		paragraphBody.RichText = true
		paragraphBody.Text = Settings.Description
		paragraphBody.TextColor3 = Color3.fromRGB(255, 255, 255)
		paragraphBody.TextSize = 14
		paragraphBody.TextTransparency = 0.5
		paragraphBody.TextWrapped = true
		paragraphBody.AutomaticSize = Enum.AutomaticSize.Y
		paragraphBody.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		paragraphBody.BackgroundTransparency = 1
		paragraphBody.BorderColor3 = Color3.fromRGB(0, 0, 0)
		paragraphBody.BorderSizePixel = 0
		paragraphBody.LayoutOrder = 1
		paragraphBody.Size = UDim2.fromScale(1, 0)
		paragraphBody.Parent = paragraph

		paragraph.Parent = prompt

		local interactions = Instance.new("Frame")
		interactions.Name = "Interactions"
		interactions.AutomaticSize = Enum.AutomaticSize.Y
		interactions.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		interactions.BackgroundTransparency = 1
		interactions.BorderColor3 = Color3.fromRGB(0, 0, 0)
		interactions.BorderSizePixel = 0
		interactions.LayoutOrder = 1
		interactions.Size = UDim2.fromScale(1, 0)

		local uIListLayout1 = Instance.new("UIListLayout")
		uIListLayout1.Name = "UIListLayout"
		uIListLayout1.Padding = UDim.new(0, 10)
		uIListLayout1.SortOrder = Enum.SortOrder.LayoutOrder
		uIListLayout1.Parent = interactions

		local uIPadding = Instance.new("UIPadding")
		uIPadding.Name = "UIPadding"
		uIPadding.PaddingTop = UDim.new(0, 20)
		uIPadding.Parent = interactions

		interactions.Parent = prompt

		local uIListLayout2 = Instance.new("UIListLayout")
		uIListLayout2.Name = "UIListLayout"
		uIListLayout2.SortOrder = Enum.SortOrder.LayoutOrder
		uIListLayout2.Parent = prompt

		prompt.Parent = dialog

		dialog.Parent = dialogCanvas

		local canvasIn = Tween(dialogCanvas, TweenInfo.new(0.1, Enum.EasingStyle.Sine), { GroupTransparency = 0 })
		local canvasOut = Tween(dialogCanvas, TweenInfo.new(0.1, Enum.EasingStyle.Sine), { GroupTransparency = 1 })

		local scaleIn = Tween(promptUIScale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), { Scale = 1 })
		local scaleOut = Tween(promptUIScale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), { Scale = 0.95 })

		local function dialogIn()
			canvasIn:Play()
			scaleIn:Play()
			canvasIn.Completed:Wait()
			dialog.Parent = base
		end

		local function dialogOut()
			if not dialog.Parent then return end
			dialog.Parent = dialogCanvas
			canvasOut:Play()
			scaleOut:Play()
			canvasOut.Completed:Wait()
			dialogCanvas:Destroy()
		end

		for _, v in pairs(Settings.Buttons) do
			local button = Instance.new("TextButton")
			button.Name = "Button"
			button.FontFace = SafeFont(assets.interFont)
			button.Text = v.Name
			button.TextColor3 = Color3.fromRGB(255, 255, 255)
			button.TextSize = 15
			button.TextTransparency = 0.5
			button.TextTruncate = Enum.TextTruncate.AtEnd
			button.AutoButtonColor = false
			button.AutomaticSize = Enum.AutomaticSize.Y
			button.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
			button.BorderColor3 = Color3.fromRGB(0, 0, 0)
			button.BorderSizePixel = 0
			button.Size = UDim2.fromScale(1, 0)

			local uIPadding1 = Instance.new("UIPadding")
			uIPadding1.Name = "UIPadding"
			uIPadding1.PaddingBottom = UDim.new(0, 9)
			uIPadding1.PaddingLeft = UDim.new(0, 10)
			uIPadding1.PaddingRight = UDim.new(0, 10)
			uIPadding1.PaddingTop = UDim.new(0, 9)
			uIPadding1.Parent = button

			local baseUICorner1 = Instance.new("UICorner")
			baseUICorner1.Name = "BaseUICorner"
			baseUICorner1.CornerRadius = UDim.new(0, 0)
			baseUICorner1.Parent = button

			button.Parent = interactions

			local TweenSettings = {
				DefaultTransparency = 0,
				DefaultTransparency2 = 0.5,
				HoverTransparency = 0.3,
				HoverTransparency2 = 0.6,

				EasingStyle = Enum.EasingStyle.Sine
			}

			local function ChangeState(State)
				if State == "Idle" then
					Tween(button, TweenInfo.new(0.2, TweenSettings.EasingStyle), {
						BackgroundTransparency = TweenSettings.DefaultTransparency,
						TextTransparency = TweenSettings.DefaultTransparency2
					}):Play()
				elseif State == "Hover" then
					Tween(button, TweenInfo.new(0.2, TweenSettings.EasingStyle), {
						BackgroundTransparency = TweenSettings.HoverTransparency,
						TextTransparency = TweenSettings.HoverTransparency2
					}):Play()
				end
			end

			button.MouseButton1Click:Connect(function()
				if dialogCanvas.GroupTransparency ~= 0 then return end
				optionCall(v.Callback)

				dialogOut()
			end)

			button.MouseEnter:Connect(function()
				ChangeState("Hover")
			end)
			button.MouseLeave:Connect(function()
				ChangeState("Idle")
			end)
		end

		dialogIn()

		function DialogFunctions:UpdateTitle(New)
			paragraphHeader.Text = New
		end
		function DialogFunctions:UpdateDescription(New)
			paragraphBody.Text = New
		end

		function DialogFunctions:Cancel()
			dialogOut()
		end

		return DialogFunctions
	end

	function WindowFunctions:SetNotificationsState(State)
		notifications.Visible = State
	end

	function WindowFunctions:GetNotificationsState(State)
		return notifications.Visible
	end

	local windowMouseCaptured = false
	local previousMouseBehavior
	local previousMouseIconEnabled

	local function setWindowMouseState(isOpen)
		if isOpen then
			if not windowMouseCaptured then
				pcall(function()
					previousMouseBehavior = UserInputService.MouseBehavior
				end)
				pcall(function()
					previousMouseIconEnabled = UserInputService.MouseIconEnabled
				end)
				windowMouseCaptured = true
			end

			pcall(function()
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
			end)
			return
		end

		if not windowMouseCaptured then
			return
		end

		pcall(function()
			if previousMouseBehavior ~= nil then
				UserInputService.MouseBehavior = previousMouseBehavior
			end
			if previousMouseIconEnabled ~= nil then
				UserInputService.MouseIconEnabled = previousMouseIconEnabled
			end
		end)

		windowMouseCaptured = false
		previousMouseBehavior = nil
		previousMouseIconEnabled = nil
	end

	function WindowFunctions:SetState(State)
		local nextState = State == true
		windowState = nextState
		base.Visible = nextState
		setWindowMouseState(nextState)
	end

	function WindowFunctions:GetState()
		return windowState
	end

	local onUnloadCallback

	function WindowFunctions:Unload()
		optionCall(onUnloadCallback)
		setWindowMouseState(false)
		macLib:Destroy()
		unloaded = true
	end

	function WindowFunctions.onUnloaded(callback)
		onUnloadCallback = callback
	end

	local MenuKeybind = Settings.Keybind or Enum.KeyCode.RightControl

	local function ToggleMenu()
		if activeLoadingGuis > 0 then
			return
		end

		local state = not WindowFunctions:GetState()
		WindowFunctions:SetState(state)
		WindowFunctions:Notify({
			Title = Settings.Title,
			Description = (state and "Maximized " or "Minimized ") .. "the menu. Use " .. tostring(MenuKeybind.Name) .. " to toggle it.",
			Lifetime = 5
		})
	end

	UserInputService.InputEnded:Connect(function(inp, gpe)
		if gpe then return end
		if inp.KeyCode == MenuKeybind then
			ToggleMenu()
		end
	end)

	minimize.MouseButton1Click:Connect(ToggleMenu)
	exit.MouseButton1Click:Connect(function()
		WindowFunctions:Dialog({
			Title = Settings.Title,
			Description = "Are you sure you want to exit the menu? You will lose any unsaved configurations.",
			Buttons = {
				{
					Name = "Confirm",
					Callback = function()
						WindowFunctions:Unload()
					end,
				},
				{
					Name = "Cancel"
				}
			}
		})
	end)

	-- Mobile Toggle/Lock buttons (shown only on touch devices)
	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	if isMobile then
		local mobileLocked = false

		local mobileGui = Instance.new("ScreenGui")
		pcall(function() mobileGui.ResetOnSpawn = false end)
		pcall(function() mobileGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
		pcall(function() mobileGui.DisplayOrder = 2147483646 end)
		pcall(function() mobileGui.ScreenInsets = Enum.ScreenInsets.None end)
		mobileGui.Name = "MobileControls"

		local parentedMobile = false
		if LocalPlayer then
			local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:FindFirstChild("PlayerGui")
			if pg then
				mobileGui.Parent = pg
				parentedMobile = true
			end
		end
		if not parentedMobile then
			local okCG, cg = pcall(function()
				return cloneref and cloneref(MacLib.GetService("CoreGui")) or MacLib.GetService("CoreGui")
			end)
			if okCG then mobileGui.Parent = cg end
		end

		-- Container frame in bottom-right corner
		local mobileContainer = Instance.new("Frame")
		mobileContainer.Name = "MobileContainer"
		mobileContainer.AnchorPoint = Vector2.new(1, 1)
		mobileContainer.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
		mobileContainer.BackgroundTransparency = 0.15
		mobileContainer.BorderSizePixel = 0
		mobileContainer.Position = UDim2.new(1, -14, 1, -14)
		mobileContainer.Size = UDim2.fromOffset(110, 44)
		mobileContainer.ZIndex = 10
		mobileContainer.Parent = mobileGui

		local mobileContainerCorner = Instance.new("UICorner")
		mobileContainerCorner.CornerRadius = UDim.new(0, 8)
		mobileContainerCorner.Parent = mobileContainer

		local mobileContainerStroke = Instance.new("UIStroke")
		mobileContainerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		mobileContainerStroke.Color = Color3.fromRGB(255, 255, 255)
		mobileContainerStroke.Transparency = 0.82
		mobileContainerStroke.Parent = mobileContainer

		local mobileLayout = Instance.new("UIListLayout")
		mobileLayout.FillDirection = Enum.FillDirection.Horizontal
		mobileLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		mobileLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		mobileLayout.Padding = UDim.new(0, 6)
		mobileLayout.SortOrder = Enum.SortOrder.LayoutOrder
		mobileLayout.Parent = mobileContainer

		local mobilePadding = Instance.new("UIPadding")
		mobilePadding.PaddingLeft = UDim.new(0, 7)
		mobilePadding.PaddingRight = UDim.new(0, 7)
		mobilePadding.Parent = mobileContainer

		local function makeMobileButton(labelText, layoutOrder)
			local btn = Instance.new("TextButton")
			btn.Name = labelText .. "MobileBtn"
			btn.AutoButtonColor = false
			btn.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
			btn.BackgroundTransparency = 0
			btn.BorderSizePixel = 0
			btn.FontFace = SafeFont(assets.interFont, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
			btn.Text = labelText
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			btn.TextSize = 12
			btn.TextTransparency = 0.1
			btn.Size = UDim2.fromOffset(48, 30)
			btn.LayoutOrder = layoutOrder
			btn.ZIndex = 11
			btn.Parent = mobileContainer

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 6)
			btnCorner.Parent = btn

			local btnStroke = Instance.new("UIStroke")
			btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			btnStroke.Color = Color3.fromRGB(255, 255, 255)
			btnStroke.Transparency = 0.88
			btnStroke.Parent = btn

			btn.MouseButton1Down:Connect(function()
				Tween(btn, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {
					BackgroundColor3 = Color3.fromRGB(55, 55, 55)
				}):Play()
			end)
			btn.MouseButton1Up:Connect(function()
				Tween(btn, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {
					BackgroundColor3 = Color3.fromRGB(34, 34, 34)
				}):Play()
			end)

			return btn, btnStroke
		end

		local toggleBtn = makeMobileButton("Toggle", 0)
		local lockBtn, lockBtnStroke = makeMobileButton("Lock", 1)

		-- Toggle button logic
		toggleBtn.MouseButton1Click:Connect(function()
			if mobileLocked then return end
			ToggleMenu()
		end)

		-- Lock button logic
		lockBtn.MouseButton1Click:Connect(function()
			mobileLocked = not mobileLocked
			if mobileLocked then
				lockBtn.Text = "Unlock"
				Tween(lockBtn, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {
					BackgroundColor3 = Color3.fromRGB(180, 60, 60),
					TextTransparency = 0
				}):Play()
				Tween(lockBtnStroke, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {
					Transparency = 0.6
				}):Play()
				Tween(toggleBtn, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {
					TextTransparency = 0.55
				}):Play()
			else
				lockBtn.Text = "Lock"
				Tween(lockBtn, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {
					BackgroundColor3 = Color3.fromRGB(34, 34, 34),
					TextTransparency = 0.1
				}):Play()
				Tween(lockBtnStroke, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {
					Transparency = 0.88
				}):Play()
				Tween(toggleBtn, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {
					TextTransparency = 0.1
				}):Play()
			end
		end)
	end
	-- End mobile buttons

	function WindowFunctions:SetKeybind(Keycode)
		MenuKeybind = Keycode
	end

	function WindowFunctions:SetAcrylicBlurState(State)
		acrylicBlur = State
		base.BackgroundTransparency = State and 0.05 or 0
	end

	function WindowFunctions:GetAcrylicBlurState()
		return acrylicBlur
	end

	local function _SetUserInfoState(State)
		if State then
			headshot.Image = (isReady and headshotImage) or "rbxassetid://0"
			username.Text = "@" .. LocalPlayer.Name
			displayName.Text = LocalPlayer.DisplayName
		else
			headshot.Image = assets.userInfoBlurred
			local nameLength = #LocalPlayer.Name
			local displayNameLength = #LocalPlayer.DisplayName
			username.Text = "@" .. string.rep(".", nameLength)
			displayName.Text = string.rep(".", displayNameLength)
		end
	end

	local showUserInfo
	if Settings.ShowUserInfo ~= nil then
		showUserInfo = Settings.ShowUserInfo
	else
		showUserInfo = true
	end

	_SetUserInfoState(showUserInfo)

	function WindowFunctions:SetUserInfoState(State)
		_SetUserInfoState(State)
	end
	function WindowFunctions:GetUserInfoState(State)
		return showUserInfo
	end

	function WindowFunctions:SetSize(Size)
		base.Size = Size
	end
	function WindowFunctions:GetSize(Size)
		return base.Size
	end

	function WindowFunctions:SetScale(Scale)
		baseUIScale.Scale = Scale
	end
	function WindowFunctions:GetScale()
		return baseUIScale.Scale
	end

	local ClassParser = {
		["Toggle"] = {
			Save = function(Flag, data)
				return {
					type = "Toggle", 
					flag = Flag, 
					state = data.State or false
				}
			end,
			Load = function(Flag, data)
				if MacLib.Options[Flag] and data.state ~= nil then
					MacLib.Options[Flag]:UpdateState(data.state)
				end
			end
		},
		["Slider"] = {
			Save = function(Flag, data)
				return {
					type = "Slider", 
					flag = Flag, 
					value = (data.Value and tostring(data.Value)) or false
				}
			end,
			Load = function(Flag, data)
				if MacLib.Options[Flag] and data.value then
					MacLib.Options[Flag]:UpdateValue(data.value)
				end
			end
		},
		["Input"] = {
			Save = function(Flag, data)
				return {
					type = "Input", 
					flag = Flag, 
					text = data.Text
				}
			end,
			Load = function(Flag, data)
				if MacLib.Options[Flag] and data.text and type(data.text) == "string" then
					MacLib.Options[Flag]:UpdateText(data.text)
				end
			end
		},
		["Keybind"] = {
			Save = function(Flag, data)
				local bind = data.Bind
				if type(bind) == "function" then
					bind = nil
				end
				if bind == nil and type(data.GetBind) == "function" then
					bind = data:GetBind()
				end
				if bind == nil then
					bind = data.Value
				end
				local bindName = nil
				if typeof(bind) == "EnumItem" then
					bindName = bind.Name
				elseif type(bind) == "string" and bind ~= "" and bind ~= "None" then
					bindName = bind
				end
				return {
					type = "Keybind", 
					flag = Flag, 
					bind = bindName
				}
			end,
			Load = function(Flag, data)
				if MacLib.Options[Flag] and data.bind then
					if type(MacLib.Options[Flag].Bind) == "function" then
						MacLib.Options[Flag]:Bind(Enum.KeyCode[data.bind])
					elseif type(MacLib.Options[Flag].SetValue) == "function" then
						MacLib.Options[Flag]:SetValue(data.bind)
					end
				end
			end
		},
		["Dropdown"] = {
			Save = function(Flag, data)
				return {
					type = "Dropdown", 
					flag = Flag, 
					value = data.Value
				}
			end,
			Load = function(Flag, data)
				if MacLib.Options[Flag] and data.value then
					MacLib.Options[Flag]:UpdateSelection(data.value)
				end
			end
		},
		["Colorpicker"] = {
			Save = function(Flag, data)
				local function Color3ToHex(color)
					if typeof(color) ~= "Color3" then
						return nil
					end
					return string.format("#%02X%02X%02X", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
				end

				return {
					type = "Colorpicker", 
					flag = Flag, 
					color = Color3ToHex(data.Color or data.Value) or nil,
					alpha = data.Alpha
				}
			end,
			Load = function(Flag, data)
				local function HexToColor3(hex)
					local r = tonumber(hex:sub(2, 3), 16) / 255
					local g = tonumber(hex:sub(4, 5), 16) / 255
					local b = tonumber(hex:sub(6, 7), 16) / 255
					return Color3.new(r, g, b)
				end

				if MacLib.Options[Flag] and data.color then
					MacLib.Options[Flag]:SetColor(HexToColor3(data.color)) 
					if data.alpha then
						MacLib.Options[Flag]:SetAlpha(data.alpha)
					end
				end
			end
		}
	}

	local function BuildFolderTree()
		if isStudio or not (isfolder and makefolder) then return "Config system unavailable." end

		local paths = {
			MacLib.Folder,
			MacLib.Folder .. "/settings"
		}

		for i = 1, #paths do
			local str = paths[i]
			if not isfolder(str) then
				makefolder(str)
			end
		end
	end

	function MacLib:LoadAutoLoadConfig()
		if isStudio or not (isfile and readfile) then return "Config system unavailable." end

		if isfile(MacLib.Folder .. "/settings/autoload.txt") then
			local name = readfile(MacLib.Folder .. "/settings/autoload.txt")

			local suc, err = MacLib:LoadConfig(name)
			if not suc then
				WindowFunctions:Notify({
					Title = "Interface",
					Description = "Error loading autoload config: " .. err
				})
			end

			WindowFunctions:Notify({
				Title = "Interface",
				Description = string.format("Autoloaded config: %q", name),
			})
		end
	end

	function MacLib:SetFolder(Folder)
		if isStudio then return "Config system unavailable." end

		MacLib.Folder = Folder;
		BuildFolderTree()
	end

	function MacLib:SaveConfig(Path)
		if isStudio or not writefile then return "Config system unavailable." end

		if (not Path) then
			return false, "Please select a config file."
		end

		local fullPath = MacLib.Folder .. "/settings/" .. Path .. ".json"

		local data = {
			objects = {}
		}

		for flag, option in next, MacLib.Options do
			if not ClassParser[option.Class] then continue end
			if option.IgnoreConfig then continue end

			table.insert(data.objects, ClassParser[option.Class].Save(flag, option))
		end	

		local success, encoded = pcall(HttpService.JSONEncode, HttpService, data)
		if not success then
			return false, "Unable to encode into JSON data"
		end

		writefile(fullPath, encoded)
		return true
	end

	function MacLib:LoadConfig(Path)
		if isStudio or not (isfile and readfile) then return "Config system unavailable." end

		if (not Path) then
			return false, "Please select a config file."
		end

		local file = MacLib.Folder .. "/settings/" .. Path .. ".json"
		if not isfile(file) then return false, "Invalid file" end

		local success, decoded = pcall(HttpService.JSONDecode, HttpService, readfile(file))
		if not success then return false, "Unable to decode JSON data." end

		for _, option in next, decoded.objects do
			if ClassParser[option.type] then
				task.spawn(function() 
					ClassParser[option.type].Load(option.flag, option) 
				end)
			end
		end

		return true
	end

	function MacLib:RefreshConfigList()
		if isStudio or not (isfolder and listfiles) then return "Config system unavailable." end

		local list = (isfolder(MacLib.Folder) and isfolder(MacLib.Folder .. "/settings")) and listfiles(MacLib.Folder .. "/settings") or {}

		local out = {}
		for i = 1, #list do
			local file = list[i]
			if file:sub(-5) == ".json" then
				local pos = file:find(".json", 1, true)
				local start = pos

				local char = file:sub(pos, pos)
				while char ~= "/" and char ~= "\\" and char ~= "" do
					pos = pos - 1
					char = file:sub(pos, pos)
				end

				if char == "/" or char == "\\" then
					local name = file:sub(pos + 1, start - 1)
					if name ~= "options" then
						table.insert(out, name)
					end
				end
			end
		end

		return out
	end

	macLib.Enabled = false

	local assetList = {}
	for _, assetId in pairs(assets) do
		table.insert(assetList, assetId)
	end

	if Settings.PreloadAssets == true or Settings.BlockingPreload == true then
		pcall(function()
			ContentProvider:PreloadAsync(assetList)
		end)
	else
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(assetList)
			end)
		end)
	end
	macLib.Enabled = true
	windowState = true
	setWindowMouseState(true)

	return WindowFunctions
end

--// TiRex / Obsidian compatibility layer
local compatState = {
	Windows = {},
	KeyPickers = {},
	StatusLabels = {},
	SquareCornerRoots = {},
	InputBound = false,
	InputBeganConnection = nil,
	InputEndedConnection = nil
}

local unpackArgs = unpack or table.unpack

local function runCallback(callback, ...)
	if type(callback) ~= "function" then
		return
	end

	local args = { ... }
	local function invoke()
		local ok, err = pcall(callback, unpackArgs(args))
		if not ok then
			warn("[MacLib] callback error: " .. tostring(err))
		end
	end

	if task and type(task.spawn) == "function" then
		task.spawn(invoke)
	else
		coroutine.wrap(invoke)()
	end
end

local function firstNonNil(...)
	local values = { ... }
	for i = 1, #values do
		if values[i] ~= nil then
			return values[i]
		end
	end
	return nil
end

local function normalizeKeyName(value)
	if type(value) == "table" then
		value = value.Key or value.Value or value[1]
	end
	if typeof(value) == "EnumItem" then
		return value.Name
	end

	local text = tostring(value or "None")
	text = text:gsub("^Enum%.KeyCode%.", "")
	text = text:gsub("^KeyCode%.", "")
	text = text:gsub("^Enum%.UserInputType%.", "")
	text = text:gsub("^UserInputType%.", "")
	if text == "" or string.lower(text) == "nil" then
		text = "None"
	end
	return text
end

local function parseKeyPickerValue(value, mode)
	local parsedMode = mode
	if type(value) == "table" then
		if value.Mode ~= nil then
			parsedMode = tostring(value.Mode)
		elseif value[2] ~= nil then
			parsedMode = tostring(value[2])
		end
	end
	return normalizeKeyName(value), parsedMode
end

local function enumItemByName(enumType, name)
	local target = string.lower(tostring(name or ""))
	if target == "" or target == "none" then
		return nil
	end

	for _, item in ipairs(enumType:GetEnumItems()) do
		if string.lower(item.Name) == target then
			return item
		end
	end
	return nil
end

local function inputMatchesKey(input, keyName)
	local normalized = normalizeKeyName(keyName)
	if normalized == "None" then
		return false
	end
	if input.KeyCode and input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode.Name == normalized then
		return true
	end
	if input.UserInputType and input.UserInputType.Name == normalized then
		return true
	end
	return false
end

local function ensureCompatInput()
	if compatState.InputBound then
		return
	end
	compatState.InputBound = true

	compatState.InputBeganConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or UserInputService:GetFocusedTextBox() then
			return
		end

		for _, keyPicker in pairs(compatState.KeyPickers) do
			if keyPicker.Active ~= false and inputMatchesKey(input, keyPicker.Value) then
				if keyPicker.SyncToggleState and keyPicker.OwnerToggle and type(keyPicker.OwnerToggle.SetValue) == "function" then
					if keyPicker.Mode == "Hold" then
						keyPicker.OwnerToggle:SetValue(true)
					else
						keyPicker.OwnerToggle:SetValue(not keyPicker.OwnerToggle.Value)
					end
				end
				runCallback(keyPicker.Callback, keyPicker.Value)
			end
		end
	end)

	compatState.InputEndedConnection = UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		for _, keyPicker in pairs(compatState.KeyPickers) do
			if keyPicker.Active ~= false
				and keyPicker.Mode == "Hold"
				and keyPicker.SyncToggleState
				and keyPicker.OwnerToggle
				and inputMatchesKey(input, keyPicker.Value) then
				keyPicker.OwnerToggle:SetValue(false)
			end
		end
	end)
end

local function createLoadingGui(settings)
	settings = settings or {}
	local gui = GetGui()
	gui.Name = "TiRexLoading"

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
	holder.BorderSizePixel = 0
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(320, 128)
	holder.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 0)
	corner.Parent = holder

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.88
	stroke.Parent = holder

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 16)
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingRight = UDim.new(0, 18)
	padding.PaddingTop = UDim.new(0, 16)
	padding.Parent = holder

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.FontFace = SafeFont(assets.interFont, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
	title.Text = settings.Title or "TiRex"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(1, 0, 0, 22)
	title.Parent = holder

	local message = Instance.new("TextLabel")
	message.Name = "Message"
	message.BackgroundTransparency = 1
	message.FontFace = SafeFont(assets.interFont, Enum.FontWeight.Medium, Enum.FontStyle.Normal)
	message.Text = "Loading..."
	message.TextColor3 = Color3.fromRGB(230, 230, 230)
	message.TextSize = 13
	message.TextXAlignment = Enum.TextXAlignment.Left
	message.Size = UDim2.new(1, 0, 0, 18)
	message.Parent = holder

	local description = Instance.new("TextLabel")
	description.Name = "Description"
	description.BackgroundTransparency = 1
	description.FontFace = SafeFont(assets.interFont)
	description.Text = ""
	description.TextColor3 = Color3.fromRGB(190, 190, 190)
	description.TextSize = 12
	description.TextWrapped = true
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.Size = UDim2.new(1, 0, 0, 30)
	description.Parent = holder

	local progressBack = Instance.new("Frame")
	progressBack.Name = "ProgressBack"
	progressBack.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	progressBack.BorderSizePixel = 0
	progressBack.Size = UDim2.new(1, 0, 0, 5)
	progressBack.Parent = holder

	local progressCorner = Instance.new("UICorner")
	progressCorner.CornerRadius = UDim.new(0, 0)
	progressCorner.Parent = progressBack

	local progress = Instance.new("Frame")
	progress.Name = "Progress"
	progress.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	progress.BorderSizePixel = 0
	progress.Size = UDim2.fromScale(0, 1)
	progress.Parent = progressBack

	local progressFillCorner = Instance.new("UICorner")
	progressFillCorner.CornerRadius = UDim.new(0, 0)
	progressFillCorner.Parent = progress

	local loading = {
		Destroyed = false,
		TotalSteps = tonumber(settings.TotalSteps) or 1,
		CurrentStep = 0
	}

	function loading:SetMessage(text)
		message.Text = tostring(text or "")
	end
	function loading:SetDescription(text)
		description.Text = tostring(text or "")
	end
	function loading:SetCurrentStep(step)
		self.CurrentStep = math.clamp(tonumber(step) or 0, 0, self.TotalSteps)
		progress.Size = UDim2.fromScale(self.TotalSteps > 0 and (self.CurrentStep / self.TotalSteps) or 1, 1)
	end
	function loading:Continue()
		self:Destroy()
	end
	function loading:Destroy()
		if self.Destroyed then
			return
		end
		self.Destroyed = true
		activeLoadingGuis = math.max(0, activeLoadingGuis - 1)
		gui:Destroy()
	end

	activeLoadingGuis += 1
	return loading
end

local function makeNotificationPayload(settings, time)
	if type(settings) == "table" then
		return {
			Title = settings.Title or MacLib.Name or "TiRex",
			Description = settings.Description or settings.Text or "",
			Lifetime = settings.Lifetime or settings.Time or time or 3,
			Style = settings.Style,
			SizeX = settings.SizeX,
			Scale = settings.Scale,
			Callback = settings.Callback
		}
	end

	return {
		Title = MacLib.Name or "TiRex",
		Description = tostring(settings or ""),
		Lifetime = time or 3
	}
end

local function isIgnoredOption(flag)
	local ignoreIndexes = MacLib.SaveManager and MacLib.SaveManager.IgnoreIndexes
	return type(ignoreIndexes) == "table" and table.find(ignoreIndexes, flag) ~= nil
end

local function createDraggableLabel(text)
	local gui = GetGui()
	gui.Name = "TiRexStatusLabel"

	local label = Instance.new("TextButton")
	label.Name = "StatusLabel"
	label.AutoButtonColor = false
	label.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
	label.BackgroundTransparency = 0.1
	label.BorderSizePixel = 0
	label.FontFace = SafeFont(assets.interFont, Enum.FontWeight.Medium, Enum.FontStyle.Normal)
	label.Text = tostring(text or "TiRex")
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 13
	label.Position = UDim2.fromOffset(18, 18)
	label.Size = UDim2.fromOffset(180, 30)
	label.Visible = true
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 0)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.88
	stroke.Parent = label

	local dragging = false
	local dragStart
	local startPos

	label.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = label.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			label.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)

	local proxy = {}
	function proxy:SetText(value)
		label.Text = tostring(value or "")
	end
	function proxy:SetVisible(state)
		label.Visible = state == true
	end
	function proxy:GetFrame()
		return gui
	end
	function proxy:Destroy()
		gui:Destroy()
	end

	table.insert(compatState.StatusLabels, proxy)
	return proxy
end

local function installKeyPicker(flag, settings, ownerToggle, section, ownerProxy)
	settings = settings or {}
	ensureCompatInput()

	local defaultValue, defaultMode = parseKeyPickerValue(settings.Default or "None", settings.Mode or "Toggle")
	local keyProxy = {
		Value = defaultValue,
		Mode = defaultMode or "Toggle",
		SyncToggleState = settings.SyncToggleState == true,
		OwnerToggle = ownerToggle,
		Callback = settings.Callback,
		ChangedCallback = settings.ChangedCallback,
		Active = true,
		NoUI = settings.NoUI == true,
		IgnoreConfig = isIgnoredOption(flag),
		Class = "Keybind"
	}

	local rawKeybind
	if not keyProxy.NoUI and section and type(section.Keybind) == "function" then
		local enumDefault = enumItemByName(Enum.KeyCode, keyProxy.Value) or enumItemByName(Enum.UserInputType, keyProxy.Value)
		rawKeybind = section:Keybind({
			Name = settings.Text or settings.Name or flag,
			Default = enumDefault,
			onBinded = function(bind)
				keyProxy.Value = normalizeKeyName(bind)
				if flag == "ScriptKeybind" and MacLib._activeWindow and type(MacLib._activeWindow.SetKeybind) == "function" then
					local enumKey = enumItemByName(Enum.KeyCode, keyProxy.Value)
					if enumKey then
						MacLib._activeWindow:SetKeybind(enumKey)
					end
				end
				runCallback(keyProxy.ChangedCallback, keyProxy.Value)
			end
		}, nil)
	end

	function keyProxy:SetValue(value)
		local newValue, newMode = parseKeyPickerValue(value, self.Mode)
		self.Value = newValue
		self.Mode = newMode or self.Mode

		if rawKeybind then
			local enumValue = enumItemByName(Enum.KeyCode, self.Value) or enumItemByName(Enum.UserInputType, self.Value)
			if enumValue and type(rawKeybind.Bind) == "function" then
				rawKeybind:Bind(enumValue)
			elseif type(rawKeybind.Unbind) == "function" then
				rawKeybind:Unbind()
			end
		end

		if flag == "ScriptKeybind" and MacLib._activeWindow and type(MacLib._activeWindow.SetKeybind) == "function" then
			local enumKey = enumItemByName(Enum.KeyCode, self.Value)
			if enumKey then
				MacLib._activeWindow:SetKeybind(enumKey)
			end
		end

		runCallback(self.ChangedCallback, self.Value)
	end
	function keyProxy:Bind(value)
		self:SetValue(value)
	end
	function keyProxy:Unbind()
		self:SetValue("None")
	end
	function keyProxy:GetBind()
		return enumItemByName(Enum.KeyCode, self.Value) or enumItemByName(Enum.UserInputType, self.Value) or self.Value
	end
	function keyProxy:GetState()
		return self.Value
	end
	function keyProxy:SetVisibility(state)
		if rawKeybind and type(rawKeybind.SetVisibility) == "function" then
			rawKeybind:SetVisibility(state)
		end
	end

	if ownerProxy then
		ownerProxy.KeyPicker = keyProxy
	end
	compatState.KeyPickers[flag] = keyProxy
	MacLib.Options[flag] = keyProxy
	return keyProxy
end

local function wrapLabel(rawLabel, groupProxy)
	local proxy = {
		Raw = rawLabel,
		Value = nil
	}

	function proxy:SetText(value)
		self.Value = tostring(value or "")
		if rawLabel and type(rawLabel.UpdateName) == "function" then
			rawLabel:UpdateName(self.Value)
		end
	end
	function proxy:SetVisibility(state)
		if rawLabel and type(rawLabel.SetVisibility) == "function" then
			rawLabel:SetVisibility(state)
		end
	end
	function proxy:AddKeyPicker(flag, settings)
		settings = settings or {}
		local inlineSettings = {}
		for key, value in pairs(settings) do
			inlineSettings[key] = value
		end
		inlineSettings.NoUI = true

		local keyProxy = groupProxy:_AddKeyPicker(flag, inlineSettings, nil, self)
		if not rawLabel or type(rawLabel.GetFrame) ~= "function" then
			return keyProxy
		end

		local labelFrame, labelText = rawLabel:GetFrame()
		if typeof(labelFrame) ~= "Instance" then
			return keyProxy
		end

		labelFrame.ClipsDescendants = false
		if typeof(labelText) == "Instance" then
			labelText.Size = UDim2.new(1, -100, 1, 0)
			labelText.TextTransparency = 0.35
		end

		local binderBox = Instance.new("TextButton")
		binderBox.Name = "BinderBox"
		binderBox.FontFace = SafeFont(assets.interFont, Enum.FontWeight.Medium, Enum.FontStyle.Normal)
		binderBox.Text = "-"
		binderBox.TextColor3 = Color3.fromRGB(255, 255, 255)
		binderBox.TextSize = 12
		binderBox.TextScaled = false
		binderBox.TextTransparency = 0
		binderBox.TextTruncate = Enum.TextTruncate.AtEnd
		binderBox.AnchorPoint = Vector2.new(1, 0.5)
		binderBox.AutomaticSize = Enum.AutomaticSize.X
		binderBox.AutoButtonColor = false
		binderBox.BackgroundColor3 = Color3.fromRGB(130, 130, 130)
		binderBox.BackgroundTransparency = 0.76
		binderBox.BorderSizePixel = 0
		binderBox.Position = UDim2.fromScale(1, 0.5)
		binderBox.Size = UDim2.fromOffset(21, 21)
		binderBox.ZIndex = 10
		binderBox.Parent = labelFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 0)
		corner.Parent = binderBox

		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = Color3.fromRGB(150, 150, 150)
		stroke.Transparency = 0.35
		stroke.Parent = binderBox

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 6)
		padding.PaddingRight = UDim.new(0, 6)
		padding.Parent = binderBox

		local textSize = Instance.new("UITextSizeConstraint")
		textSize.MaxTextSize = 12
		textSize.MinTextSize = 9
		textSize.Parent = binderBox

		local sizeConstraint = Instance.new("UISizeConstraint")
		sizeConstraint.MinSize = Vector2.new(21, 21)
		sizeConstraint.MaxSize = Vector2.new(96, 21)
		sizeConstraint.Parent = binderBox

		local binding = false
		local suppressUntil = 0
		local function formatKeyName(value)
			local name = normalizeKeyName(value)
			if name == "None" or name == "" or name == "nil" then
				return "-"
			end
			local shortNames = {
				MouseButton1 = "M1",
				MouseButton2 = "M2",
				MouseButton3 = "M3",
				LeftShift = "LS",
				RightShift = "RS",
				LeftControl = "LC",
				RightControl = "RC",
				LeftAlt = "LA",
				RightAlt = "RA",
				Space = "Space",
				Return = "EN",
				Backspace = "BK"
			}
			return shortNames[name] or (#name <= 6 and name or string.sub(name, 1, 6))
		end

		local function updateInlineVisual(isBinding)
			if isBinding then
				binderBox.Text = "..."
				binderBox.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
				binderBox.BackgroundTransparency = 0.08
				stroke.Color = Color3.fromRGB(255, 255, 255)
				stroke.Transparency = 0.12
			else
				binderBox.Text = formatKeyName(keyProxy.Value)
				local hasValue = keyProxy.Value and keyProxy.Value ~= "None"
				binderBox.BackgroundColor3 = hasValue and Color3.fromRGB(24, 24, 24) or Color3.fromRGB(130, 130, 130)
				binderBox.BackgroundTransparency = hasValue and 0.08 or 0.76
				stroke.Color = hasValue and Color3.fromRGB(224, 224, 224) or Color3.fromRGB(150, 150, 150)
				stroke.Transparency = hasValue and 0.12 or 0.35
			end
		end

		binderBox.MouseButton1Click:Connect(function()
			if tick() < suppressUntil then
				return
			end
			binding = not binding
			updateInlineVisual(binding)
		end)

		UserInputService.InputBegan:Connect(function(input)
			if not binding then
				return
			end
			local isKeyboard = input.UserInputType == Enum.UserInputType.Keyboard
			local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.MouseButton2
				or input.UserInputType == Enum.UserInputType.MouseButton3
			if not isKeyboard and not isMouse then
				return
			end
			if isKeyboard and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete) then
				keyProxy:SetValue("None")
			elseif isKeyboard then
				keyProxy:SetValue(input.KeyCode.Name)
			else
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					suppressUntil = tick() + 0.2
				end
				keyProxy:SetValue(input.UserInputType.Name)
			end
			binding = false
			updateInlineVisual(false)
		end)

		local oldSetValue = keyProxy.SetValue
		function keyProxy:SetValue(value)
			oldSetValue(self, value)
			updateInlineVisual(false)
		end

		local oldSetVisibility = keyProxy.SetVisibility
		function keyProxy:SetVisibility(state)
			if oldSetVisibility then
				oldSetVisibility(self, state)
			end
			binderBox.Visible = state == true
		end

		updateInlineVisual(false)
		return keyProxy
	end
	function proxy:KeyPicker(flag, settings)
		return self:AddKeyPicker(flag, settings)
	end
	function proxy:addKeyPicker(flag, settings)
		return self:AddKeyPicker(flag, settings)
	end
	function proxy:KeyPicket(flag, settings)
		return self:AddKeyPicker(flag, settings)
	end
	function proxy:AddKeyPicket(flag, settings)
		return self:AddKeyPicker(flag, settings)
	end
	function proxy:addKeyPicket(flag, settings)
		return self:AddKeyPicker(flag, settings)
	end
	function proxy:AddKeybind(flag, settings)
		return self:AddKeyPicker(flag, settings)
	end
	function proxy:addKeybind(flag, settings)
		return self:AddKeyPicker(flag, settings)
	end

	return proxy
end

local function makeGroupProxy(section)
	local groupProxy = {
		_section = section
	}

	function groupProxy:_AddKeyPicker(flag, settings, ownerToggle, ownerProxy)
		return installKeyPicker(flag, settings, ownerToggle, section, ownerProxy)
	end
	function groupProxy:AddKeyPicker(flag, settings)
		return self:_AddKeyPicker(flag, settings, nil, self)
	end
	function groupProxy:KeyPicker(flag, settings)
		return self:AddKeyPicker(flag, settings)
	end
	function groupProxy:addKeyPicker(flag, settings)
		return self:AddKeyPicker(flag, settings)
	end
	function groupProxy:KeyPicket(flag, settings)
		return self:AddKeyPicker(flag, settings)
	end
	function groupProxy:AddKeyPicket(flag, settings)
		return self:AddKeyPicker(flag, settings)
	end
	function groupProxy:addKeyPicket(flag, settings)
		return self:AddKeyPicker(flag, settings)
	end

	function groupProxy:AddLabel(text)
		local raw = section:Label({
			Text = tostring(text or "")
		})
		local proxy = wrapLabel(raw, self)
		proxy.Value = tostring(text or "")
		return proxy
	end

	function groupProxy:AddDivider()
		return section:Divider()
	end

	function groupProxy:AddUIPassthrough(flag, settings)
		settings = settings or {}
		if type(section.Custom) == "function" then
			return section:Custom({
				Name = flag,
				Instance = settings.Instance,
				Height = settings.Height,
				Visible = settings.Visible
			}, flag)
		end
		return self:AddLabel(flag)
	end

	function groupProxy:AddButton(text, callback)
		local settings = type(text) == "table" and text or {
			Name = tostring(text or "Button"),
			Callback = callback
		}
		return section:Button(settings)
	end

	local function addBooleanOption(flag, settings, rendererName)
		settings = settings or {}
		local toggleProxy
		local renderer = section and section[rendererName]
		if type(renderer) ~= "function" then
			renderer = section and section.Toggle
		end

		local rawToggle = renderer(section, {
			Name = settings.Text or settings.Name or tostring(flag),
			Default = settings.Default == true,
			Callback = function(value)
				if toggleProxy then
					toggleProxy.Value = value == true
					toggleProxy.State = toggleProxy.Value
				end
				runCallback(settings.Callback, value == true)
			end
		}, nil)

		toggleProxy = {
			Raw = rawToggle,
			Value = settings.Default == true,
			State = settings.Default == true,
			Class = "Toggle",
			IgnoreConfig = isIgnoredOption(flag),
			Settings = settings
		}

		function toggleProxy:SetValue(value)
			local desired = value == true
			if self.Value == desired then
				return
			end
			self.Value = desired
			self.State = desired
			if rawToggle and type(rawToggle.UpdateState) == "function" then
				rawToggle:UpdateState(desired)
			end
		end
		function toggleProxy:UpdateState(value)
			self:SetValue(value)
		end
		function toggleProxy:GetState()
			return self.Value
		end
		function toggleProxy:UpdateName(name)
			if rawToggle and type(rawToggle.UpdateName) == "function" then
				rawToggle:UpdateName(name)
			end
		end
		function toggleProxy:SetVisibility(state)
			if rawToggle and type(rawToggle.SetVisibility) == "function" then
				rawToggle:SetVisibility(state)
			end
		end
		function toggleProxy:AddKeyPicker(keyFlag, keySettings)
			return groupProxy:_AddKeyPicker(keyFlag, keySettings, self, self)
		end
		function toggleProxy:AddKeybind(keyFlag, keySettings)
			return self:AddKeyPicker(keyFlag, keySettings)
		end
		function toggleProxy:addKeybind(keyFlag, keySettings)
			return self:AddKeyPicker(keyFlag, keySettings)
		end
		function toggleProxy:addKeyPicker(keyFlag, keySettings)
			return self:AddKeyPicker(keyFlag, keySettings)
		end
		function toggleProxy:KeyPicket(keyFlag, keySettings)
			return self:AddKeyPicker(keyFlag, keySettings)
		end
		function toggleProxy:AddKeyPicket(keyFlag, keySettings)
			return self:AddKeyPicker(keyFlag, keySettings)
		end
		function toggleProxy:addKeyPicket(keyFlag, keySettings)
			return self:AddKeyPicker(keyFlag, keySettings)
		end
		function toggleProxy:AddColorPicker(colorFlag, colorSettings)
			return groupProxy:AddColorPicker(colorFlag, colorSettings, self)
		end
		function toggleProxy:addColorPicker(colorFlag, colorSettings)
			return self:AddColorPicker(colorFlag, colorSettings)
		end
		function toggleProxy:AddColorpicker(colorFlag, colorSettings)
			return self:AddColorPicker(colorFlag, colorSettings)
		end
		function toggleProxy:addColorpicker(colorFlag, colorSettings)
			return self:AddColorPicker(colorFlag, colorSettings)
		end

		MacLib.Toggles[flag] = toggleProxy
		MacLib.Options[flag] = toggleProxy
		return toggleProxy
	end

	function groupProxy:AddCheckbox(flag, settings)
		return addBooleanOption(flag, settings, "Checkbox")
	end

	function groupProxy:AddToggle(flag, settings)
		return addBooleanOption(flag, settings, "Toggle")
	end
	function groupProxy:AddKeybind(flag, settings)
		return self:AddKeyPicker(flag, settings)
	end
	function groupProxy:addKeybind(flag, settings)
		return self:AddKeybind(flag, settings)
	end
	function groupProxy:AddKeyPicket(flag, settings)
		return self:AddKeyPicker(flag, settings)
	end
	function groupProxy:addKeyPicket(flag, settings)
		return self:AddKeyPicker(flag, settings)
	end

	function groupProxy:AddSlider(flag, settings)
		settings = settings or {}
		local sliderProxy
		local rawSlider = section:Slider({
			Name = settings.Text or settings.Name or tostring(flag),
			Default = firstNonNil(settings.Default, settings.Min, settings.Minimum, 0),
			Minimum = firstNonNil(settings.Min, settings.Minimum, 0),
			Maximum = firstNonNil(settings.Max, settings.Maximum, 100),
			DisplayMethod = "Value",
			Precision = settings.Rounding or settings.Precision,
			Prefix = settings.Prefix,
			Suffix = settings.Suffix,
			Callback = function(value)
				if sliderProxy then
					sliderProxy.Value = value
				end
				runCallback(settings.Callback, value)
			end,
			onInputComplete = settings.onInputComplete
		}, nil)

		sliderProxy = rawSlider or {}
		sliderProxy.Value = firstNonNil(settings.Default, settings.Min, settings.Minimum, 0)
		sliderProxy.Class = "Slider"
		sliderProxy.IgnoreConfig = isIgnoredOption(flag)
		sliderProxy.CompatSettings = settings

		local oldUpdateValue = sliderProxy.UpdateValue
		function sliderProxy:SetValue(value)
			self.Value = tonumber(value) or self.Value
			if oldUpdateValue then
				oldUpdateValue(self, self.Value)
			end
		end
		function sliderProxy:UpdateValue(value)
			self:SetValue(value)
		end

		MacLib.Options[flag] = sliderProxy
		return sliderProxy
	end

	function groupProxy:AddDropdown(flag, settings)
		settings = settings or {}
		local values = settings.Values or settings.Options or {}
		local dropdownProxy
		local rawDropdown = section:Dropdown({
			Name = settings.Text or settings.Name or tostring(flag),
			Options = values,
			Default = settings.Default,
			Multi = settings.Multi == true,
			Required = settings.Required == true or settings.AllowNull == false,
			Search = settings.Searchable == true or settings.Search == true,
			Callback = function(value)
				if dropdownProxy then
					dropdownProxy.Value = value
				end
				runCallback(settings.Callback, value)
			end
		}, nil)

		local initialValue = nil
		if type(settings.Default) == "number" then
			initialValue = values[settings.Default]
		elseif type(settings.Default) == "table" and settings.Multi then
			initialValue = settings.Default
		else
			initialValue = settings.Default
		end

		dropdownProxy = rawDropdown or {}
		dropdownProxy.Value = initialValue
		dropdownProxy.Values = values
		dropdownProxy.Class = "Dropdown"
		dropdownProxy.IgnoreConfig = isIgnoredOption(flag)
		dropdownProxy.CompatSettings = settings

		local oldUpdateSelection = dropdownProxy.UpdateSelection
		local oldClearOptions = dropdownProxy.ClearOptions
		local oldInsertOptions = dropdownProxy.InsertOptions
		function dropdownProxy:SetValue(value)
			self.Value = value
			if oldUpdateSelection then
				oldUpdateSelection(self, value)
			end
		end
		function dropdownProxy:UpdateSelection(value)
			self:SetValue(value)
		end
		function dropdownProxy:SetValues(newValues)
			self.Values = newValues or {}
			if oldClearOptions then
				oldClearOptions(self)
			end
			if oldInsertOptions then
				oldInsertOptions(self, self.Values)
			end
			if settings.AllowNull == false and self.Values[1] then
				self:SetValue(1)
			end
		end

		MacLib.Options[flag] = dropdownProxy
		return dropdownProxy
	end

	function groupProxy:AddInput(flag, settings)
		settings = settings or {}
		local inputProxy
		local rawInput = section:Input({
			Name = settings.Text or settings.Name or tostring(flag),
			Default = settings.Default or "",
			Placeholder = settings.Placeholder or settings.PlaceholderText or "",
			AcceptedCharacters = settings.AcceptedCharacters or "All",
			CharacterLimit = settings.CharacterLimit,
			Callback = function(value)
				if inputProxy then
					inputProxy.Value = value
					inputProxy.Text = value
				end
				runCallback(settings.Callback, value)
			end,
			onChanged = settings.onChanged
		}, nil)

		inputProxy = rawInput or {}
		inputProxy.Value = settings.Default or ""
		inputProxy.Text = settings.Default or ""
		inputProxy.Class = "Input"
		inputProxy.IgnoreConfig = isIgnoredOption(flag)
		inputProxy.CompatSettings = settings

		local oldUpdateText = inputProxy.UpdateText
		function inputProxy:SetValue(value)
			self.Value = tostring(value or "")
			self.Text = self.Value
			if oldUpdateText then
				oldUpdateText(self, self.Value)
			end
		end

		MacLib.Options[flag] = inputProxy
		return inputProxy
	end

	function groupProxy:AddColorPicker(flag, settings, ownerToggle)
		settings = settings or {}
		local colorProxy
		local rawColor = section:Colorpicker({
			Name = settings.Title or settings.Text or settings.Name or tostring(flag),
			Default = settings.Default or Color3.fromRGB(255, 255, 255),
			Alpha = settings.Alpha,
			Callback = function(color, alpha)
				if colorProxy then
					colorProxy.Value = color
					colorProxy.Color = color
					colorProxy.Alpha = alpha
				end
				runCallback(settings.Callback, color, alpha)
			end
		}, nil)

		colorProxy = rawColor or {}
		colorProxy.Value = settings.Default or Color3.fromRGB(255, 255, 255)
		colorProxy.Color = colorProxy.Value
		colorProxy.Alpha = settings.Alpha
		colorProxy.Class = "Colorpicker"
		colorProxy.IgnoreConfig = isIgnoredOption(flag)
		colorProxy.CompatSettings = settings

		local oldSetColor = colorProxy.SetColor
		function colorProxy:SetValue(color)
			self.Value = color
			self.Color = color
			if oldSetColor then
				oldSetColor(self, color)
			end
		end
		function colorProxy:AddKeyPicker(keyFlag, keySettings)
			return groupProxy:_AddKeyPicker(keyFlag, keySettings, ownerToggle, self)
		end
		function colorProxy:AddKeybind(keyFlag, keySettings)
			return self:AddKeyPicker(keyFlag, keySettings)
		end
		function colorProxy:addKeybind(keyFlag, keySettings)
			return self:AddKeyPicker(keyFlag, keySettings)
		end
		function colorProxy:addKeyPicker(keyFlag, keySettings)
			return self:AddKeyPicker(keyFlag, keySettings)
		end
		function colorProxy:KeyPicker(keyFlag, keySettings)
			return self:AddKeyPicker(keyFlag, keySettings)
		end
		function colorProxy:KeyPicket(keyFlag, keySettings)
			return self:AddKeyPicker(keyFlag, keySettings)
		end
		function colorProxy:AddKeyPicket(keyFlag, keySettings)
			return self:AddKeyPicker(keyFlag, keySettings)
		end
		function colorProxy:addKeyPicket(keyFlag, keySettings)
			return self:AddKeyPicker(keyFlag, keySettings)
		end

		MacLib.Options[flag] = colorProxy
		return colorProxy
	end
	function groupProxy:AddColorpicker(flag, settings, ownerToggle)
		return self:AddColorPicker(flag, settings, ownerToggle)
	end
	function groupProxy:addColorPicker(flag, settings, ownerToggle)
		return self:AddColorPicker(flag, settings, ownerToggle)
	end
	function groupProxy:addColorpicker(flag, settings, ownerToggle)
		return self:AddColorPicker(flag, settings, ownerToggle)
	end
	function groupProxy:ColorPicker(flag, settings, ownerToggle)
		return self:AddColorPicker(flag, settings, ownerToggle)
	end
	function groupProxy:Colorpicker(flag, settings, ownerToggle)
		return self:AddColorPicker(flag, settings, ownerToggle)
	end

	return groupProxy
end

local function makeTabProxy(rawTab)
	local tabProxy = {
		_tab = rawTab
	}

	local function addGroup(side, title, icon)
		local section = rawTab:Section({ Side = side })
		if title and title ~= "" then
			if icon then
				local header = section:Custom({
					Name = "GroupHeader",
					Height = 24,
					ClipsDescendants = false
				})
				local headerFrame = header:GetFrame()
				local iconInstance = createIconInstance(icon, 16, Color3.fromRGB(255, 255, 255), 0.3)
				iconInstance.Name = "GroupIcon"
				iconInstance.AnchorPoint = Vector2.new(0, 0.5)
				iconInstance.Position = UDim2.fromScale(0, 0.5)
				iconInstance.Size = UDim2.fromOffset(16, 16)
				iconInstance.Parent = headerFrame

				local headerText = Instance.new("TextLabel")
				headerText.Name = "HeaderText"
				headerText.FontFace = SafeFont(
					assets.interFont,
					Enum.FontWeight.Medium,
					Enum.FontStyle.Normal
				)
				headerText.RichText = true
				headerText.Text = tostring(title)
				headerText.TextColor3 = Color3.fromRGB(255, 255, 255)
				headerText.TextSize = 16
				headerText.TextTransparency = 0.3
				headerText.TextWrapped = true
				headerText.TextXAlignment = Enum.TextXAlignment.Left
				headerText.TextYAlignment = Enum.TextYAlignment.Center
				headerText.AnchorPoint = Vector2.new(0, 0.5)
				headerText.AutomaticSize = Enum.AutomaticSize.Y
				headerText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				headerText.BackgroundTransparency = 1
				headerText.BorderColor3 = Color3.fromRGB(0, 0, 0)
				headerText.BorderSizePixel = 0
				headerText.Position = UDim2.new(0, 24, 0.5, 0)
				headerText.Size = UDim2.new(1, -24, 0, 0)
				headerText.Parent = headerFrame
			else
				section:Header({ Name = title })
			end
		end
		return makeGroupProxy(section)
	end

	function tabProxy:AddLeftGroupbox(title, icon)
		return addGroup("Left", title, icon)
	end
	function tabProxy:AddRightGroupbox(title, icon)
		return addGroup("Right", title, icon)
	end
	function tabProxy:AddGroupbox(title, icon)
		return addGroup("Left", title, icon)
	end
	function tabProxy:Select()
		if rawTab and type(rawTab.Select) == "function" then
			rawTab:Select()
		end
	end
	function tabProxy:InsertConfigSection(side)
		if rawTab and type(rawTab.InsertConfigSection) == "function" then
			return rawTab:InsertConfigSection(side or "Left")
		end
	end

	return tabProxy
end

function MacLib:CreateLoading(settings)
	local ok, loading = pcall(createLoadingGui, settings)
	if ok and type(loading) == "table" then
		return loading
	end

	warn("[TiRex] CreateLoading failed: " .. tostring(loading))
	return {
		Destroyed = false,
		TotalSteps = tonumber(settings and settings.TotalSteps) or 1,
		CurrentStep = 0,
		SetMessage = function() end,
		SetDescription = function() end,
		SetCurrentStep = function(self, step)
			self.CurrentStep = math.clamp(tonumber(step) or 0, 0, self.TotalSteps)
		end,
		Continue = function(self)
			self:Destroy()
		end,
		Destroy = function(self)
			self.Destroyed = true
		end
	}
end

function MacLib:CreateWindow(settings)
	settings = settings or {}
	self.Name = settings.Title or "TiRex"
	local rawWindow = self:Window({
		Title = self.Name,
		Subtitle = settings.Footer or settings.Subtitle or "",
		Size = settings.Size or DEFAULT_WINDOW_SIZE,
		MinSize = settings.MinimumSize or settings.MinSize or MIN_WINDOW_SIZE,
		DragStyle = settings.DragStyle or 1,
		DisabledWindowControls = settings.DisabledWindowControls or {},
		ShowUserInfo = settings.ShowUserInfo ~= false,
		Keybind = settings.ToggleKeybind or settings.Keybind or Enum.KeyCode.G,
		AcrylicBlur = settings.AcrylicBlur == true
	})

	self._activeWindow = rawWindow
	table.insert(compatState.Windows, rawWindow)

	if self.SaveManager and self.SaveManager.Folder and type(self.SetFolder) == "function" then
		pcall(function()
			self:SetFolder(self.SaveManager.Folder)
		end)
	end

	local tabGroup = rawWindow:TabGroup()
	local windowProxy = {
		Raw = rawWindow,
		Settings = settings,
		TabCount = 0
	}

	function windowProxy:AddTab(name, icon)
		local image = icon
		if type(image) == "number" then
			image = "rbxassetid://" .. tostring(image)
		end

		local rawTab = tabGroup:Tab({
			Name = tostring(name or "Tab"),
			Image = image
		})

		self.TabCount += 1
		local tabProxy = makeTabProxy(rawTab)
		if self.TabCount == 1 then
			tabProxy:Select()
		end
		return tabProxy
	end
	function windowProxy:Notify(payload)
		return rawWindow:Notify(makeNotificationPayload(payload))
	end
	function windowProxy:AddProfile(profileSettings)
		if type(rawWindow.AddProfile) == "function" then
			return rawWindow:AddProfile(profileSettings)
		end
	end
	function windowProxy:Unload()
		return rawWindow:Unload()
	end
	function windowProxy:SetState(state)
		return rawWindow:SetState(state)
	end
	function windowProxy:GetState()
		return rawWindow:GetState()
	end

	return windowProxy
end

function MacLib:Notify(settings, time)
	if self._activeWindow and type(self._activeWindow.Notify) == "function" then
		return self._activeWindow:Notify(makeNotificationPayload(settings, time))
	end
	warn("[TiRex] Notification before window is ready: " .. tostring(type(settings) == "table" and settings.Description or settings))
	return nil
end

function MacLib:AddProfile(settings)
	if self._activeWindow and type(self._activeWindow.AddProfile) == "function" then
		return self._activeWindow:AddProfile(settings)
	end
end

function MacLib:AddDraggableLabel(text)
	return createDraggableLabel(text)
end

function MacLib:Unload()
	if compatState.InputBeganConnection then
		pcall(function()
			compatState.InputBeganConnection:Disconnect()
		end)
		compatState.InputBeganConnection = nil
	end
	if compatState.InputEndedConnection then
		pcall(function()
			compatState.InputEndedConnection:Disconnect()
		end)
		compatState.InputEndedConnection = nil
	end
	compatState.InputBound = false
	compatState.KeyPickers = {}

	for _, statusLabel in ipairs(compatState.StatusLabels) do
		pcall(function()
			statusLabel:Destroy()
		end)
	end
	compatState.StatusLabels = {}

	for _, window in ipairs(compatState.Windows) do
		pcall(function()
			window:Unload()
		end)
	end
	compatState.Windows = {}
	self._activeWindow = nil
end

local function compatColorFromHex(value, fallback)
	if typeof(value) == "Color3" then
		return value
	end

	if type(value) == "string" then
		local hex = value:gsub("#", ""):gsub("0x", "")
		if #hex == 6 then
			local r = tonumber(hex:sub(1, 2), 16)
			local g = tonumber(hex:sub(3, 4), 16)
			local b = tonumber(hex:sub(5, 6), 16)
			if r and g and b then
				return Color3.fromRGB(r, g, b)
			end
		end
	end

	return fallback
end

local function compatColorToHex(color)
	if typeof(color) ~= "Color3" then
		return nil
	end
	return string.format("%02x%02x%02x",
		math.clamp(math.floor(color.R * 255 + 0.5), 0, 255),
		math.clamp(math.floor(color.G * 255 + 0.5), 0, 255),
		math.clamp(math.floor(color.B * 255 + 0.5), 0, 255)
	)
end

local function compatEnsureFolder(path)
	if isStudio or type(path) ~= "string" or path == "" then
		return false, "Config system unavailable."
	end
	if not (isfolder and makefolder) then
		return false, "Folder APIs unavailable."
	end

	local partial = ""
	for part in path:gmatch("[^/\\]+") do
		partial = partial == "" and part or (partial .. "/" .. part)
		if not isfolder(partial) then
			makefolder(partial)
		end
	end
	return true
end

local function compatGetLibrary(manager)
	return (manager and manager.Library) or MacLib
end

local function compatGetThemePayload(theme)
	if type(theme) ~= "table" then
		return nil
	end
	if type(theme[2]) == "table" then
		return theme[2]
	end
	return theme
end

local function compatNormalizeTheme(theme)
	local payload = compatGetThemePayload(theme) or {}
	return {
		Background = compatColorFromHex(payload.BackgroundColor or payload.Background or payload.WindowBackground, Color3.fromRGB(24, 24, 24)),
		Main = compatColorFromHex(payload.MainColor or payload.Main or payload.ElementBackground, Color3.fromRGB(36, 36, 36)),
		Accent = compatColorFromHex(payload.AccentColor or payload.Accent, Color3.fromRGB(255, 255, 255)),
		Outline = compatColorFromHex(payload.OutlineColor or payload.Outline or payload.BorderColor, Color3.fromRGB(82, 82, 82)),
		Font = compatColorFromHex(payload.FontColor or payload.TextColor or payload.Font, Color3.fromRGB(255, 255, 255)),
		MutedFont = compatColorFromHex(payload.MutedFontColor or payload.MutedTextColor, Color3.fromRGB(205, 205, 205))
	}
end

local function compatApplyThemeToRoot(root, theme)
	if typeof(root) ~= "Instance" then
		return
	end

	local normalized = compatNormalizeTheme(theme)
	local panelColor = normalized.Main
	local controlColor = normalized.Main:Lerp(normalized.Font, 0.045)
	local trackColor = normalized.Main:Lerp(normalized.Font, 0.09)
	local sliderFillColor = normalized.Accent:Lerp(normalized.Background, 0.28)
	local headColor = normalized.Font:Lerp(normalized.Accent, 0.18)
	local subtleStrokeColor = normalized.Outline:Lerp(normalized.Font, 0.12)
	if not compatState.SquareCornerRoots[root] and root.DescendantAdded then
		compatState.SquareCornerRoots[root] = root.DescendantAdded:Connect(function(obj)
			if obj:IsA("UICorner") then
				obj.CornerRadius = UDim.new(0, 0)
			end
		end)
	end
	local backgroundNames = {
		Base = true,
		Holder = true,
		Prompt = true,
		Notification = true,
		GlobalSettings = true,
		Dialog = true,
		ProfileModal = true
	}
	local mainNames = {
		Section = true,
		Dropdown = true,
		Search = true,
		InputBox = true,
		BinderBox = true,
		SliderValue = true,
		Button = true,
		Confirm = true,
		Cancel = true,
		ProfileButton = true,
		ProfileCard = true,
		CheckboxButton = true,
		DiscordButton = true,
		WebsiteButton = true,
		LogoutButton = true
	}

	for _, obj in ipairs(root:GetDescendants()) do
		if obj:IsA("UICorner") then
			obj.CornerRadius = UDim.new(0, 0)
		elseif obj:IsA("UIStroke") then
			if obj.Parent and (obj.Parent.Name == "BinderBox" or obj.Parent.Name == "CheckboxButton") then
				-- Keep keybind boxes in the same state-driven style as checkboxes.
			elseif obj.Parent and obj.Parent.Name == "Section" then
				obj.Color = subtleStrokeColor
				obj.Transparency = 0.58
			elseif obj.Parent and (obj.Parent.Name == "SliderValue" or obj.Parent.Name == "InputBox" or obj.Parent.Name == "Dropdown") then
				obj.Color = subtleStrokeColor
				obj.Transparency = math.max(obj.Transparency, 0.62)
			else
				obj.Color = subtleStrokeColor
			end
		elseif obj:IsA("Frame") and obj.Name == "Line" and obj.Parent and obj.Parent:IsA("CanvasGroup") then
			obj.BackgroundColor3 = normalized.Font
		elseif obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
			if obj.Name == "BinderBox" then
				obj.TextColor3 = normalized.Font
				obj.TextTransparency = 0
			elseif obj.Name == "Checkmark" then
				obj.TextColor3 = normalized.Background
			elseif obj.Name == "ProfileTier" then
				obj.TextColor3 = normalized.Background
			else
				obj.TextColor3 = normalized.Font
			end
			if obj:IsA("TextBox") then
				obj.PlaceholderColor3 = normalized.MutedFont
			end
			if obj.BackgroundTransparency < 0.99 then
				if obj.Name == "Value" and obj:FindFirstChild("Slide") then
					-- Keep the colorpicker value slider hue intact.
				elseif obj.Name == "ProfileTier" then
					obj.BackgroundColor3 = normalized.Font
				elseif obj.Name == "BinderBox" then
					-- Keybind boxes manage their own enabled/empty/binding colors.
				elseif obj.Name == "CheckboxButton" then
					-- Checkbox state manages its own fill.
				elseif obj.Name == "Toggle" and obj:IsA("ImageButton") then
					-- Toggle state manages its own fill.
				else
					obj.BackgroundColor3 = mainNames[obj.Name] and controlColor or normalized.Background
				end
			end
		elseif obj:IsA("ScrollingFrame") then
			obj.ScrollBarImageColor3 = normalized.Accent
			if obj.BackgroundTransparency < 0.99 then
				obj.BackgroundColor3 = panelColor
			end
		elseif obj:IsA("Frame") or obj:IsA("CanvasGroup") then
			if obj.BackgroundTransparency < 0.99 then
				if backgroundNames[obj.Name] then
					obj.BackgroundColor3 = normalized.Background
				elseif obj.Name == "SliderFill" then
					obj.BackgroundColor3 = sliderFillColor
				elseif mainNames[obj.Name] then
					obj.BackgroundColor3 = obj.Name == "Section" and panelColor or controlColor
					if obj.Name == "Section" then
						obj.BackgroundTransparency = 0.10
					end
				end
			end
		elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
			if obj.Name == "TabImage" or obj.Name == "GroupIcon" or obj.Name == "IconImage" or obj.Name == "LucideSprite" then
				obj.ImageColor3 = normalized.Font
			elseif obj.Name == "SliderBar" then
				obj.BackgroundColor3 = trackColor
				obj.BackgroundTransparency = 0.06
			elseif obj.Name == "SliderHead" or obj.Name == "TogglerHead" then
				obj.ImageTransparency = 1
				obj.BackgroundColor3 = headColor
				obj.BackgroundTransparency = obj.Name == "TogglerHead" and obj.BackgroundTransparency or 0
			elseif obj.Name == "Checkmark" then
				obj.ImageColor3 = normalized.Accent
			elseif obj.Name == "Wheel" and obj:FindFirstChild("WheelHueGradient") then
				-- Keep the generated colorpicker hue field from being themed to gray.
			elseif obj.BackgroundTransparency < 0.99 then
				obj.BackgroundColor3 = controlColor
			end
		end
	end
end

MacLib.ThemeManager = MacLib.ThemeManager or {}
MacLib.ThemeManager.BuiltInThemes = MacLib.ThemeManager.BuiltInThemes or {
	Default = {
		"Default",
		{
			BackgroundColor = "0f1012",
			MainColor = "1a1b1f",
			AccentColor = "e0e0e0",
			OutlineColor = "3a3c40",
			FontColor = "f5f5f6",
			MutedFontColor = "a9abb0"
		}
	},
	["Minimalist White/Silver"] = {
		"Minimalist White/Silver",
		{
			BackgroundColor = "0f1012",
			MainColor = "1a1b1f",
			AccentColor = "e0e0e0",
			OutlineColor = "3a3c40",
			FontColor = "f5f5f6",
			MutedFontColor = "a9abb0"
		}
	},
	TiRex = {
		"TiRex",
		{
			BackgroundColor = "0f1012",
			MainColor = "1a1b1f",
			AccentColor = "e0e0e0",
			OutlineColor = "3a3c40",
			FontColor = "f5f5f6",
			MutedFontColor = "a9abb0"
		}
	},
	Professional = {
		"Professional",
		{
			BackgroundColor = "0f1012",
			MainColor = "1a1b1f",
			AccentColor = "e0e0e0",
			OutlineColor = "3a3c40",
			FontColor = "f5f5f6",
			MutedFontColor = "a9abb0"
		}
	}
}
MacLib.ThemeManager.Library = MacLib.ThemeManager.Library or MacLib
MacLib.ThemeManager.Folder = MacLib.ThemeManager.Folder or "TiRex"
MacLib.ThemeManager.CurrentTheme = MacLib.ThemeManager.CurrentTheme or "Default"

function MacLib.ThemeManager:SetLibrary(lib)
	self.Library = lib or MacLib
end

function MacLib.ThemeManager:SetFolder(folder)
	self.Folder = folder or self.Folder or "TiRex"
end

function MacLib.ThemeManager:GetTheme(theme)
	if type(theme) == "table" then
		return theme
	end
	local name = tostring(theme or self.CurrentTheme or "Default")
	return self.BuiltInThemes[name] or self.BuiltInThemes.Default
end

function MacLib.ThemeManager:GetThemeNames()
	local names = {}
	for name in pairs(self.BuiltInThemes or {}) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function MacLib.ThemeManager:ApplyTheme(theme)
	local library = compatGetLibrary(self)
	local selectedTheme = self:GetTheme(theme)
	self.CurrentTheme = type(theme) == "string" and theme or self.CurrentTheme or "Default"

	for _, rawWindow in ipairs(compatState.Windows) do
		if rawWindow and rawWindow.Gui then
			compatApplyThemeToRoot(rawWindow.Gui, selectedTheme)
		end
	end

	for _, statusLabel in ipairs(compatState.StatusLabels) do
		if statusLabel and statusLabel.GetFrame then
			compatApplyThemeToRoot(statusLabel:GetFrame(), selectedTheme)
		end
	end

	if library._activeWindow and library._activeWindow.Gui then
		compatApplyThemeToRoot(library._activeWindow.Gui, selectedTheme)
	end

	return true
end

function MacLib.ThemeManager:SetTheme(theme)
	self.CurrentTheme = type(theme) == "string" and theme or self.CurrentTheme
	return self:ApplyTheme(theme)
end

function MacLib.ThemeManager:LoadDefault()
	local themeName = self.CurrentTheme or "Default"
	if not isStudio and isfile and readfile and self.Folder then
		local path = self.Folder .. "/theme.txt"
		if isfile(path) then
			local savedTheme = tostring(readfile(path) or ""):gsub("^%s+", ""):gsub("%s+$", "")
			if self.BuiltInThemes[savedTheme] then
				themeName = savedTheme
			end
		end
	end
	return self:SetTheme(themeName)
end

function MacLib.ThemeManager:SaveDefault(theme)
	local themeName = tostring(theme or self.CurrentTheme or "Default")
	self.CurrentTheme = themeName
	if isStudio or not (writefile and self.Folder) then
		return false, "Theme save unavailable."
	end
	local okFolder, folderErr = compatEnsureFolder(self.Folder)
	if not okFolder then
		return false, folderErr
	end
	writefile(self.Folder .. "/theme.txt", themeName)
	return true
end

function MacLib.ThemeManager:ApplyToTab(tab)
	self:ApplyTheme(self.CurrentTheme or "Default")
	if not (tab and type(tab.AddLeftGroupbox) == "function") then
		return nil
	end

	local names = self:GetThemeNames()
	local defaultIndex = table.find(names, self.CurrentTheme or "Default") or table.find(names, "Default") or 1
	local group = tab:AddLeftGroupbox("Theme", "palette")
	local dropdown = group:AddDropdown("ThemeManager_Theme", {
		Text = "Theme",
		Values = names,
		Default = defaultIndex,
		Multi = false,
		AllowNull = false,
		Callback = function(themeName)
			self:SetTheme(themeName)
		end
	})
	if MacLib.Options.ThemeManager_Theme then
		MacLib.Options.ThemeManager_Theme.IgnoreConfig = true
	end
	group:AddButton("Apply Theme", function()
		self:ApplyTheme(dropdown.Value or self.CurrentTheme or "Default")
	end)
	group:AddButton("Save Theme Default", function()
		local ok, err = self:SaveDefault(dropdown.Value or self.CurrentTheme or "Default")
		if not ok and MacLib.Notify then
			MacLib:Notify({
				Title = "TiRex",
				Description = tostring(err),
				Time = 2
			})
		end
	end)
	return group
end

MacLib.SaveManager = MacLib.SaveManager or {}
MacLib.SaveManager.Library = MacLib.SaveManager.Library or MacLib
MacLib.SaveManager.Folder = MacLib.SaveManager.Folder or "TiRex/Games"
MacLib.SaveManager.IgnoreIndexes = MacLib.SaveManager.IgnoreIndexes or {}
MacLib.SaveManager.IgnoreThemes = MacLib.SaveManager.IgnoreThemes or false

function MacLib.SaveManager:SetLibrary(lib)
	self.Library = lib or MacLib
end

function MacLib.SaveManager:IgnoreThemeSettings()
	self.IgnoreThemes = true
	self:SetIgnoreIndexes({ "ThemeManager_Theme" })
end

function MacLib.SaveManager:SetIgnoreIndexes(indexes)
	self.IgnoreIndexes = indexes or {}
	if type(indexes) == "table" then
		for _, flag in ipairs(indexes) do
			if MacLib.Options[flag] then
				MacLib.Options[flag].IgnoreConfig = true
			end
		end
	end
end

function MacLib.SaveManager:SetFolder(folder)
	self.Folder = folder or self.Folder or "TiRex/Games"
	local library = compatGetLibrary(self)
	library.Folder = self.Folder
	if type(library.SetFolder) == "function" then
		pcall(function()
			library:SetFolder(self.Folder)
		end)
	end
end

function MacLib.SaveManager:GetFolder()
	return self.Folder or (compatGetLibrary(self).Folder) or "TiRex/Games"
end

function MacLib.SaveManager:Save(name)
	local library = compatGetLibrary(self)
	self:SetFolder(self:GetFolder())
	if type(library.SaveConfig) == "function" then
		return library:SaveConfig(name)
	end
	return false, "SaveConfig unavailable."
end

function MacLib.SaveManager:Load(name)
	local library = compatGetLibrary(self)
	self:SetFolder(self:GetFolder())
	if type(library.LoadConfig) == "function" then
		return library:LoadConfig(name)
	end
	return false, "LoadConfig unavailable."
end

function MacLib.SaveManager:RefreshConfigList()
	local library = compatGetLibrary(self)
	self:SetFolder(self:GetFolder())
	if type(library.RefreshConfigList) == "function" then
		return library:RefreshConfigList()
	end
	return {}
end

function MacLib.SaveManager:SetAutoload(name)
	if type(name) ~= "string" or name == "" then
		return false, "Please select a config file."
	end
	if isStudio or not writefile then
		return false, "Autoload save unavailable."
	end
	local folder = self:GetFolder()
	local okFolder, folderErr = compatEnsureFolder(folder .. "/settings")
	if not okFolder then
		return false, folderErr
	end
	writefile(folder .. "/settings/autoload.txt", name)
	return true
end

function MacLib.SaveManager:LoadAutoloadConfig()
	local library = compatGetLibrary(self)
	self:SetFolder(self:GetFolder())
	if type(library.LoadAutoLoadConfig) == "function" then
		return library:LoadAutoLoadConfig()
	end
	return false, "LoadAutoLoadConfig unavailable."
end

function MacLib.SaveManager:BuildConfigSection(tab)
	self:SetFolder(self:GetFolder())
	if tab and type(tab.InsertConfigSection) == "function" then
		return tab:InsertConfigSection("Left")
	end
	return nil
end

function MacLib:Demo()
	local Window = MacLib:Window({
		Title = "TiRex Demo",
		Subtitle = "This is a subtitle.",
		Size = UDim2.fromOffset(868, 650),
		DragStyle = 1,
		DisabledWindowControls = {},
		ShowUserInfo = true,
		Keybind = Enum.KeyCode.RightControl,
		AcrylicBlur = true,
	})

	local globalSettings = {
		UIBlurToggle = Window:GlobalSetting({
			Name = "UI Blur",
			Default = Window:GetAcrylicBlurState(),
			Callback = function(bool)
				Window:SetAcrylicBlurState(bool)
				Window:Notify({
					Title = Window.Settings.Title,
					Description = (bool and "Enabled" or "Disabled") .. " UI Blur",
					Lifetime = 5
				})
			end,
		}),
		NotificationToggler = Window:GlobalSetting({
			Name = "Notifications",
			Default = Window:GetNotificationsState(),
			Callback = function(bool)
				Window:SetNotificationsState(bool)
				Window:Notify({
					Title = Window.Settings.Title,
					Description = (bool and "Enabled" or "Disabled") .. " Notifications",
					Lifetime = 5
				})
			end,
		}),
		ShowUserInfo = Window:GlobalSetting({
			Name = "Show User Info",
			Default = Window:GetUserInfoState(),
			Callback = function(bool)
				Window:SetUserInfoState(bool)
				Window:Notify({
					Title = Window.Settings.Title,
					Description = (bool and "Showing" or "Redacted") .. " User Info",
					Lifetime = 5
				})
			end,
		})
	}

	local tabGroups = {
		TabGroup1 = Window:TabGroup()
	}

	local tabs = {
		Main = tabGroups.TabGroup1:Tab({ Name = "Demo", Image = "rbxassetid://18821914323" }),
		Settings = tabGroups.TabGroup1:Tab({ Name = "Settings", Image = "rbxassetid://10734950309" })
	}

	local sections = {
		MainSection1 = tabs.Main:Section({ Side = "Left" }),
	}

	sections.MainSection1:Header({
		Name = "Header #1"
	})

	sections.MainSection1:Button({
		Name = "Button",
		Callback = function()
			Window:Dialog({
				Title = Window.Settings.Title,
				Description = "Lorem ipsum odor amet, consectetuer adipiscing elit. Eros vestibulum aliquet mattis, ex platea nunc.",
				Buttons = {
					{
						Name = "Confirm",
						Callback = function()
							print("Confirmed!")
						end,
					},
					{
						Name = "Cancel"
					}
				}
			})
		end,
	})

	sections.MainSection1:Input({
		Name = "Input",
		Placeholder = "Input",
		AcceptedCharacters = "All",
		Callback = function(input)
			Window:Notify({
				Title = Window.Settings.Title,
				Description = "Successfully set input to " .. input
			})
		end,
		onChanged = function(input)
			print("Input is now " .. input)
		end,
	}, "Input")

	sections.MainSection1:Slider({
		Name = "Slider",
		Default = 50,
		Minimum = 0,
		Maximum = 100,
		DisplayMethod = "Percent",
		Precision = 0,
		Callback = function(Value)
			print("Changed to ".. Value)
		end
	}, "Slider")

	sections.MainSection1:Toggle({
		Name = "Toggle",
		Default = false,
		Callback = function(value)
			Window:Notify({
				Title = Window.Settings.Title,
				Description = (value and "Enabled " or "Disabled ") .. "Toggle"
			})
		end,
	}, "Toggle")

	sections.MainSection1:Keybind({
		Name = "Keybind",
		Blacklist = false,
		Callback = function(binded)
			Window:Notify({
				Title = "Demo Window",
				Description = "Pressed keybind - "..tostring(binded.Name),
				Lifetime = 3
			})
		end,
		onBinded = function(bind)
			Window:Notify({
				Title = "Demo Window",
				Description = "Successfully Binded Keybind to - "..tostring(bind.Name),
				Lifetime = 3
			})
		end,
	}, "Keybind")

	sections.MainSection1:Colorpicker({
		Name = "Colorpicker",
		Default = Color3.fromRGB(0, 255, 255),
		Callback = function(color)
			print("Color: ", color)
		end,
	}, "Colorpicker")

	local alphaColorPicker = sections.MainSection1:Colorpicker({
		Name = "Transparency Colorpicker",
		Default = Color3.fromRGB(255,0,0),
		Alpha = 0,
		Callback = function(color, alpha)
			print("Color: ", color, " Alpha: ", alpha)
		end,
	}, "TransparencyColorpicker")

	local rainbowActive
	local rainbowConnection
	local hue = 0

	sections.MainSection1:Toggle({
		Name = "Rainbow",
		Default = false,
		Callback = function(value)
			rainbowActive = value

			if rainbowActive then
				rainbowConnection = game:GetService("RunService").RenderStepped:Connect(function(deltaTime)
					hue = (hue + deltaTime * 0.1) % 1
					alphaColorPicker:SetColor(Color3.fromHSV(hue, 1, 1))
				end)
			elseif rainbowConnection then
				rainbowConnection:Disconnect()
				rainbowConnection = nil
			end
		end,
	}, "RainbowToggle")

	local optionTable = {
		"Apple",
		"Banana",
		"Orange",
		"Grapes",
		"Pineapple",
		"Mango",
		"Strawberry",
		"Blueberry",
		"Watermelon",
		"Peach"
	}

	local Dropdown = sections.MainSection1:Dropdown({
		Name = "Dropdown",
		Multi = false,
		Required = true,
		Options = optionTable,
		Default = 1,
		Callback = function(Value)
			print("Dropdown changed: ".. Value)
		end,
	}, "Dropdown")

	local MultiDropdown = sections.MainSection1:Dropdown({
		Name = "Multi Dropdown",
		Search = true,
		Multi = true,
		Required = false,
		Options = optionTable,
		Default = {"Apple", "Orange"},
		Callback = function(Value)
			local Values = {}
			for Value, State in next, Value do
				table.insert(Values, Value)
			end
			print("Mutlidropdown changed:", table.concat(Values, ", "))
		end,
	}, "MultiDropdown")

	sections.MainSection1:Button({
		Name = "Update Selection",
		Callback = function()
			Dropdown:UpdateSelection("Grapes")
			MultiDropdown:UpdateSelection({"Banana", "Pineapple"})
		end,
	})

	sections.MainSection1:Divider()

	sections.MainSection1:Header({
		Text = "Header #2"
	})

	sections.MainSection1:Paragraph({
		Header = "Paragraph",
		Body = "Paragraph body. Lorem ipsum odor amet, consectetuer adipiscing elit. Morbi tempus netus aliquet per velit est gravida."
	})

	sections.MainSection1:Label({
		Text = "Label. Lorem ipsum odor amet, consectetuer adipiscing elit."
	})

	sections.MainSection1:SubLabel({
		Text = "Sub-Label. Lorem ipsum odor amet, consectetuer adipiscing elit."
	})

	MacLib:SetFolder("TiRex")
	tabs.Settings:InsertConfigSection("Left")

	Window.onUnloaded(function()
		print("Unloaded!")
	end)

	tabs.Main:Select()
	MacLib:LoadAutoLoadConfig()
end

return MacLib
