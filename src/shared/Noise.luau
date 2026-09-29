--!native
--[[
	Noise
	-----
	Seeded wrappers around Luau's built-in math.noise (improved Perlin noise).
	math.noise is deterministic, so the same seed produces the same world on
	every machine.

	Each "channel" is a separate slice through 3D noise space, so fields that
	use different channels are uncorrelated.
]]

local noise = math.noise
local abs = math.abs

local Noise = {}
Noise.__index = Noise

function Noise.new(seed: number)
	local self = setmetatable({}, Noise)
	-- A non-integer base keeps us off the lattice, where Perlin noise is 0.
	self.base = (seed % 9973) * 1.6180339 + 0.3719
	return self
end

-- Raw 2D noise, roughly [-1, 1] but usually within +-0.5.
function Noise:n2(x: number, z: number, channel: number): number
	return noise(x, z, self.base + channel * 3.7131)
end

-- 1D noise along a line.
function Noise:n1(t: number, channel: number): number
	return noise(t, self.base + channel * 3.7131, 0.5371)
end

-- 1D noise remapped to roughly [0, 1].
function Noise:u1(t: number, channel: number): number
	local v = noise(t, self.base + channel * 3.7131, 0.5371) * 1.4 + 0.5
	if v < 0 then
		return 0
	elseif v > 1 then
		return 1
	end
	return v
end

-- 2D noise remapped to roughly [0, 1].
function Noise:u2(x: number, z: number, channel: number): number
	local v = noise(x, z, self.base + channel * 3.7131) * 1.4 + 0.5
	if v < 0 then
		return 0
	elseif v > 1 then
		return 1
	end
	return v
end

-- Fractal Brownian motion. Output is scaled to roughly [-1, 1].
function Noise:fbm2(x: number, z: number, octaves: number, channel: number): number
	local w = self.base + channel * 3.7131
	local sum, amp, freq, norm = 0, 1, 1, 0
	for i = 1, octaves do
		sum += amp * noise(x * freq, z * freq, w + i * 1.37)
		norm += amp
		amp *= 0.5
		freq *= 2.03
	end
	return sum / norm * 2.2
end

-- 1D fbm along a line, roughly [-1, 1].
function Noise:fbm1(t: number, octaves: number, channel: number): number
	local w = self.base + channel * 3.7131
	local sum, amp, freq, norm = 0, 1, 1, 0
	for i = 1, octaves do
		sum += amp * noise(t * freq, w + i * 1.37, 0.5371)
		norm += amp
		amp *= 0.5
		freq *= 2.03
	end
	return sum / norm * 2.2
end

-- Ridged multifractal in [0, 1]. Sharp crests make mountain ranges.
function Noise:ridged2(x: number, z: number, octaves: number, channel: number): number
	local w = self.base + channel * 3.7131
	local sum, amp, freq, norm, prev = 0, 1, 1, 0, 1
	for i = 1, octaves do
		local n = 1 - abs(noise(x * freq, z * freq, w + i * 1.37) * 2.1)
		if n < 0 then
			n = 0
		end
		n *= n
		sum += n * amp * prev
		norm += amp
		prev = n
		amp *= 0.5
		freq *= 2.01
	end
	return sum / norm
end

return Noise
