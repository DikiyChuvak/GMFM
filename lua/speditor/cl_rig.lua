--[[
SPeditor — the character rig (a0.9, as SFM's rig_biped).

With the rig on (R, the doll button on the Primary Viewport bar) the selected character shows
controls instead of having to hit small bone markers:

  hands, feet     boxes        — pull the limb (IK: shoulder-elbow-hand, thigh-knee-foot)
  elbows, knees   diamonds     — turn the bend of the limb (the pole: where the knee points),
                                 the hand / foot stays where it is
  pelvis          a big ring   — moves the body, the planted feet stay on the ground
  spine, neck,    rings        — turn (the rotate gizmo)
  head

Left-side controls are blue, right-side ones orange, the middle ones green (the selected one
yellow, the one under the cursor brighter). A control is a bone: picking it selects the bone,
keys and undo work as for any bone.

Own IK chains (the bone menu → IK chain…): any bone can be the end of a two-link chain with
the two bones above it picked by hand (a model with twist bones between the shoulder and the
forearm, a tail, a wing, the calf and the forearm of an SFM model). Saved per model in
data/speditor/ik/<crc of the model>.json as { [end bone] = { mid = bone, root = bone } }.

  C.RigOn() / C.SetRig(on)
  SPeditor.Rig.ChainFor(ent, bone, phys)   root, mid of the IK chain ending at bone (or nil)
  SPeditor.Rig.PoleOf(ent, bone, phys)     end, root when bone is the middle of a chain
  SPeditor.Rig.Controls(ent)               { { bone, kind = "end"|"pole"|"root"|"fk", side }, … }
  SPeditor.Rig.Pick(ent)                   the control under the cursor
  SPeditor.Rig.Draw(ent)
]]
SPeditor = SPeditor or {}
SPeditor.Rig = SPeditor.Rig or {}
local Rig = SPeditor.Rig
local C   = SPeditor.Client
local L   = SPeditor.L

local cvRig = CreateClientConVar("gmfm_rig", "0", true, false, "Character rig controls in the viewport (as SFM's rig)")
-- size and line width of the controls (b0.1: on a face or a hand close up they covered what was
-- being posed), times the default; head = false leaves out the rings of the spine, neck and head
local cvSize  = CreateClientConVar("gmfm_rig_size", "1", true, false, "Rig control size, times the default (0.2..3)")
local cvWidth = CreateClientConVar("gmfm_rig_width", "1", true, false, "Rig line width, times the default (0.2..3)")
local cvRings = CreateClientConVar("gmfm_rig_rings", "1", true, false, "Rig: show the rings of the spine, neck and head")
C.RIG_SIZES = { 0.35, 0.6, 1, 1.5 }
function C.GetRigSize() return math.Clamp(cvSize:GetFloat(), 0.2, 3) end
function C.GetRigWidth() return math.Clamp(cvWidth:GetFloat(), 0.2, 3) end
function C.RigRings() return cvRings:GetBool() end
function C.RigOn() return cvRig:GetBool() end
function C.SetRig(on) RunConsoleCommand("gmfm_rig", on and "1" or "0") end

---------------------------------------------------------------------
-- Own IK chains
---------------------------------------------------------------------
local DIR = "speditor/ik"
local custom = {}           -- [model] = { [end bone name] = { mid = name, root = name } }

local function chainFile(model) return DIR .. "/" .. util.CRC(string.lower(model or "")) .. ".json" end

function Rig.Custom(model)
	model = string.lower(model or "")
	if custom[model] == nil then
		local t = util.JSONToTable(file.Read(chainFile(model), "DATA") or "") or {}
		custom[model] = istable(t) and t or {}
	end
	return custom[model]
end

-- midName / rootName = nil: the bone is no longer the end of an own chain
function Rig.SetCustom(model, endName, midName, rootName)
	local t = Rig.Custom(model)
	t[endName] = (midName and rootName) and { mid = midName, root = rootName } or nil
	file.CreateDir(DIR)
	file.Write(chainFile(model), util.TableToJSON(t, true))
	Rig.cache = {}
end

-- the nearest ancestor of a bone that is a physics bone (phys) or any bone
local function upFrom(ent, bone, phys)
	local b, guard = ent:GetBoneParent(bone), 0
	while b and b >= 0 and guard < 256 do
		if not phys or C.PhysIndexOfBone(ent, b) then return b end
		b = ent:GetBoneParent(b)
		guard = guard + 1
	end
end

function Rig.ChainFor(ent, bone, phys)
	if not IsValid(ent) or not bone or bone < 0 then return nil end
	local name = ent:GetBoneName(bone) or ""
	local own = Rig.Custom(ent:GetModel())[name]
	if own then
		local mid, root = ent:LookupBone(own.mid), ent:LookupBone(own.root)
		if mid and root and (not phys or (C.PhysIndexOfBone(ent, mid) and C.PhysIndexOfBone(ent, root) and C.PhysIndexOfBone(ent, bone))) then
			return root, mid
		end
	end
	if not SPeditor.IK.IsEndEffector(name) then return nil end
	if phys and not C.PhysIndexOfBone(ent, bone) then return nil end
	local mid = upFrom(ent, bone, phys)
	local root = mid and upFrom(ent, mid, phys)
	if mid and root then return root, mid end
end

-- bone as the middle (elbow, knee) of a chain: the end of that chain and its root
function Rig.PoleOf(ent, bone, phys)
	for _, c in ipairs(Rig.Controls(ent)) do
		if c.kind == "end" and c.mid == bone then return c.bone, c.root end
	end
end

---------------------------------------------------------------------
-- Controls of a model
---------------------------------------------------------------------
Rig.cache = Rig.cache or {}

local function sideOf(name)
	local n = "_" .. string.lower(name) .. "_"
	if string.find(n, "[_%.%s]l[_%.%s]") or string.find(n, "left", 1, true) then return "L" end
	if string.find(n, "[_%.%s]r[_%.%s]") or string.find(n, "right", 1, true) then return "R" end
	return "C"
end

local FK = { "spine", "chest", "neck", "head" }

function Rig.Controls(ent)
	if not IsValid(ent) then return {} end
	local phys = C.IsRagdoll(ent)
	local key = (ent:GetModel() or "") .. "|" .. ent:GetBoneCount() .. "|" .. tostring(phys)
	local list = Rig.cache[key]
	if list then return list end
	list = {}
	local used = {}
	for b = 0, ent:GetBoneCount() - 1 do
		local root, mid = Rig.ChainFor(ent, b, phys)
		if root then
			local side = sideOf(ent:GetBoneName(b) or "")
			list[#list + 1] = { bone = b, kind = "end", side = side, root = root, mid = mid }
			list[#list + 1] = { bone = mid, kind = "pole", side = side }
			used[b], used[mid], used[root] = true, true, true
		end
	end
	-- the pelvis: the first physics body of a ragdoll, else a bone called so (or the first one)
	local pelvis = phys and ent:TranslatePhysBoneToBone(0) or nil
	if not pelvis or pelvis < 0 then
		pelvis = ent:LookupBone("ValveBiped.Bip01_Pelvis")
		for b = 0, ent:GetBoneCount() - 1 do
			if pelvis then break end
			if string.find(string.lower(ent:GetBoneName(b) or ""), "pelvis", 1, true) then pelvis = b end
		end
	end
	if pelvis and pelvis >= 0 then
		list[#list + 1] = { bone = pelvis, kind = "root", side = "C" }
		used[pelvis] = true
	end
	for b = 0, ent:GetBoneCount() - 1 do
		local n = string.lower(ent:GetBoneName(b) or "")
		if not used[b] and (not phys or C.PhysIndexOfBone(ent, b)) then
			for _, w in ipairs(FK) do
				if string.find(n, w, 1, true) then
					list[#list + 1] = { bone = b, kind = "fk", side = sideOf(n) }
					used[b] = true
					break
				end
			end
		end
	end
	Rig.cache[key] = list
	return list
end

---------------------------------------------------------------------
-- Picking and drawing
---------------------------------------------------------------------
local PICK_PX = 18

function Rig.Pick(ent)
	if not C.RigOn() or not IsValid(ent) or C.IsAux(ent) then return nil end
	local mx, my = gui.MousePos()
	local best, bestD
	local k = math.Clamp(C.GetRigSize(), 0.5, 2)
	for _, c in ipairs(Rig.Controls(ent)) do
		local p = (c.kind ~= "fk" or C.RigRings()) and C.GetBoneWorld(ent, c.bone)
		if p then
			local x, y, vis = C.ProjectToViewport(p)
			if vis then
				local d = math.sqrt((x - mx) ^ 2 + (y - my) ^ 2)
				-- the ring of the pelvis is picked by its size
				local r = (c.kind == "root" and PICK_PX * 2 or PICK_PX) * k
				if d < r and (not bestD or d < bestD) then best, bestD = c, d end
			end
		end
	end
	return best
end

local SIDE_COL = { L = Color(70, 150, 255), R = Color(255, 140, 50), C = Color(90, 220, 110) }
local COL_SEL  = Color(255, 225, 60)

local function ring(pos, axis, r, col, width)
	local u = axis:Angle():Right()
	local v = axis:Cross(u)
	local prev
	for s = 0, 32 do
		local a = s / 32 * math.pi * 2
		local p = pos + (u * math.cos(a) + v * math.sin(a)) * r
		if prev then render.DrawBeam(prev, p, width, 0, 1, col) end
		prev = p
	end
end

function Rig.Draw(ent)
	if not C.RigOn() or not IsValid(ent) or C.IsAux(ent) then return end
	render.SetColorMaterialIgnoreZ()
	local vp = C.GetView()
	local hov = C.hoverRig
	local size, width = C.GetRigSize(), C.GetRigWidth()
	for _, c in ipairs(Rig.Controls(ent)) do
		local p, a
		if c.kind ~= "fk" or C.RigRings() then p, a = C.GetBoneWorld(ent, c.bone) end
		if p then
			local s = math.max(p:Distance(vp) * 0.022 * size, 0.3)
			local col = SIDE_COL[c.side] or SIDE_COL.C
			local hot = hov and hov.bone == c.bone
			if c.bone == C.selBone and ent == C.selected then col = COL_SEL end
			local alpha = hot and 255 or 190
			local fill = Color(col.r, col.g, col.b, hot and 120 or 60)
			local line = Color(col.r, col.g, col.b, alpha)
			local w = s * (hot and 0.22 or 0.12) * width / math.sqrt(size)
			if c.kind == "end" then
				local half = Vector(s, s, s)
				render.DrawBox(p, a, -half, half, fill)
				render.DrawWireframeBox(p, a, -half, half, line, false)
			elseif c.kind == "pole" then
				local d = s * 0.8
				local ax = { a:Forward(), a:Right(), a:Up() }
				for i = 1, 3 do render.DrawBeam(p - ax[i] * d, p + ax[i] * d, w, 0, 1, line) end
				render.DrawSphere(p, d * 0.45, 6, 6, fill)
			elseif c.kind == "root" then
				ring(p, Vector(0, 0, 1), s * 3.2, line, w * 1.4)
			else
				ring(p, a:Forward(), s * 1.8, line, w)
			end
		end
	end
end

-- the name of a control for the status line and its tooltip
function Rig.Label(ent, c)
	local n = string.gsub(ent:GetBoneName(c.bone) or "", "^ValveBiped%.Bip01_", "")
	return L("rig_kind_" .. c.kind) .. ": " .. n
end

---------------------------------------------------------------------
-- The bone menu: an own IK chain ending at this bone
---------------------------------------------------------------------
function Rig.ChainMenu(m, ent, bone)
	if not IsValid(ent) or not bone or bone < 0 then return end
	local name = ent:GetBoneName(bone) or ""
	local short = function(n) return (string.gsub(n or "", "^ValveBiped%.Bip01_", "")) end
	local sub, opt = m:AddSubMenu(L("rig_chain"))
	if opt and opt.SetIcon then opt:SetIcon("icon16/link.png") end
	-- the ancestors of the bone: the middle and the root are picked among them
	local ups, b = {}, ent:GetBoneParent(bone)
	while b and b >= 0 and #ups < 8 do
		ups[#ups + 1] = b
		b = ent:GetBoneParent(b)
	end
	local cur = Rig.Custom(ent:GetModel())[name]
	for i = 1, #ups - 1 do
		local mid = ups[i]
		local midMenu = sub:AddSubMenu(string.format(L("rig_chain_mid"), short(ent:GetBoneName(mid))))
		for j = i + 1, #ups do
			local root = ups[j]
			midMenu:AddOption(string.format(L("rig_chain_root"), short(ent:GetBoneName(root))), function()
				Rig.SetCustom(ent:GetModel(), name, ent:GetBoneName(mid), ent:GetBoneName(root))
				SPeditor.Notify(string.format(L("rig_chain_set"), short(name), short(ent:GetBoneName(mid)), short(ent:GetBoneName(root))), 2)
			end):SetChecked(cur and cur.mid == ent:GetBoneName(mid) and cur.root == ent:GetBoneName(root) or false)
		end
	end
	if cur then
		sub:AddSpacer()
		sub:AddOption(L("rig_chain_clear"), function() Rig.SetCustom(ent:GetModel(), name, nil, nil) end):SetIcon("icon16/cross.png")
	end
end
