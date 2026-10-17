--[[
SAeditor — ghosts (onion skin, a0.6): the selected model is shown see-through in its pose at
the key before the playhead (blue) and at the key after it (green), so a motion can be judged
without scrubbing back and forth. Only in the editor's viewports, never in a render.

The server works the poses out (SA.StateAt — bone keys included) and sends them on request;
a ghost is a copy of the model whose physical bones are placed from that pose and whose other
bones (fingers, the face) hang on them as they hang on the model now.
]]
local MOD = SPeditor.Mod("saeditor")
local SA  = MOD.SA
local C   = SPeditor.Client

local cvGhosts = CreateClientConVar("saeditor_ghosts", "0", true, false, "SAeditor: show the pose at the keys around the playhead", 0, 1)

local TINT = { { 0.35, 0.6, 1 }, { 0.4, 1, 0.45 } }     -- the key before, the key after
local ALPHA = 0.3

function SA.GhostsOn() return cvGhosts:GetBool() end
function SA.ToggleGhosts() RunConsoleCommand("saeditor_ghosts", cvGhosts:GetBool() and "0" or "1") end

local want = nil          -- what was last asked for: "uid|f1|f2|serial"
local states = {}         -- [slot] = { f, pos, ang, phys, scale } of the shown object
local stateUID = 0
local models = {}         -- [slot] = ClientsideModel
local serial = 0
local nextAsk = 0

MOD:Hook("SAeditor_Changed", function() serial = serial + 1 end, "ghost")

local function removeModels()
	for i, m in pairs(models) do
		if IsValid(m) then m:Remove() end
		models[i] = nil
	end
end

-- the keys around the frame: the last one before it and the first one after it
local function around(uid, frame)
	local before, after
	for _, k in ipairs(SA.tracks[uid] or {}) do
		if k.f < frame - 0.01 then before = k.f elseif k.f > frame + 0.01 and not after then after = k.f end
	end
	return before, after
end

local function target()
	local ent = C.selected
	if not IsValid(ent) or C.IsAux(ent) then return nil end
	local uid = SA.UID(ent)
	if uid == 0 or not SA.tracks[uid] then return nil end
	return ent, uid
end

MOD:Hook("Think", function()
	if not cvGhosts:GetBool() or not C.active or SA.playing or SA.rendering then
		if next(states) then states = {} end
		return
	end
	if RealTime() < nextAsk then return end
	nextAsk = RealTime() + 0.15
	local ent, uid = target()
	if not ent then
		states, want = {}, nil
		return
	end
	local before, after = around(uid, SA.frame)
	local key = table.concat({ uid, before or -1, after or -1, serial }, "|")
	if key == want then return end
	want = key
	if not before and not after then
		states = {}
		return
	end
	MOD:NetStart("Ghost")
	net.WriteUInt(uid, 32)
	local frames = {}
	if before then frames[#frames + 1] = before end
	if after then frames[#frames + 1] = after end
	net.WriteUInt(#frames, 4)
	for _, f in ipairs(frames) do net.WriteUInt(f, 32) end
	net.SendToServer()
end, "ghost")

MOD:NetReceive("Ghost", function()
	local t = SPeditor.ReadTable()
	if not istable(t) then return end
	local ent, uid = target()
	if not ent or uid ~= tonumber(t.uid) then return end
	local before, after = around(uid, SA.frame)
	states, stateUID = {}, uid
	for _, st in ipairs(istable(t.states) and t.states or {}) do
		if isvector(st.pos) and isangle(st.ang) then
			local slot = (tonumber(st.f) == before) and 1 or ((tonumber(st.f) == after) and 2 or nil)
			if slot then states[slot] = st end
		end
	end
end)

-- the model of a slot: a copy of the selected model, its bones set by the callback below
local function ghostModel(slot, ent)
	local m = models[slot]
	local mdl = ent:GetModel()
	if IsValid(m) and m.SAModel == mdl then return m end
	if IsValid(m) then m:Remove() end
	m = ClientsideModel(mdl, RENDERGROUP_TRANSLUCENT)
	if not IsValid(m) then return nil end
	m:SetNoDraw(true)
	m.SAModel = mdl
	m:AddCallback("BuildBonePositions", function(g, nb)
		local st, rel, src = g.SAState, g.SARel, g.SASource
		if not st or not rel or not IsValid(src) then return end
		local world = {}
		for b = 0, nb - 1 do
			local mtx
			local w = g.SAPhys[b]
			if w then
				mtx = Matrix()
				mtx:SetTranslation(w[1])
				mtx:SetAngles(w[2])
			else
				local par = src:GetBoneParent(b)
				if rel.local_[b] and par and par >= 0 and world[par] then
					mtx = world[par] * rel.local_[b]
				else
					mtx = rel.world[b]
				end
			end
			if mtx then
				world[b] = mtx
				-- bones the model does not use at this level of detail are not set up and
				-- cannot be written
				if g:GetBoneMatrix(b) then g:SetBoneMatrix(b, mtx) end
			end
		end
	end)
	models[slot] = m
	return m
end

-- the bones of the model now, each relative to its parent (the bones that have no pose in the
-- ghost data hang on their parents the same way)
local function relations(ent)
	ent:SetupBones()
	local rel = { local_ = {}, world = {} }
	for b = 0, ent:GetBoneCount() - 1 do
		local mb = ent:GetBoneMatrix(b)
		if mb then
			rel.world[b] = mb
			local par = ent:GetBoneParent(b)
			local mp = par and par >= 0 and ent:GetBoneMatrix(par)
			if mp then rel.local_[b] = mp:GetInverseTR() * mb end
		end
	end
	return rel
end

local function drawGhost(slot, ent, st)
	local g = ghostModel(slot, ent)
	if not IsValid(g) then return end
	g.SAState, g.SASource = st, ent
	g:SetPos(st.pos)
	g:SetAngles(st.ang)
	g:SetSkin(ent:GetSkin())
	if C.IsRagdoll(ent) then
		-- physical bones from the pose: the root at the snapshot place, the rest relative to it
		local phys = {}
		local root = ent:TranslatePhysBoneToBone(0)
		if root and root >= 0 then phys[root] = { st.pos, st.ang } end
		for i, p in pairs(istable(st.phys) and st.phys or {}) do
			i = tonumber(i)
			local b = i and ent:TranslatePhysBoneToBone(i)
			if b and b >= 0 and istable(p) and isvector(p.p) and isangle(p.a) then
				local wp, wa = LocalToWorld(p.p, p.a, st.pos, st.ang)
				phys[b] = { wp, wa }
			end
		end
		g.SAPhys = phys
	else
		-- a prop: the whole model at the place of the key
		g.SAPhys = {}
		g:SetModelScale(tonumber(st.scale) or ent:GetModelScale() or 1)
	end
	g.SARel = relations(ent)
	if not C.IsRagdoll(ent) then g.SARel = nil end
	g:InvalidateBoneCache()
	local tint = TINT[slot]
	render.SetBlend(ALPHA)
	render.SetColorModulation(tint[1], tint[2], tint[3])
	g:DrawModel()
	render.SetColorModulation(1, 1, 1)
	render.SetBlend(1)
end

MOD:Hook("PostDrawTranslucentRenderables", function(depth, sky)
	if depth or sky or not C.active or C.hideUI or C.exporting or C.vpPass == "secondary" then return end
	if not cvGhosts:GetBool() or SA.playing or SA.rendering or not next(states) then return end
	local ent, uid = target()
	if not ent or uid ~= stateUID then return end
	for slot = 1, 2 do
		local st = states[slot]
		if st then
			local ok, err = pcall(drawGhost, slot, ent, st)
			if not ok then
				render.SetColorModulation(1, 1, 1)
				render.SetBlend(1)
				ErrorNoHalt("[SAeditor] ghost: " .. tostring(err) .. "\n")
				states[slot] = nil
			end
		end
	end
end, "ghost")

MOD:Hook("SPeditor_StateChanged", function(on)
	if not on then
		removeModels()
		states, want = {}, nil
	end
end, "ghost")
