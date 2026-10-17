-- SAeditor (Source Animation Editor) — the animation part of SPeditor.
-- Keyframe animation: a timeline with keys in the editor's bottom window,
-- playback, model animation import for ragdolls, sounds and voices on the timeline
-- and rendering of the animation to a video.
-- Loaded by speditor_init.lua after the editor core (sh_component.lua).
return {
	name   = "SAeditor",
	net    = { "Config", "Seek", "Play", "Key", "Restore", "Bake", "Sync", "Summary", "Frame", "Sounds",
		"Proc", "Curve", "CurveData", "SMH", "Lip", "Show", "Cam", "Ghost", "Cuts", "Rec" },
	shared = { "sh_saeditor.lua" },
	server = { "sv_saeditor.lua", "sv_saeditor_record.lua" },
	client = { "cl_saeditor.lua", "cl_saeditor_sound.lua", "cl_saeditor_video.lua", "cl_saeditor_ui.lua",
		"cl_saeditor_curves.lua", "cl_saeditor_extra.lua", "cl_saeditor_lipsync.lua", "cl_saeditor_show.lua", "cl_saeditor_easy.lua",
		"cl_saeditor_ghost.lua", "cl_saeditor_cuts.lua", "cl_saeditor_player.lua", "cl_saeditor_record.lua",
		"cl_saeditor_guides.lua" },
}
