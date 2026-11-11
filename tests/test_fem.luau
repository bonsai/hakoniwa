--!strict
-- tests/test_fem.luau
-- Unit tests for Fem.luau: Singularity detection, reactions, stability, backward compatibility

-- Global Color3 mock for standalone Luau/Lune
local Color3Mock = {}
Color3Mock.__index = Color3Mock

function Color3Mock.new(r: number, g: number, b: number)
	return setmetatable({ R = r, G = g, B = b }, Color3Mock)
end

function Color3Mock:Lerp(other: any, alpha: number)
	return Color3Mock.new(
		self.R + (other.R - self.R) * alpha,
		self.G + (other.G - self.G) * alpha,
		self.B + (other.B - self.B) * alpha
	)
end

(getfenv(0) :: any).Color3 = Color3Mock

local Fem = require("../src/shared/Fem")

local function assertAlmostEqual(a: number, b: number, tol: number?, msg: string?)
	local t = tol or 1e-6
	local diff = math.abs(a - b)
	if diff > t then
		error(string.format("%s: expected %g, got %g (diff %g > %g)", msg or "Assertion failed", b, a, diff, t))
	end
end

local function assertTrue(cond: boolean, msg: string?)
	if not cond then
		error(msg or "Expected condition to be true")
	end
end

local function assertFalse(cond: boolean, msg: string?)
	if cond then
		error(msg or "Expected condition to be false")
	end
end

print("--- Running FEM tests ---")

-- Test 1: Simple 3-node stable determinate truss
-- Triangle: node 1 at (0, 0) pinned (fixedX=true, fixedY=true)
--           node 2 at (4, 0) roller (fixedY=true)
--           node 3 at (2, 3) free, loadY = -10
do
	local model: Fem.Model = {
		nodes = {
			{ x = 0, y = 0, fixedX = true, fixedY = true },
			{ x = 4, y = 0, fixedY = true },
			{ x = 2, y = 3, loadY = -10 },
		},
		elements = {
			{ a = 1, b = 2, E = 1000, A = 1 },
			{ a = 1, b = 3, E = 1000, A = 1 },
			{ a = 2, b = 3, E = 1000, A = 1 },
		},
	}

	local res = Fem.solve(model)
	assertTrue(res.ok, "Determinate truss should solve successfully")
	assertTrue(res.message == nil, "Determinate truss should have nil message")
	assertTrue(#res.elements == 3, "Result should have 3 elements")
	assertTrue(#res.reactions == 3, "Result should have 3 reactions")

	-- Equilibrium check: sum of reactions + sum of loads == 0
	local sumRx = res.reactions[1].x + res.reactions[2].x + res.reactions[3].x
	local sumRy = res.reactions[1].y + res.reactions[2].y + res.reactions[3].y
	assertAlmostEqual(sumRx, 0, 1e-6, "Equilibrium in X: sumRx should be 0")
	assertAlmostEqual(sumRy, 10, 1e-6, "Equilibrium in Y: sumRy should balance external load -10")

	-- Symmetry check: R1.y == R2.y == 5, R3 = (0, 0)
	assertAlmostEqual(res.reactions[1].y, 5, 1e-6, "Reaction 1 Y should be 5")
	assertAlmostEqual(res.reactions[2].y, 5, 1e-6, "Reaction 2 Y should be 5")
	assertAlmostEqual(res.reactions[3].x, 0, 1e-6, "Reaction at free node X should be 0")
	assertAlmostEqual(res.reactions[3].y, 0, 1e-6, "Reaction at free node Y should be 0")

	-- Displacements at pinned node 1 should be 0
	assertAlmostEqual(res.ux[1], 0, 1e-9, "ux[1] == 0")
	assertAlmostEqual(res.uy[1], 0, 1e-9, "uy[1] == 0")
	assertAlmostEqual(res.uy[2], 0, 1e-9, "uy[2] == 0")
	assertTrue(res.uy[3] < 0, "Node 3 should deflect downwards")
	print("Test 1 (Determinate stable truss) passed.")
end

-- Test 2: Indeterminate stable truss
-- 4-node box with diagonal bracing, nodes 1 and 2 fixed
do
	local model: Fem.Model = {
		nodes = {
			{ x = 0, y = 0, fixedX = true, fixedY = true },
			{ x = 10, y = 0, fixedX = true, fixedY = true },
			{ x = 10, y = 10, loadX = 5 },
			{ x = 0, y = 10 },
		},
		elements = {
			{ a = 1, b = 2, E = 2000, A = 2 },
			{ a = 2, b = 3, E = 2000, A = 2 },
			{ a = 3, b = 4, E = 2000, A = 2 },
			{ a = 4, b = 1, E = 2000, A = 2 },
			{ a = 1, b = 3, E = 2000, A = 2 },
			{ a = 2, b = 4, E = 2000, A = 2 },
		},
	}

	local res = Fem.solve(model)
	assertTrue(res.ok, "Indeterminate truss should solve successfully")
	assertTrue(res.message == nil, "Indeterminate truss message should be nil")
	assertTrue(#res.elements == 6, "Should have 6 element results")

	local totalRx = 0
	local totalRy = 0
	for _, r in ipairs(res.reactions) do
		totalRx += r.x
		totalRy += r.y
	end
	assertAlmostEqual(totalRx, -5, 1e-6, "Total reaction in X should balance +5 load")
	assertAlmostEqual(totalRy, 0, 1e-6, "Total reaction in Y should be 0")
	print("Test 2 (Indeterminate stable truss) passed.")
end

-- Test 3: Unstable truss: completely free (insufficient supports)
do
	local model: Fem.Model = {
		nodes = {
			{ x = 0, y = 0, loadX = 1 },
			{ x = 5, y = 0 },
			{ x = 2.5, y = 4 },
		},
		elements = {
			{ a = 1, b = 2, E = 1000, A = 1 },
			{ a = 2, b = 3, E = 1000, A = 1 },
			{ a = 3, b = 1, E = 1000, A = 1 },
		},
	}

	local res = Fem.solve(model)
	assertFalse(res.ok, "Unconstrained truss must fail")
	assertTrue(res.message ~= nil, "Unconstrained truss must return error message")
	assertTrue(#res.elements == 0, "Failed truss must have empty elements")
	assertAlmostEqual(res.maxAbsStress, 0, 1e-9, "maxAbsStress must be 0 on failure")
	assertAlmostEqual(res.maxAbsDisp, 0, 1e-9, "maxAbsDisp must be 0 on failure")
	-- Check that no NaN or Inf is present
	for _, v in ipairs(res.ux) do
		assertTrue(v == 0 and v == v, "ux should be 0 on failure")
	end
	for _, v in ipairs(res.uy) do
		assertTrue(v == 0 and v == v, "uy should be 0 on failure")
	end
	for _, r in ipairs(res.reactions) do
		assertTrue(r.x == 0 and r.y == 0, "reactions should be 0 on failure")
	end
	print("Test 3 (Completely free truss failure) passed.")
end

-- Test 4: Mechanism (unstable despite some supports: 4-bar linkage without diagonals)
-- Pinned at node 1 (0,0) and node 2 (10, 0), square 10x10 with no cross brace
-- Upper bar can sway freely in x direction
do
	local model: Fem.Model = {
		nodes = {
			{ x = 0, y = 0, fixedX = true, fixedY = true },
			{ x = 10, y = 0, fixedX = true, fixedY = true },
			{ x = 10, y = 10, loadX = 10 },
			{ x = 0, y = 10 },
		},
		elements = {
			{ a = 1, b = 4, E = 1000, A = 1 },
			{ a = 4, b = 3, E = 1000, A = 1 },
			{ a = 3, b = 2, E = 1000, A = 1 },
		},
	}

	local res = Fem.solve(model)
	assertFalse(res.ok, "Mechanism (4-bar linkage) must fail due to singularity")
	assertTrue(res.message ~= nil, "Mechanism must provide error message")
	assertTrue(#res.elements == 0, "Failed mechanism elements must be empty")
	assertAlmostEqual(res.maxAbsStress, 0, 1e-9, "maxAbsStress must be 0")
	assertAlmostEqual(res.maxAbsDisp, 0, 1e-9, "maxAbsDisp must be 0")
	print("Test 4 (Mechanism singularity detection) passed.")
end

-- Test 5: Collinear node with no perpendicular restraint (mechanism at single joint)
do
	local model: Fem.Model = {
		nodes = {
			{ x = 0, y = 0, fixedX = true, fixedY = true },
			{ x = 10, y = 0, fixedX = true, fixedY = true },
			{ x = 5, y = 0, loadY = -5 }, -- Collinear, y-direction stiffness is 0!
		},
		elements = {
			{ a = 1, b = 3, E = 1000, A = 1 },
			{ a = 3, b = 2, E = 1000, A = 1 },
		},
	}

	local res = Fem.solve(model)
	assertFalse(res.ok, "Collinear nodes without transverse support must fail (zero pivot / diagonal)")
	assertTrue(res.message ~= nil, "Collinear mechanism must provide error message")
	assertTrue(#res.elements == 0, "Collinear mechanism elements must be empty")
	print("Test 5 (Collinear zero transverse stiffness) passed.")
end

-- Test 6: Empty model / fully fixed model
do
	local model: Fem.Model = {
		nodes = {
			{ x = 0, y = 0, fixedX = true, fixedY = true },
			{ x = 1, y = 0, fixedX = true, fixedY = true },
		},
		elements = {
			{ a = 1, b = 2, E = 100, A = 1 },
		},
	}

	local res = Fem.solve(model)
	assertTrue(res.ok, "All nodes fixed should succeed trivially with 0 displacement")
	assertAlmostEqual(res.maxAbsDisp, 0, 1e-9, "Disp should be 0")
	print("Test 6 (Fully fixed model) passed.")
end

-- Test 7: stressToColor compatibility
do
	local c1 = Fem.stressToColor(0, 100)
	local c2 = Fem.stressToColor(50, 100)
	local c3 = Fem.stressToColor(-50, 100)
	assertTrue(c1 ~= nil and c2 ~= nil and c3 ~= nil, "stressToColor returns color")
	print("Test 7 (stressToColor compatibility) passed.")
end

print("All FEM tests passed successfully!")
return true
