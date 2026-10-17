--[[
SPeditor — key bindings (Interface settings → Keys).

Every editor action that has a key is listed in K.LIST with its default. The player's
changes are kept in data/speditor/keys.json (only the ones that differ from the default).
Component hotkeys (COMP:AddHotkey, SAeditor) can be changed too: their id is "comp:" .. hotkey id.

A bind = { key = KEY_* / MOUSE_*, ctrl = bool, shift = bool, alt = bool }, or false (no key).
Kinds of actions:
  press  fires once when the key goes down with exactly these modifiers (Ctrl+Z, F, Del)
  hold   works while the key is held, modifiers do not matter (flight WASD, Shift: faster)
  click  a click in the viewport with these modifiers (the key is always LMB)

API:
  K.Get(id)          the bind of an action (the player's or the default), or false
  K.Set(id, bind)    change it (nil: back to the default, false: no key)
  K.Text(id)         "Ctrl + Z", "" when there is no key
  K.BindText(bind)
  K.Down(id)         a hold action: its key is held
  K.ClickIs(id)      a click action: its modifiers are held right now
  K.ClickAny(ids)    one of them
  K.Fired(id)        a press action fired this frame (call once per frame per id)
]]
SPeditor.Client = SPeditor.Client or {}
local C = SPeditor.Client
local L = SPeditor.L

C.Keys = C.Keys or {}
local K = C.Keys

local FILE = "speditor/keys.json"

-- group: the heading on the settings page; desc: dictionary key of the caption
K.LIST = {
	{ id = "select_add",     kind = "click", group = "keys_g_select", desc = "keys_select_add",     key = MOUSE_LEFT, shift = true },
	{ id = "select_add2",    kind = "click", group = "keys_g_select", desc = "keys_select_add2",    key = MOUSE_LEFT, ctrl = true },
	{ id = "focus",          kind = "press", group = "keys_g_select", desc = "help_focus",          key = KEY_F },
	{ id = "delete",         kind = "press", group = "keys_g_select", desc = "obj_delete",          key = KEY_DELETE },
	{ id = "duplicate",      kind = "press", group = "keys_g_select", desc = "obj_duplicate",       key = KEY_D, ctrl = true },

	-- area = "list": only while the cursor is over the object list; there they win over the
	-- keys of the same combination elsewhere (Ctrl + C / Ctrl + V copy a pose in the viewport)
	{ id = "list_select_all", kind = "press", group = "keys_g_list", desc = "keys_list_select_all", key = KEY_A, ctrl = true, area = "list" },
	{ id = "list_copy",       kind = "press", group = "keys_g_list", desc = "keys_list_copy",       key = KEY_C, ctrl = true, area = "list" },
	{ id = "list_paste",      kind = "press", group = "keys_g_list", desc = "keys_list_paste",      key = KEY_V, ctrl = true, area = "list" },

	{ id = "gizmo_move",     kind = "press", group = "keys_g_gizmo",  desc = "keys_gizmo_move",     key = KEY_1 },
	{ id = "gizmo_rotate",   kind = "press", group = "keys_g_gizmo",  desc = "keys_gizmo_rotate",   key = KEY_2 },
	{ id = "gizmo_scale",    kind = "press", group = "keys_g_gizmo",  desc = "keys_gizmo_scale",    key = KEY_4 },
	{ id = "gizmo_space",    kind = "press", group = "keys_g_gizmo",  desc = "help_space",          key = KEY_3 },
	{ id = "ik",             kind = "press", group = "keys_g_gizmo",  desc = "help_ik",             key = KEY_I },
	{ id = "stretch",        kind = "press", group = "keys_g_gizmo",  desc = "help_stretch",        key = KEY_T },
	{ id = "skeleton",       kind = "press", group = "keys_g_gizmo",  desc = "help_skeleton",       key = KEY_B },

	{ id = "undo",           kind = "press", group = "keys_g_edit",   desc = "edit_undo",           key = KEY_Z, ctrl = true },
	{ id = "redo",           kind = "press", group = "keys_g_edit",   desc = "edit_redo",           key = KEY_Y, ctrl = true },
	{ id = "redo2",          kind = "press", group = "keys_g_edit",   desc = "keys_redo2",          key = KEY_Z, ctrl = true, shift = true },
	{ id = "pose_copy",      kind = "press", group = "keys_g_edit",   desc = "pose_copy",           key = KEY_C, ctrl = true },
	{ id = "pose_paste",     kind = "press", group = "keys_g_edit",   desc = "pose_paste",          key = KEY_V, ctrl = true },

	{ id = "camview",        kind = "press", group = "keys_g_camera", desc = "help_camview",        key = KEY_V },
	{ id = "fly_forward",    kind = "hold",  group = "keys_g_camera", desc = "keys_fly_forward",    key = KEY_W },
	{ id = "fly_back",       kind = "hold",  group = "keys_g_camera", desc = "keys_fly_back",       key = KEY_S },
	{ id = "fly_left",       kind = "hold",  group = "keys_g_camera", desc = "keys_fly_left",       key = KEY_A },
	{ id = "fly_right",      kind = "hold",  group = "keys_g_camera", desc = "keys_fly_right",      key = KEY_D },
	{ id = "fly_up",         kind = "hold",  group = "keys_g_camera", desc = "keys_fly_up",         key = KEY_E },
	{ id = "fly_down",       kind = "hold",  group = "keys_g_camera", desc = "keys_fly_down",       key = KEY_Q },
	{ id = "fly_fast",       kind = "hold",  group = "keys_g_camera", desc = "keys_fly_fast",       key = KEY_LSHIFT },
	{ id = "fly_slow",       kind = "hold",  group = "keys_g_camera", desc = "keys_fly_slow",       key = KEY_LCONTROL },
}
K.ById = {}
for _, a in ipairs(K.LIST) do K.ById[a.id] = a end

local function copyBind(b)
	if not b then return false end
	return { key = b.key, ctrl = b.ctrl and true or false, shift = b.shift and true or false, alt = b.alt and true or false }
end

-- the action description of an id (built-in or a component hotkey)
function K.Action(id)
	local a = K.ById[id]
	if a then return a end
	if isstring(id) and string.sub(id, 1, 5) == "comp:" then
		local hid = string.sub(id, 6)
		for _, h in ipairs(SPeditor.Components and SPeditor.Components.hotkeys or {}) do
			if h.id == hid then return { id = id, kind = "press", key = h.key, ctrl = h.ctrl, shift = h.shift, hotkey = h } end
		end
	end
end

function K.Default(id)
	local a = K.Action(id)
	return a and copyBind(a) or false
end

---------------------------------------------------------------------
-- Saving
---------------------------------------------------------------------
K.user = K.user or nil

local function load()
	K.user = {}
	local raw = file.Read(FILE, "DATA")
	local t = raw and util.JSONToTable(raw)
	if not istable(t) then return end
	for id, b in pairs(t) do
		if isstring(id) then
			-- until a0.6 SAeditor was a mod and its keys were saved as "mod:…"
			if string.sub(id, 1, 4) == "mod:" then id = "comp:" .. string.sub(id, 5) end
			if b == false then
				K.user[id] = false
			elseif istable(b) and isnumber(b.k) then
				K.user[id] = { key = b.k, ctrl = b.c == true, shift = b.s == true, alt = b.a == true }
			end
		end
	end
end

local function save()
	local t = {}
	for id, b in pairs(K.user) do
		t[id] = b and { k = b.key, c = b.ctrl, s = b.shift, a = b.alt } or false
	end
	file.CreateDir("speditor")
	file.Write(FILE, util.TableToJSON(t, true))
end

function K.Get(id)
	if not K.user then load() end
	local b = K.user[id]
	if b ~= nil then return b end
	return K.Default(id)
end

function K.Same(a, b)
	if not a or not b then return not a and not b end
	return a.key == b.key and (a.ctrl and true or false) == (b.ctrl and true or false)
		and (a.shift and true or false) == (b.shift and true or false) and (a.alt and true or false) == (b.alt and true or false)
end

function K.Set(id, bind)
	if not K.user then load() end
	if bind == nil or K.Same(copyBind(bind), K.Default(id)) then
		K.user[id] = nil
	else
		K.user[id] = copyBind(bind)
	end
	save()
	hook.Run("SPeditor_KeysChanged", id)
end

function K.ResetAll()
	K.user = {}
	save()
	hook.Run("SPeditor_KeysChanged")
end

---------------------------------------------------------------------
-- Names
---------------------------------------------------------------------
local NAMES = {
	[KEY_DELETE] = "Del", [KEY_SPACE] = "Space", [KEY_ENTER] = "Enter", [KEY_BACKSPACE] = "Backspace",
	[KEY_TAB] = "Tab", [KEY_HOME] = "Home", [KEY_END] = "End", [KEY_INSERT] = "Ins",
	[KEY_PAGEUP] = "PgUp", [KEY_PAGEDOWN] = "PgDn", [KEY_UP] = "↑", [KEY_DOWN] = "↓", [KEY_LEFT] = "←", [KEY_RIGHT] = "→",
	[KEY_LSHIFT] = "Shift", [KEY_RSHIFT] = "R-Shift", [KEY_LCONTROL] = "Ctrl", [KEY_RCONTROL] = "R-Ctrl",
	[KEY_LALT] = "Alt", [KEY_RALT] = "R-Alt", [KEY_COMMA] = ",", [KEY_PERIOD] = ".", [KEY_CAPSLOCK] = "Caps Lock",
	[MOUSE_4] = "Mouse 4", [MOUSE_5] = "Mouse 5", [MOUSE_MIDDLE] = "MMB",
}

function K.KeyName(code)
	if code == MOUSE_LEFT then return L("key_lmb") end
	if code == MOUSE_RIGHT then return L("key_rmb") end
	if NAMES[code] then return NAMES[code] end
	local n = input.GetKeyName(code)
	if not n or n == "" then return "#" .. tostring(code) end
	return #n == 1 and string.upper(n) or (string.upper(string.sub(n, 1, 1)) .. string.lower(string.sub(n, 2)))
end

function K.BindText(b)
	if not b then return "" end
	return (b.ctrl and "Ctrl + " or "") .. (b.shift and "Shift + " or "") .. (b.alt and "Alt + " or "") .. K.KeyName(b.key)
end

function K.Text(id) return K.BindText(K.Get(id)) end

---------------------------------------------------------------------
-- Polling
---------------------------------------------------------------------
local function isDown(code)
	if not code then return false end
	if code >= MOUSE_FIRST and code <= MOUSE_LAST then return input.IsMouseDown(code) end
	return input.IsKeyDown(code)
end
K.IsDown = isDown

function K.Mods()
	return input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL),
		input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT),
		input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT)
end

local function modsMatch(b)
	local ctrl, shift, alt = K.Mods()
	-- a bind on a modifier key itself (Shift as a key) does not ask that modifier to be "off"
	local k = b.key
	if k == KEY_LCONTROL or k == KEY_RCONTROL then ctrl = b.ctrl end
	if k == KEY_LSHIFT or k == KEY_RSHIFT then shift = b.shift end
	if k == KEY_LALT or k == KEY_RALT then alt = b.alt end
	return ctrl == (b.ctrl and true or false) and shift == (b.shift and true or false) and alt == (b.alt and true or false)
end

function K.Down(id)
	local b = K.Get(id)
	return b and isDown(b.key) or false
end

function K.ClickIs(id)
	local b = K.Get(id)
	return b and modsMatch(b) or false
end

function K.ClickAny(ids)
	for _, id in ipairs(ids) do
		if K.ClickIs(id) then return true end
	end
	return false
end

local down = {}
function K.Fired(id)
	local b = K.Get(id)
	if not b then
		down[id] = nil
		return false
	end
	local d = isDown(b.key)
	local fired = d and not down[id]
	down[id] = d
	return fired and modsMatch(b) and not K.capturing
end

-- the actions that have the same bind as this one (only actions of the same kind and the same
-- area can clash; the flight keys work only while flying, so they do not clash with the others)
function K.Conflicts(id, bind)
	local out = {}
	if not bind then return out end
	local a = K.Action(id)
	local function check(oid, okind, oarea)
		if oid ~= id and okind == a.kind and oarea == a.area and K.Same(K.Get(oid), bind) then out[#out + 1] = oid end
	end
	for _, o in ipairs(K.LIST) do check(o.id, o.kind, o.area) end
	for _, h in ipairs(SPeditor.Components and SPeditor.Components.hotkeys or {}) do check("comp:" .. h.id, "press", nil) end
	return out
end

function K.Caption(id)
	local a = K.Action(id)
	if not a then return id end
	if a.hotkey then
		local h = a.hotkey
		return (h.desc and L(h.desc) or h.id) .. "   [" .. tostring(h.comp and h.comp.name or "?") .. "]"
	end
	return L(a.desc)
end

---------------------------------------------------------------------
-- Capturing a new key (the settings page)
---------------------------------------------------------------------
local MODIFIERS = {
	[KEY_LCONTROL] = true, [KEY_RCONTROL] = true, [KEY_LSHIFT] = true, [KEY_RSHIFT] = true,
	[KEY_LALT] = true, [KEY_RALT] = true, [KEY_LWIN] = true, [KEY_RWIN] = true,
}
-- mouse buttons a press action may take (LMB / RMB / MMB belong to the viewport)
local PRESS_MOUSE = { MOUSE_4, MOUSE_5 }
local escUntil = 0

-- K.Capture(id, done): waits for the next key; done(bind) or done(nil) when cancelled (Esc)
function K.Capture(id, done)
	local a = K.Action(id)
	if not a then return end
	K.capturing = { id = id, done = done, kind = a.kind, t0 = RealTime(), was = {} }
	-- what is held at the start (the click that started the capture) is not taken
	for code = KEY_FIRST, KEY_LAST do K.capturing.was[code] = input.IsKeyDown(code) end
	for code = MOUSE_FIRST, MOUSE_LAST do K.capturing.was[code] = input.IsMouseDown(code) end
end

function K.CancelCapture()
	local c = K.capturing
	K.capturing = nil
	if c and c.done then c.done(nil) end
end

local function finish(bind)
	local c = K.capturing
	K.capturing = nil
	escUntil = RealTime() + 0.3
	if c and c.done then c.done(bind) end
end

hook.Add("Think", "SPeditor.KeyCapture", function()
	local c = K.capturing
	if not c then return end
	local ctrl, shift, alt = K.Mods()
	local function edge(code, d)
		local fired = d and not c.was[code]
		c.was[code] = d
		return fired
	end
	for code = KEY_FIRST, KEY_LAST do
		if edge(code, input.IsKeyDown(code)) then
			if code == KEY_ESCAPE then return finish(nil) end
			if c.kind == "hold" then
				return finish({ key = code })
			elseif c.kind == "press" and not MODIFIERS[code] then
				return finish({ key = code, ctrl = ctrl, shift = shift, alt = alt })
			end
		end
	end
	for code = MOUSE_FIRST, MOUSE_LAST do
		if edge(code, input.IsMouseDown(code)) then
			if c.kind == "click" and code == MOUSE_LEFT then
				-- Alt + LMB is the orbit, and a plain click selects
				if alt then
					SPeditor.Notify(L("keys_click_alt"), 1)
				elseif not ctrl and not shift then
					SPeditor.Notify(L("keys_click_need_mod"), 1)
				else
					return finish({ key = MOUSE_LEFT, ctrl = ctrl, shift = shift })
				end
			elseif c.kind ~= "click" then
				for _, m in ipairs(PRESS_MOUSE) do
					if m == code then return finish({ key = code, ctrl = c.kind == "press" and ctrl, shift = c.kind == "press" and shift, alt = c.kind == "press" and alt }) end
				end
			end
		end
	end
end)

-- Esc cancels the capture and must not open the game menu
hook.Add("OnPauseMenuShow", "SPeditor.KeyCapture", function()
	if K.capturing or RealTime() < escUntil then
		escUntil = RealTime() + 0.3
		return false
	end
end)

-- the editor is closed while a key is being waited for
hook.Add("SPeditor_StateChanged", "SPeditor.KeyCapture", function(on)
	if not on and K.capturing then K.CancelCapture() end
end)
