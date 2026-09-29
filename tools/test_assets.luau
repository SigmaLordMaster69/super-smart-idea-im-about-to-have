--[[
	Asset pack integration test: builds fake Toolbox-style models (with
	scripts inside, odd sizes and orientations), loads them through
	AssetLibrary, then checks chunks and the car use them.
	  lune run tools/test_assets
]]

local process = require("@lune/process")
local env = require("./env")
local roblox = env.roblox
local Instance, Vector3, CFrame, Color3 = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3

local Config = env.require("src/shared/Config")
local World = env.require("src/shared/World")
local AssetLibrary = env.require("src/client/AssetLibrary")
local ChunkManager = env.require("src/client/ChunkManager")
local Car = env.require("src/client/Car")

local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

local function part(parent, name, size, cf, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	for k, v in props or {} do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function folderPath(root, path)
	local node = root
	for name in string.gmatch(path, "[^/]+") do
		local child = node:FindFirstChild(name)
		if not child then
			child = Instance.new("Folder")
			child.Name = name
			child.Parent = node
		end
		node = child
	end
	return node
end

-- fake asset packs, deliberately placed far from the origin and oddly sized
local root = Instance.new("Folder")
root.Name = "InfiniteRoadAssets"

local function fakeTree(name, height)
	local m = Instance.new("Model")
	m.Name = name
	part(m, "Trunk", Vector3.new(1, height * 0.4, 1), CFrame.new(500, 200 + height * 0.2, -300))
	part(m, "Leaves", Vector3.new(height * 0.5, height * 0.6, height * 0.5), CFrame.new(500, 200 + height * 0.7, -300))
	part(m, "Hitbox", Vector3.new(80, 80, 80), CFrame.new(500, 200, -300), { Transparency = 1 })
	local virus = Instance.new("Script")
	virus.Name = "Spread"
	virus.Parent = m
	local sound = Instance.new("Sound")
	sound.Parent = m.Leaves
	return m
end
fakeTree("PackPineA", 60).Parent = folderPath(root, "Trees/Pine")
fakeTree("PackPineB", 12).Parent = folderPath(root, "Trees/Pine")
fakeTree("PackOak", 30).Parent = folderPath(root, "Trees/Oak")
local bushes = folderPath(root, "Plants/Bush")
fakeTree("PackBush", 3).Parent = bushes

local rock = Instance.new("MeshPart")
rock.Name = "PackRock"
rock.Size = Vector3.new(20, 12, 16)
rock.CFrame = CFrame.new(-40, 3, 90)
rock.Parent = folderPath(root, "Rocks")

-- a speed limit sign with its own text label, facing +Z (needs YawOffset 180)
local sign = Instance.new("Model")
sign.Name = "PackSpeedSign"
part(sign, "Pole", Vector3.new(0.4, 8, 0.4), CFrame.new(10, 4, 10))
local board = part(sign, "Board", Vector3.new(3, 3.5, 0.2), CFrame.new(10, 7, 10))
local gui = Instance.new("SurfaceGui")
local lbl = Instance.new("TextLabel")
lbl.Name = "Text"
lbl.Text = "55"
lbl.Parent = gui
gui.Parent = board
sign:SetAttribute("YawOffset", 180)
sign.Parent = folderPath(root, "Signs/SpeedLimit")

-- guard rail segment lying along X, 12 studs long
local rail = Instance.new("Model")
rail.Name = "PackRail"
part(rail, "Beam", Vector3.new(12, 1, 0.4), CFrame.new(0, 2.2, 0))
part(rail, "Post", Vector3.new(0.4, 2.8, 0.4), CFrame.new(0, 1.4, 0))
rail.Parent = folderPath(root, "Road/GuardRail")

-- a 20-stud car pointing -Z with four named wheels and a steering wheel
local carModel = Instance.new("Model")
carModel.Name = "PackCar"
part(carModel, "BodyShell", Vector3.new(8, 4, 20), CFrame.new(0, 3.5, 0))
for _, pos in { Vector3.new(-3.6, 1.6, -6.5), Vector3.new(3.6, 1.6, -6.5), Vector3.new(-3.6, 1.6, 6.5), Vector3.new(3.6, 1.6, 6.5) } do
	local wheel = Instance.new("Model")
	wheel.Name = "Wheel"
	part(wheel, "Tyre", Vector3.new(1.4, 3.2, 3.2), CFrame.new(pos))
	part(wheel, "Rim", Vector3.new(1.5, 2, 2), CFrame.new(pos))
	wheel.Parent = carModel
end
part(carModel, "SteeringWheel", Vector3.new(1.5, 1.5, 0.2), CFrame.new(-1.5, 4.5, -2))
local seat = Instance.new("VehicleSeat")
seat.Parent = carModel
local s2 = Instance.new("LocalScript")
s2.Parent = carModel
carModel.Parent = folderPath(root, "Car/Body")

-- a 10-stud motorcycle pointing -Z with named wheels and a script inside
local bikeModel = Instance.new("Model")
bikeModel.Name = "PackBike"
part(bikeModel, "Frame", Vector3.new(1.4, 2.4, 6), CFrame.new(40, 3, 40))
part(bikeModel, "FrontWheel", Vector3.new(0.8, 3, 3), CFrame.new(40, 1.5, 36.5))
part(bikeModel, "BackTire", Vector3.new(0.8, 3, 3), CFrame.new(40, 1.5, 43.5))
local s3 = Instance.new("Script")
s3.Parent = bikeModel
bikeModel.Parent = folderPath(root, "Motorcycle/Body")

---------------------------------------------------------------------------
local assets = AssetLibrary.new(root)
print("summary: " .. table.concat(assets.summary, ", "))
check(assets:has("pine") and assets:has("oak") and assets:has("bush") and assets:has("rock"), "tree/plant/rock kinds loaded")
check(assets:has("SpeedLimit"), "sign kind loaded")
check(assets.rail ~= nil and math.abs(assets.rail.length - 12) < 0.01, "rail segment length 12 along Z")
check(assets.carSource ~= nil, "car body found")

-- templates are clean, grounded and scaled
for _, kind in { "pine", "oak", "bush" } do
	for sizeClass = 1, 3 do
		local m = assets:pick(kind, sizeClass, 0)
		for _, d in m:GetDescendants() do
			check(not d:IsA("LuaSourceContainer") and not d:IsA("Sound"), kind .. " still has " .. d.ClassName)
			if d:IsA("BasePart") then
				check(d.Anchored and not d.CanQuery, kind .. " part not anchored/queryable")
			end
		end
		local lo, hi = AssetLibrary.bounds(m)
		local target = AssetLibrary.Kinds[kind].sizes[sizeClass]
		check(math.abs(lo.Y) < 0.01, string.format("%s base at %.2f, expected 0", kind, lo.Y))
		check(math.abs((hi.Y - lo.Y) - target) < 0.05, string.format("%s size %d height %.2f, expected %.2f", kind, sizeClass, hi.Y - lo.Y, target))
		check(math.abs((lo.X + hi.X) / 2) < 0.01 and math.abs((lo.Z + hi.Z) / 2) < 0.01, kind .. " not centred")
	end
end

-- sign: turned around and text replaced
local speed = assets:pick("SpeedLimit", 1, 0)
AssetLibrary.setText(speed, "90")
local label
for _, d in speed:GetDescendants() do
	if d:IsA("TextLabel") then
		label = d
	end
end
check(label and label.Text == "90", "sign text replaced")

---------------------------------------------------------------------------
-- chunks use the assets
local world = World.new(Config, 777)
local manager = ChunkManager.new(world, Config, env.terrain, assets)
local road = world.road
road:ensureFlags(12000)
local kRail
for k = 200, 12000 do
	if road:hasRail(k, 1) or road:hasRail(k, -1) then
		kRail = k
		break
	end
end
local focus = road:frameAtIndex(kRail or 600)
manager:setOrigin(focus)
manager:setFocus(focus)
for _ = 1, 20000 do
	manager:update(0.05)
	if manager:progress(300) >= 1 then
		break
	end
end
local names = {}
for _, d in manager.container:GetDescendants() do
	if d:IsA("Model") then
		names[d.Name] = (names[d.Name] or 0) + 1
	elseif d:IsA("BasePart") and d.Name == "GuardRail" then
		names.RailCollider = (names.RailCollider or 0) + 1
		check(d.Transparency == 1 and d.CanCollide, "rail collider must be invisible and solid")
	end
end
local list = {}
for n, c in names do
	table.insert(list, n .. "=" .. c)
end
table.sort(list)
print("models: " .. table.concat(list, " "))
check((names.PackPineA or 0) + (names.PackPineB or 0) + (names.PackOak or 0) > 0, "asset trees placed")
check((names.Pine or 0) == 0 and (names.Oak or 0) == 0, "procedural pines/oaks replaced")
check((names.PackRail or 0) > 0, "asset rail segments placed")

---------------------------------------------------------------------------
-- the car takes the body and its wheels
local car = Car.new(Config, Color3.new(1, 0, 0), assets)
local body = car.model:FindFirstChild("Body")
check(body ~= nil, "car body attached")
check(car.customBody == true, "car flagged as custom body")
for _, d in car.model:GetDescendants() do
	check(not d:IsA("LuaSourceContainer") and not d:IsA("VehicleSeat"), "car kept a " .. d.ClassName)
end
-- body scaled 20 -> 15 long, so wheels sit at +-3.6*0.75 = 2.7, +-6.5*0.75 = 4.875
local w1 = car.wheels[1]
print(string.format("front-left wheel at x=%.2f z=%.2f r=%.2f", w1.x, w1.z, w1.radius))
check(math.abs(w1.x + 2.7) < 0.05 and math.abs(w1.z + 4.875) < 0.05, "wheel position taken from the model")
check(math.abs(w1.radius - 1.2) < 0.05, "wheel radius taken from the model")
local steering = body:FindFirstChild("SteeringWheel")
check(steering ~= nil, "steering wheel kept as body")
local attachedToWheel = false
for _, d in w1.part:GetChildren() do
	attachedToWheel = attachedToWheel or d:IsA("WeldConstraint")
end
local tyreWelded = false
for _, d in body:GetDescendants() do
	if d:IsA("WeldConstraint") and d.Part0 == w1.part then
		tyreWelded = true
	end
end
check(tyreWelded, "model tyres welded to the suspension rig")

---------------------------------------------------------------------------
-- the motorcycle takes its body; the rider stays
local bike = Car.new(Config, Color3.new(0, 1, 0), assets, "Motorcycle")
local bikeBody = bike.bikeParts:FindFirstChild("BikeBody")
check(bikeBody ~= nil, "bike body attached")
for _, d in bike.model:GetDescendants() do
	check(not d:IsA("LuaSourceContainer"), "bike kept a " .. d.ClassName)
end
-- scaled 10 -> 8 long: wheels at z = +-3.5 * 0.8 = 2.8
print(string.format("bike wheels at z=%.2f / %.2f", bike.frontWheel.z, bike.rearWheel.z))
check(math.abs(bike.frontWheel.z + 2.8) < 0.1 and math.abs(bike.rearWheel.z - 2.8) < 0.1, "bike wheel positions taken from the model")
local frontWelded = false
for _, d in bikeBody:GetDescendants() do
	if d:IsA("WeldConstraint") and d.Part0 == bike.frontWheel.part and d.Part1.Name == "FrontWheel" then
		frontWelded = true
	end
end
check(frontWelded, "bike front wheel welded to the steering rig")
local riderVisible, oldBikeHidden = false, true
for _, d in bike.bikeParts:GetDescendants() do
	if d:IsA("BasePart") and not d:IsDescendantOf(bikeBody) then
		if d:GetAttribute("IR_Rider") then
			riderVisible = riderVisible or d.Transparency < 1
		elseif d.Name == "Tank" or d.Name == "Seat" then
			oldBikeHidden = oldBikeHidden and d.Transparency == 1
		end
	end
end
check(riderVisible, "rider still visible on the premade bike")
check(oldBikeHidden, "procedural bike hidden")
bike.speed = 50
bike.chassis.AssemblyAngularVelocity = Vector3.zero
bike:render(1 / 60)

if failures == 0 then
	print("ALL ASSET CHECKS PASSED")
else
	print(failures .. " FAILURES")
	process.exit(1)
end
