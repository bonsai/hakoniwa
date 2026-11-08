--!strict
-- Fem — 2D トラス有限要素法（Finite Element Method）ソルバ
--
-- 目的: 配置された箱庭の構造を簡易解析し、各部材の軸応力と節点変位を求める。
--       結果を Roblox のパーツの色（応力）と位置（変形）に反映する。
--
-- 単位: 長さ = studs（Roblox）。E・A は相対値でよい（色分けが目的）。
-- 手法: 各節点 2 自由度（uX, uY）のトラス要素。K u = f をガウス消去で解く。
--
-- 参考: 構造力学の標準的な直接剛性法。

local Fem = {}

export type Node = {
	x: number,
	y: number,
	fixedX: boolean?,   -- 支持（x 固定）
	fixedY: boolean?,   -- 支持（y 固定）
	loadX: number?,     -- 外力
	loadY: number?,
}

export type Element = {
	a: number,          -- 節点 index
	b: number,          -- 節点 index
	E: number,          -- ヤング係数（相対）
	A: number,          -- 断面積（相対）
}

export type Model = {
	nodes: { Node },
	elements: { Element },
}

export type ElementResult = {
	index: number,
	length: number,
	axial: number,      -- 軸力（+ 引張 / - 圧縮）
	stress: number,     -- 応力 = axial / A
}

export type Result = {
	ux: { number },     -- 節点変位
	uy: { number },
	elements: { ElementResult },
	maxAbsStress: number,
	maxAbsDisp: number,
}

local EPS = 1e-9

-- --- 線形代数（密行列・行優先のフラット配列） --------------------------------

local function gaussSolve(K: { number }, f: { number }, n: number): { number }
	-- K: n*n (row-major), f: n  →  x: n（部分ピボット付きガウス消去）
	local A = table.clone(K)
	local b = table.clone(f)

	for col = 1, n do
		-- ピボット選択
		local piv = col
		local best = math.abs(A[(col - 1) * n + col])
		for r = col + 1, n do
			local v = math.abs(A[(r - 1) * n + col])
			if v > best then
				best = v
				piv = r
			end
		end
		if best < EPS then
			continue -- 特異に近い列はスキップ（拘束で消えている想定）
		end
		if piv ~= col then
			for c = 1, n do
				A[(col - 1) * n + c], A[(piv - 1) * n + c] = A[(piv - 1) * n + c], A[(col - 1) * n + c]
			end
			b[col], b[piv] = b[piv], b[col]
		end
		-- 消去
		local pivotVal = A[(col - 1) * n + col]
		for r = col + 1, n do
			local factor = A[(r - 1) * n + col] / pivotVal
			if factor ~= 0 then
				for c = col, n do
					A[(r - 1) * n + c] -= factor * A[(col - 1) * n + c]
				end
				b[r] -= factor * b[col]
			end
		end
	end

	-- 後退代入
	local x = table.create(n, 0)
	for r = n, 1, -1 do
		local s = b[r]
		for c = r + 1, n do
			s -= A[(r - 1) * n + c] * x[c]
		end
		local diag = A[(r - 1) * n + r]
		x[r] = if math.abs(diag) > EPS then s / diag else 0
	end
	return x
end

-- --- ソルバ -----------------------------------------------------------------

function Fem.solve(model: Model): Result
	local nodes = model.nodes
	local elems = model.elements
	local nn = #nodes
	local ndof = nn * 2

	-- 全体剛性行列 K と荷重ベクトル f
	local K = table.create(ndof * ndof, 0)
	local f = table.create(ndof, 0)

	local function dofX(i: number): number
		return (i - 1) * 2 + 1
	end
	local function dofY(i: number): number
		return (i - 1) * 2 + 2
	end

	local lengths = table.create(#elems, 0)
	local dirs = table.create(#elems, { c = 0, s = 0 })

	for ei, e in ipairs(elems) do
		local na, nb = nodes[e.a], nodes[e.b]
		local dx, dy = nb.x - na.x, nb.y - na.y
		local L = math.sqrt(dx * dx + dy * dy)
		if L < EPS then
			L = EPS
		end
		local c, s = dx / L, dy / L
		lengths[ei] = L
		dirs[ei] = { c = c, s = s }

		local k = (e.E * e.A) / L
		-- 4x4 要素剛性（自由度: ax, ay, bx, by）
		local ke = {
			c * c, c * s, -c * c, -c * s,
			c * s, s * s, -c * s, -s * s,
			-c * c, -c * s, c * c, c * s,
			-c * s, -s * s, c * s, s * s,
		}
		local map = { dofX(e.a), dofY(e.a), dofX(e.b), dofY(e.b) }
		for r = 1, 4 do
			for cc = 1, 4 do
				K[(map[r] - 1) * ndof + map[cc]] += k * ke[(r - 1) * 4 + cc]
			end
		end
	end

	-- 節点外力
	for i, node in ipairs(nodes) do
		f[dofX(i)] += node.loadX or 0
		f[dofY(i)] += node.loadY or 0
	end

	-- 境界条件（固定自由度を除去）
	local free: { number } = {}
	local mapFree: { [number]: number } = {}
	for i, node in ipairs(nodes) do
		if not node.fixedX then
			local d = dofX(i)
			table.insert(free, d)
			mapFree[d] = #free
		end
		if not node.fixedY then
			local d = dofY(i)
			table.insert(free, d)
			mapFree[d] = #free
		end
	end
	local nf = #free

	-- 縮約系 Kf uf = ff
	local Kf = table.create(nf * nf, 0)
	local ff = table.create(nf, 0)
	for r = 1, nf do
		local gr = free[r]
		ff[r] = f[gr]
		for c = 1, nf do
			Kf[(r - 1) * nf + c] = K[(gr - 1) * ndof + free[c]]
		end
	end

	local uf = if nf > 0 then gaussSolve(Kf, ff, nf) else table.create(0, 0)

	-- 全体変位へ戻す
	local ux = table.create(nn, 0)
	local uy = table.create(nn, 0)
	for r = 1, nf do
		local g = free[r]
		local i = math.floor((g - 1) / 2) + 1
		if g % 2 == 1 then
			ux[i] = uf[r]
		else
			uy[i] = uf[r]
		end
	end

	-- 要素応力
	local results: { ElementResult } = {}
	local maxAbsStress = 0
	local maxAbsDisp = 0
	for ei, e in ipairs(elems) do
		local L = lengths[ei]
		local d = dirs[ei]
		local dux = ux[e.b] - ux[e.a]
		local duy = uy[e.b] - uy[e.a]
		local elong = dux * d.c + duy * d.s
		local strain = elong / L
		local stress = e.E * strain
		local axial = stress * e.A
		if math.abs(stress) > maxAbsStress then
			maxAbsStress = math.abs(stress)
		end
		table.insert(results, {
			index = ei,
			length = L,
			axial = axial,
			stress = stress,
		})
	end
	for i = 1, nn do
		maxAbsDisp = math.max(maxAbsDisp, math.abs(ux[i]), math.abs(uy[i]))
	end

	return {
		ux = ux,
		uy = uy,
		elements = results,
		maxAbsStress = maxAbsStress,
		maxAbsDisp = maxAbsDisp,
	}
end

-- --- 応力 → 色（引張=青, 圧縮=赤, 0=白） -------------------------------------

function Fem.stressToColor(stress: number, maxAbs: number): Color3
	if maxAbs < EPS then
		return Color3.new(1, 1, 1)
	end
	local t = math.clamp(stress / maxAbs, -1, 1)
	if t >= 0 then
		-- 引張: 白 → 青
		return Color3.new(1 - t, 1 - t, 1).Lerp(Color3.new(0.2, 0.4, 1), t)
	else
		-- 圧縮: 白 → 赤
		return Color3.new(1, 1 + t, 1 + t).Lerp(Color3.new(1, 0.25, 0.2), -t)
	end
end

return Fem
