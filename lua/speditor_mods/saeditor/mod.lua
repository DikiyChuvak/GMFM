-- SAeditor (Source Animation Editor) — a mod built into SPeditor.
-- Adds keyframe animation: a timeline with keys in the editor's bottom window,
-- playback, model animation import for ragdolls, sounds and voices on the timeline
-- and rendering of the animation to a video.
-- The editor itself stays a tool for still scenes: without this mod it has
-- not a single line about time.
return {
	name        = "SAeditor",
	version     = "0.4",
	author      = "SPeditor",
	description = {
		en = "Source Animation Editor: a timeline with keyframes for everything in the scene, playback, model animation import for ragdolls, spatial sounds and voices, effects played by keys, rendering to a video with sound.",
		ru = "Source Animation Editor: таймлайн с ключевыми кадрами для всего, что есть в сцене, воспроизведение, импорт анимаций модели на рэгдолл, пространственные звуки и голоса, эффекты по ключам, рендер в видео со звуком.",
	},
	api    = 1,
	net    = { "Config", "Seek", "Play", "Key", "Restore", "Bake", "Sync", "Summary", "Frame", "Sounds" },
	shared = { "sh_saeditor.lua" },
	server = { "sv_saeditor.lua" },
	client = { "cl_saeditor.lua", "cl_saeditor_sound.lua", "cl_saeditor_video.lua", "cl_saeditor_ui.lua" },
}
