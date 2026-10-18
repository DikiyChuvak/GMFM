-- SPeditor loader
SPeditor = SPeditor or {}

local BASE = "speditor/"

local SHARED = { "sh_config", "sh_errors", "sh_util", "sh_lang", "sh_component" }
local SERVER_FILES = { "sv_net", "sv_speditor", "sv_persistence", "sv_adopt", "sv_pac" }
local CLIENT_FILES = {
	"cl_net", "cl_pac", "cl_keys", "cl_scene", "cl_history", "cl_camera", "cl_gizmo",
	"cl_bone_manip", "cl_flex", "cl_ik", "cl_shadows", "cl_lights", "cl_effects", "cl_tools", "cl_shaders", "cl_postfx", "cl_render", "cl_ssao", "cl_export",
	"cl_ui_theme", "cl_ui_notify", "cl_ui_notify_custom", "cl_ui_themes", "cl_ui_userthemes", "cl_ui_settings", "cl_ui_dock", "cl_ui_soundpick", "cl_ui_main", "cl_ui_ase", "cl_ui_ev", "cl_ui_pages",
	"cl_ui_model_list", "cl_ui_props", "cl_ui_pac", "cl_ui_adopt", "cl_ui_render", "cl_ui_shaders", "cl_ui_effects", "cl_ui_about", "cl_ui_report", "cl_selftest", "cl_ui_guide", "cl_guides", "cl_ui_lang",
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
	-- language packs of the community (sh_lang.lua, SPeditor.AddLanguage)
	for _, f in ipairs(file.Find("speditor_lang/*.lua", "LUA") or {}) do AddCSLuaFile("speditor_lang/" .. f) end
else
	for _, name in ipairs(CLIENT_FILES) do
		local path = BASE .. name .. ".lua"
		if file.Exists(path, "LUA") then include(path) end
	end
end

-- Built-in components (lua/speditor/<id>/component.lua) are loaded after the editor core
if SPeditor.Components and SPeditor.Components.Load then SPeditor.Components.Load("saeditor") end

-- Language packs (lua/speditor_lang/<code>.lua of any addon) come last, so that they can
-- translate the strings of the components too. Only the client shows text.
if CLIENT then
	for _, f in ipairs(file.Find("speditor_lang/*.lua", "LUA") or {}) do
		local ok, err = pcall(include, "speditor_lang/" .. f)
		if not ok then MsgC(Color(255, 200, 80), "[SPeditor lang] ", f, ": ", tostring(err), "\n") end
	end
	hook.Run("SPeditor_LanguagesLoaded")
end
