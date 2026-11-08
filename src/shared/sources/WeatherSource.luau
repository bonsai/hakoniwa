--!strict
-- S6 気象 Weather — 雨・風・気温・警報
-- 契約: { now = { rain, wind, temp, alert }, forecast = { {...} } }
-- 由来: 気象庁 オープンデータ（bake_weather.py）

local Types = require(script.Parent.Types)

local Source: Types.Source = {
	id = "weather",
	name = "気象",
	category = "disaster",
	schema = "hakoniwa-weather/v1",
} :: Types.Source

function Source.load(ctx: Types.Context)
	return ctx.getData("weather") or { now = { rain = 0, wind = 0, temp = 20, alert = "none" } }
end

function Source.validate(data: any): (boolean, string?)
	if type(data) ~= "table" or type(data.now) ~= "table" then
		return false, "now が必要"
	end
	return true
end

function Source.apply(world: Types.World, data: any): ()
	world.setWeather(data.now)
	world.log(("気象: 雨 %.1f / 風 %.1f / %s"):format(
		data.now.rain or 0, data.now.wind or 0, tostring(data.now.alert)))
end

return Source
