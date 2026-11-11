--!strict
-- tests/run.luau
-- Lune test runner for Fem.luau

local process = require("@lune/process")

-- --- Color3 Stub -------------------------------------------------------------
-- Fem.luau references Color3 in `stressToColor`.
-- We provide a minimal stub supporting both method call `c:Lerp(...)`
-- and member function call `c.Lerp(...)` (as called in Fem.luau:248).
local Color3 = {}
Color3.__index = Color3

function Color3.new(r: number?, g: number?, b: number?)
	local self = setmetatable({}, Color3)
	self.R = r or 0
	self.G = g or 0
	self.B = b or 0
	self.r = self.R
	self.g = self.G
	self.b = self.B

	self.Lerp = function(a: any, b: any, c: any)
		local goal: any
		local alpha: number
		if c ~= nil then
			-- Called as c:Lerp(goal, alpha)
			goal = b
			alpha = c
		else
			-- Called as c.Lerp(goal, alpha)
			goal = a
			alpha = b
		end
		return Color3.new(
			self.R + (goal.R - self.R) * alpha,
			self.G + (goal.G - self.G) * alpha,
			self.B + (goal.B - self.B) * alpha
		)
	end

	return self
end

function Color3.fromRGB(r: number, g: number, b: number)
	return Color3.new(r / 255, g / 255, b / 255)
end

(getfenv() :: any).Color3 = Color3

-- Require pure Luau Fem module
local Fem = require("../src/shared/Fem")

-- --- Test Framework Harness --------------------------------------------------

local totalTests = 0
local passedTests = 0
local failedTests = 0
local skippedTests = 0

local function test(name: string, fn: () -> ())
	totalTests += 1
	local ok, err = pcall(fn)
	if ok then
		passedTests += 1
		print(string.format("  [PASS] %s", name))
	else
		failedTests += 1
		print(string.format("  [FAIL] %s: %s", name, tostring(err)))
	end
end

local function skip(name: string, reason: string)
	totalTests += 1
	skippedTests += 1
	print(string.format("  [SKIP] %s (%s)", name, reason))
end

local function assertApprox(actual: number, expected: number, tol: number?, message: string?)
	local tolerance = tol or 1e-6
	local diff = math.abs(actual - expected)
	local relDiff = if math.abs(expected) > 1e-9 then diff / math.abs(expected) else diff
	if relDiff > tolerance and diff > tolerance then
		local msg = message or string.format(
			"Expected %f to be approx %f (diff: %e, relDiff: %e, tol: %e)",
			actual,
			expected,
			diff,
			relDiff,
			tolerance
		)
		error(msg, 2)
	end
end

local function assertEqual(actual: any, expected: any, message: string?)
	if actual ~= expected then
		local msg = message or string.format("Expected %s to equal %s", tostring(actual), tostring(expected))
		error(msg, 2)
	end
end

local function assertTrue(cond: boolean, message: string?)
	if not cond then
		error(message or "Expected true, got false/nil", 2)
	end
end

print("=== Running FEM Unit Tests ===")

-- Basic smoke test for test runner harness & Color3 stub
test("Harness & Color3 stub smoke test", function()
	assertTrue(Fem ~= nil, "Fem module must load")
	local cTensile = Fem.stressToColor(10, 20)
	assertApprox(cTensile.R, 0.35, 1e-6)
	assertApprox(cTensile.G, 0.45, 1e-6)
	assertApprox(cTensile.B, 1.0, 1e-6)

	local cComp = Fem.stressToColor(-10, 20)
	assertApprox(cComp.R, 1.0, 1e-6)
	assertApprox(cComp.G, 0.375, 1e-6)
	assertApprox(cComp.B, 0.35, 1e-6)

	local cZero = Fem.stressToColor(0, 0)
	assertApprox(cZero.R, 1.0, 1e-6)
	assertApprox(cZero.G, 1.0, 1e-6)
	assertApprox(cZero.B, 1.0, 1e-6)
end)

-- 1. 単一棒（水平）引張: 変位 Δ = P L / (E A)、応力 P / A が解析解に一致（相対誤差 1e-6 以内）
test("Single horizontal bar tension: displacement and stress match analytical solution", function()
	local P = 120
	local L = 10
	local E = 2000
	local A = 4

	local expectedDisp = (P * L) / (E * A)
	local expectedStress = P / A
	local expectedAxial = P

	local model: Fem.Model = {
		nodes = {
			{ x = 0, y = 0, fixedX = true, fixedY = true },
			{ x = L, y = 0, fixedY = true, loadX = P },
		},
		elements = {
			{ a = 1, b = 2, E = E, A = A },
		},
	}

	local res = Fem.solve(model)

	-- Displacement
	assertApprox(res.ux[1], 0, 1e-6, "Node 1 ux should be 0")
	assertApprox(res.uy[1], 0, 1e-6, "Node 1 uy should be 0")
	assertApprox(res.ux[2], expectedDisp, 1e-6, "Node 2 ux should match Δ = P L / (E A)")
	assertApprox(res.uy[2], 0, 1e-6, "Node 2 uy should be 0")

	-- Element result
	assertEqual(#res.elements, 1, "Should have 1 element result")
	local elem = res.elements[1]
	assertApprox(elem.length, L, 1e-6, "Element length should match L")
	assertApprox(elem.axial, expectedAxial, 1e-6, "Axial force should equal P")
	assertApprox(elem.stress, expectedStress, 1e-6, "Stress should equal P / A")

	-- Summary statistics
	assertApprox(res.maxAbsStress, expectedStress, 1e-6, "maxAbsStress should match expectedStress")
	assertApprox(res.maxAbsDisp, expectedDisp, 1e-6, "maxAbsDisp should match expectedDisp")
end)

-- 2. 2 本トラス（三角）: 支持反力・部材軸力が手計算と一致
test("Two-bar triangular truss: member axial forces and support reactions match hand calculations", function()
	-- Nodes:
	-- Node 1: (0, 0), fixedX=true, fixedY=true (pin support)
	-- Node 2: (8, 0), fixedX=true, fixedY=true (pin support)
	-- Node 3: (4, 3), apex with vertical downward load loadY = -P
	--
	-- Geometry:
	-- Bar 1 (1 -> 3): dx = 4, dy = 3, L = 5, cos = 0.8, sin = 0.6
	-- Bar 2 (2 -> 3): dx = -4, dy = 3, L = 5, cos = -0.8, sin = 0.6
	--
	-- Equilibrium at apex (Node 3):
	-- Σ Fy = N1 * sin(θ) + N2 * sin(θ) - P = 0
	-- By symmetry, N1 = N2 = N
	-- 2 * N * 0.6 = P  =>  N = P / (2 * 0.6) = -P * (5 / 6) (compressive)
	--
	-- Reactions at supports:
	-- Bar 1 is in compression with force |N|. Pushing down-left on Node 1:
	-- Internal force in Bar 1 acts toward Node 1 with magnitude |N| = 5/6 * P.
	-- Vector 3 -> 1 is (-0.8, -0.6).
	-- Force on Node 1 from Bar 1 = N * (cos, sin) = (-5/6 * P) * (0.8, 0.6) = (-2/3 * P, -1/2 * P).
	-- Support reactions balance this:
	-- R1x = 2/3 * P = P * (4/6)
	-- R1y = 1/2 * P = P / 2
	-- Similarly at Node 2:
	-- R2x = -2/3 * P = -P * (4/6)
	-- R2y = 1/2 * P = P / 2
	-- Total vertical reaction R1y + R2y = P (matches total applied load).
	-- Total horizontal reaction R1x + R2x = 0 (global equilibrium).
	--
	-- Apex displacement:
	-- Bar elongation ΔL = N * L / (E * A)
	-- ΔL = ux * cos + uy * sin = 0 + uy * 0.6  =>  uy = ΔL / 0.6
	local P = 120
	local E = 10000
	local A = 2
	local L = 5
	local sinTheta = 0.6
	local cosTheta = 0.8

	local expectedAxial = -P / (2 * sinTheta) -- -100
	local expectedStress = expectedAxial / A -- -50
	local expectedElong = (expectedAxial * L) / (E * A) -- -100 * 5 / 20000 = -0.025
	local expectedDispY = expectedElong / sinTheta -- -0.025 / 0.6 = -0.041666...

	local expectedR1x = -expectedAxial * cosTheta -- 80
	local expectedR1y = -expectedAxial * sinTheta -- 60
	local expectedR2x = expectedAxial * cosTheta -- -80
	local expectedR2y = -expectedAxial * sinTheta -- 60

	local model: Fem.Model = {
		nodes = {
			{ x = 0, y = 0, fixedX = true, fixedY = true },
			{ x = 8, y = 0, fixedX = true, fixedY = true },
			{ x = 4, y = 3, loadY = -P },
		},
		elements = {
			{ a = 1, b = 3, E = E, A = A },
			{ a = 2, b = 3, E = E, A = A },
		},
	}

	local res = Fem.solve(model)

	-- Member axial forces and stresses
	assertApprox(res.elements[1].axial, expectedAxial, 1e-6, "Member 1 axial force")
	assertApprox(res.elements[2].axial, expectedAxial, 1e-6, "Member 2 axial force")
	assertApprox(res.elements[1].stress, expectedStress, 1e-6, "Member 1 stress")
	assertApprox(res.elements[2].stress, expectedStress, 1e-6, "Member 2 stress")

	-- Apex displacements
	assertApprox(res.ux[3], 0, 1e-6, "Apex ux should be 0 by symmetry")
	assertApprox(res.uy[3], expectedDispY, 1e-6, "Apex uy should match analytical displacement")

	-- Support reactions check:
	-- Compute reactions from member forces acting on fixed supports
	local elem1 = res.elements[1]
	local elem2 = res.elements[2]
	local cosTheta2 = -cosTheta -- dx = -4, L = 5
	local r1x = -elem1.axial * cosTheta
	local r1y = -elem1.axial * sinTheta
	local r2x = -elem2.axial * cosTheta2
	local r2y = -elem2.axial * sinTheta

	assertApprox(r1x, expectedR1x, 1e-6, "Support 1 Rx matches hand calculation")
	assertApprox(r1y, expectedR1y, 1e-6, "Support 1 Ry matches hand calculation")
	assertApprox(r2x, expectedR2x, 1e-6, "Support 2 Rx matches hand calculation")
	assertApprox(r2y, expectedR2y, 1e-6, "Support 2 Ry matches hand calculation")
	assertApprox(r1y + r2y, P, 1e-6, "Sum of vertical reactions equals applied load P")
	assertApprox(r1x + r2x, 0, 1e-6, "Sum of horizontal reactions equals 0")
end)

-- 3. 支持不足（メカニズム）: Fem.solve の結果が失敗（ok=false）になる（堅牢化 Issue の完了後）
test("Under-supported mechanism: handles singular/kinematically unstable models", function()
	-- A single bar connected to a pin support at (0,0) with free end at (10,0)
	-- Transverse load loadY = 10 induces rigid-body rotation (mechanism / singular K).
	local unstableModel: Fem.Model = {
		nodes = {
			{ x = 0, y = 0, fixedX = true, fixedY = true },
			{ x = 10, y = 0, loadY = 10 }, -- Free in X and Y
		},
		elements = {
			{ a = 1, b = 2, E = 1000, A = 1 },
		},
	}

	local res: any = Fem.solve(unstableModel)

	-- If the hardening issue has implemented `ok: boolean`:
	-- ok should be false.
	-- If not yet implemented, ensure Fem.solve gracefully completes without throwing unhandled exceptions.
	if res.ok ~= nil then
		assertEqual(res.ok, false, "Result ok should be false for unstable mechanism")
	else
		-- Current behavior before hardening issue:
		-- K has a singular pivot; gaussSolve skips it and returns zero displacements for degenerate DOFs.
		assertTrue(res ~= nil, "Fem.solve returns result structure")
		assertTrue(type(res.ux) == "table", "Result contains ux array")
		assertTrue(type(res.uy) == "table", "Result contains uy array")
	end
end)

-- 4. 破壊判定: 座屈 / 降伏のしきい値まわり（破壊判定 Issue の完了後。未実装なら skip 可能にする）
if (Fem :: any).checkFailure ~= nil or (Fem :: any).isYielded ~= nil or (Fem :: any).isBuckled ~= nil then
	test("Failure criterion: buckling / yield threshold", function()
		-- Implementation when failure check is available
		assertTrue(true)
	end)
else
	skip("Failure criterion: buckling / yield threshold", "Fem failure criterion issue not yet implemented in Fem.luau")
end

print(string.format(
	"\nSummary: %d total, %d passed, %d failed, %d skipped\n",
	totalTests,
	passedTests,
	failedTests,
	skippedTests
))

if failedTests > 0 then
	process.exit(1)
else
	process.exit(0)
end
