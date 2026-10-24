-- Shared settings of GM:FM — Garry's Mod Filmmaker (called SPeditor until b0.1; the code keeps
-- the SPeditor table, hooks and the data/speditor folder, so that mods and saved scenes work on)
SPeditor = SPeditor or {}
SPeditor.Name     = "GM:FM"
SPeditor.FullName = "Garry's Mod Filmmaker"
SPeditor.Version = "b0.2.4"
SPeditor.VersionBase = "b0.2"   -- the release the patch builds on: About lists its news under the patch's
SPeditor.VersionPrev = "b0.2.3" -- the patch before this one
-- every update since b0.1, newest first: version, release date, prefix of its news in the
-- language files (About → What's new, b0.2.4)
SPeditor.History = {
	{ "b0.2.4", "2026-10-24", "about_w" },
	{ "b0.2.3", "2026-10-23", "about_u" },
	{ "b0.2.2", "2026-10-22", "about_p" },
	{ "b0.2.1", "2026-10-22", "about_v021_" },
	{ "b0.2",   "2026-10-21", "about_n" },
	{ "b0.1",   "2026-10-20", "about_v01_" },
}
SPeditor.GitHub  = "https://github.com/DikiyChuvak/GMFM"     -- address of the addon page (empty: the About window shows a caption instead of a link)
SPeditor.BugsURL = "https://steamcommunity.com/workshop/filedetails/discussion/3817852435/567048683131023614/"   -- "Bug Report and ideas" (Help → Report a problem)

SPeditor.Net = {
	Toggle        = "SPeditor_Toggle",
	State         = "SPeditor_State",
	Notice        = "SPeditor_Notice",
	Spawn         = "SPeditor_Spawn",
	Spawned       = "SPeditor_Spawned",
	ObjRemove     = "SPeditor_ObjRemove",
	ObjRestore    = "SPeditor_ObjRestore",
	Delete        = "SPeditor_Delete",
	Duplicate     = "SPeditor_Duplicate",
	Transform     = "SPeditor_Transform",
	PhysBone      = "SPeditor_PhysBone",
	BoneManip     = "SPeditor_BoneManip",
	Reset         = "SPeditor_Reset",
	Flex          = "SPeditor_Flex",
	EyeTarget     = "SPeditor_EyeTarget",
	Skin          = "SPeditor_Skin",
	Bodygroup     = "SPeditor_Bodygroup",
	Rename        = "SPeditor_Rename",
	Flags         = "SPeditor_Flags",
	DropToFloor   = "SPeditor_DropToFloor",
	LightSpawn    = "SPeditor_LightSpawn",
	LightEdit     = "SPeditor_LightEdit",
	Cleanup       = "SPeditor_Cleanup",
	PoseGet       = "SPeditor_PoseGet",
	PoseData      = "SPeditor_PoseData",
	PoseApply     = "SPeditor_PoseApply",
	SceneSave     = "SPeditor_SceneSave",
	SceneLoad     = "SPeditor_SceneLoad",
	SceneLoaded   = "SPeditor_SceneLoaded",
	SceneList     = "SPeditor_SceneList",
	SceneListData = "SPeditor_SceneListData",
	SceneDelete   = "SPeditor_SceneDelete",
	CameraSpawn   = "SPeditor_CameraSpawn",
	CameraEdit    = "SPeditor_CameraEdit",
	CameraView    = "SPeditor_CameraView",
	Scale         = "SPeditor_Scale",
	Attach        = "SPeditor_Attach",
	Outfit        = "SPeditor_Outfit",      -- b0.2.4: put a saved outfit on a character (cl_presets.lua)
	Aim           = "SPeditor_Aim",
	Look          = "SPeditor_Look",
	CameraFX      = "SPeditor_CameraFX",
	ShadowCtl     = "SPeditor_ShadowCtl",
	ViewPos       = "SPeditor_ViewPos",
	EffectSpawn   = "SPeditor_EffectSpawn",
	EffectEdit    = "SPeditor_EffectEdit",
	AdoptList     = "SPeditor_AdoptList",
	AdoptListData = "SPeditor_AdoptListData",
	Adopt         = "SPeditor_Adopt",
	PAC           = "SPeditor_PAC",        -- PAC3 outfits of scene objects (sv_pac.lua, cl_pac.lua)
	PACSync       = "SPeditor_PACSync",
	Env           = "GMFM_Env",            -- the lighting of the whole map (sv_env.lua, cl_env.lua)
	EnvInfo       = "GMFM_EnvInfo",
	EnvLightmaps  = "GMFM_EnvLightmaps",
	EnvMapSounds  = "GMFM_EnvMapSounds",
}

-- Extended settings of a spot light (shadows, falloff, beam shape).
-- One list for client and server: the LightEdit network packet, scene saving,
-- edit history and interface controls all follow it.
-- key — field name in state tables, nw — NetworkVar name of the speditor_light entity
SPeditor.LightFields = {
	{ key = "soft",  nw = "ShadowSoft",  min = 0,    max = 5,    default = 0.2 },
	{ key = "bias",  nw = "ShadowBias",  min = 0,    max = 0.01, default = 0.0001 },
	{ key = "near",  nw = "ShadowNear",  min = 1,    max = 1000, default = 10 },
	{ key = "slope", nw = "ShadowSlope", min = 0,    max = 16,   default = 0 },
	{ key = "attc",  nw = "AttConst",    min = 0,    max = 10,   default = 0 },
	{ key = "attl",  nw = "AttLinear",   min = 0,    max = 2000, default = 100 },
	{ key = "attq",  nw = "AttQuad",     min = 0,    max = 5000, default = 0 },
	{ key = "osize", nw = "OrthoSize",   min = 8,    max = 4000, default = 200 },
	-- a0.2: soft light and visible source (a0.1 scenes lack these fields — they stay zero, the look does not change)
	{ key = "edge",  nw = "EdgeSoft",    min = 0,    max = 1,    default = 0 },     -- softness of the spot edge
	{ key = "area",  nw = "SourceSize",  min = 0,    max = 64,   default = 0 },     -- source size: soft shadows in the render
	{ key = "glow",  nw = "GlowSize",    min = 0,    max = 400,  default = 0 },     -- glow of the source, units (0 — none)
	{ key = "glowb", nw = "GlowBright",  min = 0,    max = 4,    default = 1 },
	{ key = "vol",   nw = "VolStrength", min = 0,    max = 1,    default = 0 },     -- visible beam in the air
	{ key = "voll",  nw = "VolLength",   min = 0.05, max = 1,    default = 0.5 },   -- beam length as a share of the distance
}
SPeditor.DefaultLightTexture = "effects/flashlight001"

-- Motion of a scene camera (a0.3): shake and smoothness. One list for client and server.
-- key — field name in state tables and in the CameraEdit message, nw — NetworkVar name.
--   shake     how far the camera is thrown about, units (0 — it stands still)
--   shakerot  how far it is turned about, degrees
--   shakefreq how fast, shakes per second
--   smooth    smoothing of the camera's path in an animation, seconds: the camera does not
--             stop and turn sharply at the keys but floats through them
--   znear     the near clipping plane, units (b0.2.2, SFM's znear): what is closer to the lens
--             than this is cut away — a smaller one lets the camera come right up to a face
SPeditor.CameraFields = {
	{ key = "shake",     nw = "ShakeAmp",  min = 0,   max = 40, default = 0 },
	{ key = "shakerot",  nw = "ShakeRot",  min = 0,   max = 15, default = 0 },
	{ key = "shakefreq", nw = "ShakeFreq", min = 0.2, max = 20, default = 3 },
	{ key = "smooth",    nw = "CamSmooth", min = 0,   max = 3,  default = 0 },
	{ key = "znear",     nw = "ZNear",     min = 0.1, max = 100, default = 3 },
}

-- Effect objects (a0.3, the speditor_effect entity). An effect is one of:
--   pcf  — a particle system of the engine (the game's own .pcf files and those of addons);
--          the editor can stop it at any moment, so it has an exact "moment" in a still;
--   tool — an effect of the Emitter tool of the sandbox (the "EffectType" list);
--   lua  — an effect started with util.Effect (engine and Lua effects, addons included).
-- The last two play by themselves and cannot be stopped: they are started over, not frozen.
-- key — field name in state tables, nw — NetworkVar name of the entity.
SPeditor.EffectSources = { pcf = true, tool = true, lua = true }
SPeditor.EffectFields = {
	{ key = "time",   nw = "FxTime",   min = 0,    max = 600,  default = 0.25 },   -- the moment of the effect, seconds from its start
	{ key = "scale",  nw = "FxScale",  min = 0.05, max = 20,   default = 1 },      -- size (tool and lua effects)
	{ key = "length", nw = "FxLength", min = 0,    max = 8000, default = 0 },      -- distance to the second point (tracers, beams)
}

-- A checked copy of an effect description { src, name, file }, or nil
function SPeditor.CleanEffect(d)
	if type(d) ~= "table" then return nil end
	local src, name, path = d.src, d.name, d.file
	if not SPeditor.EffectSources[src] or type(name) ~= "string" then return nil end
	if name == "" or #name > 96 or string.find(name, "[%c\"]") then return nil end
	if src ~= "pcf" and string.find(name, "[^%w_%-%.]") then return nil end
	if src ~= "pcf" or type(path) ~= "string" then path = "" end
	if path ~= "" then
		path = string.gsub(path, "\\", "/")
		if #path > 120 or string.find(path, "..", 1, true) or not string.match(path, "^particles/[%w_%-/%. ]+%.pcf$") then path = "" end
	end
	return { src = src, name = name, file = path }
end

-- Prop shadows from the map light (the shadow_control entity): allowed values
SPeditor.MapShadowLimits = {
	dist = { min = 0, max = 4000, default = 75 },      -- shadow length
	dark = { min = 0, max = 255,  default = 128 },     -- shadow colour: 0 — black, 255 — invisible
	pitch = { min = 5, max = 90,  default = 80 },      -- direction pitch (90 — straight down)
	yaw  = { min = 0, max = 360,  default = 30 },
}

SPeditor.Config = {
	MaxProps        = 200,
	MaxLights       = 24,
	MaxCameras      = 16,
	MaxEffects      = 64,
	MaxSceneName    = 48,
	MaxMetaLen      = 8000,
	AutosaveKeep    = 5,       -- how many autosaves to keep
	SaveDir         = "speditor",
	SpawnDistance   = 120,
	MaxRenderSide   = 3840,
	DuplicateOffset = 30,
}

-- The "no textures" material: the model turns plain white and takes the object colour
SPeditor.WhiteMaterial = "models/debug/debugwhite"

SPeditor.LightPresets = {
	{ name = "Soft white",     r = 255, g = 244, b = 224, radius = 400, brightness = 2,   fov = 60 },
	{ name = "Warm lamp",      r = 255, g = 180, b = 100, radius = 300, brightness = 2,   fov = 45 },
	{ name = "Cool moonlight", r = 140, g = 180, b = 255, radius = 600, brightness = 1.5, fov = 90 },
	{ name = "Neon cyan",      r = 70,  g = 235, b = 255, radius = 240, brightness = 3,   fov = 30 },
	{ name = "Neon magenta",   r = 255, g = 70,  b = 180, radius = 240, brightness = 3,   fov = 30 },
	{ name = "Fire",           r = 255, g = 100, b = 30,  radius = 200, brightness = 4,   fov = 50 },
}

-- Light kinds (a0.2): a full set of settings, not just a colour. They are applied to
-- the selected light (the preset column) or create a new one right away ("+" → Soft light).
-- ltype: 1 — spot, 0 — point; sh — extended settings (SPeditor.LightFields,
-- shadows, ortho, tex); whatever sh lacks takes the default.
-- The "speditor_gen/…" masks are drawn by the editor itself (cl_lights.lua).
SPeditor.LightKinds = {
	{ name = "Softbox",        ltype = 1, r = 255, g = 246, b = 234, radius = 600,  brightness = 1.6, fov = 75,
		sh = { tex = "speditor_gen/softbox", area = 18, soft = 1, attc = 1, attl = 0 } },
	{ name = "Strip light",    ltype = 1, r = 255, g = 248, b = 240, radius = 600,  brightness = 1.8, fov = 70,
		sh = { tex = "speditor_gen/strip", area = 12, soft = 0.8, attc = 1, attl = 0 } },
	{ name = "Beauty dish",    ltype = 1, r = 255, g = 240, b = 226, radius = 500,  brightness = 2,   fov = 60,
		sh = { tex = "speditor_gen/round", area = 10, soft = 0.6, attc = 1, attl = 0, glow = 40 } },
	{ name = "Ring light",     ltype = 1, r = 255, g = 250, b = 245, radius = 420,  brightness = 2,   fov = 64,
		sh = { tex = "speditor_gen/ring", area = 6, soft = 0.5, attc = 1, attl = 0, glow = 60, glowb = 1.2 } },
	{ name = "Rim light",      ltype = 1, r = 214, g = 232, b = 255, radius = 600,  brightness = 3.5, fov = 40,
		sh = { tex = "speditor_gen/round", edge = 0.3, area = 5, attc = 1, attl = 0 } },
	{ name = "Window light",   ltype = 1, r = 226, g = 238, b = 255, radius = 800,  brightness = 2.6, fov = 55,
		sh = { tex = "speditor_gen/window", area = 5, attc = 1, attl = 0, vol = 0.15, voll = 0.6 } },
	{ name = "Blinds",         ltype = 1, r = 255, g = 226, b = 184, radius = 800,  brightness = 3,   fov = 55,
		sh = { tex = "speditor_gen/blinds", area = 2, attc = 1, attl = 0, vol = 0.2, voll = 0.6 } },
	{ name = "Through leaves", ltype = 1, r = 255, g = 242, b = 204, radius = 1400, brightness = 2.6, fov = 60,
		sh = { tex = "speditor_gen/leaves", ortho = true, osize = 260, area = 5, attc = 1, attl = 0 } },
	{ name = "Golden hour",    ltype = 1, r = 255, g = 188, b = 118, radius = 1800, brightness = 3,   fov = 60,
		sh = { tex = "speditor_gen/round", ortho = true, osize = 340, area = 9, attc = 1, attl = 0 } },
	{ name = "Sunset gel",     ltype = 1, r = 255, g = 255, b = 255, radius = 900,  brightness = 2.6, fov = 70,
		sh = { tex = "speditor_gen/sunset", area = 10, attc = 1, attl = 0 } },
	{ name = "Moonlight",      ltype = 1, r = 150, g = 182, b = 255, radius = 1800, brightness = 1.1, fov = 60,
		sh = { tex = "speditor_gen/round", ortho = true, osize = 340, area = 14, attc = 1, attl = 0 } },
	{ name = "Stage spot",     ltype = 1, r = 255, g = 255, b = 255, radius = 900,  brightness = 5,   fov = 26,
		sh = { tex = "speditor_gen/disc", area = 2, attc = 1, attl = 0, vol = 0.6, voll = 0.75, glow = 120, glowb = 1.5 } },
	{ name = "Street lamp",    ltype = 1, r = 255, g = 202, b = 132, radius = 520,  brightness = 3,   fov = 100,
		sh = { tex = "speditor_gen/round", edge = 0.4, area = 6, vol = 0.3, voll = 0.5, glow = 110, glowb = 1.4 } },
	{ name = "Headlight",      ltype = 1, r = 236, g = 242, b = 255, radius = 1200, brightness = 5,   fov = 44,
		sh = { edge = 0.4, area = 3, attc = 1, attl = 0, vol = 0.4, voll = 0.4, glow = 170, glowb = 2 } },
	{ name = "Beacon",         ltype = 1, r = 255, g = 255, b = 255, radius = 700,  brightness = 4,   fov = 80,
		sh = { tex = "speditor_gen/split", area = 3, attc = 1, attl = 0, glow = 150, glowb = 1.6 } },
	{ name = "Eye slit",       ltype = 1, r = 255, g = 244, b = 230, radius = 500,  brightness = 3,   fov = 40,
		sh = { tex = "speditor_gen/slit", area = 2, attc = 1, attl = 0 } },
	{ name = "Candle",         ltype = 0, r = 255, g = 150, b = 62,  radius = 220,  brightness = 3,   fov = 60,
		sh = { glow = 42, glowb = 1.4 } },
	{ name = "Light bulb",     ltype = 0, r = 255, g = 214, b = 170, radius = 380,  brightness = 2.5, fov = 60,
		sh = { glow = 70, glowb = 1.2 } },
	{ name = "Neon tube",      ltype = 0, r = 90,  g = 230, b = 255, radius = 300,  brightness = 3.5, fov = 60,
		sh = { glow = 95, glowb = 1.6 } },
}

SPeditor.BoneGroups = {
	{ name = "Fingers", patterns = { "finger", "thumb" } },
	{ name = "Face",    patterns = { "jaw", "eye", "brow", "lip", "cheek", "tongue", "mouth", "face" } },
	{ name = "Spine",   patterns = { "pelvis", "spine", "neck", "head" } },
	{ name = "Arms",    patterns = { "clavicle", "upperarm", "forearm", "hand", "trapezius", "shoulder", "elbow", "wrist", "ulna", "bicep" } },
	{ name = "Legs",    patterns = { "thigh", "calf", "foot", "toe", "knee", "ankle" } },
}

-- Frame presets (aspect gate). w/h = 0 -> a free frame, sized by the viewport window.
SPeditor.Aspects = {
	{ id = "free",  name = "Free",         w = 0,  h = 0 },
	{ id = "16:9",  name = "16:9",         w = 16, h = 9 },
	{ id = "9:16",  name = "9:16",         w = 9,  h = 16 },
	{ id = "4:3",   name = "4:3",          w = 4,  h = 3 },
	{ id = "3:4",   name = "3:4",          w = 3,  h = 4 },
	{ id = "3:2",   name = "3:2",          w = 3,  h = 2 },
	{ id = "2:3",   name = "2:3 (poster)", w = 2,  h = 3 },
	{ id = "1:1",   name = "1:1",          w = 1,  h = 1 },
	{ id = "21:9",  name = "21:9",         w = 21, h = 9 },
	{ id = "A",     name = "A-series",     w = 1000, h = 1414 },
}

SPeditor.RenderSides = { 1280, 1920, 2560, 3840 }
