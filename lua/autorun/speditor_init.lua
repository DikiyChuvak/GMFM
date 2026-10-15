-- SPeditor loader
SPeditor = SPeditor or {}

local BASE = "speditor/"

local SHARED = { "sh_config", "sh_util", "sh_lang", "sh_mods" }
local SERVER_FILES = { "sv_net", "sv_speditor", "sv_persistence", "sv_adopt" }
local CLIENT_FILES = {
	"cl_net", "cl_scene", "cl_history", "cl_camera", "cl_gizmo",
	"cl_bone_manip", "cl_flex", "cl_ik", "cl_shadows", "cl_lights", "cl_effects", "cl_tools", "cl_shaders", "cl_postfx", "cl_render", "cl_export",
	"cl_ui_theme", "cl_ui_notify", "cl_ui_notify_custom", "cl_ui_themes", "cl_ui_userthemes", "cl_ui_settings", "cl_ui_dock", "cl_ui_main", "cl_ui_ase", "cl_ui_ev", "cl_ui_pages",
	"cl_ui_model_list", "cl_ui_props", "cl_ui_adopt", "cl_ui_render", "cl_ui_shaders", "cl_ui_effects", "cl_ui_about", "cl_mods_guide", "cl_ui_mods",
	"cl_speditor",
}

-- Derma skins of the interface themes: included on the client when a theme is chosen (cl_ui_themes.lua)
local SKIN_FILES = { "gmod", "speditor", "darkui", "steam2004", "gmod98", "oneshot", "lambdaui", "ecoui", "gmodxp", "vanillaui" }

local function exists(path)
	if file.Exists(path, "LUA") then return true end
	if SERVER then MsgC(Color(255, 200, 80), "[SPeditor] missing file: ", path, "\n") end
	return false
end

for _, name in ipairs(SHARED) do
	local path = BASE .. name .. ".lua"
	if exists(path) then
		if SERVER then AddCSLuaFile(path) end
		include(path)
	end
end

if SERVER then
	for _, name in ipairs(SERVER_FILES) do
		local path = BASE .. name .. ".lua"
		if exists(path) then include(path) end
	end
	for _, name in ipairs(CLIENT_FILES) do
		local path = BASE .. name .. ".lua"
		if file.Exists(path, "LUA") then AddCSLuaFile(path) end
	end
	for _, name in ipairs(SKIN_FILES) do
		local path = BASE .. "skins/" .. name .. ".lua"
		if file.Exists(path, "LUA") then AddCSLuaFile(path) end
	end
	-- notification styles and sound sets of other addons (cl_ui_notify_custom.lua)
	for _, f in ipairs(file.Find("speditor_notify/*.lua", "LUA") or {}) do AddCSLuaFile("speditor_notify/" .. f) end
else
	for _, name in ipairs(CLIENT_FILES) do
		local path = BASE .. name .. ".lua"
		if file.Exists(path, "LUA") then include(path) end
	end
end

-- Mods (lua/speditor_mods/<id>/mod.lua) are loaded after the editor itself
if SPeditor.Mods and SPeditor.Mods.LoadAll then SPeditor.Mods.LoadAll() end
