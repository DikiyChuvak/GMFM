-- Selection, object list, mouse picking, bones in world coordinates.
-- Mouse rays and point projection are computed relative to the Primary Viewport
-- rectangle (the view lives in a window, not full screen).
SPeditor.Client = SPeditor.Client or {}
local C = SPeditor.Client

function C.IsLight(e)   return IsValid(e) and e:GetClass() == "speditor_light" end
function C.IsCamera(e)  return IsValid(e) and e:GetClass() == "speditor_camera" end
function C.IsRagdoll(e) return IsValid(e) and e:GetClass() == "prop_ragdoll" end
function C.IsEffect(e)  return IsValid(e) and e:GetClass() == "speditor_effect" end
function C.IsAux(e)     return C.IsLight(e) or C.IsCamera(e) or C.IsEffect(e) end

-- An editor object that belongs to this player. On a server with several
-- editors other players' objects are visible in the world but do not get into the list,
-- mouse picking or history (the server would not let you change them anyway). Every
-- player has own object UIDs, so without the owner check undo could find someone else's object.
function C.IsMine(e)
	if not SPeditor.IsEditable(e) then return false end
	local owner = e:GetNW2Entity("SPeditor_OwnerPly")
	return not IsValid(owner) or owner == LocalPlayer()
end

local objects, nextScan = {}, 0
function C.Objects()
	if RealTime() >= nextScan then
		nextScan = RealTime() + 0.5
		objects = {}
		for _, e in ipairs(ents.GetAll()) do
			if C.IsMine(e) then objects[#objects + 1] = e end
		end
	end
	return objects
end

local listCache, listCacheFor

function C.BuildEntityList()
	local scan = C.Objects()
	if listCache and listCacheFor == scan then return listCache end
	local objs = {}
	for _, e in ipairs(scan) do
		if IsValid(e) then objs[#objs + 1] = e end
	end
	table.sort(objs, function(a, b) return a:EntIndex() < b:EntIndex() end)
	local list, counters = {}, {}
	-- an object whose fields are not readable yet (its networked values still on the way) is
	-- named by its class instead of breaking the whole list (the Animation Set Editor tree,
	-- the timeline, the menus are all built from it)
	local function describe(e)
		local kind, base
		if C.IsLight(e) then
			-- the name depends on the light type: Spot Light N / Point Light N
			kind = "light"
			base = SPeditor.L((e:GetLightType() == 1) and "obj_name_spot" or "obj_name_point")
		elseif C.IsCamera(e) then
			kind, base = "camera", SPeditor.L("obj_name_camera")
		elseif C.IsEffect(e) then
			kind, base = "effect", e:GetFxName()
			if base == "" then base = SPeditor.L("obj_name_effect") end
		else
			kind = C.IsRagdoll(e) and "ragdoll" or "prop"
			base = string.StripExtension(string.GetFileFromFilename(e:GetModel() or "prop") or "prop")
		end
		return kind, base
	end
	for _, e in ipairs(objs) do
		local ok, kind, base = pcall(describe, e)
		if not ok or not isstring(base) or base == "" then
			kind = (C.IsLight(e) and "light") or (C.IsCamera(e) and "camera") or (C.IsEffect(e) and "effect")
				or (C.IsRagdoll(e) and "ragdoll") or "prop"
			base = e:GetClass()
		end
		counters[base] = (counters[base] or 0) + 1
		local custom = e:GetNW2String("SPeditor_Name", "")
		list[#list + 1] = {
			ent = e,
			name = (custom ~= "") and custom or (base .. " " .. counters[base]),
			custom = custom ~= "",
			class = e:GetClass(), kind = kind,
			ltype = C.IsLight(e) and e:GetLightType() or nil,
			parent = e:GetNW2Entity("SPeditor_Parent"),
			hidden = e:GetNW2Bool("SPeditor_Hidden", false),
			locked = e:GetNW2Bool("SPeditor_Locked", false),
		}
	end
	listCache, listCacheFor = list, scan
	return list
end

function C.IsHidden(e) return IsValid(e) and e:GetNW2Bool("SPeditor_Hidden", false) end
function C.IsLocked(e) return IsValid(e) and e:GetNW2Bool("SPeditor_Locked", false) end

-- Hidden models are not drawn (NoDraw on the client); everything comes back when the editor is left.
local nextVis = 0
SPeditor.Hook("Think", "SPeditor.ApplyVisibility", function()
	if RealTime() < nextVis then return end
	nextVis = RealTime() + 0.3
	for _, e in ipairs(C.Objects()) do
		if IsValid(e) and not C.IsAux(e) then
			local hide = C.active and C.IsHidden(e) or false
			if e.SPHidden ~= hide then
				e.SPHidden = hide
				e:SetNoDraw(hide)
			end
		end
	end
end)

-- Stretching along axes and a disabled shadow (extended properties, see S.ApplyLook).
-- Stretching is a scale matrix at draw time; the render bounds stretch
-- with the model, otherwise it would be clipped at the frame edge. The shadow in the spot
-- lights' shadow maps is removed by skipping the model in the depth pass.
-- Applies to all editor objects, including other players' and outside the editor.
local ONE = Vector(1, 1, 1)
local looked, nextLookScan = {}, 0
local STUDIO_SHADOWDEPTH = STUDIO_SHADOWDEPTHTEXTURE or 0x40000000

-- Colours of material slots (a0.8, look.tints): the slot is drawn with a copy of its material
-- whose $color2 ($color for unlit shaders) is multiplied by the colour. The copy is made from
-- the text of the .vmt (a "patch" material is merged into the one it includes): the values the
-- engine reports for a loaded material include its internal flags and defaults, which do not
-- make a working material again.
local tintCache = {}
local function readVMT(path, depth)
	local raw = file.Read("materials/" .. path .. ".vmt", "GAME")
	if not raw then return nil end
	local shader = string.match(raw, "^%s*\"?([%w_]+)\"?")
	local kv = util.KeyValuesToTable(raw)
	if not shader or not istable(kv) then return nil end
	if string.lower(shader) == "patch" and (depth or 0) < 3 then
		local inc = kv.include
		if not isstring(inc) then return nil end
		inc = string.gsub(string.gsub(string.lower(inc), "^materials/", ""), "%.vmt$", "")
		local bshader, bkv = readVMT(inc, (depth or 0) + 1)
		if not bshader then return nil end
		for _, part in ipairs({ kv.insert, kv.replace }) do
			if istable(part) then for k, v in pairs(part) do bkv[k] = v end end
		end
		return bshader, bkv
	end
	kv.include, kv.insert, kv.replace = nil, nil, nil
	return shader, kv
end

local function vec3(v)
	if isnumber(v) then return v, v, v end
	if isstring(v) then
		local a, b, c = string.match(v, "([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)")
		if a then
			local x, y, z = tonumber(a), tonumber(b), tonumber(c)
			-- {255 128 0} is in 0..255
			if string.find(v, "{", 1, true) then return x / 255, y / 255, z / 255 end
			return x, y, z
		end
		local n = tonumber(v)
		if n then return n, n, n end
	end
	return 1, 1, 1
end

function C.TintMaterial(path, col)
	if not isstring(path) or path == "" then return nil end
	path = string.lower(string.gsub(path, "\\", "/"))
	local key = string.format("%s|%d,%d,%d", path, col[1], col[2], col[3])
	local m = tintCache[key]
	if m ~= nil then return m or nil end
	tintCache[key] = false
	local shader, kv = readVMT(path)
	if not shader then return nil end
	local unlit = string.find(string.lower(shader), "unlit", 1, true) ~= nil
	local field = unlit and "$color" or "$color2"
	-- player models: a proxy writes the player colour into $color2, and $blendtintbybasealpha
	-- applies $color2 only to the masked part — the colour must cover the whole material
	if istable(kv.proxies) then
		for name, p in pairs(kv.proxies) do
			if string.lower(tostring(name)) == "playercolor" or (istable(p) and isstring(p.resultvar)
				and string.lower(p.resultvar) == field and string.lower(tostring(p.srcvar1 or "")) ~= field) then
				kv.proxies[name] = nil
			end
		end
	end
	local masked = tonumber(kv["$blendtintbybasealpha"]) == 1
	kv["$blendtintbybasealpha"] = nil
	local x, y, z = vec3(kv[field])
	if masked then x, y, z = 1, 1, 1 end
	kv[field] =string.format("[%.4f %.4f %.4f]", x * col[1] / 255, y * col[2] / 255, z * col[3] / 255)
	local ok, mat = pcall(CreateMaterial, "speditor_tint3_" .. util.CRC(key), shader, kv)
	if not ok or not mat or mat:IsError() then return nil end
	tintCache[key] = mat
	return mat
end

-- the material put on a slot: the engine's own (slots 0..31) or one the client draws (32 and on)
local function slotMaterial(e, idx)
	if idx < 32 then
		local sub = e:GetSubMaterial(idx)
		return (sub and sub ~= "") and sub or nil
	end
	for i, m in string.gmatch(e:GetNW2String("SPeditor_SubMats", ""), "(%d+):([^;]+)") do
		if tonumber(i) == idx then return m end
	end
end

-- { [slot] = material } for an object with slot colours or with materials on slots past the
-- engine's 32 (nil when it has neither)
local function tintMats(e)
	local str = e:GetNW2String("SPeditor_Tints", "")
	local extra = e:GetNW2String("SPeditor_SubMats", "")
	if str == "" and extra == "" then return nil end
	local slots = e:GetMaterials() or {}
	local whole = e:GetMaterial() or ""
	local out
	for idx, m in string.gmatch(extra, "(%d+):([^;]+)") do
		local mat = whole == "" and Material(m) or nil
		if mat and not mat:IsError() then
			out = out or {}
			out[tonumber(idx)] = mat
		end
	end
	for idx, r, g, b in string.gmatch(str, "(%d+):(%d+),(%d+),(%d+)") do
		idx = tonumber(idx)
		local sub = slotMaterial(e, idx)
		local path = sub or (whole ~= "" and whole or slots[idx + 1])
		local mat = C.TintMaterial(path, { tonumber(r), tonumber(g), tonumber(b) })
		if mat then
			out = out or {}
			out[idx] = mat
		end
	end
	return out
end

-- the draw of an object with a look of its own: no shadow in the spot lights' shadow maps,
-- coloured material slots
local function noShadowDraw(self, flags)
	if self.SPNoShadow and flags and bit.band(flags, STUDIO_SHADOWDEPTH) ~= 0 then return end
	local t = self.SPTintMats
	if t then
		for idx, mat in pairs(t) do render.MaterialOverrideByIndex(idx, mat) end
		self:DrawModel(flags)
		render.MaterialOverrideByIndex()
		return
	end
	self:DrawModel(flags)
end

-- The engine's blob / render-to-texture shadow of a prop falls along the map's light
-- (shadow_control), whatever lights the scene has. With gmfm_shadow_onlylights (Shadows
-- tab, on by default) the objects of the scene drop it while the editor is open: their
-- shadows come only from the editor's spot and point lights (shadow maps, cl_shadows.lua).
local function wantsBlob(e)
	if e.SPNoShadow then return false end
	local Sh = SPeditor.Shadows
	return not (C.active and Sh and Sh.OnlyLights and Sh.OnlyLights())
end

local function applyLook(e)
	local st = e:GetNW2Vector("SPeditor_Stretch", ONE)
	if e.SPStretch ~= st then
		e.SPStretch = Vector(st.x, st.y, st.z)
		e.SPBounds = e.SPBounds or { e:GetRenderBounds() }
		if st:DistToSqr(ONE) < 1e-6 then
			e:DisableMatrix("RenderMultiply")
			e:SetRenderBounds(e.SPBounds[1], e.SPBounds[2])
		else
			local m = Matrix()
			m:Scale(st)
			e:EnableMatrix("RenderMultiply", m)
			e:SetRenderBounds(e.SPBounds[1] * st, e.SPBounds[2] * st)
		end
	end
	local ns = e:GetNW2Bool("SPeditor_NoShadow", false)
	local blob = not ns and wantsBlob(e)
	if e.SPBlob ~= blob then
		e.SPBlob = blob
		e:DrawShadow(blob)
	end
	local tints = e:GetNW2String("SPeditor_Tints", "")
	local extra = e:GetNW2String("SPeditor_SubMats", "")
	local tintKey = tints .. "#" .. extra
	if tints ~= "" or extra ~= "" then
		tintKey = tintKey .. "|" .. (e:GetMaterial() or "") .. "|" .. (e:GetModel() or "")
		for idx in string.gmatch(tints, "(%d+):") do tintKey = tintKey .. "|" .. (slotMaterial(e, tonumber(idx)) or "") end
	end
	if e.SPTintKey ~= tintKey then
		e.SPTintKey = tintKey
		e.SPTintMats = tintKey ~= "#" and tintMats(e) or nil
	end
	local own = ns or e.SPTintMats ~= nil
	if e.SPNoShadow ~= ns or e.SPOwnDraw ~= own then
		e.SPNoShadow, e.SPOwnDraw = ns, own
		if own then
			if not e.SPWorn then e.RenderOverride = noShadowDraw end
		elseif e.RenderOverride == noShadowDraw then
			e.RenderOverride = nil
		end
	end
end

-- "Worn" objects (attached with "Wear", S.WEAR on the server): clothing made for the same
-- skeleton must bend with the wearer's bones, so it is drawn by a client-side copy merged into the
-- wearer's bones (EF_BONEMERGE); the object itself stays invisible at its rigid place, where it
-- can still be clicked and selected.
local function drawNothing() end

local function dropWorn(e)
	if IsValid(e.SPWorn) then e.SPWorn:Remove() end
	e.SPWorn = nil
	if e.RenderOverride == drawNothing then e.RenderOverride = e.SPOwnDraw and noShadowDraw or nil end
end

-- The bones of the copy that the wearer has too are copied from the wearer by the engine, and
-- it ignores their offsets (b0.1, a Workshop report: the bones of a worn object could not be
-- edited). Here the object's offsets are put on such bones the way the engine puts them on any
-- other bone (position in the parent's space, turn and size in the bone's own), and every bone
-- below follows.
local mxDelta = {}
local function wornBones(csm, n)
	local e = csm.SPWornOf
	if not IsValid(e) or not e:HasBoneManipulations() then return end
	local parent = csm:GetParent()
	if not IsValid(parent) then return end
	local merged = csm.SPMerged
	if not merged or csm.SPMergedOf ~= parent:GetModel() then
		merged = {}
		for b = 0, csm:GetBoneCount() - 1 do
			local name = csm:GetBoneName(b)
			merged[b] = name ~= nil and parent:LookupBone(name) ~= nil
		end
		csm.SPMerged, csm.SPMergedOf = merged, parent:GetModel()
	end
	local D = mxDelta
	for k in pairs(D) do D[k] = nil end
	for b = 0, n - 1 do
		local m = csm:GetBoneMatrix(b)
		if m then
			local pb = csm:GetBoneParent(b)
			local dp = pb >= 0 and D[pb] or nil
			local mp, ma, ms = vector_origin, angle_zero, nil
			if merged[b] then
				mp, ma, ms = e:GetManipulateBonePosition(b), e:GetManipulateBoneAngles(b), e:GetManipulateBoneScale(b)
			end
			local moves = mp ~= vector_origin or ma ~= angle_zero
			local sized = ms ~= nil and (ms.x ~= 1 or ms.y ~= 1 or ms.z ~= 1)
			if dp or moves or sized then
				local nm = dp and dp * m or Matrix(m)
				if moves then
					if mp ~= vector_origin then
						local pm = pb >= 0 and csm:GetBoneMatrix(pb)
						local off = Vector(mp)
						if pm then off:Rotate(pm:GetAngles()) end
						nm:SetTranslation(nm:GetTranslation() + off)
					end
					if ma ~= angle_zero then nm:Rotate(ma) end
				end
				if dp or moves then D[b] = nm * m:GetInverseTR() end
				if sized then nm:Scale(ms) end
				csm:SetBoneMatrix(b, nm)
			end
		end
	end
end

local function applyWorn(e)
	local parent = e:GetNW2Bool("SPeditor_Merge", false) and C.AttachParent(e) or nil
	if not parent then
		if e.SPWorn ~= nil then dropWorn(e) end
		return
	end
	local csm = e.SPWorn
	if not IsValid(csm) or csm:GetModel() ~= e:GetModel() or csm:GetParent() ~= parent then
		if IsValid(csm) then csm:Remove() end
		csm = ClientsideModel(e:GetModel(), RENDERGROUP_OPAQUE)
		if not IsValid(csm) then return end
		csm:SetParent(parent)
		csm:SetLocalPos(vector_origin)
		csm:SetLocalAngles(angle_zero)
		csm:AddEffects(bit.bor(EF_BONEMERGE, EF_BONEMERGE_FASTCULL))
		csm.SPWornOf = e
		csm:AddCallback("BuildBonePositions", wornBones)
		e.SPWorn = csm
		-- the object itself is never drawn, so the engine never reads its skeleton: its bone
		-- names stayed "__INVALIDBONE__" and the bone list of a worn object was empty
		e:SetupBones()
		e:CallOnRemove("SPeditor.Worn", function(ent) if IsValid(ent.SPWorn) then ent.SPWorn:Remove() end end)
	end
	e.RenderOverride = drawNothing
	-- the copy looks like the object: skin, bodygroups, colour, material, hidden, shadow
	if csm:GetSkin() ~= e:GetSkin() then csm:SetSkin(e:GetSkin()) end
	for i = 0, e:GetNumBodyGroups() - 1 do
		local v = e:GetBodygroup(i)
		if csm:GetBodygroup(i) ~= v then csm:SetBodygroup(i, v) end
	end
	local col = e:GetColor()
	if csm:GetColor() ~= col then
		csm:SetColor(col)
		csm:SetRenderMode(col.a < 255 and RENDERMODE_TRANSCOLOR or RENDERMODE_NORMAL)
	end
	if csm:GetMaterial() ~= e:GetMaterial() then csm:SetMaterial(e:GetMaterial()) end
	-- the materials of single slots too (a0.9: a worn object kept its own textures)
	for i = 0, math.min(#(e:GetMaterials() or {}), 32) - 1 do
		local m = e:GetSubMaterial(i) or ""
		if (csm:GetSubMaterial(i) or "") ~= m then csm:SetSubMaterial(i, m ~= "" and m or nil) end
	end
	csm:SetNoDraw(e:GetNoDraw() or parent:GetNoDraw())
	csm:DrawShadow(e.SPBlob ~= false)
	csm.SPNoShadow, csm.SPTintMats = e.SPNoShadow, e.SPTintMats
	csm.RenderOverride = e.SPOwnDraw and noShadowDraw or nil
	-- bone offsets of the worn object (its own bones the wearer lacks: hair, coat tails,
	-- straps; the merged ones follow the wearer anyway)
	if e:HasBoneManipulations() or csm.SPManip then
		csm.SPManip = e:HasBoneManipulations() or nil
		for b = 0, math.min(e:GetBoneCount(), csm:GetBoneCount()) - 1 do
			local ma, mp, ms = e:GetManipulateBoneAngles(b), e:GetManipulateBonePosition(b), e:GetManipulateBoneScale(b)
			if csm:GetManipulateBoneAngles(b) ~= ma then csm:ManipulateBoneAngles(b, ma) end
			if csm:GetManipulateBonePosition(b) ~= mp then csm:ManipulateBonePosition(b, mp) end
			if csm:GetManipulateBoneScale(b) ~= ms then csm:ManipulateBoneScale(b, ms) end
		end
	end
	-- TF2 paint and crit glow (Hat Painter & Crit Glow Tools): their material proxies read
	-- the drawn entity's ProxyentPaintColor / ProxyentCritGlow, and the copy is what is drawn
	if (csm.SPProxyScan or 0) < RealTime() then
		csm.SPProxyScan = RealTime() + 0.5
		local et, ct = e:GetTable(), csm:GetTable()
		for k, v in pairs(et) do
			if isstring(k) and string.sub(k, 1, 8) == "Proxyent" and ct[k] ~= v then ct[k] = v end
		end
		for k in pairs(ct) do
			if isstring(k) and string.sub(k, 1, 8) == "Proxyent" and et[k] == nil then ct[k] = nil end
		end
	end
end

SPeditor.Hook("Think", "SPeditor.ApplyLook", function()
	if RealTime() >= nextLookScan then
		nextLookScan = RealTime() + 0.5
		looked = {}
		for _, e in ipairs(ents.GetAll()) do
			if SPeditor.IsEditable(e) and not C.IsAux(e) then looked[#looked + 1] = e end
		end
	end
	for _, e in ipairs(looked) do
		if IsValid(e) then
			applyLook(e)
			applyWorn(e)
			-- a model without physics animates on the client: its base pose is held at the
			-- moment the server chose (S.ApplyLook, look.cycle)
			local cyc = e:GetNW2Float("SPeditor_Cycle", -1)
			if cyc >= 0 and e:GetCycle() ~= cyc then
				e:SetPlaybackRate(0)
				e:SetCycle(cyc)
			end
		end
	end
end)

function C.IsWorn(ent)
	return IsValid(ent) and ent:GetNW2Bool("SPeditor_Merge", false) and C.AttachParent(ent) ~= nil
end

-- Full model scale per axis: the uniform one multiplied by the stretch
function C.ScaleVec(ent)
	return C.GetStretch(ent) * (ent:GetModelScale() or 1)
end

-- Display name as in the object list
function C.DisplayName(ent)
	if not IsValid(ent) then return "—" end
	for _, obj in ipairs(C.BuildEntityList()) do
		if obj.ent == ent then return obj.name end
	end
	return SPeditor.L("obj_name_entity") .. " " .. ent:EntIndex()
end

---------------------------------------------------------------------
-- Selection. C.selected — the main object (it has the gizmo, bones, properties);
-- C.multi — additionally selected ones (Shift / Ctrl + click): they are moved, rotated,
-- scaled, duplicated and deleted together with the main one.
---------------------------------------------------------------------
C.multi = C.multi or {}

function C.IsMulti(ent)
	for _, e in ipairs(C.multi) do
		if e == ent then return true end
	end
	return false
end

function C.ClearMulti()
	if #C.multi == 0 then return end
	C.multi = {}
	hook.Run("SPeditor_MultiChanged")
end

-- the main object and all additional ones (only live ones)
function C.SelectionList()
	local list = {}
	if IsValid(C.selected) then list[1] = C.selected end
	for _, e in ipairs(C.multi) do
		if IsValid(e) and e ~= C.selected then list[#list + 1] = e end
	end
	return list
end

-- keepMulti = true: change the main object without resetting the additional ones
function C.Select(ent, bone, keepMulti)
	if ent ~= nil and not C.IsMine(ent) then ent = nil end
	if not keepMulti then C.ClearMulti() end
	C.selected = ent
	C.selBone  = bone or -1
	C.gizmo.drag = nil
	hook.Run("SPeditor_Selected", C.selected, C.selBone)
end

-- the click binds that add to the selection (cl_keys.lua)
C.MULTI_CLICK = { "select_add", "select_add2" }

-- Shift / Ctrl + click: add an object to the selection or remove it
function C.ToggleMulti(ent)
	if not C.IsMine(ent) then return end
	if not IsValid(C.selected) then
		C.Select(ent, -1)
		return
	end
	if ent == C.selected then
		-- deselecting the main one: the first additional object becomes the main one
		local nxt = table.remove(C.multi, 1)
		C.Select(IsValid(nxt) and nxt or nil, -1, true)
		hook.Run("SPeditor_MultiChanged")
		return
	end
	for i, e in ipairs(C.multi) do
		if e == ent then
			table.remove(C.multi, i)
			hook.Run("SPeditor_MultiChanged")
			return
		end
	end
	C.multi[#C.multi + 1] = ent
	hook.Run("SPeditor_MultiChanged")
end

function C.AttachParent(ent)
	local p = IsValid(ent) and ent:GetNW2Entity("SPeditor_Parent") or nil
	return IsValid(p) and p or nil
end

function C.CanScale(ent)
	return IsValid(ent) and not C.IsAux(ent) and not C.IsRagdoll(ent)
end

-- Delete everything selected as one history step
function C.DeleteSelection()
	local list = C.SelectionList()
	if #list == 0 then return end
	local uids = {}
	for _, e in ipairs(list) do
		local uid = e:GetNW2Int("SPeditor_UID", 0)
		if uid ~= 0 then uids[#uids + 1] = uid end
		C.SendDelete(e, true)
	end
	C.Select(nil)
	if #uids > 0 then
		C.PushHistory("delete",
			function() for _, uid in ipairs(uids) do C.SendObjRestore(uid) end end,
		function() for _, uid in ipairs(uids) do C.SendObjRemove(uid) end end)
	end
end

-- Duplicate everything selected (or the given objects): the copies come back one by one
-- (Net.Spawned, cl_net.lua); together they are one history step and become the new selection.
-- onDone(uids) is called with the UIDs of the copies.
function C.DuplicateSelection(list, onDone)
	list = list or C.SelectionList()
	if #list == 0 then return false end
	-- copies of the previous command are still on the way: they would be counted in this one
	if C.dupBatch then return false end
	C.dupBatch = { n = #list, uids = {}, idx = {}, untilT = RealTime() + 3, onDone = onDone }
	for _, e in ipairs(list) do C.SendDuplicate(e) end
	return true
end

-- all copies arrived (or the time is up: some could not be made, a limit)
function C.FinishDuplicate()
	local b = C.dupBatch
	C.dupBatch = nil
	if not b or #b.uids == 0 then return end
	local uids = b.uids
	C.PushHistory("spawn",
		function() for _, uid in ipairs(uids) do C.SendObjRemove(uid) end end,
	function() for _, uid in ipairs(uids) do C.SendObjRestore(uid) end end)
	C.pendingMulti = { idx = b.idx, untilT = RealTime() + 3 }
	if b.onDone then b.onDone(uids) end
end

-- Copies in a row (a0.9): n copies of ent, each step further than the one before (a fence, a
-- row of chairs, a crowd). One after another: a copy is moved once it has arrived.
function C.ArrayDuplicate(ent, n, step)
	if not IsValid(ent) or n < 1 then return end
	local p0, a0 = C.GetEntityTransform(ent)
	local i = 0
	local function find(uid)
		for _, e in ipairs(C.Objects()) do
			if IsValid(e) and e:GetNW2Int("SPeditor_UID", 0) == uid then return e end
		end
	end
	local function nextCopy()
		i = i + 1
		if i > n or not IsValid(ent) then return end
		local ok = C.DuplicateSelection({ ent }, function(uids)
			timer.Simple(0.15, function()
				local e = uids[1] and find(uids[1])
				if IsValid(e) then C.SendTransform(e, p0 + step * i, a0, true) end
				timer.Simple(0.1, nextCopy)
			end)
		end)
		if not ok then timer.Simple(0.3, function() i = i - 1 nextCopy() end) end
	end
	nextCopy()
end

-- the objects "select all" takes: everything in the object list but locked and hidden ones
-- (they cannot be clicked in the viewport either, and would be moved unseen)
function C.SelectAll()
	local list = {}
	for _, obj in ipairs(C.BuildEntityList()) do
		local e = obj.ent
		if IsValid(e) and not C.IsLocked(e) and not C.IsHidden(e) then list[#list + 1] = e end
	end
	if #list == 0 then return end
	C.Select(list[1], -1)
	for i = 2, #list do C.multi[#C.multi + 1] = list[i] end
	if #list > 1 then hook.Run("SPeditor_MultiChanged") end
	SPeditor.Notify(string.format(SPeditor.L("obj_selected_all"), #list), 0)
end

-- SFM's "Delete Models Outside Camera Frustum" (b0.2.1), as a selection: the objects no scene
-- camera sees (by their bounding sphere, at the render's proportions) are selected, so they can be
-- deleted or hidden. Cameras and lights are left out; nothing is selected without a camera.
function C.SelectOutsideCameras()
	local cams = {}
	for _, e in ipairs(C.Objects()) do
		if IsValid(e) and C.IsCamera(e) then cams[#cams + 1] = e end
	end
	if #cams == 0 then
		SPeditor.Notify(SPeditor.L("render_need_camera"), 1)
		return
	end
	local W, H = C.GetRenderSize()
	local aspect = W / math.max(H, 1)
	local views = {}
	for i, cam in ipairs(cams) do
		local pos, ang = C.CameraPose(cam)
		local tx = math.tan(math.rad(math.Clamp(cam:GetCameraFOV(), 1, 175)) / 2)
		views[i] = { pos = pos, f = ang:Forward(), r = ang:Right(), u = ang:Up(), tx = tx, ty = tx / aspect }
	end
	local function seen(e)
		local c = C.CenterOf(e) or e:GetPos()
		local rad = math.max(e:BoundingRadius(), 4)
		for _, v in ipairs(views) do
			local d = c - v.pos
			local z = d:Dot(v.f)
			if z > -rad then
				local zz = math.max(z, 1)
				if math.abs(d:Dot(v.r)) <= v.tx * zz + rad * 1.5 and math.abs(d:Dot(v.u)) <= v.ty * zz + rad * 1.5 then return true end
			end
		end
		return false
	end
	local list = {}
	for _, obj in ipairs(C.BuildEntityList()) do
		local e = obj.ent
		if IsValid(e) and not C.IsCamera(e) and not C.IsLight(e) and not C.IsLocked(e) and not C.IsHidden(e) and not seen(e) then
			list[#list + 1] = e
		end
	end
	if #list == 0 then
		C.Select(nil)
		SPeditor.Notify(SPeditor.L("sel_outside_none"), 0)
		return
	end
	C.Select(list[1], -1)
	for i = 2, #list do C.multi[#C.multi + 1] = list[i] end
	if #list > 1 then hook.Run("SPeditor_MultiChanged") end
	SPeditor.Notify(string.format(SPeditor.L("sel_outside"), #list), 0)
end

-- The object clipboard (Ctrl + C / Ctrl + V over the object list). It keeps references by UID:
-- an object deleted and brought back by undo is still found. A paste duplicates them, and the
-- clipboard moves to the copies, so the next paste puts the next copies a step further.
C.objClip = C.objClip or nil

function C.CopyObjects()
	local list = C.SelectionList()
	if #list == 0 then
		SPeditor.Notify(SPeditor.L("obj_clip_empty"), 0)
		return
	end
	C.objClip = {}
	for _, e in ipairs(list) do C.objClip[#C.objClip + 1] = C.Ref(e) end
	SPeditor.Notify(string.format(SPeditor.L("obj_copied"), #list), 2)
end

function C.PasteObjects()
	if not C.objClip then
		SPeditor.Notify(SPeditor.L("obj_clip_empty"), 0)
		return
	end
	local list = {}
	for _, ref in ipairs(C.objClip) do
		local e = C.Deref(ref)
		if IsValid(e) then list[#list + 1] = e end
	end
	if #list == 0 then
		SPeditor.Notify(SPeditor.L("obj_clip_gone"), 1)
		return
	end
	C.DuplicateSelection(list, function(uids)
		C.objClip = {}
		for _, uid in ipairs(uids) do C.objClip[#C.objClip + 1] = { uid = uid } end
	end)
end

-- the cursor is over the object list (the Animation Set Editor tree)
function C.MouseOverObjectList()
	local tree = SPeditor.UI and SPeditor.UI.ObjectTree
	if not IsValid(tree) or not tree:IsVisible() then return false end
	local p = vgui.GetHoveredPanel()
	while IsValid(p) do
		if p == tree then return true end
		p = p:GetParent()
	end
	return false
end

-- the copies are selected once the client has them all
local function resolvePendingMulti()
	local pm = C.pendingMulti
	local found, all = {}, true
	for _, i in ipairs(pm.idx) do
		local e = Entity(i)
		if IsValid(e) and C.IsMine(e) then found[#found + 1] = e else all = false end
	end
	if not all and RealTime() < pm.untilT then return end
	C.pendingMulti = nil
	if #found == 0 then return end
	for _, e in ipairs(found) do hook.Run("SPeditor_ObjectSpawned", e) end
	C.Select(found[1], -1)
	for i = 2, #found do C.multi[#C.multi + 1] = found[i] end
	if #found > 1 then hook.Run("SPeditor_MultiChanged") end
end

SPeditor.Hook("Think", "SPeditor.SelectionWatch", function()
	if C.dupBatch and RealTime() >= C.dupBatch.untilT then C.FinishDuplicate() end
	if C.pendingMulti then resolvePendingMulti() end
	if C.selected ~= nil and not IsValid(C.selected) then
		C.Select(nil, -1, true)
	end
	for i = #C.multi, 1, -1 do
		if not IsValid(C.multi[i]) then
			table.remove(C.multi, i)
			hook.Run("SPeditor_MultiChanged")
		end
	end
	if C.pendingSelect then
		local e = Entity(C.pendingSelect)
		if IsValid(e) and C.IsMine(e) then
			C.pendingSelect = nil
			hook.Run("SPeditor_ObjectSpawned", e)
			C.Select(e, -1)
		elseif RealTime() > (C.pendingUntil or 0) then
			C.pendingSelect = nil
		end
	end
end)

function C.SpawnModel(model)
	local pos, ang = C.GetView()
	local spawnPos = pos + ang:Forward() * SPeditor.Config.SpawnDistance
	C.SendSpawn(model, spawnPos, Angle(0, ang.y + 180, 0))
end

local function setup(ent)
	local f = FrameNumber()
	if ent.SPeditor_Setup ~= f then
		ent.SPeditor_Setup = f
		ent:SetupBones()
	end
end

function C.GetBoneWorld(ent, bone)
	-- a worn object is seen as its copy merged into the wearer: its bones are there
	if IsValid(ent) and IsValid(ent.SPWorn) then ent = ent.SPWorn end
	setup(ent)
	if C.ApplyStretch then C.ApplyStretch(ent) end
	local m = ent:GetBoneMatrix(bone)
	if not m then return nil end
	return m:GetTranslation(), m:GetAngles()
end

function C.PhysIndexOfBone(ent, bone)
	return SPeditor.PhysOfBone(ent, bone)
end

function C.GetEntityTransform(ent)
	if C.IsRagdoll(ent) then
		local p, a = C.GetBoneWorld(ent, ent:TranslatePhysBoneToBone(0))
		if p then return p, a end
	end
	return ent:GetPos(), ent:GetAngles()
end

---------------------------------------------------------------------
-- Frame (aspect gate) and viewport geometry.
-- The frame rect = the rectangle of the actual image inside the Primary Viewport.
-- MouseRay and ProjectToViewport are inverse to each other and use the half-frame
-- tangents computed by the engine itself (util.AimVector): FOV in Source
-- is given for 4:3, so tan(fov/2) is NOT the vertical tangent.
---------------------------------------------------------------------
local cvAspect = CreateClientConVar("gmfm_aspect", "16:9", true, false)
local cvSide   = CreateClientConVar("gmfm_render_side", "1920", true, false)
CreateClientConVar("gmfm_render_custom", "0", true, false)
CreateClientConVar("gmfm_render_w", "1920", true, false)
CreateClientConVar("gmfm_render_h", "1080", true, false)
CreateClientConVar("gmfm_render_fullbright", "0", true, false)
CreateClientConVar("gmfm_render_format", "png", true, false)
CreateClientConVar("gmfm_render_quality", "90", true, false)
CreateClientConVar("gmfm_render_ss", "1", true, false)          -- smoothing (2x render)
CreateClientConVar("gmfm_dof", "0", true, false)                -- depth of field
CreateClientConVar("gmfm_dof_aperture", "0.6", true, false)     -- aperture radius, units
CreateClientConVar("gmfm_dof_samples", "32", true, false)

function C.GetAspectDef()
	local id = cvAspect:GetString()
	for _, a in ipairs(SPeditor.Aspects) do
		if a.id == id then return a end
	end
	return SPeditor.Aspects[2]
end

-- a number (w/h), or nil if the frame is free
function C.GetAspect()
	local a = C.GetAspectDef()
	if a.w <= 0 or a.h <= 0 then return nil end
	return a.w / a.h
end

function C.SetAspect(id)
	RunConsoleCommand("gmfm_aspect", id)
end

function C.GetRenderSide()
	local side = math.floor(cvSide:GetFloat())
	return math.Clamp(side, 256, SPeditor.Config.MaxRenderSide)
end

function C.SetRenderSide(side)
	RunConsoleCommand("gmfm_render_side", tostring(side))
end

-- fit a frame with the ratio aspect into a w*h rectangle (centred)
function C.FitRect(w, h, aspect)
	if not aspect then return 0, 0, w, h end
	local iw, ih = w, w / aspect
	if ih > h then ih, iw = h, h * aspect end
	return (w - iw) / 2, (h - ih) / 2, iw, ih
end

-- size of the final render in pixels
function C.GetRenderSize()
	if GetConVar("gmfm_render_custom"):GetBool() then
		return math.Clamp(GetConVar("gmfm_render_w"):GetInt(), 16, SPeditor.Config.MaxRenderSide),
		math.Clamp(GetConVar("gmfm_render_h"):GetInt(), 16, SPeditor.Config.MaxRenderSide)
	end
	local side = C.GetRenderSide()
	local aspect = C.GetAspect()
	if not aspect then
		-- "free": the Primary Viewport's proportions. While it is hidden (another tab over it,
		-- the editor closing) the last ones it had — the whole screen (16:9) gave a render of
		-- other proportions than the viewport the user framed in (b0.2.1)
		local _, _, vw, vh, isPanel = C.PanelRect()
		if isPanel and vw > 16 and vh > 16 then C.freeAspect = vw / vh end
		aspect = C.freeAspect or vw / math.max(vh, 1)
	end
	local w, h
	if aspect >= 1 then
		w, h = side, side / aspect
	else
		w, h = side * aspect, side
	end
	return math.max(math.floor(w + 0.5), 16), math.max(math.floor(h + 0.5), 16)
end

-- the whole Primary Viewport panel (x, y, w, h, isPanel)
function C.PanelRect()
	local UI = SPeditor.UI
	if UI and IsValid(UI.PrimaryVP) and IsValid(UI.PrimaryVP.view) and UI.PageShown and UI.PageShown("primary") then
		local x, y = UI.PrimaryVP.view:LocalToScreen(0, 0)
		return x, y, UI.PrimaryVP.view:GetWide(), UI.PrimaryVP.view:GetTall(), true
	end
	return 0, 0, ScrW(), ScrH(), false
end

-- the frame image inside the panel (in screen coordinates)
function C.ViewportRect()
	local px, py, pw, ph, isPanel = C.PanelRect()
	if not isPanel then return px, py, pw, ph end
	local ix, iy, iw, ih = C.FitRect(pw, ph, C.GetAspect())
	return px + ix, py + iy, iw, ih
end

-- The cursor is over the view (and not over a window that covers the viewport)
function C.MouseInViewport()
	local px, py, pw, ph, isPanel = C.PanelRect()
	local mx, my = gui.MousePos()
	if mx < px or mx > px + pw or my < py or my > py + ph then return false end
	local hp = vgui.GetHoveredPanel()
	if isPanel then
		local view = SPeditor.UI.PrimaryVP.view
		if not IsValid(hp) or (hp ~= view and not hp:HasParent(view)) then return false end
	elseif IsValid(hp) and hp ~= vgui.GetWorldPanel() then
		-- the Primary Viewport is closed: the view is the screen, but not where a window or a
		-- menu is (b0.2.4: a press on the Windows menu closed the menu before its option ran,
		-- so the closed viewport could not be brought back)
		return false
	end
	return true
end

local projCache = { frame = -1 }

local function halfTangents(ang, fov, vw, vh)
	local fr = FrameNumber()
	local c = projCache
	if c.frame == fr and c.fov == fov and c.vw == vw and c.vh == vh and c.ang == ang then
		return c.tx, c.ty
	end
	local fwd, right, up = ang:Forward(), ang:Right(), ang:Up()
	local r = util.AimVector(ang, fov, vw, vh * 0.5, vw, vh)   -- right edge of the frame
	local u = util.AimVector(ang, fov, vw * 0.5, 0, vw, vh)    -- top edge of the frame
	local tx = r:Dot(right) / math.max(r:Dot(fwd), 1e-6)
	local ty = u:Dot(up) / math.max(u:Dot(fwd), 1e-6)
	if not (tx > 0 and ty > 0) or tx ~= tx or ty ~= ty then
		-- fallback Source formula: fov is given for 4:3
		ty = math.tan(math.rad(fov) / 2) * 0.75
		tx = ty * (vw / math.max(vh, 1))
	end
	c.frame, c.fov, c.vw, c.vh, c.ang, c.tx, c.ty = fr, fov, vw, vh, Angle(ang.p, ang.y, ang.r), tx, ty
	return tx, ty
end

function C.MouseRay()
	local pos, ang, fov = C.GetView()
	local vx, vy, vw, vh = C.ViewportRect()
	local mx, my = gui.MousePos()
	local tx, ty = halfTangents(ang, fov, math.max(vw, 1), math.max(vh, 1))
	local fx = ((mx - vx) / math.max(vw, 1)) * 2 - 1
	local fy = ((my - vy) / math.max(vh, 1)) * 2 - 1
	local dir = (ang:Forward() + ang:Right() * (fx * tx) - ang:Up() * (fy * ty)):GetNormalized()
	return pos, dir
end

-- Projection of a world point into screen coordinates of the frame. Returns x, y, visible.
function C.ProjectToViewport(p)
	local pos, ang, fov = C.GetView()
	local vx, vy, vw, vh = C.ViewportRect()
	local d = p - pos
	local depth = d:Dot(ang:Forward())
	if depth <= 0 then return 0, 0, false end
	local tx, ty = halfTangents(ang, fov, math.max(vw, 1), math.max(vh, 1))
	local nx = d:Dot(ang:Right()) / (depth * tx)
	local ny = d:Dot(ang:Up()) / (depth * ty)
	if nx < -1.5 or nx > 1.5 or ny < -1.5 or ny > 1.5 then return 0, 0, false end
	local x = vx + (nx * 0.5 + 0.5) * vw
	local y = vy + (0.5 - ny * 0.5) * vh
	return x, y, true
end

local function rayPointDist(origin, dir, p)
	local v = p - origin
	local t = v:Dot(dir)
	if t <= 0 then return nil end
	return (v - dir * t):Length(), t
end

-- IMPORTANT: the filter function in util.TraceLine returns true for entities that
-- MUST be hit by the ray (the world is always hit). There used to be
-- "not IsEditable" here, which made the ray ignore exactly the editor objects, and
-- ragdolls could not be picked by clicking the model.
function C.PickEntity()
	local origin, dir = C.MouseRay()
	local far = 32768
	local tr = util.TraceLine({
			start  = origin,
			endpos = origin + dir * far,
			filter = function(e) return SPeditor.IsEditable(e) end,
	})
	local worldDist = tr.HitWorld and origin:Distance(tr.HitPos) or math.huge
	local best, bestDist
	if IsValid(tr.Entity) and C.IsMine(tr.Entity) and not C.IsLight(tr.Entity) and not C.IsEffect(tr.Entity)
		and not C.IsLocked(tr.Entity) and not C.IsHidden(tr.Entity) then
		best, bestDist = tr.Entity, origin:Distance(tr.HitPos)
	end
	for _, e in ipairs(C.Objects()) do
		if IsValid(e) and e ~= C.camera.viewEnt and not C.IsLocked(e) and not C.IsHidden(e) then
			-- lights of other addons taken from the map may have no size of their own: picked as a point too
			local foreignPoint = C.IsForeign and C.IsForeign(e) and e:BoundingRadius() < 12
			if C.IsLight(e) or C.IsEffect(e) or foreignPoint then
				local d, t = rayPointDist(origin, dir, e:GetPos())
				if d and d < math.max(16, t * 0.03) and t < worldDist and (not bestDist or t < bestDist) then
					best, bestDist = e, t
				end
			elseif C.IsRagdoll(e) then
				-- the trace may miss thin parts (fingers, head): look for the physics bone nearest to the ray
				for b = 0, e:GetBoneCount() - 1 do
					if C.PhysIndexOfBone(e, b) then
						local bp = C.GetBoneWorld(e, b)
						if bp then
							local d, t = rayPointDist(origin, dir, bp)
							if d and d < math.max(6, t * 0.02) and t < worldDist and (not bestDist or t < bestDist) then
								best, bestDist = e, t
							end
						end
					end
				end
			else
				local sc = C.ScaleVec(e)
				local hit = util.IntersectRayWithOBB(origin, dir * far, e:GetPos(), e:GetAngles(), e:OBBMins() * sc, e:OBBMaxs() * sc)
				if hit then
					local t = origin:Distance(hit)
					if t < worldDist and (not bestDist or t < bestDist) then
						best, bestDist = e, t
					end
				end
			end
		end
	end
	return best
end

-- The physical bone of a ragdoll whose part of the body is under the cursor: the point the
-- ray hits (or, if the trace misses a thin part, the ray itself) to the nearest segment
-- bone -> physical child bone.
function C.PickBodyBone(ent)
	local origin, dir = C.MouseRay()
	local tr = util.TraceLine({ start = origin, endpos = origin + dir * 32768,
			filter = function(e) return e == ent end })
	local hitPos = (tr.Entity == ent) and tr.HitPos or nil
	local segs = {}
	for b = 0, ent:GetBoneCount() - 1 do
		if C.PhysIndexOfBone(ent, b) then
			local p = C.GetBoneWorld(ent, b)
			if p then
				local any = false
				for c = 0, ent:GetBoneCount() - 1 do
					if c ~= b and C.PhysIndexOfBone(ent, c) then
						-- the nearest physical ancestor of c is b
						local par = ent:GetBoneParent(c)
						while par and par >= 0 and not C.PhysIndexOfBone(ent, par) do par = ent:GetBoneParent(par) end
						if par == b then
							local q = C.GetBoneWorld(ent, c)
							if q then segs[#segs + 1] = { b, p, q } any = true end
						end
					end
				end
				if not any then segs[#segs + 1] = { b, p, p } end
			end
		end
	end
	local best, bestD
	for _, sg in ipairs(segs) do
		local a, ab = sg[2], sg[3] - sg[2]
		local d
		if hitPos then
			local t = ab:LengthSqr() > 0 and math.Clamp((hitPos - a):Dot(ab) / ab:LengthSqr(), 0, 1) or 0
			d = hitPos:Distance(a + ab * t)
		else
			-- distance between the ray and the segment, sampled along it
			for i = 0, 8 do
				local dd = rayPointDist(origin, dir, a + ab * (i / 8))
				if dd and (not d or dd < d) then d = dd end
			end
		end
		if d and (not bestD or d < bestD) then best, bestD = sg[1], d end
	end
	return best
end

-- Bone picking by screen distance inside the viewport
function C.PickBone(ent, radiusPx)
	local mx, my = gui.MousePos()
	local best, bestD = nil, radiusPx * radiusPx
	for b = 0, ent:GetBoneCount() - 1 do
		if ent:GetBoneName(b) ~= "__INVALIDBONE__" then
			local p = C.GetBoneWorld(ent, b)
			if p then
				local x, y, vis = C.ProjectToViewport(p)
				if vis then
					local d = (x - mx) ^ 2 + (y - my) ^ 2
					if d < bestD then best, bestD = b, d end
				end
			end
		end
	end
	return best
end
