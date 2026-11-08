--!strict
-- S4 法規 Code — 防火・避難・用途のルールセット
-- 契約: { rules = { { id, type = "fire"|"egress"|"use", region = {...}, level = "info"|"warn"|"error" } } }
-- 由来: ルールセット（bake_legal.py）。法改正時は bake 再実行のみ。

local Types = require(script.Parent.Types)

local Source: Types.Source = {
	id = "code",
	name = "法規",
	category = "architecture",
	schema = "hakoniwa-code/v1",
} :: Types.Source

function Source.load(ctx: Types.Context)
	return ctx.getData("code") or { rules = {} }
end

function Source.validate(data: any): (boolean, string?)
	if type(data) ~= "table" or type(data.rules) ~= "table" then
		return false, "rules 配列が必要"
	end
	return true
end

function Source.apply(world: Types.World, data: any): ()
	local counts = { info = 0, warn = 0, error = 0 }
	for _, rule in ipairs(data.rules) do
		-- 実際の判定はドメイン側。ここでは区域をハイライトするのみ。
		if rule.region then
			world.highlight(rule.region, rule.level or "info")
		end
		counts[rule.level or "info"] += 1
	end
	world.log(("法規: info=%d warn=%d error=%d"):format(counts.info, counts.warn, counts.error))
end

return Source
