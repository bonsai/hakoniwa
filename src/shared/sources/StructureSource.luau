--!strict
-- S2 構造 Structure — FEM 応力と「折れる」判定
-- 契約: { nodes = {...}, elements = {...} } または配置パーツからの自動構築
-- 由来: 内部 FEM（Fem.luau）および StructureModel.luau。爆発（D6）はこの破壊を再利用する。

local Types = require(script.Parent.Types)
local Fem = require(script.Parent.Parent.Fem)
local StructureModel = require(script.Parent.Parent.StructureModel)

local Source: Types.Source = {
	id = "structure",
	name = "構造",
	category = "architecture",
	schema = "hakoniwa-structure/v1",
} :: Types.Source

function Source.load(ctx: Types.Context)
	-- モデルは図面/配置から構築するのが本筋。ここでは焼き込み or 空モデル。
	return ctx.getData("structure") or { nodes = {}, elements = {} }
end

function Source.validate(data: any): (boolean, string?)
	if type(data) ~= "table" then
		return false, "table が必要"
	end
	return true
end

function Source.apply(world: Types.World, data: any): ()
	local model: Fem.Model? = nil

	-- 1. data に既存のノード・要素があれば従来通り使う
	if type(data) == "table" and type(data.nodes) == "table" and #data.nodes > 0 then
		model = {
			nodes = data.nodes,
			elements = data.elements or {},
		}
	else
		-- 2. 無ければ World や data からパーツ配列を取得し StructureModel.build で構築
		local parts: { any }? = nil
		if type(data) == "table" and type(data.parts) == "table" then
			parts = data.parts
		elseif (world :: any).getPlacedParts and type((world :: any).getPlacedParts) == "function" then
			local ok, res = pcall((world :: any).getPlacedParts)
			if ok and type(res) == "table" then
				parts = res
			end
		elseif (world :: any).parts and type((world :: any).parts) == "table" then
			parts = (world :: any).parts
		end

		if parts and #parts > 0 then
			local buildOk, builtModel = pcall(StructureModel.build, parts)
			if buildOk and builtModel and #builtModel.nodes > 0 then
				model = builtModel :: any
			else
				world.log("構造: パーツからのモデル構築に失敗またはノードなし（スキップ）")
				return
			end
		end
	end

	if not model or #model.nodes == 0 then
		world.log("構造: ノードなし（スキップ）")
		return
	end

	-- 3. FEM 解析の実行（ソルバ堅牢化/例外防止）
	local solveOk, result = pcall(Fem.solve, model)
	if not solveOk or type(result) ~= "table" then
		local errMsg = if not solveOk then tostring(result) else "ソルバが結果を返しませんでした"
		world.log(("構造: 解析失敗（スキップ）: %s"):format(errMsg))
		return
	end

	-- ソルバ堅牢化 Issue に依存: ok フィールドがある場合、false であれば安全にスキップ
	if (result :: any).ok == false then
		local reason = (result :: any).reason or (result :: any).error or "支持不足または特異行列"
		world.log(("構造: 解析失敗（スキップ）: %s"):format(tostring(reason)))
		return
	end

	if not result.elements then
		world.log("構造: 要素結果なし（スキップ）")
		return
	end

	-- 4. 結果（ok, maxAbsStress, broken, failureMode, utilization）の集計
	local brokenCount = 0
	local maxUtilization = 0
	local failureModes: { [string]: number } = {}

	for idx, e in ipairs(result.elements) do
		-- 並行実装・ソルバ/破壊判定 Issue のフィールドに防御的に対応
		local elemDef = model.elements[idx]
		local yieldLimit = if elemDef and (elemDef :: any).yield then (elemDef :: any).yield else 1.0

		local isBroken = false
		local mode: string? = nil
		local util = 0

		if (e :: any).broken ~= nil then
			isBroken = (e :: any).broken == true
			mode = (e :: any).failureMode
			util = (e :: any).utilization or (math.abs(e.stress) / yieldLimit)
		else
			util = math.abs(e.stress) / yieldLimit
			if util > 1.0 then
				isBroken = true
				mode = if e.stress < 0 then "buckling" else "tensile_yield"
			end
		end

		if isBroken then
			brokenCount += 1
			local m = mode or "yield"
			failureModes[m] = (failureModes[m] or 0) + 1
			if (world :: any).markBroken and type((world :: any).markBroken) == "function" then
				pcall((world :: any).markBroken, idx, m)
			end
		end

		if util > maxUtilization then
			maxUtilization = util
		end

		if (world :: any).setStress and type((world :: any).setStress) == "function" then
			pcall((world :: any).setStress, idx, util, mode or "normal")
		end
	end

	local maxAbsStress = result.maxAbsStress or 0
	local summary = ("構造: 最大応力 %.3f / 最大利用率 %.2f / 破壊 %d 要素"):format(
		maxAbsStress,
		maxUtilization,
		brokenCount
	)
	world.log(summary)
end

return Source
