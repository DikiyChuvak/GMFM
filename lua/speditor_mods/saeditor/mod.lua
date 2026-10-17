-- SAeditor (Source Animation Editor) — a mod built into SPeditor.
-- Adds keyframe animation: a timeline with keys in the editor's bottom window,
-- playback, model animation import for ragdolls, sounds and voices on the timeline
-- and rendering of the animation to a video.
-- The editor itself stays a tool for still scenes: without this mod it has
-- not a single line about time.
return {
	name        = "SAeditor",
	version     = "0.6",
	author      = "SPeditor",
	description = {
		en = "Source Animation Editor: a timeline with keyframes for everything in the scene, playback, model animation import for ragdolls, spatial sounds and voices, effects played by keys, rendering to a video with sound.",
		ru = "Source Animation Editor: таймлайн с ключевыми кадрами для всего, что есть в сцене, воспроизведение, импорт анимаций модели на рэгдолл, пространственные звуки и голоса, эффекты по ключам, рендер в видео со звуком.",
	},
	api    = 1,
	net    = { "Config", "Seek", "Play", "Key", "Restore", "Bake", "Sync", "Summary", "Frame", "Sounds",
		"Proc", "Curve", "CurveData", "SMH", "Lip", "Show", "Cam", "Ghost", "Cuts", "Rec" },
	shared = { "sh_saeditor.lua" },
	server = { "sv_saeditor.lua", "sv_saeditor_record.lua" },
	client = { "cl_saeditor.lua", "cl_saeditor_sound.lua", "cl_saeditor_video.lua", "cl_saeditor_ui.lua",
		"cl_saeditor_curves.lua", "cl_saeditor_extra.lua", "cl_saeditor_lipsync.lua", "cl_saeditor_show.lua", "cl_saeditor_easy.lua",
		"cl_saeditor_ghost.lua", "cl_saeditor_cuts.lua", "cl_saeditor_player.lua", "cl_saeditor_record.lua",
		"cl_saeditor_guides.lua" },
}
