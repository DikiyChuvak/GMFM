--[[
GM:FM — shader test: gmfm_shadertest loads the editor's own pixel shaders (shaders/fxc/gmfm_*,
speditor_*) one at a time and draws each once into a small render target.

Why: the Linux game turns every D3D9 shader into OpenGL (ToGL) the first time it is used, and a
shader it cannot translate stops the whole game with "D3DToGL: GLSL translation error!" —
no Lua error, nothing to catch. The editor made all its occlusion shaders at once, so one bad
shader closed the game whatever was switched on.

So the test writes data/speditor/shadertest.txt BEFORE each shader ("pending") and after it has
been drawn: "ok", or "nodraw" if the render target kept its magenta clear colour. If the game
closes, the shader left "pending" is the one that did it: the next gmfm_shadertest marks it
"crash" and goes on with the shaders not tested yet. Load a map first (it draws in PostRender).
It draws with white textures and zero constants: "ok" means the shader loads and draws, not
that the effect looks right.

  gmfm_shadertest          test the shaders not tested yet (and report)
  gmfm_shadertest reset    forget the results and test them all again
  gmfm_shadertest <name>   test that one shader again (e.g. speditor_ao2_ps20b)
]]
SPeditor = SPeditor or {}
SPeditor.ShaderTest = SPeditor.ShaderTest or {}
local T = SPeditor.ShaderTest

local FILE = "speditor/shadertest.txt"
local PATTERNS = { "shaders/fxc/gmfm_*.vcs", "shaders/fxc/speditor_*.vcs" }

local function say(col, fmt, ...)
	MsgC(Color(120, 200, 255), "[GM:FM shader test] ", col, string.format(fmt, ...), "\n")
end
local WHITE, GREEN, RED, YELLOW = Color(230, 230, 230), Color(120, 230, 120), Color(255, 110, 110), Color(255, 210, 90)

-- the editor's own shaders (ps only: the editor's materials use screenspace_general's own vs)
function T.List()
	local seen, out = {}, {}
	for _, pat in ipairs(PATTERNS) do
		for _, f in ipairs(file.Find(pat, "GAME") or {}) do
			local name = string.StripExtension(string.lower(f))
			-- not the "x" copies (b0.2.6-misc.1, R.ShaderName): drawing both names of a shader would leave both
			-- dead in the next session on Linux
			if not seen[name] and (string.find(name, "_ps20b$") or string.find(name, "_ps30$")) and not string.find(name, "x_ps20b$") then
				seen[name] = true
				out[#out + 1] = name
			end
		end
	end
	table.sort(out)
	return out
end

-- results: { [name] = "pending" | "ok" | "crash" }, kept in the order of the file
local function load()
	local res = {}
	for line in string.gmatch(file.Read(FILE, "DATA") or "", "[^\n]+") do
		local name, st = string.match(line, "^(%S+)%s+(%S+)")
		if name then res[name] = st end
	end
	return res
end
local function save(res)
	file.CreateDir("speditor")
	local lines = {}
	for name, st in SortedPairs(res) do lines[#lines + 1] = name .. " " .. st end
	file.Write(FILE, table.concat(lines, "\n") .. "\n")
end

local rt
local function drawOnce(name)
	rt = rt or GetRenderTarget("gmfm_shadertest_rt", 64, 64)
	-- a material name of its own per run: a material made earlier in the session keeps its shader
	local mat = CreateMaterial("gmfm_shadertest_" .. name .. "_" .. math.floor(SysTime() * 1000), "screenspace_general", {
		["$pixshader"] = name,
		["$basetexture"] = "vgui/white", ["$texture1"] = "vgui/white", ["$texture2"] = "vgui/white",
		["$texture3"] = "vgui/white",
		["$ignorez"] = "1", ["$vertextransform"] = "1", ["$copyalpha"] = "0",
		["$alpha_blend"] = "0", ["$alpha_blend_color_overlay"] = "0",
	})
	-- cleared to magenta first: if it is still magenta after the quad, the shader drew nothing
	-- (it translated, but failed to compile / link as GLSL, or was not found)
	render.PushRenderTarget(rt)
	render.Clear(255, 0, 255, 255, true, true)
	render.SetMaterial(mat)
	render.DrawScreenQuad()
	render.CapturePixels()
	local r, g, b = render.ReadPixel(32, 32)
	render.PopRenderTarget()
	return r, g, b
end

local function summary(res)
	local ok, bad, todo = 0, {}, 0
	for _, name in ipairs(T.List()) do
		local st = res[name]
		if st == "ok" then ok = ok + 1
		elseif st == nil then todo = todo + 1
		else bad[#bad + 1] = name .. " (" .. st .. ")" end
	end
	say(#bad == 0 and GREEN or RED, "%d ok, %d failed%s, %d not tested", ok, #bad,
		#bad > 0 and (": " .. table.concat(bad, ", ")) or "", todo)
	say(WHITE, "results: garrysmod/data/%s", FILE)
end

function T.Run(only)
	local res = load()
	for name, st in pairs(res) do
		if st == "pending" then
			res[name] = "crash"
			say(RED, "%s was being tested when the game closed: marked as crash", name)
		end
	end
	save(res)

	local queue = {}
	for _, name in ipairs(T.List()) do
		if (only and name == only) or (not only and res[name] == nil) then queue[#queue + 1] = name end
	end
	if only and #queue == 0 then say(RED, "no shader %s in shaders/fxc (gmfm_*, speditor_*)", only) return end
	if #queue == 0 then summary(res) say(WHITE, "nothing left to test (gmfm_shadertest reset to test again)") return end
	say(WHITE, "%s, %d shader(s) to test: %s", system.IsLinux() and "Linux" or (system.IsOSX() and "macOS" or "Windows"),
		#queue, table.concat(queue, ", "))

	-- one shader a frame, drawn in PostRender (a render target can be drawn into there)
	local i = 0
	hook.Add("PostRender", "gmfm_shadertest", function()
		i = i + 1
		local name = queue[i]
		if not name then
			hook.Remove("PostRender", "gmfm_shadertest")
			summary(res)
			return
		end
		say(YELLOW, "%s ...", name)
		res[name] = "pending"
		save(res)            -- written before the shader is made: it survives the game closing
		local ok, r, g, b = pcall(drawOnce, name)
		if not ok then
			res[name] = "luaerror"
			say(RED, "%s: Lua error %s", name, tostring(r))
		elseif r == 255 and g == 0 and b == 255 then
			res[name] = "nodraw"
			say(RED, "%s drew nothing (still the magenta clear colour)", name)
		else
			res[name] = "ok"
			say(GREEN, "%s ok (pixel %s %s %s)", name, tostring(r), tostring(g), tostring(b))
		end
		save(res)
	end)
end

concommand.Add("gmfm_shadertest", function(_, _, args)
	local a = args[1] and string.lower(args[1])
	if a == "reset" then
		file.Delete(FILE)
		say(WHITE, "results cleared")
		T.Run()
	else
		T.Run(a)
	end
end)
