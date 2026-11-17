--!strict
-- Cockpit maths shared by VehicleBuilder (steering joint, hand grips) and the first-person view.
-- Every vehicle spec has `cockpit = { eye, control, pitch }` (blender/vehicles_spec.py): eye is where
-- the driver's head belongs, control is what the hands hold. All positions are in the vehicle's
-- build space (Roblox axes, -Z = front, y = 0 = ground); model:GetPivot() maps them to the world.
local Cockpit = {}

-- how far each kind of control turns at full lock (radians)
Cockpit.LOCK = { wheel = math.rad(110), yoke = math.rad(45), bars = math.rad(22) }

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- Frame of a steering wheel / yoke / T-bar: X to the right, Y up the rim, Z along the column back
-- towards the driver. `tilt` is how far the top of the rim leans forward from vertical.
function Cockpit.pivot(ctl: any): CFrame?
	if type(ctl) ~= "table" or type(ctl.pos) ~= "table" then
		return nil
	end
	local t = math.rad(ctl.tilt or 0)
	local right = Vector3.xAxis
	local up = Vector3.new(0, math.cos(t), -math.sin(t))
	return CFrame.fromMatrix(v3(ctl.pos), right, up, right:Cross(up))
end

-- Where the hands go, in build space: 10 and 2 o'clock on a wheel, the horns of a yoke, the grips of
-- a T-bar, or the explicit right / left points of sticks, levers and grips.
function Cockpit.grips(ctl: any): { right: Vector3, left: Vector3 }?
	if type(ctl) ~= "table" then
		return nil
	end
	if type(ctl.right) == "table" and type(ctl.left) == "table" then
		return { right = v3(ctl.right), left = v3(ctl.left) }
	end
	local cf = Cockpit.pivot(ctl)
	if not cf then
		return nil
	end
	if ctl.type == "wheel" then
		local r = ctl.radius or 0.6
		return { right = cf * Vector3.new(r * 0.866, r * 0.5, 0), left = cf * Vector3.new(-r * 0.866, r * 0.5, 0) }
	end
	local w = (ctl.width or 1) / 2
	if ctl.type == "yoke" then
		return { right = cf * Vector3.new(w * 0.95, 0.12, 0), left = cf * Vector3.new(-w * 0.95, 0.12, 0) }
	end
	return { right = cf * Vector3.new(w - 0.2, 0, 0), left = cf * Vector3.new(-(w - 0.2), 0, 0) }
end

function Cockpit.eye(spec: any): Vector3?
	local ck = type(spec) == "table" and spec.cockpit
	return if ck and type(ck.eye) == "table" then v3(ck.eye) else nil
end

return Cockpit
