--!strict
-- StructureModel — 配置パーツから FEM トラスモデルを構築する純関数群
--
-- 役割:
--   1. 配置パーツ（柱、壁など）から節点 (Node) と要素 (Element) を生成
--   2. 中心/端点を Grid にスナップし、近接節点をトレランス内でマージ
--   3. Catalog の kind / size に応じて E, A, Iy, yield, ultimate を割り当て
--   4. 最下段節点を支持固定（fixedX, fixedY）
--   5. 自重相当の下向き外力（loadY < 0）を各節点へ付加

local Grid = require(script.Parent.Grid)
local Fem = require(script.Parent.Fem)

local StructureModel = {}

export type PlacedPart = {
	position: Vector3,
	kind: string,
	size: Vector3,
	rotation: number?,
}

export type MaterialProps = {
	E: number,
	A: number,
	Iy: number,
	yield: number,
	ultimate: number,
	density: number,
}

export type ExtendedElement = Fem.Element & {
	Iy: number?,
	yield: number?,
	ultimate: number?,
}

export type ExtendedModel = {
	nodes: { Fem.Node },
	elements: { ExtendedElement },
}

-- デフォルトの材料物性定義（Catalog.luau の kind / size に対応）
local MATERIAL_DEFAULTS: { [string]: { E: number, yield: number, ultimate: number, density: number } } = {
	column = {
		E = 200,          -- 柱: 剛性高め（コンクリート/鉄骨想定）
		yield = 1.0,
		ultimate = 1.5,
		density = 1.0,
	},
	wall = {
		E = 150,          -- 壁: 面内耐力壁想定
		yield = 0.8,
		ultimate = 1.2,
		density = 1.0,
	},
	window = {
		E = 50,           -- 窓・サッシ: 剛性低め
		yield = 0.4,
		ultimate = 0.6,
		density = 0.3,
	},
	default = {
		E = 100,
		yield = 0.5,
		ultimate = 0.8,
		density = 0.5,
	},
}

function StructureModel.getMaterialProps(kind: string, size: Vector3): MaterialProps
	local base = MATERIAL_DEFAULTS[kind] or MATERIAL_DEFAULTS.default
	-- 断面積 A: 部材の水平断面 (X * Z) をベースに設定（最低限の面積を確保）
	local A = math.max(0.1, size.X * size.Z)
	-- 断面2次モーメント Iy: 単純矩形断面相当 b*h^3 / 12
	local Iy = (size.Z * (size.X ^ 3)) / 12
	if Iy <= 0 then
		Iy = 0.01
	end

	return {
		E = base.E,
		A = A,
		Iy = Iy,
		yield = base.yield,
		ultimate = base.ultimate,
		density = base.density,
	}
end

-- 許容誤差範囲内の節点を同一節点へ結合するインデックス管理
local function findOrAddNode(
	nodes: { Fem.Node },
	x: number,
	y: number,
	tolerance: number
): number
	for idx, n in ipairs(nodes) do
		local dx = n.x - x
		local dy = n.y - y
		if math.sqrt(dx * dx + dy * dy) <= tolerance then
			return idx
		end
	end
	table.insert(nodes, {
		x = x,
		y = y,
	})
	return #nodes
end

-- 要素の単位長さあたり重量（density * A）
local function propsWeight(e: ExtendedElement): number
	local density = 1.0
	-- e に density が無ければ A をベースにした相対重量
	return density * e.A
end

-- 要素の重複登録を防止（自己ループ要素や同一節点ペア）
local function addElementIfUnique(
	elements: { ExtendedElement },
	a: number,
	b: number,
	props: MaterialProps
)
	if a == b then
		return
	end
	local minIdx = math.min(a, b)
	local maxIdx = math.max(a, b)
	for _, e in ipairs(elements) do
		local ea = math.min(e.a, e.b)
		local eb = math.max(e.a, e.b)
		if ea == minIdx and eb == maxIdx then
			return
		end
	end
	table.insert(elements, {
		a = a,
		b = b,
		E = props.E,
		A = props.A,
		Iy = props.Iy,
		yield = props.yield,
		ultimate = props.ultimate,
	})
end

--[[
	build:
	  配置パーツ配列から FEM トラスモデルを構築する純関数。
	  - tolerance: 節点マージの許容距離（studs, デフォルト 0.5）
	  - gravityScale: 自重倍率（デフォルト 1.0）
]]
function StructureModel.build(
	parts: { PlacedPart },
	tolerance: number?,
	gravityScale: number?
): ExtendedModel
	local tol = tolerance or 0.5
	local gScale = gravityScale or 1.0

	local rawNodes: { Fem.Node } = {}
	local rawElements: { ExtendedElement } = {}

	for _, part in ipairs(parts) do
		local kind = part.kind or "column"
		local size = part.size or Vector3.new(1, 1, 1)
		local rotDeg = part.rotation or 0
		local snappedPos = Grid.snapVector(part.position)
		local props = StructureModel.getMaterialProps(kind, size)

		if kind == "column" then
			-- 柱: 下端節点と上端節点（1本の垂直要素）
			-- 2D FEM 平面 (x, y) = (snappedPos.X, snappedPos.Y)
			local yBottom = Grid.snap(snappedPos.Y - size.Y / 2)
			local yTop = Grid.snap(snappedPos.Y + size.Y / 2)
			local x = snappedPos.X

			local nBottom = findOrAddNode(rawNodes, x, yBottom, tol)
			local nTop = findOrAddNode(rawNodes, x, yTop, tol)
			addElementIfUnique(rawElements, nBottom, nTop, props)

		elseif kind == "wall" then
			-- 壁: 幅方向の2端点を計算し、下部2節点・上部2節点によるトラス四角形＋対角ブレース
			local yBottom = Grid.snap(snappedPos.Y - size.Y / 2)
			local yTop = Grid.snap(snappedPos.Y + size.Y / 2)

			local rotRad = math.rad(rotDeg)
			local halfW = size.X / 2
			-- 壁の主軸ベクトル（水平方向の広がり）
			local cosR = math.cos(rotRad)
			-- 2D トラスへの射影: X 軸方向投影成分
			local dx = halfW * cosR

			local x1 = Grid.snap(snappedPos.X - dx)
			local x2 = Grid.snap(snappedPos.X + dx)

			if math.abs(x1 - x2) <= tol then
				-- X 射影で幅がつぶれた（Z方向の壁など）場合は厚み分または最低幅を与える
				local span = math.max(1, Grid.snap(size.Z))
				x1 = Grid.snap(snappedPos.X - span / 2)
				x2 = Grid.snap(snappedPos.X + span / 2)
			end

			local nB1 = findOrAddNode(rawNodes, x1, yBottom, tol)
			local nB2 = findOrAddNode(rawNodes, x2, yBottom, tol)
			local nT1 = findOrAddNode(rawNodes, x1, yTop, tol)
			local nT2 = findOrAddNode(rawNodes, x2, yTop, tol)

			-- 枠要素（左柱、右柱、上梁、下梁）
			addElementIfUnique(rawElements, nB1, nT1, props)
			addElementIfUnique(rawElements, nB2, nT2, props)
			addElementIfUnique(rawElements, nT1, nT2, props)
			addElementIfUnique(rawElements, nB1, nB2, props)
			-- トラスブレース（筋交い・せん断耐力）
			addElementIfUnique(rawElements, nB1, nT2, props)
			addElementIfUnique(rawElements, nB2, nT1, props)

		else
			-- window やその他部材: 上下または水平の単純2節点要素
			local yBottom = Grid.snap(snappedPos.Y - size.Y / 2)
			local yTop = Grid.snap(snappedPos.Y + size.Y / 2)
			local x = snappedPos.X
			local nBottom = findOrAddNode(rawNodes, x, yBottom, tol)
			local nTop = findOrAddNode(rawNodes, x, yTop, tol)
			addElementIfUnique(rawElements, nBottom, nTop, props)
		end
	end

	if #rawNodes == 0 then
		return {
			nodes = {},
			elements = {},
		}
	end

	-- 1. 支持（境界条件）: 最下段（y 最小値近傍）の節点を固定（fixedX, fixedY）
	local minY = math.huge
	for _, n in ipairs(rawNodes) do
		if n.y < minY then
			minY = n.y
		end
	end

	for _, n in ipairs(rawNodes) do
		if math.abs(n.y - minY) <= tol then
			n.fixedX = true
			n.fixedY = true
		end
	end

	-- 2. 外力: 自重相当の下向き荷重（loadY < 0）
	-- 各要素の自重 (density * A * length) を両端節点に折半して配分
	for _, e in ipairs(rawElements) do
		local na = rawNodes[e.a]
		local nb = rawNodes[e.b]
		local dx = nb.x - na.x
		local dy = nb.y - na.y
		local len = math.sqrt(dx * dx + dy * dy)
		local weight = (propsWeight(e) * len) * gScale
		local halfWeight = weight / 2

		na.loadY = (na.loadY or 0) - halfWeight
		nb.loadY = (nb.loadY or 0) - halfWeight
	end

	return {
		nodes = rawNodes,
		elements = rawElements,
	}
end

return StructureModel
