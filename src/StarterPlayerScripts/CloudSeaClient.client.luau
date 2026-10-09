-- CloudSeaClient: the cloud sea under the university is made of slow, soft particle billows. Particle
-- emitters start empty, so each time the cloud sea appears on your screen (when you arrive at the
-- university; ZoneClient hides it everywhere else), every emitter is filled up straight away.
local college = workspace:WaitForChild("SahurCollege")

local function prewarm(sea: Instance)
	local billows = sea:WaitForChild("Billows", 30)
	if not billows then return end
	for _, e in billows:GetDescendants() do
		if e:IsA("ParticleEmitter") then
			e:Clear()
			e:Emit(e:GetAttribute("Prewarm") or 40)
		end
	end
end

college.ChildAdded:Connect(function(child)
	if child.Name == "CloudSea" then task.defer(prewarm, child) end
end)
local sea = college:FindFirstChild("CloudSea")
if sea then task.defer(prewarm, sea) end
