--[[
SPeditor — PAC3 outfits on scene objects (client). PAC3 is a separate addon (Workshop
104691717); without it the outfits are kept and saved but not shown.

An object wears outfits saved by PAC3's own editor (data/pac3/<name>.txt): the object's menu →
PAC3 outfits. The text of the file goes to the server (sv_pac.lua), which keeps it with the
object and the scene and hands it to every client; here it is put on through PAC3's API:
pac.SetupENT(ent) gives the entity AttachPACPart / RemovePACPart, and an outfit whose owner is
"self" follows the entity's bones — so it moves with the character in the editor, in the
animation and in the render.

  PAC.Available()                   PAC3 is installed and loaded
  PAC.Files()                       outfit files of PAC3 (names without .txt)
  PAC.List(ent)                     { { name }, ... } the outfits an object wears
  PAC.Add(ent, name)  PAC.Remove(ent, i)  PAC.Clear(ent)
  PAC.OpenEditor()                  PAC3's own editor (to make and save outfits)
  PAC.LuaData()                     PAC3's reader / writer of outfit files
The PAC3 window of SPeditor (a model on a bone, the outfits worn) is cl_ui_pac.lua.
]]
SPeditor.PAC = SPeditor.PAC or {}
local PAC = SPeditor.PAC
local C   = SPeditor.Client
local L   = SPeditor.L

PAC.data = PAC.data or {}      -- [entity index] = { { name, data }, ... }  (as the server keeps them)
PAC.dirty = PAC.dirty or {}    -- [entity index] = true: to be put on again

function PAC.Available()
	return istable(rawget(_G, "pac")) and isfunction(pac.SetupENT) and isfunction(pac.CreatePart)
end

local function luadata()
	local p = rawget(_G, "pace")
	if istable(p) and istable(p.luadata) then return p.luadata end
	if not PAC.ld and file.Exists("pac3/libraries/luadata.lua", "LUA") then PAC.ld = include("pac3/libraries/luadata.lua") end
	return PAC.ld
end

PAC.LuaData = luadata

function PAC.Files()
	local out = {}
	local files = file.Find("pac3/*.txt", "DATA", "datedesc")
	for _, f in ipairs(files or {}) do out[#out + 1] = string.StripExtension(f) end
	return out
end

function PAC.List(ent)
	return IsValid(ent) and PAC.data[ent:EntIndex()] or {}
end

function PAC.OpenEditor()
	if not PAC.Available() then
		SPeditor.Notify("#pac_missing", 1)
		return
	end
	RunConsoleCommand("pac_editor")
end

local function sendOp(ent, op, write)
	net.Start(SPeditor.Net.PAC)
	net.WriteEntity(ent)
	net.WriteUInt(op, 2)
	if write then write() end
	net.SendToServer()
end

function PAC.Add(ent, name)
	if not IsValid(ent) then return end
	local text = file.Read("pac3/" .. name .. ".txt", "DATA")
	local ld = luadata()
	if not text or text == "" then
		SPeditor.Notify("#pac_bad", 1)
		return
	end
	-- it must be a PAC3 outfit: read it now, not on every client later
	if ld then
		local ok, tbl = pcall(ld.Decode, text)
		if not ok or type(tbl) ~= "table" then
			SPeditor.Notify("#pac_bad", 1)
			return
		end
	end
	local data = util.Compress(text)
	if not data or #data > 60000 then
		SPeditor.Notify("#pac_big", 1)
		return
	end
	sendOp(ent, 0, function()
		net.WriteString(name)
		net.WriteUInt(#data, 16)
		net.WriteData(data, #data)
	end)
	if not PAC.Available() then SPeditor.Notify("#pac_missing", 0) end
end

function PAC.Remove(ent, i) if IsValid(ent) then sendOp(ent, 1, function() net.WriteUInt(i, 4) end) end end
function PAC.Clear(ent) if IsValid(ent) then sendOp(ent, 2) end end

net.Receive(SPeditor.Net.PACSync, function()
	local idx = net.ReadUInt(13)
	local op = net.ReadUInt(2)
	if op == 0 then
		local n = net.ReadUInt(4)
		PAC.data[idx] = (n > 0) and {} or nil
	else
		local name = net.ReadString()
		local data = net.ReadData(net.ReadUInt(16))
		PAC.data[idx] = PAC.data[idx] or {}
		table.insert(PAC.data[idx], { name = name, data = data })
	end
	PAC.dirty[idx] = true
end)

---------------------------------------------------------------------
-- PAC3 puts every bone of an entity that wears parts back to zero in every frame
-- (pac.ResetBones: offsets, turns, scales) and then lets its bone parts change them. On an
-- editor object that wiped the pose made in SPeditor — measured in game: 19 posed bones of a
-- character in a hat read 0 on the client — and a stretched bone (cl_bone_manip.lua). An
-- object whose outfits have no parts that move its bones (hats, glasses, models on bones) is
-- left alone; one with such parts is reset as PAC3 wants, or its bone parts would add up.
---------------------------------------------------------------------
local BONE_PARTS = { bone = true, bone2 = true, bone3 = true, custom_animation = true, interpolated_multibone = true,
	jiggle = true, entity = true, entity2 = true }

local function movesBones(outfit)
	if type(outfit) ~= "table" then return false end
	if type(outfit.self) == "table" and BONE_PARTS[outfit.self.ClassName] then return true end
	for _, c in pairs(type(outfit.children) == "table" and outfit.children or {}) do
		if movesBones(c) then return true end
	end
	return false
end

-- ent.SPeditor_PACKeep[key] = outfit: the outfits on the object (key "worn" — the scene's, "preview"
-- — the part being made in the PAC3 window)
function PAC.SetKeep(ent, key, list)
	if not IsValid(ent) then return end
	ent.SPeditor_PACKeep = ent.SPeditor_PACKeep or {}
	ent.SPeditor_PACKeep[key] = list
	local moves = false
	for _, l in pairs(ent.SPeditor_PACKeep) do
		for _, o in ipairs(l) do moves = moves or movesBones(o) end
	end
	ent.SPeditor_PACBonesFree = not moves
end

local function hookReset()
	if not istable(rawget(_G, "pac")) or not isfunction(pac.ResetBones) or pac.SPeditor_ResetBones then return end
	local orig = pac.ResetBones
	pac.SPeditor_ResetBones = orig
	pac.ResetBones = function(ent, ...)
		if IsValid(ent) and ent.SPeditor_PACBonesFree then
			ent.pac_bones_once = true
			return
		end
		return orig(ent, ...)
	end
end

---------------------------------------------------------------------
-- Putting outfits on
---------------------------------------------------------------------
local function takeOff(ent)
	for _, outfit in ipairs(ent.SPeditor_PACWorn or {}) do
		pcall(ent.RemovePACPart, ent, outfit)
	end
	ent.SPeditor_PACWorn = nil
end

local function putOn(ent, items)
	if not ent.AttachPACPart then pac.SetupENT(ent, "self") end
	ent.pac_owner = "self"
	takeOff(ent)
	local ld = luadata()
	if not ld then return end
	local worn = {}
	for _, it in ipairs(items or {}) do
		local text = util.Decompress(it.data, 1048576)
		local ok, tbl = false, nil
		if text then ok, tbl = pcall(ld.Decode, text) end
		if ok and type(tbl) == "table" then
			-- a file is one outfit ({ self, children }) or a list of them
			local roots = tbl.self and { tbl } or tbl
			for _, root in pairs(roots) do
				if type(root) == "table" and type(root.self) == "table" then
					-- the outfit belongs to the object, whoever made it
					root.self.OwnerName = "self"
					-- remembered even if PAC3 threw an error half way (a part of the outfit may
					-- already be on), so that taking it off later still reaches it
					worn[#worn + 1] = root
					local okA, err = pcall(ent.AttachPACPart, ent, root, ent)
					if not okA then ErrorNoHalt("[GM:FM] PAC3 could not put on '" .. tostring(it.name) .. "': " .. tostring(err) .. "\n") end
				end
			end
		end
	end
	ent.SPeditor_PACWorn = worn
	PAC.SetKeep(ent, "worn", worn)
	-- PAC3 hides parts farther than pac_draw_distance from the player; the editor's camera
	-- is somewhere else
	if ent.SetPACDrawDistance then ent:SetPACDrawDistance(0) end
end

-- A few times a second (every frame is too often); an entity that appeared or was made anew
-- (a scene reloaded, undo) gets its outfits again. A timer, not a Think hook: an error in
-- any hook of an event stops the rest of them — measured in game, a PAC3 light part fails
-- every frame in PAC3's own Think hook next to GShader Library's DynamicLight wrapper, and
-- no outfit was put on any more.
hook.Remove("Think", "SPeditor.PAC")
timer.Create("SPeditor.PAC", 0.2, 0, function()
	if not PAC.Available() then return end
	hookReset()
	for idx, items in pairs(PAC.data) do
		local ent = Entity(idx)
		if IsValid(ent) and (PAC.dirty[idx] or ent.SPeditor_PACFor ~= items) then
			PAC.dirty[idx] = nil
			ent.SPeditor_PACFor = items
			local ok, err = pcall(putOn, ent, items)
			if not ok then ErrorNoHalt("[GM:FM] PAC3 outfit: " .. tostring(err) .. "\n") end
		end
	end
	for idx in pairs(PAC.dirty) do
		if not PAC.data[idx] then
			PAC.dirty[idx] = nil
			local ent = Entity(idx)
			if IsValid(ent) then
				ent.SPeditor_PACFor = nil
				pcall(takeOff, ent)
				PAC.SetKeep(ent, "worn", {})
			end
		end
	end
end)

---------------------------------------------------------------------
-- The menu of an object (the Animation Set Editor tree, the viewport)
---------------------------------------------------------------------
function PAC.AddMenu(m, ent)
	local sub, opt = m:AddSubMenu(L("pac_menu"))
	opt:SetIcon("icon16/user_suit.png")
	sub:AddOption(L("pac_win_open"), function() SPeditor.UI.OpenPACWindow(ent) end):SetIcon("icon16/application_form_edit.png")
	sub:AddSpacer()
	if not PAC.Available() then
		sub:AddOption(L("pac_missing")):SetEnabled(false)
	end
	local files = PAC.Files()
	local add = sub:AddSubMenu(L("pac_add") .. "  (" .. #files .. ")")
	if #files == 0 then add:AddOption(L("pac_none")):SetEnabled(false) end
	for _, name in ipairs(files) do
		add:AddOption(name, function() PAC.Add(ent, name) end)
	end
	local worn = PAC.List(ent)
	if #worn > 0 then
		sub:AddSpacer()
		for i, it in ipairs(worn) do
			sub:AddOption(L("pac_remove") .. ": " .. it.name, function() PAC.Remove(ent, i) end):SetIcon("icon16/cross.png")
		end
		sub:AddOption(L("pac_clear"), function() PAC.Clear(ent) end)
	end
	sub:AddSpacer()
	sub:AddOption(L("pac_editor"), function() PAC.OpenEditor() end):SetIcon("icon16/pencil.png")
end
