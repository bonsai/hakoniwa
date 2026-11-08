--!strict
-- Grid — スナップ・回転のユーティリティ

local Config = require(script.Parent.Config)

local Grid = {}

function Grid.snap(value: number, size: number?): number
	local s = size or Config.GridSize
	return math.floor(value / s + 0.5) * s
end

function Grid.snapVector(v: Vector3): Vector3
	return Vector3.new(
		Grid.snap(v.X),
		math.max(0, v.Y),
		Grid.snap(v.Z)
	)
end

function Grid.snapRotation(deg: number): number
	local step = Config.RotationStep
	return math.floor(deg / step + 0.5) * step % 360
end

-- グリッド座標 → ワールド（セル中心）
function Grid.cellCenter(cx: number, cz: number): Vector3
	local s = Config.GridSize
	return Vector3.new(cx * s + s / 2, 0, cz * s + s / 2)
end

return Grid
