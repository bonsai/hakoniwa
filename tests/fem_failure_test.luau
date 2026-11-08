--!strict
-- Tests for FEM failure modes: Tensile rupture, Tensile yield, Compressive buckling, Compressive yield

-- Roblox environment mock if running under standalone luau
-- In standalone luau, require uses relative path from current file
local sharedFem = require("../src/shared/Fem")

local function assertEq(a: any, b: any, msg: string)
	if a ~= b then
		error(string.format("Assertion failed: %s (expected %s, got %s)", msg, tostring(b), tostring(a)))
	end
end

local function assertTrue(cond: boolean, msg: string)
	if not cond then
		error("Assertion failed: " .. msg)
	end
end

print("--- Running FEM failure tests ---")

-- Test 1: 引張破断 (Tensile rupture)
-- 1 bar of length L = 10, fixed at node 1 (0, 0), pulled at node 2 (10, 0)
-- A = 1.0, E = 100. Load F = +1.6 => stress = +1.6.
-- yield = 1.0, ultimate = 1.5. Since stress 1.6 >= 1.5, mode = "rupture", broken = true.
do
	local model = {
		nodes = {
			{ x = 0, y = 0, fixedX = true, fixedY = true },
			{ x = 10, y = 0, fixedY = true, loadX = 1.6 },
		},
		elements = {
			{ a = 1, b = 2, E = 100, A = 1.0, yield = 1.0, ultimate = 1.5 },
		},
	}
	local res = sharedFem.solve(model)
	local elem = res.elements[1]
	print(string.format("Test 1 (Tensile rupture): axial=%.3f, stress=%.3f, util=%.3f, mode=%s, broken=%s",
		elem.axial, elem.stress, elem.utilization, elem.failureMode, tostring(elem.broken)))
	assertEq(elem.failureMode, "rupture", "Test 1 failureMode should be rupture")
	assertEq(elem.broken, true, "Test 1 broken should be true")
	assertTrue(elem.utilization >= 1.0, "Test 1 utilization should be >= 1.0")
	assertTrue(elem.axial > 0, "Test 1 axial should be positive")
end

-- Test 2: 引張降伏 (Tensile yield)
-- Load F = +1.2 => stress = +1.2.
-- yield = 1.0, ultimate = 1.5. 1.0 <= stress < 1.5 => mode = "yield", broken = false.
do
	local model = {
		nodes = {
			{ x = 0, y = 0, fixedX = true, fixedY = true },
			{ x = 10, y = 0, fixedY = true, loadX = 1.2 },
		},
		elements = {
			{ a = 1, b = 2, E = 100, A = 1.0, yield = 1.0, ultimate = 1.5 },
		},
	}
	local res = sharedFem.solve(model)
	local elem = res.elements[1]
	print(string.format("Test 2 (Tensile yield): axial=%.3f, stress=%.3f, util=%.3f, mode=%s, broken=%s",
		elem.axial, elem.stress, elem.utilization, elem.failureMode, tostring(elem.broken)))
	assertEq(elem.failureMode, "yield", "Test 2 failureMode should be yield")
	assertEq(elem.broken, false, "Test 2 broken should be false")
	assertTrue(elem.utilization >= 1.0, "Test 2 utilization should be >= 1.0")
	assertTrue(elem.axial > 0, "Test 2 axial should be positive")
end

-- Test 3: 圧縮座屈 (Compressive buckling)
-- Slender column: L = 10, A = 1.0, E = 100.
-- Pcr = π^2 * E * Iy / (K * L)^2.
-- Default Iy = A^2 / (4π) = 1 / (4π) ≈ 0.079577.
-- Pcr = π^2 * 100 * (1/(4π)) / 100 = π / 4 ≈ 0.7854.
-- Yield limit = 1.0 (so yield force Py = 1.0).
-- If we apply compressive load F = -0.85 (node 2 loadX = -0.85):
-- |axial| = 0.85 >= Pcr (0.7854), while |stress| = 0.85 < 1.0 (yield not reached).
-- Therefore, failureMode = "buckling", broken = true.
do
	local model = {
		nodes = {
			{ x = 0, y = 0, fixedX = true, fixedY = true },
			{ x = 10, y = 0, fixedY = true, loadX = -0.85 },
		},
		elements = {
			{ a = 1, b = 2, E = 100, A = 1.0, yield = 1.0, ultimate = 1.5 },
		},
	}
	local res = sharedFem.solve(model)
	local elem = res.elements[1]
	print(string.format("Test 3 (Compressive buckling): axial=%.3f, stress=%.3f, util=%.3f, mode=%s, broken=%s",
		elem.axial, elem.stress, elem.utilization, elem.failureMode, tostring(elem.broken)))
	assertEq(elem.failureMode, "buckling", "Test 3 failureMode should be buckling")
	assertEq(elem.broken, true, "Test 3 broken should be true")
	assertTrue(elem.utilization >= 1.0, "Test 3 utilization should be >= 1.0")
	assertTrue(elem.axial < 0, "Test 3 axial should be negative")
end

-- Test 4: 圧縮降伏 (Compressive yield)
-- Short stubby column (or large Iy to avoid buckling):
-- Let L = 10, A = 1.0, E = 100.
-- We specify a large Iy = 10.0 so Pcr = π^2 * 100 * 10 / 100 = 10 * π^2 ≈ 98.696.
-- Load F = -1.2 (node 2 loadX = -1.2) => |axial| = 1.2, |stress| = 1.2.
-- |axial| = 1.2 < Pcr, but |stress| >= yield (1.0).
-- Therefore, failureMode = "yield", broken = false.
do
	local model = {
		nodes = {
			{ x = 0, y = 0, fixedX = true, fixedY = true },
			{ x = 10, y = 0, fixedY = true, loadX = -1.2 },
		},
		elements = {
			{ a = 1, b = 2, E = 100, A = 1.0, Iy = 10.0, yield = 1.0, ultimate = 1.5 },
		},
	}
	local res = sharedFem.solve(model)
	local elem = res.elements[1]
	print(string.format("Test 4 (Compressive yield): axial=%.3f, stress=%.3f, util=%.3f, mode=%s, broken=%s",
		elem.axial, elem.stress, elem.utilization, elem.failureMode, tostring(elem.broken)))
	assertEq(elem.failureMode, "yield", "Test 4 failureMode should be yield")
	assertEq(elem.broken, false, "Test 4 broken should be false")
	assertTrue(elem.utilization >= 1.0, "Test 4 utilization should be >= 1.0")
	assertTrue(elem.axial < 0, "Test 4 axial should be negative")
end

-- Test 5: 限界内のモデル (Within limits: broken = false, utilization < 1.0)
do
	local model = {
		nodes = {
			{ x = 0, y = 0, fixedX = true, fixedY = true },
			{ x = 10, y = 0, fixedY = true, loadX = 0.5 },
		},
		elements = {
			{ a = 1, b = 2, E = 100, A = 1.0 }, -- uses default yield=1.0, ultimate=1.5
		},
	}
	local res = sharedFem.solve(model)
	local elem = res.elements[1]
	print(string.format("Test 5 (Within limits): axial=%.3f, stress=%.3f, util=%.3f, mode=%s, broken=%s",
		elem.axial, elem.stress, elem.utilization, elem.failureMode, tostring(elem.broken)))
	assertEq(elem.failureMode, "none", "Test 5 failureMode should be none")
	assertEq(elem.broken, false, "Test 5 broken should be false")
	assertTrue(elem.utilization < 1.0, "Test 5 utilization should be < 1.0")
end

-- Test 6: 後方互換性 (Backward compatibility with default values)
-- Element with only E and A specified
do
	local model = {
		nodes = {
			{ x = 0, y = 0, fixedX = true, fixedY = true },
			{ x = 10, y = 0, fixedY = true, loadX = 1.8 },
		},
		elements = {
			{ a = 1, b = 2, E = 100, A = 1.0 }, -- defaults: yield=1.0, ultimate=1.5
		},
	}
	local res = sharedFem.solve(model)
	local elem = res.elements[1]
	print(string.format("Test 6 (Defaults rupture): axial=%.3f, stress=%.3f, util=%.3f, mode=%s, broken=%s",
		elem.axial, elem.stress, elem.utilization, elem.failureMode, tostring(elem.broken)))
	assertEq(elem.failureMode, "rupture", "Test 6 should rupture by default ultimate 1.5")
	assertEq(elem.broken, true, "Test 6 broken should be true")
end

-- Test 7: StructureSource apply integration
do
	local logs: { string } = {}
	local world = {
		setTerrain = function() end,
		paintZone = function() end,
		placePart = function() end,
		highlight = function() end,
		setWeather = function() end,
		log = function(msg: string)
			table.insert(logs, msg)
		end,
	}

	-- Mock script hierarchy for StructureSource
	-- StructureSource requires script.Parent.Types and script.Parent.Parent.Fem
	-- We can execute StructureSource's logic or test directly
	local structureData = {
		nodes = {
			{ x = 0, y = 0, fixedX = true, fixedY = true },
			{ x = 10, y = 0, fixedY = true, loadX = 2.0 }, -- Tensile rupture
			{ x = 0, y = 10, fixedX = true, fixedY = true },
			{ x = 10, y = 10, fixedY = true, loadX = -0.9 }, -- Compressive buckling
			{ x = 0, y = 20, fixedX = true, fixedY = true },
			{ x = 10, y = 20, fixedY = true, loadX = 1.2 }, -- Tensile yield
		},
		elements = {
			{ a = 1, b = 2, E = 100, A = 1.0 }, -- rupture (broken)
			{ a = 3, b = 4, E = 100, A = 1.0 }, -- buckling (broken)
			{ a = 5, b = 6, E = 100, A = 1.0 }, -- yield (not broken)
		},
	}

	local res = sharedFem.solve(structureData)
	assertEq(#res.elements, 3, "Should have 3 element results")
	assertEq(res.elements[1].broken, true, "Elem 1 broken")
	assertEq(res.elements[2].broken, true, "Elem 2 broken")
	assertEq(res.elements[3].broken, false, "Elem 3 not broken")
	assertEq(res.elements[1].failureMode, "rupture", "Elem 1 rupture")
	assertEq(res.elements[2].failureMode, "buckling", "Elem 2 buckling")
	assertEq(res.elements[3].failureMode, "yield", "Elem 3 yield")
	print("Test 7 (Multiple elements): All assertions passed.")
end

print("ALL TESTS PASSED SUCCESSFULLY!")
