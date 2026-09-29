--[[
	MathUtil
	--------
	Small scalar helpers shared by the generator modules.
]]

local MathUtil = {}

function MathUtil.clamp(x: number, a: number, b: number): number
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

function MathUtil.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Hermite smoothstep between edges e0 and e1.
function MathUtil.smoothstep(e0: number, e1: number, x: number): number
	local t = (x - e0) / (e1 - e0)
	if t <= 0 then
		return 0
	elseif t >= 1 then
		return 1
	end
	return t * t * (3 - 2 * t)
end

-- Polynomial smooth minimum: like math.min but with a rounded crease of size k.
function MathUtil.smin(a: number, b: number, k: number): number
	local h = 0.5 + 0.5 * (b - a) / k
	if h <= 0 then
		return b
	elseif h >= 1 then
		return a
	end
	return b + (a - b) * h - k * h * (1 - h)
end

function MathUtil.smax(a: number, b: number, k: number): number
	return -MathUtil.smin(-a, -b, k)
end

-- Deterministic 31-bit hash of integers, used to seed per-chunk RNGs.
-- Multipliers stay below 2^20 so every product is exact in a double.
local U32 = 4294967296
function MathUtil.hash(a: number, b: number, c: number, d: number?): number
	local h = bit32.bxor((a * 374761) % U32, (b * 668265) % U32)
	h = bit32.bxor(h, (c * 928371) % U32)
	if d then
		h = bit32.bxor(h, (d * 482711) % U32)
	end
	h = bit32.bxor(h, bit32.rshift(h, 15))
	h = (h * 40503) % U32
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 52733) % U32
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h % 2147483647
end

-- Shortest signed difference between two angles.
function MathUtil.angleDelta(a: number, b: number): number
	local d = (b - a) % (2 * math.pi)
	if d > math.pi then
		d -= 2 * math.pi
	end
	return d
end

return MathUtil
