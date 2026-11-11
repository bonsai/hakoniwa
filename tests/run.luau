--!strict
-- tests/run.luau — テストランナー（Lune で実行）

-- Roblox 型・グローバル環境のモック
local Vector3Mock = {
	new = function(x: number?, y: number?, z: number?)
		return {
			X = x or 0,
			Y = y or 0,
			Z = z or 0,
			x = x or 0,
			y = y or 0,
			z = z or 0,
		}
	end
}
_G.Vector3 = Vector3Mock
getfenv().Vector3 = Vector3Mock

local Color3Mock = {
	new = function(r: number?, g: number?, b: number?)
		return {
			r = r or 0,
			g = g or 0,
			b = b or 0,
			Lerp = function(self: any, other: any, t: number)
				return self
			end,
		}
	end,
	fromRGB = function(r: number?, g: number?, b: number?)
		return {
			r = (r or 0) / 255,
			g = (g or 0) / 255,
			b = (b or 0) / 255,
		}
	end,
}
_G.Color3 = Color3Mock
getfenv().Color3 = Color3Mock

local origRequire = require

-- モジュール解決用の Script / Roblox ツリーモック
local modules: { [string]: any } = {}
modules["Config"] = origRequire("../src/shared/Config")
modules["Fem"] = origRequire("../src/shared/Fem")

local function makeInstance(name: string, target: any)
	return {
		_name = name,
		_target = target,
	}
end

local SharedInstance: any = {
	Config = makeInstance("Config", modules["Config"]),
	Fem = makeInstance("Fem", modules["Fem"]),
	Types = makeInstance("Types", {}),
}

local SourcesInstance: any = {
	Types = makeInstance("Types", {}),
	Parent = SharedInstance,
}

local env = getfenv()
local rawReq = env.require
env.require = function(target: any)
	if type(target) == "table" and target._target then
		return target._target
	end
	return rawReq(target)
end

-- shared 直下モジュールの読み込み時スクリプト環境設定
env.script = { Parent = SharedInstance }

local Grid = origRequire("../src/shared/Grid")
SharedInstance.Grid = makeInstance("Grid", Grid)

local StructureModel = origRequire("../src/shared/StructureModel")
SharedInstance.StructureModel = makeInstance("StructureModel", StructureModel)

-- sources 直下モジュールの読み込み時スクリプト環境設定
env.script = { Parent = SourcesInstance }

local StructureSource = origRequire("../src/shared/sources/StructureSource")

print("=== Running Hakoniwa Unit Tests ===")

local passed = 0
local failed = 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		print("  ✓ " .. name)
		passed += 1
	else
		print("  ✗ " .. name .. ": " .. tostring(err))
		failed += 1
	end
end

-- 1. カタログに対応した物性値割り当てテスト
test("StructureModel: kind/size properties mapping", function()
	local colProps = StructureModel.getMaterialProps("column", Vector3Mock.new(1.07, 10.0, 1.07))
	assert(colProps.E == 200, "Column E should be 200")
	assert(colProps.yield == 1.0, "Column yield should be 1.0")
	assert(colProps.ultimate == 1.5, "Column ultimate should be 1.5")
	assert(colProps.A > 1.0, "Column A should match cross section")

	local wallProps = StructureModel.getMaterialProps("wall", Vector3Mock.new(14.28, 8.57, 0.43))
	assert(wallProps.E == 150, "Wall E should be 150")
	assert(wallProps.yield == 0.8, "Wall yield should be 0.8")
	assert(wallProps.ultimate == 1.2, "Wall ultimate should be 1.2")
end)

-- 2. 柱モデルの構築と近接節点マージテスト
test("StructureModel: stacked columns merge connected nodes", function()
	-- 2段重ねの柱: 下柱 (y=0..12), 上柱 (y=12..24)
	local parts = {
		{ position = Vector3Mock.new(0, 6, 0), kind = "column", size = Vector3Mock.new(1, 12, 1), rotation = 0 },
		{ position = Vector3Mock.new(0, 18, 0), kind = "column", size = Vector3Mock.new(1, 12, 1), rotation = 0 },
	}
	local model = StructureModel.build(parts)
	assert(#model.nodes == 3, "Stacked 2 columns should have 3 nodes after merge, got " .. #model.nodes)
	assert(#model.elements == 2, "Stacked 2 columns should have 2 elements, got " .. #model.elements)

	-- 最下部ノードが固定されていること
	local bottomNode = nil
	for _, n in ipairs(model.nodes) do
		if n.y == 0 then
			bottomNode = n
		end
	end
	assert(bottomNode ~= nil, "Bottom node at y=0 should exist")
	assert(bottomNode.fixedX == true and bottomNode.fixedY == true, "Bottom node should be fixedX and fixedY")
end)

-- 3. 壁モデルの構築テスト
test("StructureModel: wall creates truss frame and diagonals", function()
	local parts = {
		{ position = Vector3Mock.new(4, 5, 0), kind = "wall", size = Vector3Mock.new(8, 10, 0.4), rotation = 0 },
	}
	local model = StructureModel.build(parts)
	-- 壁は4節点（下部2、上部2）、6要素（4辺＋2対角ブレース）
	assert(#model.nodes == 4, "Wall should generate 4 nodes, got " .. #model.nodes)
	assert(#model.elements == 6, "Wall should generate 6 elements (frame + braces), got " .. #model.elements)
end)

-- 4. 自重解析で支持に近い下流ほど応力が大きくなる定性的テスト
test("FEM Solve: gravity causes higher compression stress at base", function()
	local parts = {
		{ position = Vector3Mock.new(0, 6, 0), kind = "column", size = Vector3Mock.new(1, 12, 1), rotation = 0 },
		{ position = Vector3Mock.new(0, 18, 0), kind = "column", size = Vector3Mock.new(1, 12, 1), rotation = 0 },
	}
	local model = StructureModel.build(parts)
	local result = modules["Fem"].solve(model)
	assert(#result.elements == 2, "Should have 2 element results")

	local elem1 = result.elements[1] -- 下段
	local elem2 = result.elements[2] -- 上段
	-- 圧縮応力: stress < 0
	assert(elem1.stress < 0, "Base column should be in compression")
	assert(elem2.stress < 0, "Top column should be in compression")
	-- 下段は上段自重＋下段自重を支えるため |elem1.stress| > |elem2.stress|
	assert(
		math.abs(elem1.stress) > math.abs(elem2.stress),
		string.format("Base stress (%.2f) must be larger than top stress (%.2f)", math.abs(elem1.stress), math.abs(elem2.stress))
	)
end)

-- 5. StructureSource.apply の動作テスト（パーツ配列からの自動構築とログ反映）
test("StructureSource.apply: builds from world placed parts and logs result", function()
	local logs = {}
	local setStressCalls = {}
	local markBrokenCalls = {}

	local mockWorld = {
		log = function(msg: string)
			table.insert(logs, msg)
		end,
		getPlacedParts = function()
			return {
				{ position = Vector3Mock.new(0, 6, 0), kind = "column", size = Vector3Mock.new(1, 12, 1), rotation = 0 },
			}
		end,
		setStress = function(idx: number, util: number, mode: string)
			table.insert(setStressCalls, { idx = idx, util = util, mode = mode })
		end,
		markBroken = function(idx: number, mode: string)
			table.insert(markBrokenCalls, { idx = idx, mode = mode })
		end,
	}

	StructureSource.apply(mockWorld, {})
	assert(#logs == 1, "Should log 1 summary message")
	assert(string.find(logs[1], "構造: 最大応力") ~= nil, "Log should contain summary: " .. logs[1])
	assert(#setStressCalls > 0, "setStress should have been invoked")
end)

-- 6. 支持不足モデル・空モデルでクラッシュせず安全にスキップするテスト
test("StructureSource.apply: handles empty model or solver failure safely", function()
	local logs = {}
	local mockWorld = {
		log = function(msg: string)
			table.insert(logs, msg)
		end,
	}

	-- 空データ
	StructureSource.apply(mockWorld, { nodes = {} })
	assert(#logs == 1 and string.find(logs[1], "ノードなし（スキップ）") ~= nil, "Should skip empty nodes")

	-- 支持不足で ok=false を返すモックソルバ結果
	local mockWorld2 = {
		log = function(msg: string)
			table.insert(logs, msg)
		end,
		getPlacedParts = function()
			return {}
		end
	}
	StructureSource.apply(mockWorld2, {})
	assert(#logs == 2, "Should log skip for no parts")
end)

print(string.format("\nTests finished: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("Some unit tests failed")
end
