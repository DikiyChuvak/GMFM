--[[
GM:FM — saved looks (b0.2.4, asked on the Workshop):
  * material presets, as SFM's override materials kept for later: the material of a model, the
    materials of its slots and their colours under a name, put on any object
    (Properties → Material → Presets);
  * outfits: what a character wears (the objects attached with "Wear") under a name, put on
    another character — the models are made and worn at once (ASE → right click → Outfits).

Files: data/speditor/matpresets/<name>.json, data/speditor/outfits/<name>.json

API:
  P.List(kind)                       names of the saved "matpresets" / "outfits"
  P.Delete(kind, name)
  P.SaveMaterial(ent, name) / P.ApplyMaterial(ent, name)
  P.SaveOutfit(ent, name) -> count   / P.WearOutfit(ent, name)
  P.MaterialMenu(m, ent) / P.OutfitMenu(m, ent)    the submenus
]]
SPeditor.Presets = SPeditor.Presets or {}
local P = SPeditor.Presets
local C = SPeditor.Client
local L = SPeditor.L

local function dir(kind) return SPeditor.Config.SaveDir .. "/" .. kind end

function P.List(kind)
	local out = {}
	for _, f in ipairs(file.Find(dir(kind) .. "/*.json", "DATA") or {}) do
		out[#out + 1] = string.StripExtension(f)
	end
	table.sort(out, function(a, b) return string.lower(a) < string.lower(b) end)
	return out
end

local function read(kind, name)
	local raw = file.Read(dir(kind) .. "/" .. SPeditor.SafeName(name) .. ".json", "DATA")
	local t = raw and util.JSONToTable(raw)
	return istable(t) and t or nil
end

local function write(kind, name, t)
	name = SPeditor.SafeName(name)
	if name == "" then return false end
	if not file.IsDir(SPeditor.Config.SaveDir, "DATA") then file.CreateDir(SPeditor.Config.SaveDir) end
	if not file.IsDir(dir(kind), "DATA") then file.CreateDir(dir(kind)) end
	file.Write(dir(kind) .. "/" .. name .. ".json", util.TableToJSON(t, true))
	return true
end

function P.Delete(kind, name)
	file.Delete(dir(kind) .. "/" .. SPeditor.SafeName(name) .. ".json")
end

---------------------------------------------------------------------
-- Material presets
---------------------------------------------------------------------
function P.SaveMaterial(ent, name)
	if not IsValid(ent) or C.IsAux(ent) then return false end
	local look = C.GetLook(ent)
	return write("matpresets", name, {
		material = look.material or "", submats = look.submats or {}, tints = look.tints or {},
		slots = ent:GetMaterials() or {},
	})
end

-- The slots of the preset are found on the other model by their material, then by its file
-- name (the same texture set in another folder), and last by number
local function slotOn(ent, slots, idx)
	local mine = ent:GetMaterials() or {}
	local path = slots[idx + 1]
	if path then
		for i, p in ipairs(mine) do
			if p == path then return i - 1 end
		end
		local fileName = string.GetFileFromFilename(path)
		for i, p in ipairs(mine) do
			if string.GetFileFromFilename(p) == fileName then return i - 1 end
		end
	end
	if idx < #mine then return idx end
end

function P.ApplyMaterial(ent, name)
	if not IsValid(ent) or C.IsAux(ent) then return false end
	local t = read("matpresets", name)
	if not t then return false end
	local slots = istable(t.slots) and t.slots or {}
	local function remap(src)
		local out = {}
		for k, v in pairs(istable(src) and src or {}) do
			local idx = slotOn(ent, slots, math.floor(tonumber(k) or -1))
			if idx then out[tostring(idx)] = v end
		end
		return out
	end
	C.EditLook(ent, { material = isstring(t.material) and t.material or "", submats = remap(t.submats), tints = remap(t.tints) }, true)
	return true
end

---------------------------------------------------------------------
-- Outfits
---------------------------------------------------------------------
local function worn(ent)
	local out = {}
	for _, e in ipairs(C.Objects()) do
		if IsValid(e) and e ~= ent and e:GetNW2Entity("SPeditor_Parent") == ent and e:GetNW2Bool("SPeditor_Merge", false) then
			out[#out + 1] = e
		end
	end
	return out
end
P.Worn = worn

function P.SaveOutfit(ent, name)
	local items = {}
	for _, e in ipairs(worn(ent)) do
		local groups = {}
		for i = 0, e:GetNumBodyGroups() - 1 do groups[tostring(i)] = e:GetBodygroup(i) end
		local look = C.GetLook(e)
		look.locks = nil
		items[#items + 1] = { model = e:GetModel(), skin = e:GetSkin(), groups = groups, look = look,
			scale = e:GetModelScale() ~= 1 and e:GetModelScale() or nil, name = e:GetNW2String("SPeditor_Name", "") }
	end
	if #items == 0 then return 0 end
	if not write("outfits", name, { items = items }) then return false end
	return #items
end

function P.WearOutfit(ent, name)
	if not IsValid(ent) then return false end
	local t = read("outfits", name)
	if not t or not istable(t.items) or #t.items == 0 then return false end
	net.Start(SPeditor.Net.Outfit)
	net.WriteEntity(ent)
	SPeditor.WriteTable(t.items)
	net.SendToServer()
	return true
end

---------------------------------------------------------------------
-- Menus
---------------------------------------------------------------------
local function askName(title, done)
	Derma_StringRequest(title, L("preset_name_prompt"), "", function(text)
		if SPeditor.SafeName(text) == "" then
			SPeditor.Notify("#layout_bad_name", 1)
			return
		end
		done(SPeditor.SafeName(text))
	end)
end

local function savedList(m, kind, apply, icon)
	local names = P.List(kind)
	if #names == 0 then
		local o = m:AddOption(L("preset_none"))
		if o.SetEnabled then o:SetEnabled(false) end
		return
	end
	for _, n in ipairs(names) do
		m:AddOption(n, function() apply(n) end):SetIcon(icon)
	end
	m:AddSpacer()
	local del = m:AddSubMenu(L("preset_delete"))
	for _, n in ipairs(names) do
		del:AddOption(n, function() P.Delete(kind, n) end):SetIcon("icon16/cross.png")
	end
end

function P.MaterialMenu(m, ent)
	m:AddOption(L("matpreset_save"), function()
		askName(L("matpreset_save"), function(n)
			if IsValid(ent) and P.SaveMaterial(ent, n) then SPeditor.Notify("#preset_saved|" .. n, 2) end
		end)
	end):SetIcon("icon16/disk.png")
	m:AddSpacer()
	savedList(m, "matpresets", function(n)
		if IsValid(ent) then P.ApplyMaterial(ent, n) end
	end, "icon16/palette.png")
end

function P.OutfitMenu(m, ent)
	local n = #worn(ent)
	local save = m:AddOption(string.format(L("outfit_save"), n), function()
		askName(L("outfit_title"), function(name)
			local count = IsValid(ent) and P.SaveOutfit(ent, name)
			if count and count > 0 then SPeditor.Notify("#outfit_saved|" .. name .. "|" .. count, 2) end
		end)
	end)
	save:SetIcon("icon16/disk.png")
	if n == 0 then
		if save.SetEnabled then save:SetEnabled(false) end
		save:SetTooltip(L("outfit_none_worn"))
	end
	m:AddSpacer()
	savedList(m, "outfits", function(name)
		if IsValid(ent) then P.WearOutfit(ent, name) end
	end, "icon16/user_suit.png")
end
