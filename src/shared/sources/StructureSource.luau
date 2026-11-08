--!strict
-- S2 構造 Structure — FEM 応力と「折れる」判定
-- 契約: { nodes = {...}, elements = {...} }
-- 由来: 内部 FEM（Fem.luau）。爆発（D6）はこの破壊を再利用する。

local Types = require(script.Parent.Types)
local Fem = require(script.Parent.Parent.Fem)

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
	if #data.nodes == 0 then
		world.log("構造: ノードなし（スキップ）")
		return
	end
	local result = Fem.solve({ nodes = data.nodes, elements = data.elements })
	-- 「折れる」: しきい値超過を破壊として扱う（今後の DOMAINS D3）
	local yieldLimit = 1.0
	local broken = 0
	for _, e in ipairs(result.elements) do
		if math.abs(e.stress) > yieldLimit then
			broken += 1
		end
	end
	world.log(("構造: 最大応力 %.3f / 破壊 %d 要素"):format(result.maxAbsStress, broken))
end

return Source
