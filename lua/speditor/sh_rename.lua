--[[
GM:FM — the console names of SPeditor (b0.1).

Since b0.1 every console command and variable is called gmfm_* (they were speditor_* and
saeditor_*). So that nothing a player had set up is lost:
  * the old commands still work: each one runs the new one (binds like "bind F6 speditor_toggle");
  * the values the player had saved under the old names are taken over once, the first time
    b0.1 runs (migrate below);
  * scene files made before b0.1 keep frame settings under the old names: SPeditor.OldCvar(new)
    gives the old name to look them up by.
]]
SPeditor = SPeditor or {}

-- [new name] = old name
SPeditor.CvarRenamed = {
	gmfm_access = "speditor_access", gmfm_ase_merged = "speditor_ase_merged",
	gmfm_ase_nonphys = "speditor_ase_nonphys", gmfm_ase_tree = "speditor_ase_tree",
	gmfm_aspect = "speditor_aspect", gmfm_autosave = "speditor_autosave", gmfm_bone_keys = "saeditor_bone_keys",
	gmfm_bone_size = "speditor_bone_size", gmfm_browser_sort = "speditor_browser_sort",
	gmfm_cam_fov = "speditor_cam_fov", gmfm_cam_speed = "speditor_cam_speed",
	gmfm_cam_wheel = "speditor_cam_wheel", gmfm_cam_wheel_smooth = "speditor_cam_wheel_smooth",
	gmfm_dof = "speditor_dof", gmfm_dof_aperture = "speditor_dof_aperture",
	gmfm_dof_samples = "speditor_dof_samples", gmfm_ease_new = "saeditor_ease_new",
	gmfm_ev_range = "speditor_ev_range", gmfm_exposure = "speditor_exposure", gmfm_ghosts = "saeditor_ghosts",
	gmfm_gizmo_size = "speditor_gizmo_size", gmfm_gizmo_width = "speditor_gizmo_width",
	gmfm_guides = "speditor_guides", gmfm_ik = "speditor_ik", gmfm_lang_missing = "speditor_lang_missing",
	gmfm_lang_template = "speditor_lang_template", gmfm_language = "speditor_language",
	gmfm_lip_strength = "saeditor_lip_strength", gmfm_mapshadow = "speditor_mapshadow",
	gmfm_mapshadow_dark = "speditor_mapshadow_dark", gmfm_mapshadow_dist = "speditor_mapshadow_dist",
	gmfm_mapshadow_off = "speditor_mapshadow_off", gmfm_mapshadow_pitch = "speditor_mapshadow_pitch",
	gmfm_mapshadow_yaw = "speditor_mapshadow_yaw", gmfm_notify = "speditor_notify",
	gmfm_notify_anim = "speditor_notify_anim", gmfm_notify_bar = "speditor_notify_bar",
	gmfm_notify_max = "speditor_notify_max", gmfm_notify_opacity = "speditor_notify_opacity",
	gmfm_notify_pos = "speditor_notify_pos", gmfm_notify_snd_ = "speditor_notify_snd_",
	gmfm_notify_snd_0 = "speditor_notify_snd_0", gmfm_notify_snd_1 = "speditor_notify_snd_1",
	gmfm_notify_snd_2 = "speditor_notify_snd_2", gmfm_notify_snd_3 = "speditor_notify_snd_3",
	gmfm_notify_sound = "speditor_notify_sound", gmfm_notify_soundset = "speditor_notify_soundset",
	gmfm_notify_style = "speditor_notify_style", gmfm_notify_time = "speditor_notify_time",
	gmfm_notify_width = "speditor_notify_width", gmfm_ragdoll_guard = "speditor_ragdoll_guard",
	gmfm_rec_corpses = "saeditor_rec_corpses", gmfm_rec_effects = "saeditor_rec_effects",
	gmfm_rec_npcs = "saeditor_rec_npcs", gmfm_rec_phys = "saeditor_rec_phys",
	gmfm_rec_radius = "saeditor_rec_radius", gmfm_rec_sounds = "saeditor_rec_sounds",
	gmfm_rec_step = "saeditor_rec_step", gmfm_rec_uisounds = "saeditor_rec_uisounds",
	gmfm_rec_view = "saeditor_rec_view", gmfm_record = "saeditor_record",
	gmfm_record_stop = "saeditor_record_stop", gmfm_render = "speditor_render",
	gmfm_render_custom = "speditor_render_custom", gmfm_render_dof = "saeditor_render_dof",
	gmfm_render_done_window = "speditor_render_done_window", gmfm_render_engine = "speditor_render_engine",
	gmfm_render_format = "speditor_render_format", gmfm_render_fps = "saeditor_render_fps",
	gmfm_render_fullbright = "speditor_render_fullbright", gmfm_render_h = "speditor_render_h",
	gmfm_render_mblur = "saeditor_render_mblur", gmfm_render_mode = "saeditor_render_mode",
	gmfm_render_preview = "speditor_render_preview", gmfm_render_quality = "speditor_render_quality",
	gmfm_render_samples = "saeditor_render_samples", gmfm_render_settle = "saeditor_render_settle",
	gmfm_render_shutter = "saeditor_render_shutter", gmfm_render_side = "speditor_render_side",
	gmfm_render_slowfx = "saeditor_render_slowfx", gmfm_render_ss = "speditor_render_ss",
	gmfm_render_video = "saeditor_render_video", gmfm_render_w = "speditor_render_w",
	gmfm_report = "speditor_report", gmfm_rig = "speditor_rig", gmfm_rig_rings = "speditor_rig_rings",
	gmfm_rig_size = "speditor_rig_size", gmfm_rig_width = "speditor_rig_width",
	gmfm_selftest = "speditor_selftest", gmfm_shadow_dist = "speditor_shadow_dist",
	gmfm_shadow_max = "speditor_shadow_max", gmfm_shadow_onlylights = "speditor_shadow_onlylights",
	gmfm_shadow_quality = "speditor_shadow_quality", gmfm_shadow_slope = "speditor_shadow_slope",
	gmfm_shadow_softscale = "speditor_shadow_softscale", gmfm_shadows = "speditor_shadows",
	gmfm_show = "saeditor_show", gmfm_show_camera = "saeditor_show_camera",
	gmfm_show_look = "saeditor_show_look", gmfm_show_loop = "saeditor_show_loop",
	gmfm_show_stop = "saeditor_show_stop", gmfm_show_toggle = "saeditor_show_toggle",
	gmfm_softlight_samples = "speditor_softlight_samples", gmfm_ssao = "speditor_ssao",
	gmfm_ssao_radius = "speditor_ssao_radius", gmfm_ssao_strength = "speditor_ssao_strength",
	gmfm_stretch = "speditor_stretch", gmfm_theme = "speditor_theme", gmfm_toggle = "speditor_toggle",
	gmfm_ui_accent = "speditor_ui_accent", gmfm_ui_anim = "speditor_ui_anim",
	gmfm_ui_corners = "speditor_ui_corners", gmfm_ui_font = "speditor_ui_font",
	gmfm_ui_fontsize = "speditor_ui_fontsize", gmfm_ui_scale = "speditor_ui_scale",
	gmfm_ui_snd_back = "speditor_ui_snd_back", gmfm_ui_snd_click = "speditor_ui_snd_click",
	gmfm_ui_sounds = "speditor_ui_sounds", gmfm_ui_tabstyle = "speditor_ui_tabstyle",
	gmfm_video_quality = "saeditor_render_quality", gmfm_vp_look = "speditor_vp_look",
}

function SPeditor.OldCvar(name) return SPeditor.CvarRenamed[name] end

-- The game keeps saved values in cfg/client.vdf / server.vdf, which Lua cannot read; but it hands a
-- saved value to a variable the moment one with that name is created. So the old variables are
-- created again (hidden, still saved) and what they bring is copied over once.
local function migrate()
	local flag = "speditor/b01_cvars_" .. (SERVER and "sv" or "cl") .. ".txt"
	local done = file.Exists(flag, "DATA")
	local n = 0
	for new, was in pairs(SPeditor.CvarRenamed) do
		local cv = GetConVar(new)
		-- only variables of this realm (a command has no variable; the client cannot make a
		-- server variable)
		if cv and not concommand.GetTable()[was] and (CLIENT or not cv:IsFlagSet(FCVAR_USERINFO)) then
			local old = GetConVar(was) or CreateConVar(was, cv:GetDefault(), { FCVAR_ARCHIVE, FCVAR_DONTRECORD },
				"Old name of " .. new .. " (SPeditor); kept only to take its value over")
			local v = old and old:GetString()
			if not done and v and v ~= cv:GetDefault() and cv:GetString() == cv:GetDefault() and #v < 512 then
				if SERVER then cv:SetString(v) else RunConsoleCommand(new, v) end
				n = n + 1
			end
		end
	end
	if done then return end
	file.CreateDir("speditor")
	file.Write(flag, os.date("%Y-%m-%d %H:%M:%S") .. " " .. n .. " values taken over")
	if n > 0 then MsgC(Color(120, 200, 255), "[GM:FM] settings of SPeditor taken over: ", n, "\n") end
end

-- called at the end of the loader, when every command and variable exists
function SPeditor.RenameCompat()
	local cmds = concommand.GetTable()
	local done = {}
	for new, was in pairs(SPeditor.CvarRenamed) do
		local fn = cmds[new]
		if fn and not GetConVar(was) and (not cmds[was] or SPeditor.oldAliases and SPeditor.oldAliases[was]) then
			concommand.Add(was, function(ply, _, args, str) return fn(ply, new, args, str) end)
			done[was] = true
		end
	end
	SPeditor.oldAliases = done
	local ok, err = pcall(migrate)
	if not ok then MsgC(Color(255, 120, 80), "[GM:FM] settings of SPeditor: ", tostring(err), "\n") end
end
