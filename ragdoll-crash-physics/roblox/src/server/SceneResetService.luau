--!nonstrict
-- Remembers where every loose prop started and puts the whole scene back on request.
local SceneResetService = {}
local props = {} :: { { part: BasePart, cf: CFrame } }

function SceneResetService.capture(folder: Instance)
	table.clear(props)
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") and not d.Anchored then
			table.insert(props, { part = d, cf = d.CFrame })
		end
	end
end

function SceneResetService.resetProps()
	for _, p in props do
		if p.part.Parent then
			p.part.AssemblyLinearVelocity, p.part.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
			p.part.CFrame = p.cf
		end
	end
end

-- Props knocked more than 4 studs from where they started (used by the crash report).
function SceneResetService.countDisturbed(): number
	local n = 0
	for _, p in props do
		if p.part.Parent and (p.part.Position - p.cf.Position).Magnitude > 4 then
			n += 1
		end
	end
	return n
end

return SceneResetService
