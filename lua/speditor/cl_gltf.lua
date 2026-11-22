--[[
GM:FM — glTF scene exchange (r1.0, Phase 4).

Writes a glTF 2.0 JSON with the layout of the scene: objects, their names, places,
turns and scales, the scene cameras and, in each node's extras, the keys of its track
(frame, position, angle, easing). Meshes are not copied — GMod Lua cannot read model
geometry — so open the glTF in Blender for the layout/cameras and load the key data
through the extras or re-import the keys in GM:FM. The file goes to data/speditor/export/.
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI, C = SPeditor.UI, SPeditor.Client

local function v3(v) return { v.x, v.y, v.z } end
local function a3(a) return { a.p or 0, a.y or 0, a.r or 0 } end

function UI.ExportGltf(name)
	name = SPeditor.SafeName(tostring(name or ""))
	if name == "" then name = "gmfm_scene" end
	local SA = SPeditor.Component and SPeditor.Component("saeditor") and SPeditor.Component("saeditor").SA
	local objects = C.BuildEntityList and C.BuildEntityList() or {}
	local doc = {
		asset = { version = "2.0", generator = "GM:FM r1.0 (Garry's Mod Filmmaker)" },
		scene = 0, scenes = { { nodes = {} } }, nodes = {}, cameras = {},
	}
	for _, o in ipairs(objects) do
		local ent = o.ent
		if IsValid(ent) then
			local pos, ang = ent:GetPos(), ent:GetAngles()
			local scale = ent:GetModelScale() or 1
			local node = { name = C.DisplayName(ent), translation = v3(pos), rotation = { 0, 0, 0, 1 },
				scale = { scale, scale, scale },
				extras = { model = ent:GetModel(), gmod_angles = a3(ang),
					uid = SA and SA.UID(ent) or 0, keys = {} } }
			if C.IsCamera(ent) then
				doc.cameras[#doc.cameras + 1] = { type = "perspective", perspective = {
					yfov = math.rad(C.GetCamFOV and C.GetCamFOV() or 60), znear = 1, zfar = 100000 } }
				node.camera = #doc.cameras - 1
			end
			if SA then
				for _, k in ipairs(SA.tracks[SA.UID(ent)] or {}) do
					node.extras.keys[#node.extras.keys + 1] = {
						f = k.f or k[1], pos = v3(k.pos or vector_origin),
						ease = k.e, only = k.only and table.GetKeys(k.only) or nil,
					}
				end
			end
			doc.nodes[#doc.nodes + 1] = node
			doc.scenes[1].nodes[#doc.scenes[1].nodes + 1] = #doc.nodes - 1
		end
	end
	file.CreateDir("speditor/export")
	-- GMod's DATA filesystem refuses the .gltf extension; glTF JSON is stored as .json
	local path = "speditor/export/" .. name .. ".json"
	local json = util.TableToJSON(doc, true)
	if not json or json == "" then return path end
	file.Write(path, json)
	if SPeditor.Notify then SPeditor.Notify("#gltf_saved|" .. path, 3) end
	return path
end
