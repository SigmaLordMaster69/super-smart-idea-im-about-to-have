--[[
	Prop quality checks over the catalogue in tools/render_props.luau:
	  - z-fighting: coplanar, overlapping, same-facing faces of differently
	    coloured parts (Roblox flickers between them)
	  - parts hidden entirely inside other parts (wasted instances)
	  - floating parts that touch nothing connected to the ground
	  - sign text that runs off its board
	  - part budgets: far conifers and cacti 1, other far trees <= 2,
	    near trees <= 12, signs <= 8, small plants <= 6
	  lune run tools/test_props [seed] [-v]
]]

local process = require("@lune/process")
local env = require("./env")
env.propCatalogAsLibrary = true
local Catalog = require("./render_props")

local roblox = env.roblox
local Vector3, Enum = roblox.Vector3, roblox.Enum
local CFrame = env.CFrame

local seed = 12345
local verbose = false
for _, a in process.args do
	if a == "-v" then
		verbose = true
	elseif tonumber(a) then
		seed = tonumber(a)
	end
end

local failures = 0
local function fail(msg)
	failures += 1
	print("FAIL: " .. msg)
end

local LIMITS = { far = 2, tree = 12, sign = 8, plant = 6 }
-- far trees are the most numerous; these are one part each
local FAR_SINGLE = { pine = true, snowpine = true, cactus = true }
local ZF_GAP = 0.01 -- faces closer than this z-fight
local MIN_OVERLAP = 0.005 -- smaller shared patches (sq studs) stay under a pixel
local TOUCH = 0.03 -- parts closer than this touch

---------------------------------------------------------------------------
-- Shapes
---------------------------------------------------------------------------
local function shapeOf(p)
	if p:IsA("WedgePart") then
		return "wedge"
	elseif p:IsA("CornerWedgePart") then
		return "corner"
	elseif p:IsA("Part") then
		local s = p.Shape
		if s == Enum.PartType.Ball then
			return "ball"
		elseif s == Enum.PartType.Cylinder then
			return "cylinder"
		end
	end
	return "block"
end

local function info(p)
	local s = p.Size
	local shape = shapeOf(p)
	local r
	if shape == "cylinder" then
		r = math.min(s.Y, s.Z) / 2
	elseif shape == "ball" then
		r = math.min(s.X, s.Y, s.Z) / 2
	end
	return { part = p, cf = p.CFrame, size = s, h = s / 2, shape = shape, r = r }
end

-- Signed-ish distance test: is world point `w` inside the part grown by `tol`?
local function inside(pi, w, tol)
	local l = pi.cf:PointToObjectSpace(w)
	local h = pi.h
	local shape = pi.shape
	if shape == "ball" then
		return l.Magnitude <= pi.r + tol
	elseif shape == "cylinder" then
		return math.abs(l.X) <= h.X + tol and math.sqrt(l.Y * l.Y + l.Z * l.Z) <= pi.r + tol
	end
	if math.abs(l.X) > h.X + tol or math.abs(l.Y) > h.Y + tol or math.abs(l.Z) > h.Z + tol then
		return false
	end
	if shape == "wedge" then
		local sy, sz = pi.size.Y, pi.size.Z
		return (l.Y * sz - l.Z * sy) / math.sqrt(sy * sy + sz * sz) <= tol
	elseif shape == "corner" then
		return true -- treated as its bounding box
	end
	return true
end

-- Planar faces in world space: { n = normal, d = plane offset, poly = {Vector3} }
local function faces(pi)
	if pi.faces then
		return pi.faces
	end
	local out = {}
	local cf, h = pi.cf, pi.h
	local function add(n, pts)
		local wn = cf:VectorToWorldSpace(n).Unit
		local poly = {}
		for i, q in pts do
			poly[i] = cf:PointToWorldSpace(q)
		end
		table.insert(out, { n = wn, d = wn:Dot(poly[1]), poly = poly })
	end
	local x, y, z = h.X, h.Y, h.Z
	if pi.shape == "block" or pi.shape == "corner" then
		add(Vector3.new(1, 0, 0), { Vector3.new(x, -y, -z), Vector3.new(x, y, -z), Vector3.new(x, y, z), Vector3.new(x, -y, z) })
		add(Vector3.new(-1, 0, 0), { Vector3.new(-x, -y, -z), Vector3.new(-x, -y, z), Vector3.new(-x, y, z), Vector3.new(-x, y, -z) })
		add(Vector3.new(0, 1, 0), { Vector3.new(-x, y, -z), Vector3.new(-x, y, z), Vector3.new(x, y, z), Vector3.new(x, y, -z) })
		add(Vector3.new(0, -1, 0), { Vector3.new(-x, -y, -z), Vector3.new(x, -y, -z), Vector3.new(x, -y, z), Vector3.new(-x, -y, z) })
		add(Vector3.new(0, 0, 1), { Vector3.new(-x, -y, z), Vector3.new(x, -y, z), Vector3.new(x, y, z), Vector3.new(-x, y, z) })
		add(Vector3.new(0, 0, -1), { Vector3.new(-x, -y, -z), Vector3.new(-x, y, -z), Vector3.new(x, y, -z), Vector3.new(x, -y, -z) })
	elseif pi.shape == "wedge" then
		add(Vector3.new(0, -1, 0), { Vector3.new(-x, -y, -z), Vector3.new(x, -y, -z), Vector3.new(x, -y, z), Vector3.new(-x, -y, z) })
		add(Vector3.new(0, 0, 1), { Vector3.new(-x, -y, z), Vector3.new(x, -y, z), Vector3.new(x, y, z), Vector3.new(-x, y, z) })
		add(Vector3.new(1, 0, 0), { Vector3.new(x, -y, -z), Vector3.new(x, y, z), Vector3.new(x, -y, z) })
		add(Vector3.new(-1, 0, 0), { Vector3.new(-x, -y, -z), Vector3.new(-x, -y, z), Vector3.new(-x, y, z) })
		add(Vector3.new(0, pi.size.Z, -pi.size.Y).Unit, { Vector3.new(-x, -y, -z), Vector3.new(-x, y, z), Vector3.new(x, y, z), Vector3.new(x, -y, -z) })
	elseif pi.shape == "cylinder" then
		for _, sgn in { 1, -1 } do
			local pts = {}
			for i = 1, 24 do
				local a = (i - 1) / 24 * math.pi * 2
				table.insert(pts, Vector3.new(sgn * x, math.cos(a) * pi.r, math.sin(a) * pi.r))
			end
			add(Vector3.new(sgn, 0, 0), pts)
		end
	end
	pi.faces = out
	return out
end

-- Points spread over the part's surface.
local function samples(pi)
	if pi.samples then
		return pi.samples
	end
	local out = {}
	local cf, h = pi.cf, pi.h
	local function steps(len)
		return math.clamp(math.ceil(len / 0.4), 2, 10)
	end
	if pi.shape == "ball" then
		local n = 60
		for i = 0, n - 1 do
			local yy = 1 - (i + 0.5) / n * 2
			local rr = math.sqrt(1 - yy * yy)
			local a = i * 2.39996
			table.insert(out, cf:PointToWorldSpace(Vector3.new(math.cos(a) * rr, yy, math.sin(a) * rr) * pi.r))
		end
	elseif pi.shape == "cylinder" then
		local nx, na = steps(pi.size.X), 16
		for i = 0, nx do
			local x = -h.X + pi.size.X * i / nx
			for j = 0, na - 1 do
				local a = j / na * math.pi * 2
				table.insert(out, cf:PointToWorldSpace(Vector3.new(x, math.cos(a) * pi.r, math.sin(a) * pi.r)))
			end
		end
		for _, x in { -h.X, h.X } do
			table.insert(out, cf:PointToWorldSpace(Vector3.new(x, 0, 0)))
			for j = 0, 7 do
				local a = j / 8 * math.pi * 2
				table.insert(out, cf:PointToWorldSpace(Vector3.new(x, math.cos(a) * pi.r * 0.5, math.sin(a) * pi.r * 0.5)))
			end
		end
	else
		for _, f in faces(pi) do
			local poly = f.poly
			-- grid over the face via its first corner and two edges (quads),
			-- or barycentric steps (triangles)
			local a, b, c = poly[1], poly[2], poly[#poly]
			local nu, nv = steps((b - a).Magnitude), steps((c - a).Magnitude)
			for i = 0, nu do
				for j = 0, nv do
					local u, v = i / nu, j / nv
					if #poly == 3 then
						if u + v <= 1 + 1e-9 then
							table.insert(out, a + (b - a) * u + (c - a) * v)
						end
					else
						table.insert(out, a + (b - a) * u + (c - a) * v)
					end
				end
			end
		end
	end
	pi.samples = out
	return out
end

---------------------------------------------------------------------------
-- 2D convex polygon overlap
---------------------------------------------------------------------------
local function area2(poly)
	local a = 0
	for i = 1, #poly do
		local p, q = poly[i], poly[i % #poly + 1]
		a += p[1] * q[2] - q[1] * p[2]
	end
	return a / 2
end

local function ccw(poly)
	if area2(poly) < 0 then
		local r = {}
		for i = #poly, 1, -1 do
			table.insert(r, poly[i])
		end
		return r
	end
	return poly
end

local function clip(subject, clipper)
	local out = subject
	for i = 1, #clipper do
		local a, b = clipper[i], clipper[i % #clipper + 1]
		local input = out
		out = {}
		if #input == 0 then
			break
		end
		local function side(p)
			return (b[1] - a[1]) * (p[2] - a[2]) - (b[2] - a[2]) * (p[1] - a[1])
		end
		for j = 1, #input do
			local p, q = input[j], input[j % #input + 1]
			local sp, sq = side(p), side(q)
			if sp >= 0 then
				table.insert(out, p)
			end
			if (sp >= 0) ~= (sq >= 0) then
				local t = sp / (sp - sq)
				table.insert(out, { p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t })
			end
		end
	end
	return out
end

local function basis(n)
	local ref = math.abs(n.Y) < 0.9 and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)
	local u = n:Cross(ref).Unit
	return u, n:Cross(u)
end

local function to2(poly, u, v)
	local out = {}
	for i, p in poly do
		out[i] = { p:Dot(u), p:Dot(v) }
	end
	return ccw(out)
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local function sameLook(a, b)
	local ca, cb = a.Color, b.Color
	local dc = math.abs(ca.R - cb.R) + math.abs(ca.G - cb.G) + math.abs(ca.B - cb.B)
	return dc < 3 / 255 and a.Material == b.Material and a.Transparency == b.Transparency
end

-- `others` are context parts (the road around a cut-out scene): they may
-- cover or hold up the checked parts but are not checked themselves.
local function coveredBy(infos, others, skipA, skipB, w)
	for _, list in { infos, others } do
		for _, o in list do
			if o ~= skipA and o ~= skipB and inside(o, w, -0.001) then
				return true
			end
		end
	end
	return false
end

local function zfights(infos, others)
	local found = {}
	for i = 1, #infos do
		local A = infos[i]
		for j = i + 1, #infos do
			local B = infos[j]
			if sameLook(A.part, B.part) then
				continue
			end
			-- quick reject on bounding spheres
			local reach = A.size.Magnitude / 2 + B.size.Magnitude / 2
			if (A.cf.Position - B.cf.Position).Magnitude > reach + ZF_GAP then
				continue
			end
			local hit
			for _, fa in faces(A) do
				for _, fb in faces(B) do
					local gap = math.huge
					if fa.n:Dot(fb.n) > 0.9999 then
						-- distance of b's corners from a's plane (comparing plane
						-- offsets alone is off for slightly tilted normals)
						gap = 0
						for _, q in fb.poly do
							gap = math.max(gap, math.abs(fa.n:Dot(q) - fa.d))
						end
					end
					if gap < ZF_GAP then
						local u, v = basis(fa.n)
						local poly = clip(to2(fa.poly, u, v), to2(fb.poly, u, v))
						if #poly >= 3 and math.abs(area2(poly)) > MIN_OVERLAP then
							-- probe a grid over the overlap just in front of it; the
							-- share of probes no other part covers gives the area
							-- that can actually flicker
							local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
							for _, p in poly do
								x0, x1 = math.min(x0, p[1]), math.max(x1, p[1])
								y0, y1 = math.min(y0, p[2]), math.max(y1, p[2])
							end
							local probes, open = 0, 0
							for gi = 0, 12 do
								for gj = 0, 12 do
									local q = { x0 + (x1 - x0) * (gi + 0.5) / 13, y0 + (y1 - y0) * (gj + 0.5) / 13 }
									local ok = true
									for e = 1, #poly do
										local a, b = poly[e], poly[e % #poly + 1]
										if (b[1] - a[1]) * (q[2] - a[2]) - (b[2] - a[2]) * (q[1] - a[1]) < 0 then
											ok = false
											break
										end
									end
									if ok then
										probes += 1
										local w = u * q[1] + v * q[2] + fa.n * (fa.d + 0.02)
										if not coveredBy(infos, others, A, B, w) then
											open += 1
										end
									end
								end
							end
							local cx, cy = 0, 0
							for _, p in poly do
								cx += p[1] / #poly
								cy += p[2] / #poly
							end
							local exposed = probes > 0 and math.abs(area2(poly)) * open / probes or 0
							local visible = exposed > MIN_OVERLAP
							if visible then
								hit = string.format("%s/%s faces %.3f apart, %.2f sq studs exposed", A.part.Name, B.part.Name, gap, exposed)
								if verbose then
									local at = u * cx + v * cy + fa.n * fa.d
									hit ..= string.format(" (n=%s, at %.2f %.2f %.2f, face areas %.2f / %.2f)", tostring(fa.n), at.X, at.Y, at.Z, math.abs(area2(to2(fa.poly, u, v))), math.abs(area2(to2(fb.poly, u, v))))
								end
								break
							end
						end
					end
				end
				if hit then
					break
				end
			end
			-- coaxial cylinders of the same radius
			if not hit and A.shape == "cylinder" and B.shape == "cylinder" and math.abs(A.r - B.r) < ZF_GAP then
				local ax, bx = A.cf.RightVector, B.cf.RightVector
				if math.abs(ax:Dot(bx)) > 0.9999 then
					local off = B.cf.Position - A.cf.Position
					local along = off:Dot(ax)
					if (off - ax * along).Magnitude < ZF_GAP and math.abs(along) < A.h.X + B.h.X - ZF_GAP then
						hit = string.format("%s/%s coaxial cylinders of the same radius", A.part.Name, B.part.Name)
					end
				end
			end
			if hit then
				table.insert(found, hit)
			end
		end
	end
	return found
end

local function hiddenParts(infos, others)
	local found = {}
	for _, A in infos do
		local all = true
		for _, w in samples(A) do
			local covered = false
			for _, list in { infos, others } do
				for _, o in list do
					if o ~= A and inside(o, w, 0.002) then
						covered = true
						break
					end
				end
				if covered then
					break
				end
			end
			if not covered then
				all = false
				break
			end
		end
		if all then
			table.insert(found, A.part.Name)
		end
	end
	return found
end

local function touching(A, B)
	local reach = A.size.Magnitude / 2 + B.size.Magnitude / 2
	if (A.cf.Position - B.cf.Position).Magnitude > reach + TOUCH then
		return false
	end
	for _, w in samples(A) do
		if inside(B, w, TOUCH) then
			return true
		end
	end
	for _, w in samples(B) do
		if inside(A, w, TOUCH) then
			return true
		end
	end
	return false
end

local function lowest(pi)
	local y = math.huge
	for _, w in samples(pi) do
		y = math.min(y, w.Y)
	end
	return y
end

-- Props stand on the ground at groundY (a number). Road scenes pass a
-- function instead: whether a part reaches into the ground or is a
-- structure that stands on it.
local function floating(checked, groundY, others)
	local infos = table.clone(checked)
	for _, o in others do
		table.insert(infos, o)
	end
	local n = #infos
	local grounded = {}
	local queue = {}
	for i, A in infos do
		local ok
		if type(groundY) == "function" then
			ok = groundY(A)
		else
			ok = lowest(A) <= groundY + TOUCH
		end
		if ok then
			grounded[i] = true
			table.insert(queue, i)
		end
	end
	while #queue > 0 do
		local i = table.remove(queue)
		for j = 1, n do
			if not grounded[j] and touching(infos[i], infos[j]) then
				grounded[j] = true
				table.insert(queue, j)
			end
		end
	end
	local found = {}
	for i, A in checked do
		if not grounded[i] then
			table.insert(found, A.part.Name)
		end
	end
	return found
end

---------------------------------------------------------------------------
-- Text: estimate what TextScaled draws and check it sits on a board
---------------------------------------------------------------------------
-- rough advance widths of a heavy geometric sans (em)
local WIDE = { M = 0.94, W = 1.0, m = 0.94, w = 0.88 }
local NARROW = { I = 0.34, J = 0.56, L = 0.6, T = 0.66, F = 0.62, E = 0.64, i = 0.3, l = 0.3, j = 0.3, f = 0.4, t = 0.42, r = 0.44, s = 0.54, ["1"] = 0.46, [" "] = 0.26, ["'"] = 0.25, ["."] = 0.3, [","] = 0.3 }
local function charWidth(c)
	if WIDE[c] then
		return WIDE[c]
	elseif NARROW[c] then
		return NARROW[c]
	elseif c:match("%u") then
		return 0.74
	elseif c:match("%l") then
		return 0.62
	elseif c:match("%d") then
		return 0.68
	end
	return 0.7
end
local function lineWidth(s)
	local w = 0
	for _, cp in utf8.codes(s) do
		w += charWidth(utf8.char(cp))
	end
	return w
end
local function wrapLines(text, size, boxW)
	local out = {}
	for _, para in string.split(text, "\n") do
		local line = ""
		for _, word in string.split(para, " ") do
			local trial = line == "" and word or line .. " " .. word
			if line == "" or lineWidth(trial) * size <= boxW then
				line = trial
			else
				table.insert(out, line)
				line = word
			end
		end
		table.insert(out, line)
	end
	return out
end
-- (size px, lines) TextScaled would pick for a box
local function fitText(text, boxW, boxH)
	local best = 1
	for size = 100, 1, -1 do
		local lines = wrapLines(text, size, boxW)
		local wmax = 0
		for _, l in lines do
			wmax = math.max(wmax, lineWidth(l) * size)
		end
		if wmax <= boxW and #lines * size <= boxH then
			best = size
			break
		end
	end
	return best, wrapLines(text, best, boxW)
end

local FACE = {
	Front = { n = Vector3.new(0, 0, -1), right = Vector3.new(-1, 0, 0), dims = "XY" },
	Back = { n = Vector3.new(0, 0, 1), right = Vector3.new(1, 0, 0), dims = "XY" },
	Right = { n = Vector3.new(1, 0, 0), right = Vector3.new(0, 0, -1), dims = "ZY" },
	Left = { n = Vector3.new(-1, 0, 0), right = Vector3.new(0, 0, 1), dims = "ZY" },
}

local function luminance(c)
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

-- Returns problems and the smallest text height (studs) on the model.
local function textChecks(infos)
	local problems = {}
	local smallest = math.huge
	for _, pi in infos do
		for _, gui in pi.part:GetChildren() do
			if not gui:IsA("SurfaceGui") then
				continue
			end
			local fd = FACE[gui.Face.Name]
			if not fd then
				table.insert(problems, "unsupported SurfaceGui face " .. gui.Face.Name)
				continue
			end
			local s = pi.size
			local fw = fd.dims == "XY" and s.X or s.Z
			local fh = s.Y
			local ppu = gui.PixelsPerStud
			local W, H = fw * ppu, fh * ppu
			local centre = fd.n * Vector3.new(pi.h.X, pi.h.Y, pi.h.Z)
			for _, label in gui:GetDescendants() do
				if not label:IsA("TextLabel") or label.Text == "" then
					continue
				end
				local lw = label.Size.X.Scale * W + label.Size.X.Offset
				local lh = label.Size.Y.Scale * H + label.Size.Y.Offset
				local lx = label.Position.X.Scale * W + label.Position.X.Offset - label.AnchorPoint.X * lw
				local ly = label.Position.Y.Scale * H + label.Position.Y.Offset - label.AnchorPoint.Y * lh
				local pad = label:FindFirstChildOfClass("UIPadding")
				local pl, pr, pt, pb = 0, 0, 0, 0
				if pad then
					pl, pr, pt, pb = pad.PaddingLeft.Scale, pad.PaddingRight.Scale, pad.PaddingTop.Scale, pad.PaddingBottom.Scale
				end
				local bx, by = lx + pl * lw, ly + pt * lh
				local bw, bh = lw * (1 - pl - pr), lh * (1 - pt - pb)
				local size, lines
				if label.TextScaled then
					size, lines = fitText(label.Text, bw, bh)
				else
					size = label.TextSize
					lines = wrapLines(label.Text, size, bw)
				end
				smallest = math.min(smallest, size / ppu)
				-- corners of every line's box, in canvas pixels
				local pts = {}
				local y = by + (bh - #lines * size) / 2
				for _, l in lines do
					local w = lineWidth(l) * size
					local x = bx + (bw - w) / 2
					-- glyph ink sits a little inside the line box
					local y0, y1 = y + size * 0.15, y + size * 0.85
					for _, q in { { x, y0 }, { x + w, y0 }, { x, y1 }, { x + w, y1 }, { x + w / 2, y0 }, { x + w / 2, y1 } } do
						table.insert(pts, q)
					end
					y += size
				end
				for _, q in pts do
					-- canvas (0,0) is the face's top-left corner seen from outside
					local u = q[1] / ppu - fw / 2
					local v = fh / 2 - q[2] / ppu
					local lp = centre + fd.right * u + Vector3.new(0, v, 0)
					local w = pi.cf:PointToWorldSpace(lp)
					local n = pi.cf:VectorToWorldSpace(fd.n)
					local bg
					for t = 0, 60 do
						local probe = w - n * (t * 0.01 - 0.005)
						for _, o in infos do
							if o.part.Transparency < 0.5 and inside(o, probe, 0) then
								bg = o.part
								break
							end
						end
						if bg then
							break
						end
					end
					if not bg then
						table.insert(problems, string.format("text %q runs off its board", label.Text))
						break
					elseif math.abs(luminance(bg.Color) - luminance(label.TextColor3)) < 0.25 then
						table.insert(problems, string.format("text %q runs onto %s of a similar colour", label.Text, bg.Name))
						break
					end
				end
			end
		end
	end
	return problems, smallest
end

---------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------
local list, found = Catalog.collect(seed)
local stats = { zfight = 0, hidden = 0, floating = 0, text = 0, budget = 0 }
local counts = {}

for _, item in list do
	local parts = Catalog.parts(item.model)
	local infos = {}
	for _, p in parts do
		if p.Transparency < 1 then
			table.insert(infos, info(p))
		end
	end
	local others = {}
	if item.context then
		for _, p in Catalog.parts(item.context) do
			if p.Transparency < 1 then
				table.insert(others, info(p))
			end
		end
	end
	local problems = {}
	for _, z in zfights(infos, others) do
		table.insert(problems, "z-fighting: " .. z)
		stats.zfight += 1
	end
	for _, name in hiddenParts(infos, others) do
		table.insert(problems, "hidden inside other parts: " .. name)
		stats.hidden += 1
	end
	local groundY = 0.35 -- props are placed 0.35 below the terrain surface
	if item.category == "scene" then
		-- the verge is about level with the road: a part is grounded when it
		-- reaches below the top of the nearest road slab
		local slabs = {}
		for _, group in { infos, others } do
			for _, pi in group do
				if pi.part.Name == "Road" or pi.part.Name == "BridgeDeck" then
					table.insert(slabs, pi)
				end
			end
		end
		local ROOTS = { Road = true, BridgeDeck = true, Pier = true, Abutment = true, Portal = true, PortalLintel = true }
		groundY = function(pi)
			if ROOTS[pi.part.Name] then
				return true
			end
			local low, lowP = math.huge, nil
			for _, w in samples(pi) do
				if w.Y < low then
					low, lowP = w.Y, w
				end
			end
			local best, bestD = nil, math.huge
			for _, sl in slabs do
				local l = sl.cf:PointToObjectSpace(lowP)
				local d = math.max(math.abs(l.Z) - sl.h.Z, 0)
				if d < bestD then
					best, bestD = sl, d
				end
			end
			if not best then
				return low <= 0
			end
			local top = best.cf:PointToWorldSpace(Vector3.new(0, best.h.Y, 0))
			local up = best.cf.UpVector
			return up:Dot(lowP - top) <= -0.15
		end
	end
	for _, name in floating(infos, groundY, others) do
		table.insert(problems, "floating: " .. name)
		stats.floating += 1
	end
	local all = {}
	for _, p in parts do
		table.insert(all, info(p))
	end
	local tprob, smallest = textChecks(all)
	for _, t in tprob do
		table.insert(problems, t)
		stats.text += 1
	end
	if item.category == "sign" and smallest < 0.4 then
		table.insert(problems, string.format("text only %.2f studs tall", smallest))
		stats.text += 1
	end
	local limit = LIMITS[item.category]
	if item.category == "far" and FAR_SINGLE[item.kind] then
		limit = 1
	end
	if limit and #parts > limit then
		table.insert(problems, string.format("%d parts (limit %d)", #parts, limit))
		stats.budget += 1
	end
	local key = (item.category == "far" and item.kind .. " far") or ((item.category == "tree" or item.category == "plant") and item.kind) or item.name
	counts[key] = math.max(counts[key] or 0, #parts)
	for _, pr in problems do
		fail(string.format("[%s%s] %s", item.name, item.season and (" " .. item.season) or "", pr))
	end
end

-- names other code relies on
local props = env.require("src/client/Props").new(nil)
local NAMES = { pine = "Pine", snowpine = "SnowPine", oak = "Oak", birch = "Birch", cypress = "Cypress", palm = "Palm", cactus = "Cactus", bush = "Bush", drybush = "DryBush", flowers = "Flowers" }
for _, season in Catalog.Seasons do
	props:setSeason(season)
	for kind, name in NAMES do
		local near = props:tree(kind, 2, 1, false)
		if near.Name ~= name then
			fail(string.format("%s %s near model named %s, expected %s", season, kind, near.Name, name))
		end
		if kind ~= "bush" and kind ~= "drybush" and kind ~= "flowers" then
			local far = props:tree(kind, 2, 1, true)
			if far.Name ~= name .. "Far" then
				fail(string.format("%s %s far model named %s, expected %sFar", season, kind, far.Name, name))
			end
			local collides = false
			for _, d in near:GetDescendants() do
				collides = collides or (d:IsA("BasePart") and d.CanCollide)
			end
			if not collides then
				fail(season .. " " .. kind .. " trunk should collide")
			end
		end
		if near.WorldPivot ~= CFrame.new() then
			fail(kind .. " pivot is not at its base")
		end
	end
end
for _, item in list do
	if item.category == "sign" then
		local collides = false
		for _, d in item.model:GetDescendants() do
			collides = collides or (d:IsA("BasePart") and d.CanCollide)
		end
		if not collides then
			fail(item.name .. " post should collide")
		end
	end
end
for _, need in { "straight", "curve", "railStart", "bridge", "pier", "tunnel" } do
	if not found[need] then
		fail("no road sample found for the " .. need .. " scene")
	end
end

local keys = {}
for k in counts do
	table.insert(keys, k)
end
table.sort(keys)
local out = {}
for _, k in keys do
	table.insert(out, k .. "=" .. counts[k])
end
print(string.format("%d items checked", #list))
print("most parts per item: " .. table.concat(out, " "))
print(string.format("problems: z-fighting %d, hidden %d, floating %d, text %d, over budget %d", stats.zfight, stats.hidden, stats.floating, stats.text, stats.budget))
if verbose then
	print("scene samples:", found.straight, found.curve, found.railStart, found.bridge, found.pier, found.tunnel)
end
if failures == 0 then
	print("ALL PROP CHECKS PASSED")
else
	print(failures .. " FAILURES")
	process.exit(1)
end
