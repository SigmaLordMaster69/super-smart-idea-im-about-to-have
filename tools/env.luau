--[[
	Offline test environment (Lune).

	Loads the project's ModuleScripts from disk with a fake `script` object,
	so `require(script.Parent.X)` works the same way it does under Rojo.
	Roblox datatypes come from @lune/roblox. `Random` and the few engine
	services the generator touches are polyfilled here.

	Usage:  local env = require("./env")
	        local Config = env.require("src/shared/Config")
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Env = {}

---------------------------------------------------------------------------
-- Random polyfill (xorshift-style; sequences differ from Roblox's PCG, but
-- they are deterministic, which is all the tests need)
---------------------------------------------------------------------------
local RandomMT = {}
RandomMT.__index = RandomMT

local function newRandom(seed)
	seed = math.floor(seed or os.clock() * 1e6) % 2147483647
	if seed == 0 then
		seed = 1234567
	end
	return setmetatable({ state = seed }, RandomMT)
end

function RandomMT:_next()
	-- Park-Miller minimal standard, exact in doubles
	self.state = (self.state * 48271) % 2147483647
	return self.state / 2147483647
end

function RandomMT:NextNumber(a, b)
	local r = self:_next()
	if a == nil then
		return r
	end
	return a + (b - a) * r
end

function RandomMT:NextInteger(a, b)
	return a + math.floor(self:_next() * (b - a + 1))
end

function RandomMT:Clone()
	return setmetatable({ state = self.state }, RandomMT)
end

Env.Random = { new = newRandom }

---------------------------------------------------------------------------
-- Terrain mock: records voxel writes so tests can inspect them.
---------------------------------------------------------------------------
local function newTerrainMock()
	local terrain = roblox.Instance.new("Folder")
	local mock = {
		writes = {},
		cleared = 0,
		instance = terrain,
		Name = "Terrain",
	}
	function mock:WriteVoxels(region, resolution, materials, occupancies)
		assert(resolution == 4, "resolution must be 4")
		local size = region.Size
		local nx, ny, nz = size.X / 4, size.Y / 4, size.Z / 4
		assert(nx == math.floor(nx) and ny == math.floor(ny) and nz == math.floor(nz), "region not aligned")
		assert(#materials == nx, "materials x size " .. #materials .. " ~= " .. nx)
		assert(#materials[1] == ny, "materials y size " .. #materials[1] .. " ~= " .. ny)
		assert(#materials[1][1] == nz, "materials z size")
		assert(#occupancies == nx and #occupancies[1] == ny and #occupancies[1][1] == nz, "occupancy size")
		for ix = 1, nx do
			for iy = 1, ny do
				local mrow, orow = materials[ix][iy], occupancies[ix][iy]
				for iz = 1, nz do
					local m, o = mrow[iz], orow[iz]
					assert(typeof(m) == "EnumItem", "bad material at " .. ix .. "," .. iy .. "," .. iz)
					assert(type(o) == "number" and o >= 0 and o <= 1, "bad occupancy " .. tostring(o))
				end
			end
		end
		table.insert(self.writes, { region = region, materials = materials, occupancies = occupancies })
	end
	function mock:FillRegion(region, resolution, material)
		assert(resolution == 4 and material == roblox.Enum.Material.Air, "FillRegion args")
		self.cleared += 1
	end
	function mock:Clear()
		self.writes = {}
	end
	function mock:SetMaterialColor() end
	mock.copies, mock.pastes = 0, 0
	function mock:CopyRegion(region)
		assert(typeof(region) == "Region3int16", "CopyRegion expects Region3int16")
		self.copies += 1
		return { region = region }
	end
	function mock:PasteRegion(tr, corner, pasteEmpty)
		assert(typeof(corner) == "Vector3int16", "PasteRegion expects Vector3int16 corner")
		self.pastes += 1
	end
	return mock
end

---------------------------------------------------------------------------
-- Module loader
---------------------------------------------------------------------------
local cache = {}
local baseEnv

-- fs calls yield, and yielding inside the __index metamethods below is not
-- allowed, so index the project tree once up front.
local knownFiles, knownDirs = {}, {}
local function scan(dir)
	knownDirs[dir] = true
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			scan(path)
		else
			knownFiles[path] = true
		end
	end
end
scan("src")
scan("tools")

local function fileExists(path)
	return knownFiles[path] == true
end

local function resolveFile(dir, name)
	for _, ext in { ".luau", ".lua" } do
		if fileExists(dir .. "/" .. name .. ext) then
			return dir .. "/" .. name .. ext
		end
	end
	return nil
end

local makeScriptRef

-- A folder-like proxy: indexing a name returns a module reference.
local function folderProxy(dir)
	return setmetatable({ __dir = dir }, {
		__index = function(_, name)
			if name == "Parent" then
				local parent = dir:match("^(.*)/[^/]+$") or "."
				return folderProxy(parent)
			end
			local file = resolveFile(dir, name)
			if file then
				return makeScriptRef(file)
			end
			if knownDirs[dir .. "/" .. name] then
				return folderProxy(dir .. "/" .. name)
			end
			error("no module '" .. name .. "' in " .. dir, 2)
		end,
		__tostring = function()
			return "Folder(" .. dir .. ")"
		end,
	})
end

function makeScriptRef(file)
	local dir = file:match("^(.*)/[^/]+$")
	local isInit = file:match("/init%.[%w%.]*luau?$") ~= nil
	return setmetatable({ __file = file }, {
		__index = function(_, key)
			if key == "Parent" then
				if isInit then
					return folderProxy(dir).Parent
				end
				return folderProxy(dir)
			elseif key == "Name" then
				return (file:match("([^/]+)%.luau?$"))
			end
			if isInit then
				return folderProxy(dir)[key]
			end
			error("script has no child '" .. tostring(key) .. "'", 2)
		end,
	})
end

local function loadModule(file)
	if cache[file] ~= nil then
		return cache[file]
	end
	local source = fs.readFile(file)
	-- Lune copies the environment table, so metatable fallbacks are ignored
	local env = table.clone(baseEnv)
	env.script = makeScriptRef(file)
	local chunk = luau.load(source, { debugName = file, environment = env })
	local result = chunk()
	cache[file] = result
	return result
end

local function envRequire(ref)
	if type(ref) == "table" and rawget(ref, "__file") then
		return loadModule(rawget(ref, "__file"))
	end
	if type(ref) == "string" then
		return require(ref)
	end
	error("unsupported require target " .. tostring(ref), 2)
end

---------------------------------------------------------------------------
-- Engine methods Lune does not implement
---------------------------------------------------------------------------
local function currentPivot(model)
	if model.PrimaryPart then
		return model.PrimaryPart.CFrame
	end
	return model.WorldPivot
end
roblox.implementMethod("Model", "GetPivot", currentPivot)
roblox.implementMethod("Model", "PivotTo", function(model, cf)
	local delta = cf * currentPivot(model):Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
	model.WorldPivot = cf
end)
roblox.implementMethod("Workspace", "BulkMoveTo", function(_, parts, cframes)
	assert(#parts == #cframes, "BulkMoveTo list sizes differ")
	for i, p in parts do
		p.CFrame = cframes[i]
	end
end)

local dataModel = roblox.Instance.new("DataModel")
local replicatedStorageProxy = {
	WaitForChild = function(_, name)
		assert(name == "InfiniteRoad", "unexpected WaitForChild " .. tostring(name))
		return folderProxy("src/shared")
	end,
}
local gameMock = {
	GetService = function(_, name)
		if name == "ReplicatedStorage" then
			return replicatedStorageProxy
		end
		return dataModel:GetService(name)
	end,
}

local terrainMock = newTerrainMock()
local workspaceMock = setmetatable({ Terrain = terrainMock, CurrentCamera = nil }, {
	__index = function(_, k)
		error("workspace mock has no member " .. tostring(k), 2)
	end,
})

baseEnv = {
	-- Luau standard library
	math = math,
	string = string,
	table = table,
	bit32 = bit32,
	utf8 = utf8,
	os = os,
	coroutine = coroutine,
	buffer = buffer,
	print = print,
	warn = function(...)
		print("[warn]", ...)
	end,
	error = error,
	assert = assert,
	pcall = pcall,
	xpcall = xpcall,
	select = select,
	type = type,
	typeof = typeof,
	tostring = tostring,
	tonumber = tonumber,
	pairs = pairs,
	ipairs = ipairs,
	next = next,
	rawget = rawget,
	rawset = rawset,
	rawequal = rawequal,
	setmetatable = setmetatable,
	getmetatable = getmetatable,
	unpack = table.unpack,
	-- Roblox
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	Vector3int16 = roblox.Vector3int16,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequence = roblox.NumberSequence,
	NumberRange = roblox.NumberRange,
	Region3 = roblox.Region3,
	Region3int16 = roblox.Region3int16,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	PhysicalProperties = roblox.PhysicalProperties,
	Font = roblox.Font,
	BrickColor = roblox.BrickColor,
	Enum = roblox.Enum,
	Instance = roblox.Instance,
	Random = Env.Random,
	task = task,
	workspace = workspaceMock,
	game = gameMock,
	RaycastParams = roblox.RaycastParams,
	require = envRequire,
}

Env.baseEnv = baseEnv
Env.game = gameMock
Env.workspace = dataModel:GetService("Workspace")
Env.terrain = terrainMock
Env.roblox = roblox

function Env.require(path)
	local file = resolveFile(path:match("^(.*)/[^/]+$"), path:match("([^/]+)$"))
	assert(file, "cannot find module " .. path)
	return loadModule(file)
end

return Env
