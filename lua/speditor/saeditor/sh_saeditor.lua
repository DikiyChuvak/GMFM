-- SAeditor: shared constants, interpolation maths, interface strings
local COMP = SPeditor.Component("saeditor")
COMP.SA = COMP.SA or {}
local SA = COMP.SA

SA.FPS_LIST   = { 12, 15, 24, 30, 60 }
SA.MAX_FRAMES = 432000          -- animation length in frames, at most (an hour at 120 fps)
SA.MAX_KEYS   = 100000          -- keys per object (a baked 12-minute animation has ~10 000)
-- the kinds of motion from a key to the next one. "spline" (a0.6, the default for new keys) is
-- continuous: the object passes through a key without stopping, its speed worked out from the
-- keys around (sv_saeditor.lua, segment); the others are timing curves of one stretch.
SA.EASES      = { "spline", "ease", "linear", "ease_in", "ease_out", "sine", "expo", "back", "elastic", "bounce", "hold" }
SA.EASE_MAIN  = { "spline", "ease", "linear", "ease_in", "ease_out", "hold" }    -- the buttons of the curve editor

-- Models whose animations the import offers for any character with the same skeleton:
-- the player models carry every player animation (walking, gestures, dances and whatever
-- addons add to the player animation sets).
SA.ANIM_MODELS = {
	{ "sa_imp_src_male",   "models/player/kleiner.mdl" },
	{ "sa_imp_src_female", "models/player/alyx.mdl" },
	{ "sa_imp_src_zombie", "models/player/zombie_classic.mdl" },
}

SA.MAX_SOUNDS = 384             -- sound clips in one animation
SA.SOUND_EXT  = { wav = true, mp3 = true, ogg = true }
SA.SOUND_DIR  = "data/speditor/sounds"      -- the user's own sound files

-- A sound clip: { id, path, f = start frame, uid = the object it comes from (0 — heard
-- everywhere), voice = from the character's head, vol = 0..2, pitch = speed in percent,
-- dist = distance of full volume }. Returns a checked copy, or nil for a broken clip.
function SA.CleanSound(c)
	if not istable(c) or not isstring(c.path) then return nil end
	local path = string.gsub(c.path, "\\", "/")
	if #path < 8 or #path > 200 or string.find(path, "..", 1, true) or string.find(path, "[%c\":*?<>|]") then return nil end
	if string.sub(path, 1, 6) ~= "sound/" and string.sub(path, 1, 5) ~= "data/" then return nil end
	if not SA.SOUND_EXT[string.lower(string.GetExtensionFromFilename(path) or "")] then return nil end
	local function num(v, def, min, max) return math.Clamp(tonumber(v) or def, min, max) end
	return {
		id = math.floor(num(c.id, 0, 0, 1000000)), path = path,
		f = math.floor(num(c.f, 0, 0, SA.MAX_FRAMES) + 0.5), uid = math.floor(num(c.uid, 0, 0, 2 ^ 31)),
		voice = c.voice and true or false, vol = num(c.vol, 1, 0, 2),
		pitch = math.floor(num(c.pitch, 100, 25, 400) + 0.5), dist = num(c.dist, 300, 16, 8192),
		-- trimming: seconds of the file cut off at its start and at its end
		cin = math.Round(num(c.cin, 0, 0, 3600), 3), cout = math.Round(num(c.cout, 0, 0, 3600), 3),
		-- fades: seconds over which the clip rises from silence and sinks back into it
		fin = math.Round(num(c.fin, 0, 0, 60), 3), fout = math.Round(num(c.fout, 0, 0, 60), 3),
	}
end

-- 0..1: the fade of a clip at the moment `played` seconds after its start, `left` seconds
-- before its end
function SA.SoundFade(c, played, left)
	local g = 1
	if (c.fin or 0) > 0 then g = math.min(g, math.max(played, 0) / c.fin) end
	if (c.fout or 0) > 0 then g = math.min(g, math.max(left, 0) / c.fout) end
	return g
end

-- Face keys (a0.5): an object may have a second track that keys only its face (flexes),
-- apart from the keys of its body. Its id is the object's UID + SA.FACE; while it exists,
-- the body keys do not touch the face. Every track operation works on it as on any other.
SA.FACE = 2 ^ 30
function SA.IsFaceTrack(id) return id >= SA.FACE end
function SA.FaceTrack(uid) return uid + SA.FACE end

-- Lip sync (a0.6): a mouth shape is five channels, 0..1 each — how open the jaw is, how wide
-- the lips stretch, how round they are, pressed together (m, b, p), the lower lip under the
-- teeth (f, v). SA.MouthMap(ent) says which flexes of a model make each channel.
SA.LIP_CH = { "open", "wide", "round", "close", "bite" }

-- the faces of Valve characters (HL2, TF2, CS:S… — FACS flex controllers)
local LIP_VALVE = {
	jaw_drop = { 1, 0.2, 0.35 },
	right_part = { 1, 0.6, 0.4 }, left_part = { 1, 0.6, 0.4 },
	right_mouth_drop = { 0.6, 0.3 }, left_mouth_drop = { 0.6, 0.3 },
	right_stretcher = { 0, 0.8 }, left_stretcher = { 0, 0.8 },
	right_corner_puller = { 0, 0.25 }, left_corner_puller = { 0, 0.25 },
	right_puckerer = { 0, 0, 0.8 }, left_puckerer = { 0, 0, 0.8 },
	right_funneler = { 0, 0, 0.7 }, left_funneler = { 0, 0, 0.7 },
	presser = { 0, 0, 0, 0.9 }, tightener = { 0, 0, 0, 0.3 },
	bite = { 0, 0, 0, 0, 0.8 }, lip_bite = { 0, 0, 0, 0, 0.6 },
	right_upper_raiser = { 0, 0, 0, 0, 0.35 }, left_upper_raiser = { 0, 0, 0, 0, 0.35 },
}
-- other models: flexes by name (visemes of VRChat / MMD / ported models), one channel each
local LIP_NAMES = {
	{ 1, { "jaw_open", "jawopen", "mouth_open", "mouthopen", "open_mouth", "mouth_a", "viseme_aa", "vrc.v_aa", "aa", "a", "あ" } },
	{ 2, { "viseme_e", "viseme_ih", "vrc.v_e", "vrc.v_ih", "mouth_e", "mouth_i", "ee", "e", "i", "い", "え" } },
	{ 3, { "viseme_ou", "viseme_oh", "viseme_o", "viseme_u", "vrc.v_ou", "vrc.v_oh", "mouth_o", "mouth_u", "oo", "o", "u", "ou", "お", "う" } },
	{ 4, { "viseme_pp", "vrc.v_pp", "mbp", "mouth_close", "mouthclose", "mouth_press", "mouthpress" } },
	{ 5, { "viseme_ff", "vrc.v_ff", "fv", "f_v" } },
}

-- { [flex id] = { weight of each channel } } or nil — the model has no mouth to move
function SA.MouthMap(ent)
	local n = ent:GetFlexNum() or 0
	if n == 0 then return nil end
	local byName = {}
	for i = 0, n - 1 do
		local name = string.lower(ent:GetFlexName(i) or "")
		if name ~= "" and byName[name] == nil then byName[name] = i end
	end
	local map, open = {}, false
	for name, w in pairs(LIP_VALVE) do
		local id = byName[name]
		if id then
			map[id] = w
			if (w[1] or 0) > 0 then open = true end
		end
	end
	if open then return map end
	map = {}
	for _, ch in ipairs(LIP_NAMES) do
		for _, name in ipairs(ch[2]) do
			local id = byName[name]
			if id and not map[id] then
				local w = { 0, 0, 0, 0, 0 }
				w[ch[1]] = 1
				map[id] = w
				if ch[1] == 1 then open = true end
				break
			end
		end
	end
	-- no "open" in the names: a flex with jaw / mouth and open in its name
	if not open then
		for name, id in pairs(byName) do
			if (string.find(name, "jaw", 1, true) or string.find(name, "mouth", 1, true)) and string.find(name, "open", 1, true) then
				map[id] = { 1, 0, 0, 0, 0 }
				open = true
				break
			end
		end
	end
	return open and map or nil
end

-- actions of the Key message
-- SHIFT (a0.6): several keys of one track at once — str = "f1,f2,…", arg = by how many frames,
-- frame = 1 to copy them; they all move together, so a key never lands on one still to move
-- MOTION (a0.7, the Motion Editor): the edit of the object at frame goes over a time selection,
-- str = "a0,a1,b0,b1,shape" (full between a1 and b1… see SA.TimeSelWeight)
SA.OP = { SET = 1, DELETE = 2, MOVE = 3, EASE = 4, CLEAR = 5, CLEAR_ALL = 6, COPY = 7, SHIFT = 8, MOTION = 9 }

-- The Motion Editor's time selection (a0.7), as in SFM: { a0, a1, b0, b1, shape }. Between a1
-- and b0 an edit counts in full; from a0 up to a1 and from b0 down to b1 it fades out (the
-- falloff); outside it the animation is left as it was. shape: "smooth" (ease in and out) or "linear".
SA.TIMESEL_SHAPES = { "smooth", "linear" }
function SA.TimeSelWeight(f, s)
	if not s or f < s[1] or f > s[4] then return 0 end
	local t
	if f < s[2] then
		t = (f - s[1]) / math.max(s[2] - s[1], 1e-6)
	elseif f > s[3] then
		t = (s[4] - f) / math.max(s[4] - s[3], 1e-6)
	else
		return 1
	end
	t = math.Clamp(t, 0, 1)
	if s.shape == "linear" then return t end
	return t * t * (3 - 2 * t)
end

-- "a0,a1,b0,b1,shape" <-> the selection table (frames sorted and kept inside 0 … frames)
function SA.TimeSelString(s)
	return string.format("%d,%d,%d,%d,%s", s[1], s[2], s[3], s[4], s.shape or "smooth")
end
function SA.ParseTimeSel(str, frames)
	local a0, a1, b0, b1, shape = string.match(str or "", "^(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+),?(%a*)$")
	if not a0 then return nil end
	local t = { tonumber(a0), tonumber(a1), tonumber(b0), tonumber(b1) }
	table.sort(t)
	for i = 1, 4 do t[i] = math.Clamp(t[i], 0, frames or math.huge) end
	t.shape = (shape == "linear") and "linear" or "smooth"
	return t
end

-- "bezier": a timing curve of its own, drawn in the curve editor. bz = { x1, y1, x2, y2 } —
-- the two handles of a cubic curve from (0, 0) to (1, 1), as in CSS cubic-bezier; y may
-- leave 0..1 (the motion overshoots the key and comes back, or swings back before leaving).
local function bez(t, a, b)
	local s = 1 - t
	return 3 * a * t * s * s + 3 * b * t * t * s + t * t * t
end
function SA.BezierEase(u, bz)
	local x1, y1, x2, y2 = bz[1] or 0.25, bz[2] or 0, bz[3] or 0.75, bz[4] or 1
	local lo, hi = 0, 1
	for _ = 1, 22 do
		local mid = (lo + hi) * 0.5
		if bez(mid, x1, x2) < u then lo = mid else hi = mid end
	end
	return bez((lo + hi) * 0.5, y1, y2)
end

-- a valid easing name (the menu kinds and "bezier")
function SA.ValidEase(e) return e == "bezier" or table.HasValue(SA.EASES, e) end

-- bz from "x1,y1,x2,y2" (nil if broken); x in 0..1, y in -1..2
function SA.ParseBezier(str)
	local v = {}
	for n in string.gmatch(str or "", "[^,]+") do v[#v + 1] = tonumber(n) end
	if #v ~= 4 then return nil end
	for i = 1, 4 do if v[i] ~= v[i] then return nil end end
	return { math.Clamp(v[1], 0, 1), math.Clamp(v[2], -1, 2), math.Clamp(v[3], 0, 1), math.Clamp(v[4], -1, 2) }
end

-- The handles a kind of easing corresponds to (the curve editor starts editing from them)
SA.EASE_BEZIER = {
	ease = { 0.33, 0, 0.67, 1 }, linear = { 0.33, 0.33, 0.67, 0.67 },
	ease_in = { 0.5, 0, 0.85, 0.7 }, ease_out = { 0.15, 0.3, 0.5, 1 },
}

local PI = math.pi
local function bounceOut(u)
	local n, d = 7.5625, 2.75
	if u < 1 / d then return n * u * u end
	if u < 2 / d then u = u - 1.5 / d return n * u * u + 0.75 end
	if u < 2.5 / d then u = u - 2.25 / d return n * u * u + 0.9375 end
	u = u - 2.625 / d
	return n * u * u + 0.984375
end

-- 0..1 of the way at the share u of the time (it may leave 0..1: overshoot, swing back)
function SA.EaseValue(ease, u, bz)
	if ease == "bezier" and bz then return SA.BezierEase(u, bz) end
	if ease == "hold" then return 0 end
	if ease == "linear" then return u end
	if ease == "ease_in" then return u * u end                     -- starts slowly, arrives at full speed
	if ease == "ease_out" then return 1 - (1 - u) * (1 - u) end    -- leaves at full speed, slows down at the key
	if ease == "spline" then
		-- alone (no keys around) a spline stretch is a Hermite curve with half-speed ends;
		-- between keys the server works it out from the neighbours
		local u2, u3 = u * u, u * u * u
		return (u3 - 2 * u2 + u) * 0.5 + (-2 * u3 + 3 * u2) + (u3 - u2) * 0.5
	end
	if ease == "sine" then return -(math.cos(PI * u) - 1) / 2 end   -- softer than smooth
	if ease == "expo" then                                          -- a sharp rush in the middle
		if u <= 0 then return 0 elseif u >= 1 then return 1 end
		return u < 0.5 and 2 ^ (20 * u - 10) / 2 or (2 - 2 ^ (-20 * u + 10)) / 2
	end
	if ease == "back" then                                          -- swings back, overshoots, settles
		local c2 = 1.70158 * 1.525
		if u < 0.5 then return ((2 * u) ^ 2 * ((c2 + 1) * 2 * u - c2)) / 2 end
		return ((2 * u - 2) ^ 2 * ((c2 + 1) * (u * 2 - 2) + c2) + 2) / 2
	end
	if ease == "elastic" then                                       -- springs around the key and calms down
		if u <= 0 then return 0 elseif u >= 1 then return 1 end
		return 2 ^ (-10 * u) * math.sin((u * 10 - 0.75) * (2 * PI / 3)) + 1
	end
	if ease == "bounce" then return bounceOut(u) end               -- bounces on the key like a ball
	return u * u * (3 - 2 * u)
end

---------------------------------------------------------------------
-- Rotation along the shortest arc. LerpAngle adds Euler angles one by one,
-- and between distant poses a bone travels in a "figure of eight"; here the rotation difference
-- is converted to an axis and an angle, and the rotation goes around that axis evenly.
---------------------------------------------------------------------
local sin, cos, acos, sqrt, rad, deg = math.sin, math.cos, math.acos, math.sqrt, math.rad, math.deg

-- u may leave 0..1 (an easing that overshoots): the turn goes on along the same arc
function SA.SlerpAngle(a, b, u)
	if u == 0 then return Angle(a.p, a.y, a.r) end
	if u == 1 then return Angle(b.p, b.y, b.r) end
	-- rotation of b relative to a
	local _, l = WorldToLocal(vector_origin, b, vector_origin, a)
	-- its quaternion (the AngleQuaternion formula from Source)
	local sy, cy = sin(rad(l.y) * 0.5), cos(rad(l.y) * 0.5)
	local sp, cp = sin(rad(l.p) * 0.5), cos(rad(l.p) * 0.5)
	local sr, cr = sin(rad(l.r) * 0.5), cos(rad(l.r) * 0.5)
	local x = sr * cp * cy - cr * sp * sy
	local y = cr * sp * cy + sr * cp * sy
	local z = cr * cp * sy - sr * sp * cy
	local w = cr * cp * cy + sr * sp * sy
	if w < 0 then x, y, z, w = -x, -y, -z, -w end
	local s = sqrt(math.max(1 - w * w, 0))
	local out = Angle(a.p, a.y, a.r)
	if s < 1e-5 then return out end
	-- the axis in the space of a (x forward, y left, z up) -> into the world
	local axis = a:Forward() * (x / s) - a:Right() * (y / s) + a:Up() * (z / s)
	out:RotateAroundAxis(axis, deg(2 * acos(math.min(w, 1))) * u)
	return out
end

function SA.LerpNum(a, b, u) return a + (b - a) * u end

-- Angles as quaternions (Source's AngleQuaternion / QuaternionMatrix): a weighted sum of turns
-- (the spline) is done on them
function SA.AngToQuat(a)
	local sy, cy = sin(rad(a.y) * 0.5), cos(rad(a.y) * 0.5)
	local sp, cp = sin(rad(a.p) * 0.5), cos(rad(a.p) * 0.5)
	local sr, cr = sin(rad(a.r) * 0.5), cos(rad(a.r) * 0.5)
	return sr * cp * cy - cr * sp * sy, cr * sp * cy + sr * cp * sy, cr * cp * sy - sr * sp * cy, cr * cp * cy + sr * sp * sy
end

function SA.QuatToAng(x, y, z, w)
	local fwd = Vector(1 - 2 * y * y - 2 * z * z, 2 * x * y + 2 * w * z, 2 * x * z - 2 * w * y)
	local up = Vector(2 * x * z + 2 * w * y, 2 * y * z - 2 * w * x, 1 - 2 * x * x - 2 * y * y)
	return fwd:AngleEx(up)
end

-- angles with weights (the weights add up to 1; some may be negative); ref — the index whose
-- hemisphere the others are brought to
function SA.BlendAngles(angs, ws, ref)
	local rx, ry, rz, rw = SA.AngToQuat(angs[ref])
	local X, Y, Z, W = 0, 0, 0, 0
	for i, a in ipairs(angs) do
		local x, y, z, w = SA.AngToQuat(a)
		if x * rx + y * ry + z * rz + w * rw < 0 then x, y, z, w = -x, -y, -z, -w end
		X, Y, Z, W = X + x * ws[i], Y + y * ws[i], Z + z * ws[i], W + w * ws[i]
	end
	local len = sqrt(X * X + Y * Y + Z * Z + W * W)
	if len < 1e-6 then return Angle(angs[ref].p, angs[ref].y, angs[ref].r) end
	return SA.QuatToAng(X / len, Y / len, Z / len, W / len)
end

-- The weights of the four keys around a spline stretch (Catmull-Rom with the real distances in
-- time between the keys, as a Hermite curve): t0 < t1 <= frame < t2 < t3, u — the share of t1..t2
function SA.SplineWeights(t0, t1, t2, t3, u)
	local a = (t2 - t1) / math.max(t2 - t0, 1e-6)
	local b = (t2 - t1) / math.max(t3 - t1, 1e-6)
	local u2, u3 = u * u, u * u * u
	local h00, h10, h01, h11 = 2 * u3 - 3 * u2 + 1, u3 - 2 * u2 + u, -2 * u3 + 3 * u2, u3 - u2
	return -h10 * a, h00 - h11 * b, h01 + h10 * a, h11 * b
end

---------------------------------------------------------------------
-- Tables bigger than one net message (64 KB): a long animation has tens of thousands of
-- keys. The compressed JSON goes out in parts, a few parts a tick; every part carries
-- serial · part · count. A newer table of the same message replaces one still on its way.
---------------------------------------------------------------------
local PART = 60000

-- util.JSONToTable keeps at most 15 000 entries of one table and drops the rest silently
-- (verified in game), so long key lists travel and are saved as pages of PAGE entries.
local PAGE = 10000
function SA.ToPages(list)
	local pages = {}
	for i, v in ipairs(list) do
		local p = math.floor((i - 1) / PAGE) + 1
		pages[p] = pages[p] or {}
		pages[p][#pages[p] + 1] = v
	end
	return pages
end
function SA.FromPages(pages)
	local list = {}
	for _, page in ipairs(istable(pages) and pages or {}) do
		for _, v in ipairs(istable(page) and page or {}) do list[#list + 1] = v end
	end
	return list
end
-- the same for a { [key] = value } table: up to PAGE entries it stays as it is
function SA.MapToPages(map)
	if table.Count(map) <= PAGE then return map end
	local pages, page, n = {}, {}, 0
	for k, v in pairs(map) do
		page[k], n = v, n + 1
		if n >= PAGE then pages[#pages + 1], page, n = page, {}, 0 end
	end
	if n > 0 then pages[#pages + 1] = page end
	return { pages = pages }
end
function SA.MapFromPages(t)
	if not istable(t) or not istable(t.pages) then return t end
	local map = {}
	for _, page in ipairs(t.pages) do
		for k, v in pairs(istable(page) and page or {}) do map[k] = v end
	end
	return map
end
if SERVER then
	local queue, serial = {}, 0
	local function sendPart(ply, job)
		local from = (job.i - 1) * PART
		local chunk = string.sub(job.data, from + 1, from + PART)
		COMP:NetStart(job.name)
		net.WriteUInt(job.serial, 16)
		net.WriteUInt(job.i, 16)
		net.WriteUInt(job.n, 16)
		net.WriteUInt(#chunk, 16)
		net.WriteData(chunk, #chunk)
		net.Send(ply)
		job.i = job.i + 1
	end
	function SA.SendParts(ply, name, tbl)
		local data = util.Compress(util.TableToJSON(tbl) or "{}") or ""
		serial = serial % 65535 + 1
		local job = { name = name, serial = serial, data = data, n = math.max(math.ceil(#data / PART), 1), i = 1 }
		local q = queue[ply] or {}
		queue[ply] = q
		for i = #q, 1, -1 do
			if q[i].name == name then table.remove(q, i) end
		end
		-- a table that fits one message goes out at once, as before (the order with other messages is kept)
		if #q == 0 and job.n == 1 then sendPart(ply, job) return end
		q[#q + 1] = job
	end
	hook.Add("Tick", "SAeditor.SendParts", function()
		for ply, q in pairs(queue) do
			if not IsValid(ply) then
				queue[ply] = nil
			else
				for _ = 1, 2 do
					local job = q[1]
					if not job then break end
					sendPart(ply, job)
					if job.i > job.n then table.remove(q, 1) end
				end
				if #q == 0 then queue[ply] = nil end
			end
		end
	end)
else
	local parts = {}
	function SA.ReceiveParts(name, fn)
		COMP:NetReceive(name, function()
			local ser, i, n = net.ReadUInt(16), net.ReadUInt(16), net.ReadUInt(16)
			local chunk = net.ReadData(net.ReadUInt(16))
			local buf = parts[name]
			if i == 1 then
				buf = { serial = ser, list = {} }
				parts[name] = buf
			elseif not buf or buf.serial ~= ser then
				return
			end
			buf.list[i] = chunk
			if i < n then return end
			parts[name] = nil
			local raw = util.Decompress(table.concat(buf.list))
			fn(raw and util.JSONToTable(raw) or nil)
		end)
	end
end

---------------------------------------------------------------------
-- Strings
---------------------------------------------------------------------
COMP:Lang("en", {
	sa_timeline = "Timeline",
	-- a0.6: animations from addons
	sa_imp_src_addon = "Animation pack of an addon…",
	sa_asrc_title = "Animations from addons",
	sa_asrc_hint = "Animation packs are models that hold only animations (the model browser hides them). Pick an addon — Workshop or a folder in garrysmod/addons — then a model: its animations are offered for the character if the skeletons share bone names.",
	sa_asrc_addon = "Addon", sa_asrc_model = "Model", sa_asrc_all = "Show all models of the addon, not only animation ones",
	sa_asrc_none = "No animation models here: tick “all models” to choose from the others",
	sa_asrc_info = "%d animations · %d of %d bones of the character match", sa_asrc_bad = "The model does not load",
	sa_asrc_go = "Take animations from it",
	-- a0.6: lip sync
	sa_lip_menu = "Lip sync", sa_lip_for = "Mouth of %s follows this sound", sa_lip_nobody = "Nobody in the scene has a mouth to move",
	sa_lip_strength = "How wide the mouth opens",
	sa_lip_noface = "This model has no mouth flexes to move", sa_lip_wait = "The sound is still loading: try again in a moment",
	sa_lip_failed = "The sound could not be read", sa_lip_silent = "The sound is silent: nothing to say",
	sa_lip_listening = "Listening to the sound (%d s)…",
	sa_lip_phonemes = "Lip sync: by the phonemes written in the file", sa_lip_loudness = "Lip sync: by loudness (the file has no phonemes)",
	sa_lip_done = "Lip sync: %s mouth keys on the face track",
	hist_sa_lipsync = "Lip sync",
	-- a0.6: ready motions and camera moves
	sa_easy = "Ready motion: for a character — walks, waves, dances…; for a camera — dolly, orbit, pan…",
	sa_easy_need = "Select a character or a camera first",
	sa_mo_menu = "Ready motions", sa_mo_more = "More animations…", sa_mo_missing = "This animation is not in the game",
	sa_mg_stand = "Stand", sa_mg_move = "Move", sa_mg_gesture = "Gestures", sa_mg_fun = "Fun", sa_mg_action = "Action",
	sa_mo_idle = "Stands and breathes", sa_mo_scared = "Stands scared", sa_mo_angry = "Stands angry", sa_mo_crouch = "Crouches", sa_mo_sit = "Sits cross-legged",
	sa_mo_walk = "Walks", sa_mo_run = "Runs", sa_mo_panic = "Runs in panic", sa_mo_sneak = "Sneaks crouching", sa_mo_zombie = "Walks like a zombie", sa_mo_swim = "Swims",
	sa_mo_wave = "Waves", sa_mo_yes = "Nods: yes", sa_mo_no = "Shakes the head: no", sa_mo_bow = "Bows", sa_mo_salute = "Salutes",
	sa_mo_come = "Beckons: come here", sa_mo_halt = "Signals: stop", sa_mo_forward = "Signals: forward",
	sa_mo_dance = "Dances", sa_mo_laugh = "Laughs", sa_mo_cheer = "Cheers", sa_mo_robot = "Robot dance", sa_mo_muscle = "Shows muscles",
	sa_mo_throw = "Throws", sa_mo_land = "Lands after a jump", sa_mo_flinch = "Flinches from a hit", sa_mo_die = "Falls dead", sa_mo_die2 = "Falls dead slowly",
	sa_cm_menu = "Camera move", sa_cm_need = "Select a camera first",
	sa_cm_in = "Dolly in (closer to what it sees)", sa_cm_out = "Dolly out", sa_cm_orbit_l = "Orbit left (a quarter circle)",
	sa_cm_orbit_r = "Orbit right (a quarter circle)", sa_cm_pan_l = "Pan left", sa_cm_pan_r = "Pan right",
	sa_cm_crane = "Crane up (rises, keeps looking)", sa_cm_shake = "Shake that calms down",
	hist_sa_camera_move = "Camera move",
	-- a0.6: ghosts, bone keys, a hint about edits without a key
	sa_show_cuts = "As the animation switches cameras (the Cameras row)",
	sa_pl_untitled = "Untitled scene", sa_pl_camera = "Camera", sa_pl_eyes = "Without a camera (your eyes)", sa_pl_exit = "Leave the player (Backspace)",
	sa_pl_stop = "Stop", sa_pl_prev = "Previous shot (PgUp)", sa_pl_next = "Next shot (PgDn)", sa_pl_play = "Play (Space)", sa_pl_pause = "Pause (Space)",
	sa_pl_loop_on = "Repeat: on (R)", sa_pl_loop_off = "Repeat: off (R)", sa_pl_mute = "Mute (M)",
	sa_rec_title = "Record gameplay", sa_rec_go = "Start recording",
	sa_rec_hint = "Play the game and it becomes animation, as in machinima: the editor closes, after a countdown everything you do is recorded — you as your player model with its skin and weapon, the NPCs around, their sounds and effects. Backspace stops the take; the editor opens with the actors keyed in the scene. The animation you already have plays along.",
	sa_rec_npcs = "Record the NPCs around", sa_rec_radius = "Radius for NPCs and effects, units", sa_rec_sounds = "Record sounds (steps, shots, voices)",
	sa_rec_phys = "Physics of the scene", sa_rec_phys_off = "Off", sa_rec_phys_sel = "Selected ragdolls and props",
	sa_rec_phys_all = "All ragdolls and props",
	sa_rec_phys_tip = "These scene objects are unfrozen for the take: they fall, collide, can be thrown with the physics gun — and get their own keys. Locked and attached objects stay as they are.",
	sa_rec_phys_go = "Record physics only (stay in the editor)", sa_rec_phys_stop = "Stop recording physics",
	sa_rec_phys_go_tip = "The selected ragdolls and props (all of them when nothing is selected) are let go from the current frame and fall under gravity; Stop (or Backspace) writes their keys.",
	sa_rec_phys_none = "No ragdolls or props with physics in the scene to record",
	sa_rec_done_phys = "Physics recorded: %d objects, %d keys",
	sa_rec_done_world = "Map objects recorded: %d",
	sa_rec_view = "Record my view as a camera (first person)",
	sa_rec_view_tip = "What you see while you play — where you look, how you turn, the zoom — becomes a scene camera keyed along the take, so the video can be shot through your eyes. Your own body is not drawn in it, as in the game.",
	sa_rec_done_view = "Your view is the camera %s: look through it (V) or choose it in Render → Animation → Cameras of the video",
	sa_rec_done_view_cut = "Your view is the camera %s, and the video goes through it (the Cameras row of the timeline)",
	sa_rec_effects = "Record effects (tracers, explosions, effects of weapons)", sa_rec_step = "A key every N frames",
	sa_rec_from = "The take starts at frame %d (the playhead)", sa_rec_get_ready = "Recording starts…",
	sa_rec_stop_hint = "Backspace — stop the take", sa_rec_done = "Take recorded: %d actors, %d keys, %d sounds, %d effects",
	sa_cuts_row = "Cameras", sa_cuts_empty = "Right click: which camera the animation is watched through from here",
	sa_cuts_nocam = "The scene has no cameras", sa_cuts_change = "Camera", sa_cuts_go = "Go to this cut", sa_cuts_delete = "Delete the cut",
	sa_cuts_here = "Switch to %s here (frame %d)", hist_sa_cut = "Camera cut",
	sa_ew_ease = "Smooth: starts slowly, speeds up, slows down into the next key", sa_ew_linear = "Even: the same speed all the way, starts and stops sharply",
	sa_ew_ease_in = "Speeds up: starts slowly and arrives at the next key at full speed", sa_ew_ease_out = "Slows down: leaves at full speed and comes gently to the next key",
	sa_ew_hold = "A jump: stays still and switches to the next key at once (a cut, a light switched on)",
	sa_ew_b_start_slow = "Own curve: starts slowly", sa_ew_b_start_fast = "Own curve: starts fast", sa_ew_b_start_even = "Own curve: starts at an even speed",
	sa_ew_b_end_slow = "comes gently to the next key", sa_ew_b_end_fast = "hits the next key at speed", sa_ew_b_end_even = "arrives at an even speed",
	sa_ew_b_over = "goes past the key and comes back", sa_ew_b_back = "swings back before leaving",
	sa_ew_none = "Select a key on the graph (or move the playhead between two keys) to see how it moves",
	sa_ew_from_to = "Frames %d → %d  (%.2f s)",
	sa_ghosts = "Ghosts: the selected model is shown see-through in its pose at the key before (blue) and after (green) the playhead",
	sa_bone_keys = "Bone keys: a key set while a bone is selected (K, auto key after a drag) holds only that bone, and every bone moves between its own keys",
	sa_bone_key_set = "Bone key at frame %s", sa_bone_key_here = "Set a key of this bone here", sa_bone_key_delete = "Delete the key of this bone",
	sa_bone_clear = "Delete all keys of this bone",
	sa_hint_moved = "The pose changed at a frame without a key: it will be lost when the playhead moves. Press K (or turn on Auto key) to keep it.",
	-- a0.6: watching the animation outside the editor
	sa_show = "Watch in the game (outside the editor)", sa_show_empty = "There is no animation to play yet",
	sa_show_menu = "Watch in the game", sa_show_eyes = "Walk around the scene (your own eyes)", sa_show_loop = "In a loop",
	sa_show_player = "Player", sa_show_player_tip = "Player: watch the animation through the cameras, full screen (outside the editor)",
	sa_show_eyes_tip = "Walk around the scene and watch the animation with your own eyes (Backspace stops)",
	sa_walk_hint = "Backspace — stop", sa_pl_look_on = "Render settings: on (V)", sa_pl_look_off = "Render settings: off (V)",
	sa_pl_pick_cam = "Click to pick the camera", sa_pl_look_nocam = "Render settings need a camera",
	sa_show_stop = "Stop", sa_show_cam = "Camera (name)", sa_show_cam_help = "Empty — the first camera of the scene; eyes — walk around the scene and watch it yourself.",
	sa_show_qhelp = "The animation of your scene plays in the game, with the editor closed: in the player through a scene camera, with its sounds, without the HUD (Backspace leaves it), or while you walk around the scene yourself (saeditor_show eyes). Console: saeditor_show [camera | eyes], saeditor_show_stop, saeditor_show_toggle — they can be bound to keys.",
	-- a0.5: curve editor, procedural motion, Stop Motion Helper, sound fades
	sa_ease_bezier = "Curve of its own (curve editor)",
	sa_crv_title = "Curve editor", sa_crv_none = "Nothing selected", sa_crv_pick = "Select an animated object or one of its bones",
	sa_crv_nokeys = "This object has no keys yet: set a key (K) and the curves appear here",
	sa_crv_fit = "Fit", sa_crv_fit_tip = "Show all the keys", sa_crv_norm = "Normalized",
	sa_crv_norm_tip = "Every channel scaled to its own range (degrees and units together); off — real values",
	sa_crv_ease_tip = "Motion from the selected key to the next one", sa_crv_need_key = "Select a key on a curve first",
	sa_crv_goto = "Go to this key",
	sa_crv_s_x = "X", sa_crv_s_y = "Y", sa_crv_s_z = "Z", sa_crv_s_pitch = "P", sa_crv_s_yaw = "Yw", sa_crv_s_roll = "R",
	sa_crv_s_fov = "FOV", sa_crv_s_bri = "Bri", sa_crv_s_radius = "Rad", sa_crv_s_lfov = "Cone", sa_crv_s_time = "Time",
	sa_crv_s_fxscale = "Size", sa_crv_s_scale = "Scale",
	sa_crv_ch_x = "Place: X", sa_crv_ch_y = "Place: Y", sa_crv_ch_z = "Place: Z (height)", sa_crv_ch_pitch = "Turn: pitch",
	sa_crv_ch_yaw = "Turn: yaw", sa_crv_ch_roll = "Turn: roll", sa_crv_ch_fov = "Field of view", sa_crv_ch_bri = "Brightness",
	sa_crv_ch_radius = "Radius", sa_crv_ch_lfov = "Cone angle", sa_crv_ch_time = "Moment of the effect", sa_crv_ch_fxscale = "Size of the effect",
	sa_crv_ch_scale = "Scale",
	hist_sa_curve = "Curve value", hist_sa_smh = "Stop Motion Helper import",
	sa_proc_title = "Procedural motion", sa_proc_need = "Select a model, a light or an effect",
	sa_proc_hint = "Life on top of the keys, worked out from time: it shows during playback and in the render (while you edit, the scene stays as the keys make it). Saved with the scene.",
	sa_proc_breath = "Breathing", sa_proc_rate = "Breaths a minute", sa_proc_blink = "Blinking", sa_proc_head = "Head moves by itself",
	sa_proc_sway = "Drift, units", sa_proc_freq = "Speed of the motion, Hz", sa_proc_preview = "Play to see it", sa_proc_off = "Switch off",
	sa_smh_title = "Stop Motion Helper", sa_smh_file = "SMH save", sa_smh_map = "Map", sa_smh_object = "Object in the save", sa_smh_keys = "Keys",
	sa_smh_hint = "Saves of Stop Motion Helper (garrysmod/data/smh, and data/smh or data_static/smh of addons) can be taken onto the selected object as keys, and the animation of the selected objects can be written as an SMH save (SMH: Load → the name of the model).",
	sa_smh_target = "Onto", sa_smh_no_target = "select a model in the scene", sa_smh_start = "First frame",
	sa_smh_conv = "Convert speed: SMH frames a second", sa_smh_world = "Keep the places of the save",
	sa_smh_import = "Take onto the object", sa_smh_pick = "Pick a save and an object in it",
	sa_smh_export_hint = "Write the animation of the selected objects as an SMH save named:", sa_smh_export = "Write the SMH save",
	sa_smh_need_anim = "Select animated objects first", sa_smh_none = "No SMH saves found",
	sa_smh_bad = "The SMH save cannot be read", sa_smh_kind = "SMH animates models only", sa_smh_nothing = "None of the selected objects has keys",
	sa_smh_imported = "Taken from the SMH save: %s keys", sa_smh_exported = "SMH save written (%s objects): %s",
	sa_snd_m_fin = "Fade in", sa_snd_m_fout = "Fade out", sa_snd_sec = "s",
	sa_snd_added_n = "%d sounds added one after another", sa_snd_add_n = "Add %d sounds", sa_snd_pick = "Select one or more sounds in the list",
	sa_snd_in_folder = "%d sounds in this folder · click — listen, Ctrl/Shift — several, double click — add",
	-- a0.5: face keys, frame sets in the render
	sa_face_key = "Set a face key for the selection (Shift+K): the face gets its own keys, apart from the body",
	sa_hk_face_key = "Set a face key for the selection", sa_face_row = "Face",
	sa_face_start = "Separate face keys: start here", sa_face_clear = "Remove the face keys (the body keys drive the face again)",
	sa_face_key_set = "Face key set: frame %d", sa_need_face = "Select a model with a face (flexes)",
	hist_sa_face_key = "Face key",
	sa_play = "Play / pause (Space)", sa_first = "To the first frame (Home)", sa_last = "To the last frame (End)",
	sa_prev_key = "Previous key", sa_next_key = "Next key",
	sa_prev_frame = "Previous frame (,)", sa_next_frame = "Next frame (.)",
	sa_key = "Set key for the selection (K)", sa_key_all = "Set key for every object",
	sa_key_delete = "Delete key", sa_autokey = "Auto key: every edit sets a key at the current frame",
	sa_loop = "Loop playback", sa_frame = "frame", sa_fps = "fps", sa_length = "length, s",
	sa_import = "Import model animation…", sa_render = "Render animation…",
	sa_menu = "Animation", sa_clear_track = "Remove animation of this object", sa_clear_all = "Remove all animation",
	sa_clear_all_q = "Remove all keys of all objects, the sounds and the camera cuts?",
	sa_ease = "Motion to the next key", sa_ease_ease = "Smooth", sa_ease_linear = "Linear", sa_ease_hold = "Hold (stepped)",
	sa_ease_spline = "Continuous (spline)", sa_ease_sine = "Gentle (sine)", sa_ease_expo = "Sharp (expo)", sa_ease_back = "With a swing (back)",
	sa_ease_elastic = "Springy (elastic)", sa_ease_bounce = "Bouncing (bounce)", sa_ease_more = "More",
	sa_ew_spline = "Continuous: passes through the keys without stopping, its speed follows from the keys around",
	sa_ew_sine = "Gentle: a very soft start and stop", sa_ew_expo = "Sharp: stands, rushes through the middle, stops dead",
	sa_ew_back = "With a swing: steps back first, overshoots the next key and settles on it",
	sa_ew_elastic = "Springy: overshoots the next key and wobbles around it, calming down",
	sa_ew_bounce = "Bouncing: hits the next key and bounces off it a few times, like a ball",
	sa_ease_ease_in = "Speed up (ease in)", sa_ease_ease_out = "Slow down (ease out)",
	sa_copy_key = "Copy key", sa_paste_key = "Paste key here", sa_key_here = "Set key here",
	sa_keys_n = "%d keys selected", sa_copy_keys = "Copy keys", sa_keys_delete = "Delete keys", sa_paste_keys = "Paste %d keys here",
	sa_no_tracks = "No animation yet. Select an object, move the playhead and press K — or switch Auto key on.",
	sa_need_sel = "Select an object first", sa_need_ragdoll = "Select a character (ragdoll)",
	sa_key_set = "Key set: frame %d", sa_keys_limit = "Too many keys for one object",
	sa_rd_blur = "Motion blur", sa_rd_blur_off = "Off", sa_rd_blur_n = "%d moments a frame",
	sa_rd_blur_tip = "Every frame of the video becomes the mean of several moments around it, as a film camera sees motion. The render takes that many times longer.",
	sa_rd_shutter = "Shutter", sa_rd_shutter_n = "%d°",
	sa_rd_shutter_tip = "How long the shutter stays open in a frame: 180° is the usual film look, 360° the longest blur, 90° a sharper, staccato motion.",
	sa_tsel = "Time selection (Motion Editor)",
	sa_tsel_tip = "Time selection (Motion Editor): a pose edit goes over a whole stretch of the animation, fading out at its edges. Shift + drag on the frame numbers makes one",
	sa_tsel_keys = "From the selected keys (%d – %d)", sa_tsel_around = "Around the playhead (±%d frames, with falloff)",
	sa_tsel_all = "The whole animation", sa_tsel_falloff = "Falloff", sa_tsel_fall_none = "None (a hard edge)",
	sa_tsel_fall_n = "%d frames (%s s)", sa_tsel_shape = "Falloff shape", sa_tsel_shape_smooth = "Smooth", sa_tsel_shape_linear = "Linear",
	sa_tsel_apply = "Put the current pose over the selection (K)", sa_tsel_select_keys = "Select the keys inside it",
	sa_tsel_clear = "Remove the time selection",
	sa_tsel_how = "Shift + drag on the frame numbers: a new selection. Drag its edges there; Shift + click removes it.",
	sa_motion_set = "Pose put over frames %s – %s", sa_status_tsel = "selection %d–%d",
	sa_status = "Animation: frame %d / %d  ·  %s",
	sa_status_play = "playing", sa_status_stop = "stopped", sa_status_auto = "AUTO KEY",
	sa_hk_play = "Play / pause the animation", sa_hk_key = "Set a key for the selection",
	sa_hk_prev = "Previous frame", sa_hk_next = "Next frame", sa_hk_first = "First frame", sa_hk_last = "Last frame",
	sa_imp_title = "Import model animation", sa_imp_search = "Search animations…",
	sa_imp_hint = "The animation of the model is baked into keys of the selected character, starting at the current frame.",
	sa_imp_step = "Key every N frames", sa_imp_loops = "Repeats", sa_imp_root = "Move the character along (root motion)",
	sa_imp_speed = "Speed", sa_imp_go = "Import", sa_imp_none = "This model has no animations",
	sa_imp_done = "Imported '%s': %d keys", sa_imp_col_name = "Animation", sa_imp_col_len = "Length, s",
	sa_imp_extend = "The animation is longer than the timeline: its length was increased.",
	sa_imp_src_own = "Animations of this model", sa_imp_src_male = "Player animations (male)",
	sa_imp_src_female = "Player animations (female)", sa_imp_src_zombie = "Player animations (zombie)",
	sa_imp_src_path = "Animations of another model…", sa_imp_src_prompt = "Path of a model with the same skeleton (models/….mdl):",
	sa_imp_src_tip = "A character can take the animations of another model with the same skeleton: a citizen can use the gestures and dances of the player models and of animation packs made for them.",
	sa_imp_skeleton = "This model has another skeleton: its animation does not fit the character",
	sa_imp_done_n = "Imported '%s' for %s characters",
	sa_rnd_title = "Render animation", sa_rnd_camera = "Camera",
	sa_rnd_from = "From frame", sa_rnd_to = "To frame", sa_rnd_name = "Name", 
	sa_rnd_settle = "Longest wait for the scene, s",
	sa_rnd_settle_tip = "The scene is moved by the server. A frame is taken as soon as every object has stopped on the client; this is the longest the render waits for that.",
	sa_rnd_go = "Render", sa_rnd_cancel = "Cancel",
	sa_rnd_progress = "Rendering frame %d of %d…", 
	sa_rnd_stopped = "Animation render stopped", sa_rnd_busy = "An animation render is already running",
	sa_rnd_failed = "Could not create the video file", sa_rnd_done_avi = "Animation rendered: %d frames, video %s (remove '.dat' from the name)",
	sa_rd_title = "Animated scene: %d frames, %.2f s, %d fps",
	sa_rd_what = "Render", sa_rd_anim = "The whole animation", sa_rd_frame = "Only the current frame",
	sa_rd_button = "Render animation", sa_rd_stop = "Stop the animation render",
	sa_rd_noanim = "The scene has no animation yet. Put keys on the timeline (K), import a motion or record gameplay — then the video is rendered here.",
	sa_rd_frames = "Frames", sa_rd_whole = "Whole animation",
	sa_rd_cams = "Cameras of the video", sa_rd_cam = "Shoot through",
	sa_rd_cam_cuts = "The shots below (switching cameras)",
	sa_rd_shot_none = "No shots yet: the video is shot through one camera. Add a shot to switch cameras from a frame on.",
	sa_rd_need_cam = "The scene has no cameras: + → Spawn Camera, then add shots here.",
	sa_rd_shot_n = "Shot %d", sa_rd_shot_frame = "From this frame on", sa_rd_shot_del = "Remove the shot",
	sa_rd_shot_go = "Go to its first frame", sa_rd_shot_gone = "(camera deleted)",
	sa_rd_shot_add = "Add a shot at the current frame",
	sa_rd_shots_hint = "A shot shows its camera from its frame until the next shot. Move the playhead (timeline or the preview's bar), then Add a shot: it takes the camera you look through or have selected. The shots are also the Cameras row at the top of the timeline.",
	sa_rd_note_avi = "One video file: garrysmod/data/speditor/renders/<name>.avi.dat. The game lets addons write only a few file types, so remove '.dat' from the name — it is a regular AVI that any player opens. On Windows choose WebM in Video file: a ready garrysmod/videos/<name>.webm, no renaming.",
	sa_rd_note_frame = "The Render button saves one picture of the current frame, as in a still scene.",
	hist_sa_key = "Keyframe", hist_sa_key_delete = "Delete key", hist_sa_key_move = "Move key", hist_sa_ease = "Key motion",
	hist_sa_clear = "Remove animation", hist_sa_import = "Import animation", hist_sa_paste = "Paste key",
	hist_sa_sound = "Sound", hist_sa_effect = "Effect playback",
	sa_fx_play = "Play the effect from this frame", sa_fx_to_end = "Until the end of the animation",
	sa_fx_for = "For %.2f s, then off",
	sa_rnd_fx_live = "Effects that play by themselves (%d) cannot be rendered frame by frame: in the video they run at their own speed. Use particle effects for exact frames.",
	-- a0.3: sounds and voices, faster animation render
	sa_snd_add = "Add a sound or a voice line…", sa_snd_title = "Sounds and voices",
	sa_snd_root_game = "Game sounds", sa_snd_root_user = "My files",
	sa_snd_up = "Up", sa_snd_filter = "Filter this folder…", sa_snd_col_name = "Name",
	sa_snd_preview = "Listen", sa_snd_stop = "Stop",
	sa_snd_attach = "Comes from the selected object (spatial sound)",
	sa_snd_voice = "Voice: comes from the character's head",
	sa_snd_go = "Add at the current frame",
	sa_snd_hint = "A sound is placed on the timeline at the current frame. A spatial sound gets quieter with distance from the camera and moves between left and right as the object or the camera moves. Your own files (WAV, MP3, OGG) go to garrysmod/data/speditor/sounds/. Only uncompressed WAV gets into the rendered video.",
	sa_snd_added = "Sound added: %s, frame %d", sa_snd_limit = "Too many sounds in one animation",
	sa_snd_failed = "Could not load the sound: %s",
	sa_snd_everywhere = "everywhere", sa_snd_voice_tag = "voice",
	sa_snd_m_emitter = "Comes from", sa_snd_m_none = "Nowhere: heard everywhere", sa_snd_m_selected = "The selected object",
	sa_snd_m_voice = "Voice (from the head)", sa_snd_m_volume = "Volume", sa_snd_m_pitch = "Speed and pitch",
	sa_snd_m_dist = "Distance of full volume", sa_snd_m_here = "Start at the current frame",
	sa_snd_m_dup = "Duplicate", sa_snd_m_delete = "Remove the sound", sa_snd_m_listen = "Listen", sa_snd_m_replace = "Replace the sound…",
	sa_snd_m_split = "Cut in two at the playhead", sa_snd_m_trim_in = "Trim the start to the playhead",
	sa_snd_m_trim_out = "Trim the end to the playhead", sa_snd_m_untrim = "Restore the whole sound",
	sa_snd_trim_bad = "The playhead is not inside this sound",
	sa_snd_skipped = "Sounds left out of the video (only uncompressed WAV can be mixed in): %s",
	sa_rd_quality = "Video size", sa_rd_video = "Video file",
	sa_rd_video_avi = "AVI (MJPEG with sound): data/speditor/renders, .avi.dat",
	sa_rd_video_webm = "WebM (VP8): garrysmod/videos, sound as .wav",
	sa_rd_video_tip = "WebM is made by the game's own video writer: a ready .webm in garrysmod/videos, smaller than AVI, at most the size of your screen. The editor's sound cannot go inside it, so it is saved next to it as a .wav in data/speditor/renders.",
	sa_rd_webm_no = "WebM is available on Windows only: on Linux and macOS the game's video writer makes no files.",
	sa_rnd_done_webm = "Animation rendered: %s frames, video %s (%s x %s)",
	sa_rnd_webm_wav = "The sound track is next to it: %s — put it under the video in any video editor", sa_rd_samples = "Shadow / DoF passes",
	sa_rd_fps = "Video frame rate", sa_rd_fps_anim = "As the animation (%d)",
	sa_rd_fps_tip = "Frames a second of the rendered video. Above the animation's rate the frames in between are posed between the keys (smooth 60 fps from a 24 fps animation).",
	sa_tl_tip = "Ctrl + wheel — zoom the timeline, Shift + wheel — scroll it in time, wheel — scroll the rows\nCtrl + click on a key — select several, Shift + drag — select keys in a box, drag a selected key — move them all (with Ctrl — copy)",
	sa_rd_samples_100 = "All, as in a still", sa_rd_samples_50 = "Half (faster)", sa_rd_samples_25 = "Quarter (fastest)",
	sa_rnd_part = "The video is larger than 1.9 GB: it continues in %s",
	sa_rd_q_100 = "Largest: JPEG 100 (7 times larger)", sa_rd_q_90 = "Normal: JPEG 90", sa_rd_q_70 = "Smaller by 40%: JPEG 70",
	sa_rd_q_50 = "Smaller by 65%: JPEG 50", sa_rd_q_30 = "Smallest, by 80%: JPEG 30",
	sa_rnd_size = "Video: %.1f MB, %.2f MB per second. Frames repeated without change: %d.",
	sa_rnd_mp4 = "The game can only write MJPEG video. To make it several times smaller without visible loss: ffmpeg -i %s -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac %s.mp4",
})

COMP:Lang("ru", {
	sa_timeline = "Таймлайн",
	-- a0.6: анимации из аддонов
	sa_imp_src_addon = "Пак анимаций из аддона…",
	sa_asrc_title = "Анимации из аддонов",
	sa_asrc_hint = "Паки анимаций — это модели, в которых только анимации (браузер моделей их скрывает). Выберите аддон — из Мастерской или папку в garrysmod/addons, — потом модель: её анимации подойдут персонажу, если у скелетов совпадают имена костей.",
	sa_asrc_addon = "Аддон", sa_asrc_model = "Модель", sa_asrc_all = "Показывать все модели аддона, а не только анимации",
	sa_asrc_none = "Моделей анимаций тут нет: включите «все модели», чтобы выбрать из остальных",
	sa_asrc_info = "Анимаций: %d · совпадает костей персонажа: %d из %d", sa_asrc_bad = "Модель не загружается",
	sa_asrc_go = "Брать анимации отсюда",
	-- a0.6: липсинк
	sa_lip_menu = "Липсинк", sa_lip_for = "Рот %s говорит этим звуком", sa_lip_nobody = "В сцене нет никого, у кого есть рот",
	sa_lip_strength = "Насколько открывается рот",
	sa_lip_noface = "У этой модели нет флексов рта", sa_lip_wait = "Звук ещё загружается: попробуйте через секунду",
	sa_lip_failed = "Звук не удалось прочитать", sa_lip_silent = "В звуке тишина: говорить нечего",
	sa_lip_listening = "Слушаю звук (%d с)…",
	sa_lip_phonemes = "Липсинк: по фонемам, записанным в файле", sa_lip_loudness = "Липсинк: по громкости (в файле нет фонем)",
	sa_lip_done = "Липсинк: %s ключей рта на дорожке лица",
	hist_sa_lipsync = "Липсинк",
	-- a0.6: готовые движения и пролёты камеры
	sa_easy = "Готовое движение: персонажу — ходьба, жесты, танцы…; камере — наезд, облёт, панорама…",
	sa_easy_need = "Сначала выберите персонажа или камеру",
	sa_mo_menu = "Готовые движения", sa_mo_more = "Ещё анимации…", sa_mo_missing = "Этой анимации нет в игре",
	sa_mg_stand = "Стоит", sa_mg_move = "Передвигается", sa_mg_gesture = "Жесты", sa_mg_fun = "Веселье", sa_mg_action = "Действие",
	sa_mo_idle = "Стоит и дышит", sa_mo_scared = "Стоит напуганный", sa_mo_angry = "Стоит злой", sa_mo_crouch = "Сидит на корточках", sa_mo_sit = "Сидит по-турецки",
	sa_mo_walk = "Идёт", sa_mo_run = "Бежит", sa_mo_panic = "Бежит в панике", sa_mo_sneak = "Крадётся пригнувшись", sa_mo_zombie = "Идёт как зомби", sa_mo_swim = "Плывёт",
	sa_mo_wave = "Машет рукой", sa_mo_yes = "Кивает: да", sa_mo_no = "Мотает головой: нет", sa_mo_bow = "Кланяется", sa_mo_salute = "Отдаёт честь",
	sa_mo_come = "Зовёт: иди сюда", sa_mo_halt = "Знак: стой", sa_mo_forward = "Знак: вперёд",
	sa_mo_dance = "Танцует", sa_mo_laugh = "Смеётся", sa_mo_cheer = "Радуется", sa_mo_robot = "Танец робота", sa_mo_muscle = "Показывает мускулы",
	sa_mo_throw = "Бросает", sa_mo_land = "Приземляется после прыжка", sa_mo_flinch = "Вздрагивает от удара", sa_mo_die = "Падает замертво", sa_mo_die2 = "Медленно падает замертво",
	sa_cm_menu = "Пролёт камеры", sa_cm_need = "Сначала выберите камеру",
	sa_cm_in = "Наезд (ближе к тому, что видит)", sa_cm_out = "Отъезд", sa_cm_orbit_l = "Облёт влево (четверть круга)",
	sa_cm_orbit_r = "Облёт вправо (четверть круга)", sa_cm_pan_l = "Панорама влево", sa_cm_pan_r = "Панорама вправо",
	sa_cm_crane = "Подъём (взлетает, не теряя объект)", sa_cm_shake = "Затихающая тряска",
	hist_sa_camera_move = "Пролёт камеры",
	-- a0.6: призраки, ключи костей, подсказка о правке без ключа
	sa_show_cuts = "Как переключает камеры анимация (строка «Камеры»)",
	sa_pl_untitled = "Сцена без названия", sa_pl_camera = "Камера", sa_pl_eyes = "Без камеры (своими глазами)", sa_pl_exit = "Выйти из плеера (Backspace)",
	sa_pl_stop = "Стоп", sa_pl_prev = "Предыдущий план (PgUp)", sa_pl_next = "Следующий план (PgDn)", sa_pl_play = "Воспроизвести (Пробел)", sa_pl_pause = "Пауза (Пробел)",
	sa_pl_loop_on = "Повтор: вкл (R)", sa_pl_loop_off = "Повтор: выкл (R)", sa_pl_mute = "Без звука (M)",
	sa_rec_title = "Запись игры", sa_rec_go = "Начать запись",
	sa_rec_hint = "Играйте — и игра станет анимацией, как в машиниме: редактор закроется, после отсчёта записывается всё, что вы делаете, — вы своей моделью игрока со скином и оружием, NPC вокруг, их звуки и эффекты. Backspace останавливает дубль; редактор откроется с актёрами в сцене, уже с ключами. Уже сделанная анимация играет вместе с записью.",
	sa_rec_npcs = "Записывать NPC вокруг", sa_rec_radius = "Радиус для NPC и эффектов, юниты", sa_rec_sounds = "Записывать звуки (шаги, выстрелы, голоса)",
	sa_rec_phys = "Физика сцены", sa_rec_phys_off = "Выкл.", sa_rec_phys_sel = "Выделенные регдоллы и пропы",
	sa_rec_phys_all = "Все регдоллы и пропы",
	sa_rec_phys_tip = "Эти объекты сцены на время записи размораживаются: падают, сталкиваются, их можно бросать гравипушкой — и получают свои ключи. Закреплённые и привязанные объекты остаются как есть.",
	sa_rec_phys_go = "Записать только физику (не выходя из редактора)", sa_rec_phys_stop = "Остановить запись физики",
	sa_rec_phys_go_tip = "Выделенные регдоллы и пропы (все, если ничего не выделено) отпускаются с текущего кадра и падают под действием гравитации; «Стоп» (или Backspace) записывает их ключи.",
	sa_rec_phys_none = "В сцене нет регдоллов или пропов с физикой для записи",
	sa_rec_done_phys = "Физика записана: объектов — %d, ключей — %d",
	sa_rec_done_world = "Записаны объекты карты: %d",
	sa_rec_view = "Записать мой вид как камеру (от первого лица)",
	sa_rec_view_tip = "То, что вы видите во время игры, — куда смотрите, как поворачиваетесь, зум — становится камерой сцены с ключами по всему дублю, и видео можно снять вашими глазами. Ваше собственное тело в ней не рисуется, как в игре.",
	sa_rec_done_view = "Ваш вид — камера %s: посмотрите через неё (V) или выберите её в Рендер → Анимация → Камеры видео",
	sa_rec_done_view_cut = "Ваш вид — камера %s, и видео идёт через неё (строка Cameras на таймлайне)",
	sa_rec_effects = "Записывать эффекты (трассеры, взрывы, эффекты оружия)", sa_rec_step = "Ключ каждые N кадров",
	sa_rec_from = "Дубль начнётся с кадра %d (головка)", sa_rec_get_ready = "Сейчас начнётся запись…",
	sa_rec_stop_hint = "Backspace — остановить дубль", sa_rec_done = "Дубль записан: актёров %d, ключей %d, звуков %d, эффектов %d",
	sa_cuts_row = "Камеры", sa_cuts_empty = "Правый клик: через какую камеру смотреть анимацию с этого места",
	sa_cuts_nocam = "В сцене нет камер", sa_cuts_change = "Камера", sa_cuts_go = "Перейти к этой смене", sa_cuts_delete = "Удалить смену камеры",
	sa_cuts_here = "Переключиться на %s здесь (кадр %d)", hist_sa_cut = "Смена камеры",
	sa_ew_ease = "Плавно: трогается медленно, разгоняется и тормозит к следующему ключу", sa_ew_linear = "Равномерно: одна скорость всю дорогу, резкий старт и остановка",
	sa_ew_ease_in = "Разгон: трогается медленно и приходит к следующему ключу на полной скорости", sa_ew_ease_out = "Торможение: уходит на полной скорости и мягко подходит к следующему ключу",
	sa_ew_hold = "Скачок: стоит на месте и сразу переключается на следующий ключ (склейка, включённый свет)",
	sa_ew_b_start_slow = "Своя кривая: трогается медленно", sa_ew_b_start_fast = "Своя кривая: трогается быстро", sa_ew_b_start_even = "Своя кривая: трогается равномерно",
	sa_ew_b_end_slow = "мягко подходит к ключу", sa_ew_b_end_fast = "влетает в ключ на скорости", sa_ew_b_end_even = "подходит равномерно",
	sa_ew_b_over = "проскакивает ключ и возвращается", sa_ew_b_back = "сначала отходит назад",
	sa_ew_none = "Выберите ключ на графике (или поставьте головку между двумя ключами), чтобы увидеть, как он движется",
	sa_ew_from_to = "Кадры %d → %d  (%.2f с)",
	sa_ghosts = "Призраки: выбранная модель видна полупрозрачной в позе предыдущего (синяя) и следующего (зелёная) ключа",
	sa_bone_keys = "Ключи костей: ключ, поставленный при выбранной кости (K, автоключ после перетаскивания), хранит только эту кость, и каждая кость движется между своими ключами",
	sa_bone_key_set = "Ключ кости на кадре %s", sa_bone_key_here = "Поставить ключ этой кости здесь", sa_bone_key_delete = "Удалить ключ этой кости",
	sa_bone_clear = "Удалить все ключи этой кости",
	sa_hint_moved = "Поза изменена на кадре без ключа: она пропадёт, когда головка сдвинется. Нажмите K (или включите автоключ), чтобы её сохранить.",
	-- a0.6: просмотр анимации вне редактора
	sa_show = "Смотреть в игре (вне редактора)", sa_show_empty = "Пока нечего проигрывать: анимации нет",
	sa_show_menu = "Смотреть в игре", sa_show_eyes = "Ходить по сцене (своими глазами)", sa_show_loop = "По кругу",
	sa_show_player = "Плеер", sa_show_player_tip = "Плеер: смотреть анимацию через камеры на весь экран (вне редактора)",
	sa_show_eyes_tip = "Ходить по сцене и смотреть анимацию своими глазами (Backspace — стоп)",
	sa_walk_hint = "Backspace — стоп", sa_pl_look_on = "Настройки рендера: вкл (V)", sa_pl_look_off = "Настройки рендера: выкл (V)",
	sa_pl_pick_cam = "Нажмите, чтобы выбрать камеру", sa_pl_look_nocam = "Для настроек рендера нужна камера",
	sa_show_stop = "Остановить", sa_show_cam = "Камера (имя)", sa_show_cam_help = "Пусто — первая камера сцены; eyes — ходить по сцене и смотреть самому.",
	sa_show_qhelp = "Анимация вашей сцены идёт прямо в игре, с закрытым редактором: в плеере через камеру сцены, со звуками, без HUD (Backspace — выйти), или пока вы сами ходите по сцене (saeditor_show eyes). Консоль: saeditor_show [камера | eyes], saeditor_show_stop, saeditor_show_toggle — их можно забиндить на клавиши.",
	-- a0.5: редактор кривых, процедурное движение, Stop Motion Helper, затухание звука
	sa_ease_bezier = "Своя кривая (редактор кривых)",
	sa_crv_title = "Редактор кривых", sa_crv_none = "Ничего не выделено", sa_crv_pick = "Выделите анимированный объект или его кость",
	sa_crv_nokeys = "У объекта пока нет ключей: поставьте ключ (K), и кривые появятся здесь",
	sa_crv_fit = "Вписать", sa_crv_fit_tip = "Показать все ключи", sa_crv_norm = "Нормировать",
	sa_crv_norm_tip = "Каждый канал в своём диапазоне (градусы и юниты вместе); выкл — настоящие значения",
	sa_crv_ease_tip = "Движение от выбранного ключа к следующему", sa_crv_need_key = "Сначала выберите ключ на кривой",
	sa_crv_goto = "Перейти к этому ключу",
	sa_crv_s_x = "X", sa_crv_s_y = "Y", sa_crv_s_z = "Z", sa_crv_s_pitch = "P", sa_crv_s_yaw = "Yw", sa_crv_s_roll = "R",
	sa_crv_s_fov = "FOV", sa_crv_s_bri = "Ярк", sa_crv_s_radius = "Рад", sa_crv_s_lfov = "Конус", sa_crv_s_time = "Время",
	sa_crv_s_fxscale = "Разм", sa_crv_s_scale = "Масшт",
	sa_crv_ch_x = "Место: X", sa_crv_ch_y = "Место: Y", sa_crv_ch_z = "Место: Z (высота)", sa_crv_ch_pitch = "Поворот: наклон (pitch)",
	sa_crv_ch_yaw = "Поворот: рыскание (yaw)", sa_crv_ch_roll = "Поворот: крен (roll)", sa_crv_ch_fov = "Угол обзора", sa_crv_ch_bri = "Яркость",
	sa_crv_ch_radius = "Радиус", sa_crv_ch_lfov = "Угол конуса", sa_crv_ch_time = "Момент эффекта", sa_crv_ch_fxscale = "Размер эффекта",
	sa_crv_ch_scale = "Масштаб",
	hist_sa_curve = "Значение кривой", hist_sa_smh = "Импорт из Stop Motion Helper",
	sa_proc_title = "Процедурное движение", sa_proc_need = "Выделите модель, свет или эффект",
	sa_proc_hint = "Жизнь поверх ключей, вычисляемая по времени: видна при воспроизведении и в рендере (пока вы редактируете, сцена такая, какой её делают ключи). Сохраняется со сценой.",
	sa_proc_breath = "Дыхание", sa_proc_rate = "Вдохов в минуту", sa_proc_blink = "Моргание", sa_proc_head = "Голова двигается сама",
	sa_proc_sway = "Покачивание, юниты", sa_proc_freq = "Скорость движения, Гц", sa_proc_preview = "Запустить, чтобы увидеть", sa_proc_off = "Выключить",
	sa_smh_title = "Stop Motion Helper", sa_smh_file = "Сохранение SMH", sa_smh_map = "Карта", sa_smh_object = "Объект в сохранении", sa_smh_keys = "Ключей",
	sa_smh_hint = "Сохранения Stop Motion Helper (garrysmod/data/smh, а также data/smh и data_static/smh аддонов) можно взять на выделенный объект как ключи, а анимацию выделенных объектов — записать как сохранение SMH (в SMH: Load → имя модели).",
	sa_smh_target = "На объект", sa_smh_no_target = "выделите модель в сцене", sa_smh_start = "Первый кадр",
	sa_smh_conv = "Пересчитать скорость: кадров SMH в секунду", sa_smh_world = "Оставить места из сохранения",
	sa_smh_import = "Взять на объект", sa_smh_pick = "Выберите сохранение и объект в нём",
	sa_smh_export_hint = "Записать анимацию выделенных объектов как сохранение SMH с именем:", sa_smh_export = "Записать сохранение SMH",
	sa_smh_need_anim = "Сначала выделите анимированные объекты", sa_smh_none = "Сохранений SMH не найдено",
	sa_smh_bad = "Не удалось прочитать сохранение SMH", sa_smh_kind = "SMH анимирует только модели", sa_smh_nothing = "Ни у одного выделенного объекта нет ключей",
	sa_smh_imported = "Взято из сохранения SMH: ключей — %s", sa_smh_exported = "Сохранение SMH записано (объектов: %s): %s",
	sa_snd_m_fin = "Плавное появление", sa_snd_m_fout = "Плавное затухание", sa_snd_sec = "с",
	sa_snd_added_n = "Добавлено звуков подряд: %d", sa_snd_add_n = "Добавить звуки (%d)", sa_snd_pick = "Выделите один или несколько звуков в списке",
	sa_snd_in_folder = "Звуков в папке: %d · клик — прослушать, Ctrl/Shift — несколько, двойной клик — добавить",
	-- a0.5: ключи лица, наборы кадров в рендере
	sa_face_key = "Поставить ключ лица выделенному (Shift+K): у лица свои ключи, отдельно от тела",
	sa_hk_face_key = "Поставить ключ лица выделенному", sa_face_row = "Лицо",
	sa_face_start = "Отдельные ключи лица: начать здесь", sa_face_clear = "Убрать ключи лица (лицом снова управляют ключи тела)",
	sa_face_key_set = "Ключ лица поставлен: кадр %d", sa_need_face = "Выделите модель с лицом (флексами)",
	hist_sa_face_key = "Ключ лица",
	sa_play = "Воспроизвести / пауза (Пробел)", sa_first = "К первому кадру (Home)", sa_last = "К последнему кадру (End)",
	sa_prev_key = "Предыдущий ключ", sa_next_key = "Следующий ключ",
	sa_prev_frame = "Предыдущий кадр (,)", sa_next_frame = "Следующий кадр (.)",
	sa_key = "Поставить ключ выделенному (K)", sa_key_all = "Поставить ключ всем объектам",
	sa_key_delete = "Удалить ключ", sa_autokey = "Автоключ: каждая правка ставит ключ на текущем кадре",
	sa_loop = "Повторять по кругу", sa_frame = "кадр", sa_fps = "к/с", sa_length = "длина, с",
	sa_import = "Импорт анимации модели…", sa_render = "Рендер анимации…",
	sa_menu = "Анимация", sa_clear_track = "Убрать анимацию этого объекта", sa_clear_all = "Убрать всю анимацию",
	sa_clear_all_q = "Удалить все ключи всех объектов, звуки и переключения камер?",
	sa_ease = "Движение к следующему ключу", sa_ease_ease = "Плавно", sa_ease_linear = "Равномерно", sa_ease_hold = "Скачком (ступенька)",
	sa_ease_spline = "Непрерывно (сплайн)", sa_ease_sine = "Мягко (синус)", sa_ease_expo = "Резко (экспонента)", sa_ease_back = "С замахом (back)",
	sa_ease_elastic = "Упруго (elastic)", sa_ease_bounce = "С подскоками (bounce)", sa_ease_more = "Ещё",
	sa_ew_spline = "Непрерывно: проходит через ключи не останавливаясь, скорость берётся из соседних ключей",
	sa_ew_sine = "Мягко: очень плавные старт и остановка", sa_ew_expo = "Резко: стоит, проносится через середину, встаёт как вкопанный",
	sa_ew_back = "С замахом: сначала отходит назад, проскакивает следующий ключ и возвращается на него",
	sa_ew_elastic = "Упруго: проскакивает следующий ключ и пружинит вокруг него, затихая",
	sa_ew_bounce = "С подскоками: ударяется о следующий ключ и отскакивает несколько раз, как мяч",
	sa_ease_ease_in = "Разгон (ease in)", sa_ease_ease_out = "Торможение (ease out)",
	sa_copy_key = "Копировать ключ", sa_paste_key = "Вставить ключ сюда", sa_key_here = "Поставить ключ здесь",
	sa_keys_n = "Выбрано ключей: %d", sa_copy_keys = "Копировать ключи", sa_keys_delete = "Удалить ключи", sa_paste_keys = "Вставить ключи (%d) сюда",
	sa_no_tracks = "Анимации пока нет. Выделите объект, передвиньте указатель кадра и нажмите K — или включите автоключ.",
	sa_need_sel = "Сначала выделите объект", sa_need_ragdoll = "Выделите персонажа (рэгдолл)",
	sa_key_set = "Ключ поставлен: кадр %d", sa_keys_limit = "Слишком много ключей у одного объекта",
	sa_rd_blur = "Размытие движения", sa_rd_blur_off = "Выкл.", sa_rd_blur_n = "%d моментов на кадр",
	sa_rd_blur_tip = "Каждый кадр видео становится средним из нескольких моментов вокруг него — так движение видит киноплёнка. Рендер идёт во столько же раз дольше.",
	sa_rd_shutter = "Затвор", sa_rd_shutter_n = "%d°",
	sa_rd_shutter_tip = "Сколько времени кадра затвор открыт: 180° — обычный кинематографичный вид, 360° — самое сильное размытие, 90° — резкое, «рваное» движение.",
	sa_tsel = "Выделение времени (Motion Editor)",
	sa_tsel_tip = "Выделение времени (Motion Editor): правка позы ложится на целый отрезок анимации и плавно сходит на нет к его краям. Shift + перетаскивание по номерам кадров создаёт его",
	sa_tsel_keys = "По выделенным ключам (%d – %d)", sa_tsel_around = "Вокруг курсора (±%d кадров, с затуханием)",
	sa_tsel_all = "Вся анимация", sa_tsel_falloff = "Затухание", sa_tsel_fall_none = "Нет (резкий край)",
	sa_tsel_fall_n = "%d кадров (%s с)", sa_tsel_shape = "Форма затухания", sa_tsel_shape_smooth = "Плавная", sa_tsel_shape_linear = "Линейная",
	sa_tsel_apply = "Положить текущую позу на выделение (K)", sa_tsel_select_keys = "Выделить ключи внутри",
	sa_tsel_clear = "Убрать выделение времени",
	sa_tsel_how = "Shift + перетаскивание по номерам кадров — новое выделение. Края двигаются там же; Shift + клик убирает его.",
	sa_motion_set = "Поза положена на кадры %s – %s", sa_status_tsel = "выделение %d–%d",
	sa_status = "Анимация: кадр %d / %d  ·  %s",
	sa_status_play = "идёт", sa_status_stop = "стоп", sa_status_auto = "АВТОКЛЮЧ",
	sa_hk_play = "Воспроизвести / остановить анимацию", sa_hk_key = "Поставить ключ выделенному",
	sa_hk_prev = "Предыдущий кадр", sa_hk_next = "Следующий кадр", sa_hk_first = "Первый кадр", sa_hk_last = "Последний кадр",
	sa_imp_title = "Импорт анимации модели", sa_imp_search = "Поиск анимаций…",
	sa_imp_hint = "Анимация модели запекается в ключи выделенного персонажа, начиная с текущего кадра.",
	sa_imp_step = "Ключ каждые N кадров", sa_imp_loops = "Повторов", sa_imp_root = "Двигать персонажа (перемещение из анимации)",
	sa_imp_speed = "Скорость", sa_imp_go = "Импортировать", sa_imp_none = "У этой модели нет анимаций",
	sa_imp_done = "Импортировано «%s»: ключей — %d", sa_imp_col_name = "Анимация", sa_imp_col_len = "Длина, с",
	sa_imp_extend = "Анимация длиннее таймлайна: его длина увеличена.",
	sa_imp_src_own = "Анимации этой модели", sa_imp_src_male = "Анимации игрока (мужские)",
	sa_imp_src_female = "Анимации игрока (женские)", sa_imp_src_zombie = "Анимации игрока (зомби)",
	sa_imp_src_path = "Анимации другой модели…", sa_imp_src_prompt = "Путь к модели с таким же скелетом (models/….mdl):",
	sa_imp_src_tip = "Персонаж может взять анимации другой модели с таким же скелетом: горожанин — жесты и танцы моделей игроков и наборов анимаций, сделанных для них.",
	sa_imp_skeleton = "У этой модели другой скелет: её анимация не подходит персонажу",
	sa_imp_done_n = "Импортировано «%s» для персонажей: %s",
	sa_rnd_title = "Рендер анимации", sa_rnd_camera = "Камера",
	sa_rnd_from = "С кадра", sa_rnd_to = "По кадр", sa_rnd_name = "Имя", 
	sa_rnd_settle = "Ждать сцену не дольше, с",
	sa_rnd_settle_tip = "Сцену двигает сервер. Кадр снимается, как только все объекты встали на место у клиента; это наибольшее время такого ожидания.",
	sa_rnd_go = "Рендер", sa_rnd_cancel = "Отмена",
	sa_rnd_progress = "Рендер кадра %d из %d…", 
	sa_rnd_stopped = "Рендер анимации остановлен", sa_rnd_busy = "Рендер анимации уже идёт",
	sa_rnd_failed = "Не удалось создать видеофайл", sa_rnd_done_avi = "Анимация снята: кадров — %d, видео %s (уберите «.dat» из имени)",
	sa_rd_title = "Анимированная сцена: кадров — %d, %.2f с, %d к/с",
	sa_rd_what = "Снимать", sa_rd_anim = "Всю анимацию", sa_rd_frame = "Только текущий кадр",
	sa_rd_button = "Рендер анимации", sa_rd_stop = "Остановить рендер анимации",
	sa_rd_noanim = "В сцене пока нет анимации. Поставьте ключи на таймлайне (K), импортируйте движение или запишите игру — тогда видео рендерится здесь.",
	sa_rd_frames = "Кадры", sa_rd_whole = "Вся анимация",
	sa_rd_cams = "Камеры видео", sa_rd_cam = "Снимать через",
	sa_rd_cam_cuts = "Планы ниже (переключение камер)",
	sa_rd_shot_none = "Планов пока нет: видео снимается одной камерой. Добавьте план, чтобы с какого-то кадра переключиться на другую камеру.",
	sa_rd_need_cam = "В сцене нет камер: + → Создать камеру, потом добавляйте планы здесь.",
	sa_rd_shot_n = "План %d", sa_rd_shot_frame = "С этого кадра", sa_rd_shot_del = "Удалить план",
	sa_rd_shot_go = "Перейти к его первому кадру", sa_rd_shot_gone = "(камера удалена)",
	sa_rd_shot_add = "Добавить план на текущем кадре",
	sa_rd_shots_hint = "План показывает свою камеру со своего кадра до следующего плана. Поставьте курсор времени (таймлайн или полоса превью) и нажмите «Добавить план»: он возьмёт камеру, через которую вы смотрите, или выделенную. Планы — это ещё и строка «Камеры» вверху таймлайна.",
	sa_rd_note_avi = "Один видеофайл: garrysmod/data/speditor/renders/<имя>.avi.dat. Игра разрешает аддонам создавать файлы только нескольких типов, поэтому уберите «.dat» из имени — это обычный AVI, его открывает любой проигрыватель. На Windows выберите WebM в «Видеофайл»: готовый garrysmod/videos/<имя>.webm, переименовывать не нужно.",
	sa_rd_note_frame = "Кнопка «Рендер» сохранит одну картинку текущего кадра, как у неподвижной сцены.",
	hist_sa_key = "Ключевой кадр", hist_sa_key_delete = "Удаление ключа", hist_sa_key_move = "Перенос ключа", hist_sa_ease = "Движение ключа",
	hist_sa_clear = "Удаление анимации", hist_sa_import = "Импорт анимации", hist_sa_paste = "Вставка ключа",
	hist_sa_sound = "Звук", hist_sa_effect = "Проигрывание эффекта",
	sa_fx_play = "Проиграть эффект с этого кадра", sa_fx_to_end = "До конца анимации",
	sa_fx_for = "В течение %.2f с, затем выключить",
	sa_rnd_fx_live = "Эффекты, которые проигрываются сами (%d), нельзя снять покадрово: в видео они идут со своей скоростью. Для точных кадров берите эффекты из частиц.",
	-- a0.3: sounds and voices, faster animation render
	sa_snd_add = "Добавить звук или голос…", sa_snd_title = "Звуки и голоса",
	sa_snd_root_game = "Звуки игры", sa_snd_root_user = "Мои файлы",
	sa_snd_up = "Вверх", sa_snd_filter = "Фильтр по этой папке…", sa_snd_col_name = "Имя",
	sa_snd_preview = "Прослушать", sa_snd_stop = "Стоп",
	sa_snd_attach = "Идёт от выделенного объекта (пространственный звук)",
	sa_snd_voice = "Голос: идёт от головы персонажа",
	sa_snd_go = "Добавить на текущий кадр",
	sa_snd_hint = "Звук ставится на таймлайн с текущего кадра. Пространственный звук становится тише с расстоянием до камеры и переходит между левым и правым каналом, когда движется объект или камера. Свои файлы (WAV, MP3, OGG) кладите в garrysmod/data/speditor/sounds/. В снятое видео попадает только несжатый WAV.",
	sa_snd_added = "Звук добавлен: %s, кадр %d", sa_snd_limit = "Слишком много звуков в одной анимации",
	sa_snd_failed = "Не удалось загрузить звук: %s",
	sa_snd_everywhere = "везде", sa_snd_voice_tag = "голос",
	sa_snd_m_emitter = "Откуда идёт", sa_snd_m_none = "Ниоткуда: слышен везде", sa_snd_m_selected = "Выделенный объект",
	sa_snd_m_voice = "Голос (от головы)", sa_snd_m_volume = "Громкость", sa_snd_m_pitch = "Скорость и высота",
	sa_snd_m_dist = "Расстояние полной громкости", sa_snd_m_here = "Начать с текущего кадра",
	sa_snd_m_dup = "Дублировать", sa_snd_m_delete = "Убрать звук", sa_snd_m_listen = "Прослушать", sa_snd_m_replace = "Заменить звук…",
	sa_snd_m_split = "Разрезать по курсору", sa_snd_m_trim_in = "Обрезать начало до курсора",
	sa_snd_m_trim_out = "Обрезать конец от курсора", sa_snd_m_untrim = "Вернуть звук целиком",
	sa_snd_trim_bad = "Курсор не внутри этого звука",
	sa_snd_skipped = "Звуки, не попавшие в видео (подмешать можно только несжатый WAV): %s",
	sa_rd_quality = "Размер видео", sa_rd_video = "Видеофайл",
	sa_rd_video_avi = "AVI (MJPEG со звуком): data/speditor/renders, .avi.dat",
	sa_rd_video_webm = "WebM (VP8): garrysmod/videos, звук отдельным .wav",
	sa_rd_video_tip = "WebM делает встроенная запись видео игры: готовый .webm в garrysmod/videos, меньше AVI, не больше размера вашего экрана. Звук редактора внутрь не попадает, поэтому он сохраняется рядом как .wav в data/speditor/renders.",
	sa_rd_webm_no = "WebM доступен только на Windows: на Linux и macOS встроенная запись видео игры не создаёт файлов.",
	sa_rnd_done_webm = "Анимация снята: кадров — %s, видео %s (%s x %s)",
	sa_rnd_webm_wav = "Звуковая дорожка лежит рядом: %s — подложите её под видео в любом видеоредакторе", sa_rd_samples = "Проходы теней и ГРИП",
	sa_rd_fps = "Частота кадров видео", sa_rd_fps_anim = "Как у анимации (%d)",
	sa_rd_fps_tip = "Кадров в секунду в готовом видео. Если больше, чем у анимации, промежуточные кадры берутся между ключами (плавные 60 к/с из анимации на 24).",
	sa_tl_tip = "Ctrl + колесо — масштаб таймлайна, Shift + колесо — прокрутка по времени, колесо — прокрутка строк\nCtrl + клик по ключу — выбрать несколько, Shift + перетаскивание — выбрать ключи рамкой, перетащить выбранный ключ — сдвинуть все (с Ctrl — копировать)",
	sa_rd_samples_100 = "Все, как в одном кадре", sa_rd_samples_50 = "Половина (быстрее)", sa_rd_samples_25 = "Четверть (ещё быстрее)",
	sa_rnd_part = "Видео больше 1,9 ГБ: продолжение в %s",
	sa_rd_q_100 = "Самое большое: JPEG 100 (в 7 раз больше)", sa_rd_q_90 = "Обычное: JPEG 90", sa_rd_q_70 = "Меньше на 40%: JPEG 70",
	sa_rd_q_50 = "Меньше на 65%: JPEG 50", sa_rd_q_30 = "Самое маленькое, на 80%: JPEG 30",
	sa_rnd_size = "Видео: %.1f МБ, %.2f МБ в секунду. Кадров, повторённых без изменений: %d.",
	sa_rnd_mp4 = "Игра умеет писать только видео MJPEG. Сделать его в несколько раз меньше без видимых потерь: ffmpeg -i %s -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac %s.mp4",
})
