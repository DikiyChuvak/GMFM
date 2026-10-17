--[[
SPeditor — window library (Dock) in the style of SFM, written on top of the GMod API.

Stock Derma has no window manager, so here is our own panel class
"SPeditorDock" (vgui.Register, base EditablePanel).

Windows come in two kinds:
  * DOCKED — lie edge to edge in the work area, like SFM panels. The border
    between them is shared: drag a window edge and the neighbour shrinks or grows
    (a window does not shrink below its minimum size). If a window is widened through
    free space and runs into another window, it then squeezes that one.
  * FLOATING — lie on top, move and resize freely
    (with edge snapping).

Dragging (by the tab strip):
  * the window is torn off the layout and follows the cursor, neighbours take its place;
  * over another window a docking zone is highlighted: a window edge — split it
    in half (left / right / top / bottom), the tab strip — add as a tab;
  * at the edge of the work area — dock across the full height / width;
  * release outside the zones (or with Ctrl held) — the window stays floating.

Tabs: dragging along the strip changes the order, pulling out of the strip
tears the tab off into a separate window. A double click on the strip maximizes the window
over the whole work area and back. A right click on a tab — the menu.

Window properties (right click on the tab strip → "Window properties"):
  * "Always on top" — the window stays above the other editor windows even
    when they are clicked. On by default for the model browser; it can be switched
    on for any window (Primary / Secondary Viewport and so on). The choice is kept
    in data/speditor/windows.json by the window key.

A closed docked window gives its space to the neighbours; when reopened
(Windows menu) it returns to its place if the layout has not changed,
otherwise it opens floating.

Layouts: windows, their sizes (as shares of the screen), tab sets, the
"floating" flag; named layouts in data/speditor/layouts, presets,
autosave of the last one.

API:
  Dock.Create{ key, id, title, icon, w, h, x, y, dockable, floating, onTop } -> window, page panel
  window:SetOnTop(bool)    Dock.Restack()   bring the "always on top" windows back up
  window:AddPage(id, title, panel, icon)   window:AddSheet(title, panel, icon, id)
  window:SelectPage(id)    window:Close()    window:Float()    window:ToggleMaximize()
  Dock.ShowPage(id)        show the window with the page and select its tab
  Dock.Capture() / Dock.Apply(data) / Dock.Save(name) / Dock.Load(name)
  Dock.Reset(presetName)   Dock.Presets
]]
SPeditor = SPeditor or {}
SPeditor.Dock = SPeditor.Dock or {}
local Dock = SPeditor.Dock

Dock.windows = Dock.windows or {}   -- list of live windows
Dock.pages   = Dock.pages   or {}   -- id -> { id, title, icon, panel, win }
Dock.snap    = (Dock.snap == nil) and true or Dock.snap
Dock.locked  = Dock.locked or false
Dock.drag    = nil                  -- { win, zone } while dragging

local LAYOUT_VERSION = 2

local EDGE, TAB_H = 4, 22
local GAP         = 2        -- gap between docked windows
local TOL         = 6        -- tolerance for "the edges coincide"
local SNAP_DIST   = 12
local TOP_Y       = 26       -- below the menu bar (24 px)
local BOTTOM_H    = 20       -- status bar
-- the tab strip, the menu bar and the status bar follow the interface scale (UI.S)
local function metrics()
	local S = SPeditor.UI.S
	TAB_H, TOP_Y, BOTTOM_H = S(22), S(24) + 2, S(20)
end
metrics()
hook.Add("SPeditor_FontsCreated", "SPeditor.DockMetrics", metrics)
local SIDE_BAND   = 0.28     -- share of a window at its edge = the "split" zone
local OUTER_BAND  = 16       -- px at the edge of the work area = the "full side" zone
local OUTER_FRAC  = 0.22     -- what share of the work area such a window takes

local function PAL() return SPeditor.UI.PAL end

local function copyList(t)
	local o = {}
	for i, v in ipairs(t) do o[i] = v end
	return o
end

---------------------------------------------------------------------
-- Geometry. A rectangle: { x, y, r, b } (r, b — the right and bottom edges).
---------------------------------------------------------------------
local AX = {
	x = { a = "x", z = "r", pa = "y", pz = "b", min = "minW" },
	y = { a = "y", z = "b", pa = "x", pz = "r", min = "minH" },
}

local function workspace()
	return { x = 0, y = TOP_Y, r = ScrW(), b = ScrH() - BOTTOM_H - GAP }
end

local function rectOf(w)
	local x, y = w:GetPos()
	local ww, hh = w:GetSize()
	return { x = x, y = y, r = x + ww, b = y + hh }
end

local function setRect(w, rc)
	w:SetPos(rc.x, rc.y)
	w:SetSize(rc.r - rc.x, rc.b - rc.y)
end

local function copyRect(rc) return { x = rc.x, y = rc.y, r = rc.r, b = rc.b } end

local function sameRect(p, q)
	return math.abs(p.x - q.x) <= 1 and math.abs(p.y - q.y) <= 1 and math.abs(p.r - q.r) <= 1 and math.abs(p.b - q.b) <= 1
end

local function isTiled(w)
	return IsValid(w) and w:IsVisible() and w.dockable and not w.floating
end

local function tiledList(except)
	local out = {}
	for _, w in ipairs(Dock.windows) do
		if w ~= except and isTiled(w) then out[#out + 1] = w end
	end
	return out
end

-- overlap along the axis perpendicular to ax
local function overlaps(p, q, ax)
	return math.min(p[ax.pz], q[ax.pz]) - math.max(p[ax.pa], q[ax.pa]) > 1
end

local function intersects(p, q)
	return math.min(p.r, q.r) - math.max(p.x, q.x) > TOL and math.min(p.b, q.b) - math.max(p.y, q.y) > TOL
end

-- Tidy up docked windows: edges at the borders of the work area are put exactly
-- on the border, an even gap is set between neighbours (cures layouts that are
-- a couple of pixels off after a resolution change or from old versions).
local function normalize()
	local ws = workspace()
	local list = tiledList()
	local rects = {}
	for i, w in ipairs(list) do
		local rc = rectOf(w)
		for _, ax in pairs(AX) do
			if math.abs(rc[ax.a] - ws[ax.a]) <= TOL then rc[ax.a] = ws[ax.a] end
			if math.abs(rc[ax.z] - ws[ax.z]) <= TOL then rc[ax.z] = ws[ax.z] end
		end
		rects[i] = rc
	end
	for i, p in ipairs(rects) do
		for j, q in ipairs(rects) do
			if i ~= j then
				for _, ax in pairs(AX) do
					if math.abs(p[ax.z] + GAP - q[ax.a]) <= TOL and overlaps(p, q, ax) then q[ax.a] = p[ax.z] + GAP end
				end
			end
		end
	end
	for i, w in ipairs(list) do
		if not sameRect(rects[i], rectOf(w)) then setRect(w, rects[i]) end
	end
end

-- windows with the "always on top" property — above all other editor windows
local function raiseTop()
	for _, w in ipairs(Dock.windows) do
		if IsValid(w) and w:IsVisible() and w.onTop then w:MoveToFront() end
	end
end

-- floating windows are always above docked ones
local function raiseFloating()
	for _, w in ipairs(Dock.windows) do
		if IsValid(w) and w:IsVisible() and not isTiled(w) and not w.onTop then w:MoveToFront() end
	end
	raiseTop()
end

function Dock.Restack() raiseTop() end

---------------------------------------------------------------------
-- Window properties that are not part of a layout: { [window key] = { top = bool } }
---------------------------------------------------------------------
local PROPS_FILE = "windows.json"
local winProps

local function propsPath()
	return (SPeditor.Config and SPeditor.Config.SaveDir or "speditor") .. "/" .. PROPS_FILE
end

local function loadProps()
	if not winProps then
		winProps = util.JSONToTable(file.Read(propsPath(), "DATA") or "") or {}
	end
	return winProps
end

local function saveProp(key, name, value)
	-- torn-off tabs have a random key: their properties live until the editor is closed
	if not key or string.sub(key, 1, 5) == "float" then return end
	local t = loadProps()
	t[key] = istable(t[key]) and t[key] or {}
	t[key][name] = value
	file.CreateDir(SPeditor.Config and SPeditor.Config.SaveDir or "speditor")
	file.Write(propsPath(), util.TableToJSON(t, true))
end

---------------------------------------------------------------------
-- A shared border (splitter). S — the coordinate of the line: windows "before" the line
-- have their far edge = S, windows "after" it have their near edge = S + GAP. The group
-- includes all windows whose edges lie on this line and are linked as neighbours, so
-- the whole line moves as one, like a splitter in SFM.
---------------------------------------------------------------------
local function splitGroup(self, snap, ax, side)
	local S = (side == "z") and snap[self][ax.z] or (snap[self][ax.a] - GAP)
	local minus, plus, inGroup = {}, {}, { [self] = true }
	if side == "z" then minus[1] = self else plus[1] = self end

	local grew = true
	while grew do
		grew = false
		for w, rc in pairs(snap) do
			if not inGroup[w] then
				if math.abs(rc[ax.z] - S) <= TOL then
					for _, o in ipairs(plus) do
						if overlaps(rc, snap[o], ax) then
							minus[#minus + 1], inGroup[w], grew = w, true, true
							break
						end
					end
				elseif math.abs(rc[ax.a] - (S + GAP)) <= TOL then
					for _, o in ipairs(minus) do
						if overlaps(rc, snap[o], ax) then
							plus[#plus + 1], inGroup[w], grew = w, true, true
							break
						end
					end
				end
			end
		end
	end
	return { S = S, ax = ax, minus = minus, plus = plus, inGroup = inGroup }
end

-- Move the line by d (respecting minimum sizes). new — a working copy
-- of the rectangles. Windows outside the group that the growing window runs into
-- are squeezed ("pushed").
local function moveSplit(self, g, d, snap, new)
	local ax, S = g.ax, g.S
	local ws = workspace()
	local lo, hi = -math.huge, math.huge
	for _, w in ipairs(g.minus) do
		local rc = snap[w]
		lo = math.max(lo, w[ax.min] - (rc[ax.z] - rc[ax.a]))
	end
	for _, w in ipairs(g.plus) do
		local rc = snap[w]
		hi = math.min(hi, (rc[ax.z] - rc[ax.a]) - w[ax.min])
	end

	local pushed = {}
	if #g.plus == 0 then
		hi = math.min(hi, ws[ax.z] - S)
		for w, rc in pairs(snap) do
			if not g.inGroup[w] and rc[ax.a] >= S - TOL and overlaps(rc, snap[self], ax) then
				hi = math.min(hi, rc[ax.z] - w[ax.min] - GAP - S)
				pushed[#pushed + 1] = w
			end
		end
	elseif #g.minus == 0 then
		lo = math.max(lo, ws[ax.a] - (S + GAP))
		for w, rc in pairs(snap) do
			if not g.inGroup[w] and rc[ax.z] <= S + GAP + TOL and overlaps(rc, snap[self], ax) then
				lo = math.max(lo, rc[ax.a] + w[ax.min] - S)
				pushed[#pushed + 1] = w
			end
		end
	end

	if lo > hi then d = 0 else d = math.Clamp(d, lo, hi) end
	d = math.floor(d + 0.5)

	for _, w in ipairs(g.minus) do new[w][ax.z] = snap[w][ax.z] + d end
	for _, w in ipairs(g.plus) do new[w][ax.a] = snap[w][ax.a] + d end
	for _, w in ipairs(pushed) do
		if #g.plus == 0 then
			if S + d + GAP > snap[w][ax.a] then new[w][ax.a] = S + d + GAP end
		else
			if S + d < snap[w][ax.z] then new[w][ax.z] = S + d end
		end
	end
end

---------------------------------------------------------------------
-- Freed space: the neighbours on one side that together exactly
-- cover a side of the "hole" stretch over it. Returns
-- { [win] = { old = rect, new = rect } } (for putting the window back in place).
---------------------------------------------------------------------
local function collapse(hole, except)
	local list = tiledList(except)
	local best

	local function try(ax, side)
		local line = (side == "a") and hole[ax.a] or hole[ax.z]
		local cand = {}
		for _, w in ipairs(list) do
			local rc = rectOf(w)
			local touch
			if side == "a" then touch = math.abs(rc[ax.z] + GAP - line) <= TOL
			else touch = math.abs(rc[ax.a] - GAP - line) <= TOL end
			if touch and rc[ax.pa] >= hole[ax.pa] - TOL and rc[ax.pz] <= hole[ax.pz] + TOL then
				cand[#cand + 1] = { w = w, rc = rc }
			end
		end
		if #cand == 0 then return end
		table.sort(cand, function(p, q) return p.rc[ax.pa] < q.rc[ax.pa] end)
		if math.abs(cand[1].rc[ax.pa] - hole[ax.pa]) > TOL then return end
		if math.abs(cand[#cand].rc[ax.pz] - hole[ax.pz]) > TOL then return end
		for i = 2, #cand do
			if math.abs(cand[i].rc[ax.pa] - cand[i - 1].rc[ax.pz] - GAP) > TOL then return end
		end
		if not best or #cand < #best.cand then best = { cand = cand, ax = ax, side = side } end
	end

	try(AX.x, "a") try(AX.x, "z") try(AX.y, "a") try(AX.y, "z")
	if not best then return {} end

	local grown = {}
	for _, c in ipairs(best.cand) do
		local nr = copyRect(c.rc)
		if best.side == "a" then nr[best.ax.z] = hole[best.ax.z] else nr[best.ax.a] = hole[best.ax.a] end
		grown[c.w] = { old = c.rc, new = nr }
		setRect(c.w, nr)
	end
	return grown
end

-- Squeeze all docked windows along an axis, freeing a band S at the edge.
-- Returns the band rectangle, or nil if the windows do not have enough room.
local function squeeze(ax, nearSide, S, except, apply)
	local ws = workspace()
	local lo, hi = ws[ax.a], ws[ax.z]
	local L = hi - lo
	local k = (L - S - GAP) / L
	local off = nearSide and (S + GAP) or 0
	local function f(v) return lo + off + (v - lo) * k end

	local plan = {}
	for _, w in ipairs(tiledList(except)) do
		local rc = rectOf(w)
		local nr = copyRect(rc)
		nr[ax.a] = (rc[ax.a] <= lo + TOL) and (lo + off) or math.floor(f(rc[ax.a]) + 0.5)
		nr[ax.z] = (rc[ax.z] >= hi - TOL) and (hi - (nearSide and 0 or (S + GAP))) or (math.floor(f(rc[ax.z] + GAP) + 0.5) - GAP)
		if nr[ax.z] - nr[ax.a] < w[ax.min] then return nil end
		plan[w] = nr
	end
	if apply then
		for w, nr in pairs(plan) do setRect(w, nr) end
	end

	local strip = copyRect(ws)
	if nearSide then strip[ax.z] = lo + S else strip[ax.a] = hi - S end
	return strip
end

---------------------------------------------------------------------
-- Docking zones under the cursor (for the window self that is being dragged)
---------------------------------------------------------------------
function Dock.ZoneAt(ax, ay, self)
	local ws = workspace()
	if ax < ws.x or ax > ws.r or ay < ws.y - OUTER_BAND or ay > ws.b + OUTER_BAND then return nil end
	local list = tiledList(self)
	if #list == 0 then return { kind = "fill", rect = ws } end

	-- tab strip of the window under the cursor: add as a tab
	for _, w in ipairs(list) do
		local rc = rectOf(w)
		if ax >= rc.x and ax <= rc.r and ay >= rc.y + EDGE and ay <= rc.y + EDGE + TAB_H then
			return { kind = "tab", target = w, rect = { x = rc.x, y = rc.y, r = rc.r, b = rc.y + EDGE + TAB_H + 2 } }
		end
	end

	-- edge of the work area: across the full side (the top edge — right at the menu bar,
	-- so as not to interfere with the tab strips of the top windows)
	local outer = {
		{ ax - ws.x, AX.x, true, OUTER_BAND }, { ws.r - ax, AX.x, false, OUTER_BAND },
		{ ay - ws.y, AX.y, true, EDGE - 1 }, { ws.b - ay, AX.y, false, OUTER_BAND },
	}
	for _, o in ipairs(outer) do
		if o[1] <= o[4] then
			local S = math.max(math.floor((ws[o[2].z] - ws[o[2].a]) * OUTER_FRAC), self[o[2].min])
			local strip = squeeze(o[2], o[3], S, self, false)
			if strip then return { kind = "outer", axis = o[2], near = o[3], size = S, rect = strip } end
		end
	end

	for _, w in ipairs(list) do
		local rc = rectOf(w)
		if ax >= rc.x and ax <= rc.r and ay >= rc.y and ay <= rc.b then
			local fx, fy = (ax - rc.x) / (rc.r - rc.x), (ay - rc.y) / (rc.b - rc.y)
			local sides = { { fx, AX.x, true }, { 1 - fx, AX.x, false }, { fy, AX.y, true }, { 1 - fy, AX.y, false } }
			table.sort(sides, function(p, q) return p[1] < q[1] end)
			local s = sides[1]
			if s[1] > SIDE_BAND then return nil end
			local a = s[2]
			if rc[a.z] - rc[a.a] < w[a.min] + self[a.min] + GAP then return nil end
			local mid = math.floor((rc[a.a] + rc[a.z]) / 2)
			local mine, rest = copyRect(rc), copyRect(rc)
			if s[3] then
				mine[a.z], rest[a.a] = mid - GAP / 2, mid + GAP / 2
			else
				mine[a.a], rest[a.z] = mid + GAP / 2, mid - GAP / 2
			end
			return { kind = "split", target = w, rect = mine, rest = rest }
		end
	end
	return nil
end

-- Dock the window self into a zone
function Dock.DockInto(self, zone)
	if zone.kind == "tab" then
		local target = zone.target
		if not IsValid(target) then return end
		local list = copyList(self.pages)
		for _, p in ipairs(list) do
			self:DetachPage(p.id)
			target:AdoptPage(p)
		end
		self:Remove()
		return
	end

	if zone.kind == "split" then
		if not IsValid(zone.target) then return end
		setRect(zone.target, zone.rest)
	elseif zone.kind == "outer" then
		if not squeeze(zone.axis, zone.near, zone.size, self, true) then return end
	end
	self.floating, self.undock, self.maximized = false, nil, nil
	setRect(self, zone.rect)
	raiseFloating()
end

hook.Add("PostRenderVGUI", "SPeditor.DockOverlay", function()
	local d = Dock.drag
	if not d or not d.zone or not IsValid(d.win) then return end
	local rc = d.zone.rect
	local c = SPeditor.UI.PAL.ORANGE
	surface.SetDrawColor(c.r, c.g, c.b, 70)
	surface.DrawRect(rc.x, rc.y, rc.r - rc.x, rc.b - rc.y)
	surface.SetDrawColor(c.r, c.g, c.b, 255)
	surface.DrawOutlinedRect(rc.x, rc.y, rc.r - rc.x, rc.b - rc.y, 2)
end)

---------------------------------------------------------------------
-- Snapping (floating windows)
---------------------------------------------------------------------
local function neighbours(self)
	local xs, ys = { 0, ScrW() }, { TOP_Y, ScrH() - BOTTOM_H }
	for _, w in ipairs(Dock.windows) do
		if IsValid(w) and w ~= self and w:IsVisible() then
			local x, y = w:GetPos()
			local ww, hh = w:GetSize()
			xs[#xs + 1], xs[#xs + 1], xs[#xs + 1], xs[#xs + 1] = x, x + ww, x - 4, x + ww + 4
			ys[#ys + 1], ys[#ys + 1], ys[#ys + 1], ys[#ys + 1] = y, y + hh, y - 4, y + hh + 4
		end
	end
	return xs, ys
end

local function snapValue(v, targets)
	local best, bd = v, SNAP_DIST + 1
	for _, t in ipairs(targets) do
		local d = math.abs(t - v)
		if d < bd then best, bd = t, d end
	end
	return (bd <= SNAP_DIST) and best or v
end

-- both edges of the window: the nearer one snaps
local function snapSpan(a, b, targets)
	local sa, sb = snapValue(a, targets), snapValue(b, targets)
	local da, db = math.abs(sa - a), math.abs(sb - b)
	if da == 0 and db == 0 then return 0 end
	if da <= db and da > 0 then return sa - a end
	if db > 0 then return sb - b end
	return 0
end

---------------------------------------------------------------------
-- Window panel
---------------------------------------------------------------------
local PANEL = {}

function PANEL:Init()
	self.pages    = {}
	self.active   = nil
	self.dockable = true
	self.floating = false
	self.minW, self.minH = SPeditor.UI.S(200), SPeditor.UI.S(120)
	self.HdrBtns  = {}
	self.SPeditorDock = true
	self:SetMouseInputEnabled(true)
	self:SetKeyboardInputEnabled(false)

	self.content = vgui.Create("DPanel", self)
	self.content.Paint = function(_, w, h)
		surface.SetDrawColor(PAL().BG)
		surface.DrawRect(0, 0, w, h)
	end
end

function PANEL:SetDockable(b) self.dockable = b and true or false end

-- "Always on top". save = false — do not remember (the default value).
function PANEL:SetOnTop(on, save)
	self.onTop = on and true or false
	if save ~= false then saveProp(self.key, "top", self.onTop) end
	if self.onTop then self:MoveToFront() end
	raiseTop()
end

function PANEL:PerformLayout(w, h)
	self.content:SetPos(EDGE, EDGE + TAB_H)
	self.content:SetSize(w - EDGE * 2, h - EDGE * 2 - TAB_H)
	local x = w - EDGE - 2
	for _, b in ipairs(self.HdrBtns) do
		if IsValid(b) then
			x = x - 20
			b:SetPos(x, EDGE + 2)
		end
	end
end

-- Tab geometry (in window coordinates)
function PANEL:TabRects()
	surface.SetFont("SPeditor.Small")
	local out, x = {}, EDGE + 2
	for _, p in ipairs(self.pages) do
		local tw = surface.GetTextSize(p.title)
		local w = tw + 20 + (p.icon and SPeditor.UI.IconSize(TAB_H) + 2 or 0)
		out[#out + 1] = { page = p, x = x, w = w }
		x = x + w + 2
	end
	return out
end

function PANEL:TabAt(mx, my)
	if my < EDGE or my > EDGE + TAB_H then return nil end
	for _, t in ipairs(self:TabRects()) do
		if mx >= t.x and mx <= t.x + t.w then return t.page end
	end
end

-- The frame and the tab strip are drawn by the theme chrome (UI.PaintChrome, cl_ui_theme.lua)
function PANEL:Paint(w, h)
	local tabs = self:TabRects()
	local mx, my = self:CursorPos()
	local hover = self:IsHovered() and self:TabAt(mx, my)
	for _, t in ipairs(tabs) do
		t.on = (t.page.id == self.active)
		t.hot = (t.page == hover)
	end
	SPeditor.UI.PaintChrome("Window", self, w, h, { tiled = isTiled(self), onTop = self.onTop, tabs = tabs, edge = EDGE, tabH = TAB_H })
end

---------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------
function PANEL:AddPage(id, title, panel, icon)
	local page = { id = id, title = title, icon = icon, panel = panel, win = self }
	panel:SetParent(self.content)
	panel:Dock(FILL)
	panel:SetVisible(false)
	self.pages[#self.pages + 1] = page
	Dock.pages[id] = page
	if not self.active then self:SelectPage(id) end
	return page
end

-- compatibility with DPropertySheet: the default id = the title
function PANEL:AddSheet(title, panel, icon, id)
	if panel.SetBackgroundColor then panel:SetBackgroundColor(PAL().BG) end
	return self:AddPage(id or title, title, panel, icon)
end

function PANEL:SelectPage(id)
	for _, p in ipairs(self.pages) do
		local on = (p.id == id)
		if IsValid(p.panel) then p.panel:SetVisible(on) end
		if on then self.active = id end
	end
end

-- take a page out without destroying its panel
function PANEL:DetachPage(id)
	for i, p in ipairs(self.pages) do
		if p.id == id then
			table.remove(self.pages, i)
			if self.active == id then
				self.active = nil
				local nxt = self.pages[math.min(i, #self.pages)]
				if nxt then self:SelectPage(nxt.id) end
			end
			return p
		end
	end
end

function PANEL:AdoptPage(page)
	page.panel:SetParent(self.content)
	page.panel:Dock(FILL)
	page.panel:SetVisible(false)
	page.win = self
	self.pages[#self.pages + 1] = page
	Dock.pages[page.id] = page
	self:SelectPage(page.id)
end

function PANEL:AddCloseButton()
	local b = vgui.Create("DButton", self)
	b:SetSize(SPeditor.UI.S(18), SPeditor.UI.S(18))
	b:SetText("")
	b.Paint = function(s, w, h) SPeditor.UI.PaintChrome("CloseButton", s, w, h) end
	b.DoClick = function() self:Close() end
	self.HdrBtns[#self.HdrBtns + 1] = b
	self:InvalidateLayout()
	return b
end

function PANEL:OnRemove()
	for i, w in ipairs(Dock.windows) do
		if w == self then table.remove(Dock.windows, i) break end
	end
end

---------------------------------------------------------------------
-- Mouse: moving, resizing, docking
---------------------------------------------------------------------
-- which edges are under the cursor: {l,r,t,b} or nil
function PANEL:EdgeAt(mx, my)
	local w, h = self:GetSize()
	local l, r, t, b = mx <= EDGE, mx >= w - EDGE, my <= EDGE, my >= h - EDGE
	-- corners: a small zone along the edges
	if mx <= 12 and my <= 12 then l, t = true, true end
	if mx >= w - 12 and my <= 12 then r, t = true, true end
	if mx <= 12 and my >= h - 12 then l, b = true, true end
	if mx >= w - 12 and my >= h - 12 then r, b = true, true end
	-- over a tab the size changes only by the frame itself: otherwise the first tab
	-- could not be grabbed with the mouse (the corner zone is wider than the frame)
	if mx > EDGE and my > EDGE and mx < w - EDGE and self:TabAt(mx, my) then return nil end
	if l or r or t or b then return { l = l, r = r, t = t, b = b } end
end

local function cursorFor(e)
	if not e then return "arrow" end
	if (e.l and e.t) or (e.r and e.b) then return "sizenwse" end
	if (e.r and e.t) or (e.l and e.b) then return "sizenesw" end
	if e.l or e.r then return "sizewe" end
	return "sizens"
end

function PANEL:Think()
	if self.resize or self.press then return end
	if vgui.GetHoveredPanel() == self and not Dock.locked and not self.maximized then
		local mx, my = self:CursorPos()
		self:SetCursor(cursorFor(self:EdgeAt(mx, my)))
	else
		self:SetCursor("arrow")
	end
end

---------------------------------------------------------------------
-- Window states: close, make floating, maximize
---------------------------------------------------------------------
function PANEL:Close()
	if self.maximized then self:ToggleMaximize() end
	if isTiled(self) then
		local rc = rectOf(self)
		self:SetVisible(false)
		self.undock = { rect = rc, grown = collapse(rc, self) }
	else
		self:SetVisible(false)
	end
end

-- Bring a closed window back. A docked one returns to its place if the
-- neighbours have not changed since; otherwise it opens floating.
function PANEL:Reopen()
	if self:IsVisible() then return end
	if self.dockable and not self.floating then
		local u = self.undock
		local ok = u ~= nil
		if ok then
			for w, g in pairs(u.grown) do
				if not (isTiled(w) and sameRect(rectOf(w), g.new)) then ok = false break end
			end
		end
		if ok then
			for w, g in pairs(u.grown) do setRect(w, g.old) end
			setRect(self, u.rect)
		end
		if not ok or next(u.grown) == nil then
			local mine = rectOf(self)
			for _, w in ipairs(tiledList(self)) do
				if intersects(mine, rectOf(w)) then self.floating = true break end
			end
		end
	end
	self.undock = nil
	self:SetVisible(true)
	self:MakePopup()
	self:SetKeyboardInputEnabled(false)
	raiseTop()
end

-- Tear the window off the layout: the neighbours take its place
function PANEL:Float()
	if self.maximized then self:ToggleMaximize() end
	if not isTiled(self) then return end
	local rc = rectOf(self)
	self.floating = true
	collapse(rc, self)
	local w = math.Clamp(rc.r - rc.x, self.minW, math.floor(ScrW() * 0.42))
	local h = math.Clamp(rc.b - rc.y, self.minH, math.floor(ScrH() * 0.55))
	self:SetSize(w, h)
	self:MoveToFront()
	raiseTop()
end

function PANEL:ToggleMaximize()
	local m = self.maximized
	if m then
		self.maximized = nil
		self.floating = m.floating
		setRect(self, m.rect)
		raiseFloating()
	else
		self.maximized = { rect = rectOf(self), floating = self.floating }
		self.floating = true
		setRect(self, workspace())
		self:MoveToFront()
		raiseTop()
	end
end

---------------------------------------------------------------------
-- Mouse: resizing
---------------------------------------------------------------------
function PANEL:BeginResize(edge)
	local snap = {}
	local tiled = isTiled(self)
	if tiled then
		for _, w in ipairs(tiledList()) do snap[w] = rectOf(w) end
	end
	snap[self] = rectOf(self)
	local r = { e = edge, mx = gui.MouseX(), my = gui.MouseY(), snap = snap, tiled = tiled, groups = {} }
	if tiled then
		if edge.l then r.groups.l = splitGroup(self, snap, AX.x, "a") end
		if edge.r then r.groups.r = splitGroup(self, snap, AX.x, "z") end
		if edge.t then r.groups.t = splitGroup(self, snap, AX.y, "a") end
		if edge.b then r.groups.b = splitGroup(self, snap, AX.y, "z") end
	end
	self.resize = r
	self:MouseCapture(true)
end

function PANEL:DoResize(ax, ay)
	local r = self.resize
	local dx, dy = ax - r.mx, ay - r.my

	if r.tiled then
		local new = {}
		for w, rc in pairs(r.snap) do new[w] = copyRect(rc) end
		if r.groups.l then moveSplit(self, r.groups.l, dx, r.snap, new) end
		if r.groups.r then moveSplit(self, r.groups.r, dx, r.snap, new) end
		if r.groups.t then moveSplit(self, r.groups.t, dy, r.snap, new) end
		if r.groups.b then moveSplit(self, r.groups.b, dy, r.snap, new) end
		for w, rc in pairs(new) do
			if IsValid(w) and not sameRect(rc, rectOf(w)) then setRect(w, rc) end
		end
		return
	end

	-- floating window: free, with snapping
	local s = r.snap[self]
	local nx, ny, nr, nb = s.x, s.y, s.r, s.b
	if r.e.l then nx = s.x + dx end
	if r.e.r then nr = s.r + dx end
	if r.e.t then ny = s.y + dy end
	if r.e.b then nb = s.b + dy end

	if Dock.snap then
		local xs, ys = neighbours(self)
		if r.e.l then nx = snapValue(nx, xs) end
		if r.e.r then nr = snapValue(nr, xs) end
		if r.e.t then ny = snapValue(ny, ys) end
		if r.e.b then nb = snapValue(nb, ys) end
	end

	if nr - nx < self.minW then
		if r.e.l then nx = nr - self.minW else nr = nx + self.minW end
	end
	if nb - ny < self.minH then
		if r.e.t then ny = nb - self.minH else nb = ny + self.minH end
	end
	nx, nr = math.max(nx, 0), math.min(nr, ScrW())
	ny, nb = math.max(ny, TOP_Y), math.min(nb, ScrH() - BOTTOM_H)
	self:SetPos(nx, ny)
	self:SetSize(math.max(nr - nx, self.minW), math.max(nb - ny, self.minH))
end

---------------------------------------------------------------------
-- Mouse: dragging a window and tabs
---------------------------------------------------------------------
-- The window is torn off the layout and then follows the cursor
function PANEL:BeginDrag(ax, ay)
	if self.maximized then self:ToggleMaximize() end
	local x, y = self:GetPos()
	local w0 = self:GetWide()
	local fx = math.Clamp((ax - x) / math.max(w0, 1), 0, 1)
	if isTiled(self) then self:Float() end
	local w = self:GetWide()
	self.press = {
		dragging = true, moved = true,
		gx = math.Clamp(math.floor(fx * w), 24, math.max(w - 48, 24)),
		gy = EDGE + math.floor(TAB_H / 2),
	}
	self:MoveToFront()
	if not self.onTop then raiseTop() end
	self:MouseCapture(true)
	self:SetCursor("sizeall")
	self:DragTo(ax, ay)
end

function PANEL:DragTo(ax, ay)
	local pr = self.press
	local w, h = self:GetSize()
	local nx, ny = ax - pr.gx, ay - pr.gy

	local zone
	local ctrl = input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
	if self.dockable and not ctrl then zone = Dock.ZoneAt(ax, ay, self) end

	if not zone and Dock.snap then
		local xs, ys = neighbours(self)
		nx = nx + snapSpan(nx, nx + w, xs)
		ny = ny + snapSpan(ny, ny + h, ys)
	end
	nx = math.Clamp(nx, 0, math.max(ScrW() - w, 0))
	ny = math.Clamp(ny, TOP_Y, math.max(ScrH() - BOTTOM_H - h, TOP_Y))
	self:SetPos(nx, ny)
	Dock.drag = { win = self, zone = zone }
end

-- Reordering a tab along the strip
function PANEL:ReorderTab(page, mx)
	local rects = self:TabRects()
	local idx
	for i, t in ipairs(rects) do
		if t.page == page then idx = i break end
	end
	if not idx then return end
	local prev, nxt = rects[idx - 1], rects[idx + 1]
	if prev and mx < prev.x + prev.w / 2 then
		self.pages[idx], self.pages[idx - 1] = self.pages[idx - 1], self.pages[idx]
	elseif nxt and mx > nxt.x + nxt.w / 2 then
		self.pages[idx], self.pages[idx + 1] = self.pages[idx + 1], self.pages[idx]
	end
end

function PANEL:OnMousePressed(code)
	self:MoveToFront()
	if isTiled(self) then raiseFloating() else raiseTop() end
	local mx, my = self:CursorPos()

	if code == MOUSE_RIGHT then
		if my <= EDGE + TAB_H then self:TabMenu(self:TabAt(mx, my)) end
		return
	end
	if code ~= MOUSE_LEFT then return end

	local inStrip = my <= EDGE + TAB_H
	local tab = inStrip and self:TabAt(mx, my) or nil
	if tab then self:SelectPage(tab.id) end

	-- double click on the tab strip: maximize / restore
	if inStrip and not Dock.locked then
		local now = SysTime()
		if now - (self.lastStripClick or 0) < 0.3 then
			self.lastStripClick = 0
			self:ToggleMaximize()
			return
		end
		self.lastStripClick = now
	end
	if Dock.locked then return end

	local edge = (not self.maximized) and self:EdgeAt(mx, my) or nil
	if edge then
		self:BeginResize(edge)
		return
	end

	if inStrip then
		self.press = { mx = gui.MouseX(), my = gui.MouseY(), page = tab, moved = false }
		self:MouseCapture(true)
	end
end

-- pull a tab out into a new floating window
function PANEL:TearOff(page, ax, ay)
	if #self.pages <= 1 then return self end
	local p = self:DetachPage(page.id)
	if not p then return self end
	local w, h = self:GetSize()
	local win = Dock.NewWindow({ w = math.min(w, 420), h = math.min(h, 420), x = ax - 40, y = ay - 12, dockable = true, floating = true,
			onTop = self.onTop })
	win:AdoptPage(p)
	win:AddCloseButton()
	return win
end

function PANEL:OnCursorMoved()
	local ax, ay = gui.MouseX(), gui.MouseY()

	if self.resize then
		self:DoResize(ax, ay)
		return
	end

	local pr = self.press
	if not pr then return end
	if pr.dragging then
		self:DragTo(ax, ay)
		return
	end

	if not pr.moved and math.abs(ax - pr.mx) + math.abs(ay - pr.my) < 5 then return end
	pr.moved = true

	-- tab of a multi-tab window: along the strip — order, away from the strip — tear off
	if pr.page and #self.pages > 1 then
		local mx, my = self:CursorPos()
		if my < EDGE - 18 or my > EDGE + TAB_H + 18 then
			local win = self:TearOff(pr.page, ax, ay)
			self:MouseCapture(false)
			self.press = nil
			if win ~= self then win:BeginDrag(ax, ay) end
		else
			self:ReorderTab(pr.page, mx)
		end
		return
	end

	self:BeginDrag(ax, ay)
end

function PANEL:OnMouseReleased(code)
	if code ~= MOUSE_LEFT then return end
	self:MouseCapture(false)
	self:SetCursor("arrow")
	self.resize = nil

	local pr = self.press
	self.press = nil
	if pr and pr.dragging then
		local d = Dock.drag
		Dock.drag = nil
		if d and d.win == self and d.zone then Dock.DockInto(self, d.zone) end
	end
end

function PANEL:TabMenu(tab)
	local L = SPeditor.L
	local m = SPeditor.UI.Menu()
	if not Dock.locked then
		if tab and #self.pages > 1 then
			m:AddOption(L("dock_float"), function()
				local ax, ay = self:GetPos()
				self:TearOff(tab, ax + 40, ay + 40)
			end)
		elseif isTiled(self) then
			m:AddOption(L("dock_float"), function()
				local x, y = self:GetPos()
				self:Float()
				self:SetPos(x + 40, y + 40)
			end)
		end
		m:AddOption(L(self.maximized and "dock_restore" or "dock_maximize"), function() self:ToggleMaximize() end)
		m:AddSpacer()
	end
	local props = m:AddSubMenu(L("dock_props"))
	props:AddOption(L("dock_ontop"), function() self:SetOnTop(not self.onTop) end):SetChecked(self.onTop and true or false)
	m:AddSpacer()
	m:AddOption(L("dock_close"), function() self:Close() end)
	m:Open()
end

vgui.Register("SPeditorDock", PANEL, "EditablePanel")

---------------------------------------------------------------------
-- Window factory
---------------------------------------------------------------------
function Dock.NewWindow(o)
	local win = SPeditor.UI.Skin(vgui.Create("SPeditorDock"))
	win:SetSize(SPeditor.UI.S(o.w or 400), SPeditor.UI.S(o.h or 300))
	win:SetPos(o.x or 100, o.y or TOP_Y)
	win:SetDockable(o.dockable ~= false)
	win.floating = o.floating and true or false
	win:MakePopup()
	win:SetKeyboardInputEnabled(false)
	win.key = o.key or ("float" .. (#Dock.windows + 1) .. "_" .. math.floor(SysTime() * 1000) % 100000)
	Dock.windows[#Dock.windows + 1] = win
	if o.floating then SPeditor.UI.FadeIn(win) end
	-- "always on top": the user's saved choice, otherwise the default value
	local saved = loadProps()[win.key]
	if istable(saved) and saved.top ~= nil then
		win.onTop = saved.top and true or false
	else
		win.onTop = o.onTop and true or false
	end
	raiseTop()
	return win
end

-- A window with one page. Returns the window and the page panel (Body).
function Dock.Create(o)
	local win = Dock.NewWindow(o)
	local body = vgui.Create("DPanel")
	body.Paint = function(_, w, h)
		surface.SetDrawColor(PAL().BG)
		surface.DrawRect(0, 0, w, h)
	end
	win:AddPage(o.id or o.key, o.title or "", body, o.icon)
	if o.close ~= false then win:AddCloseButton() end
	return win, body
end

function Dock.ByKey(key)
	for _, w in ipairs(Dock.windows) do
		if IsValid(w) and w.key == key then return w end
	end
end

function Dock.ShowPage(id)
	local p = Dock.pages[id]
	if not p or not IsValid(p.win) then return false end
	p.win:Reopen()
	p.win:SelectPage(id)
	p.win:MoveToFront()
	if isTiled(p.win) then raiseFloating() else raiseTop() end
	return true
end

function Dock.Clear()
	for _, w in ipairs(copyList(Dock.windows)) do
		if IsValid(w) then w:Remove() end
	end
	Dock.windows, Dock.pages = {}, {}
	Dock.drag = nil
end

function Dock.SetLocked(on) Dock.locked = on and true or false end

---------------------------------------------------------------------
-- "Always on top": the engine itself raises the window that was clicked (including
-- its content, bypassing the window's own handlers). So after a
-- click on any other editor window the pinned windows are brought back
-- up. Menus and dialogs are left alone: they are not Dock windows and open later.
---------------------------------------------------------------------
local function dockOf(pnl)
	while IsValid(pnl) do
		if pnl.SPeditorDock then return pnl end
		pnl = pnl:GetParent()
	end
end

local function anyTop()
	for _, w in ipairs(Dock.windows) do
		if IsValid(w) and w.onTop and w:IsVisible() then return true end
	end
	return false
end

hook.Add("VGUIMousePressed", "SPeditor.DockOnTop", function(pnl)
	if #Dock.windows == 0 or not anyTop() then return end
	local win = dockOf(pnl)
	if win and not win.onTop then raiseTop() end
end)

-- Safety net: a pinned window under the cursor turned out to be covered by a regular window
-- (the window was raised by code or the click bypassed the hook) — bring it back up.
local nextTopCheck = 0
hook.Add("Think", "SPeditor.DockOnTop", function()
	if #Dock.windows == 0 or RealTime() < nextTopCheck then return end
	nextTopCheck = RealTime() + 0.2
	if Dock.drag or input.IsMouseDown(MOUSE_LEFT) then return end
	local over = dockOf(vgui.GetHoveredPanel())
	if not over or over.onTop then return end
	local mx, my = gui.MousePos()
	for _, w in ipairs(Dock.windows) do
		if IsValid(w) and w.onTop and w:IsVisible() then
			local rc = rectOf(w)
			if mx >= rc.x and mx < rc.r and my >= rc.y and my < rc.b then
				raiseTop()
				return
			end
		end
	end
end)

---------------------------------------------------------------------
-- Layouts: capture / apply / files / presets
---------------------------------------------------------------------
local function dir()
	return (SPeditor.Config and SPeditor.Config.SaveDir or "speditor") .. "/layouts"
end

local function ensureDir()
	local acc = ""
	for part in string.gmatch(dir(), "[^/]+") do
		acc = (acc == "") and part or (acc .. "/" .. part)
		if not file.IsDir(acc, "DATA") then file.CreateDir(acc) end
	end
end

-- The menu bar and the status bar change their height with the interface scale. A layout
-- remembers the work area its windows were laid out for (Dock.placedWS: the bars of the last
-- Apply; the scale itself changes before the old layout is captured) and is stretched to the
-- present one when applied: before, after 200 % → 100 % the windows stayed lower, with a
-- strip of empty space above them and below.
local function currentWS()
	local sh = ScrH()
	return { top = TOP_Y / sh, bottom = (BOTTOM_H + GAP) / sh }
end

function Dock.Capture()
	local sw, sh = ScrW(), ScrH()
	local data = { version = LAYOUT_VERSION, windows = {}, snap = Dock.snap, locked = Dock.locked, ws = Dock.placedWS or currentWS() }
	for _, w in ipairs(Dock.windows) do
		if IsValid(w) then
			-- a maximized window is saved with its regular place
			local rc = w.maximized and w.maximized.rect or rectOf(w)
			local floating = w.floating
			if w.maximized then floating = w.maximized.floating end
			local ids = {}
			for _, p in ipairs(w.pages) do ids[#ids + 1] = p.id end
			data.windows[w.key] = {
				x = rc.x / sw, y = rc.y / sh, w = (rc.r - rc.x) / sw, h = (rc.b - rc.y) / sh,
				visible = w:IsVisible(), floating = floating and true or false,
				pages = ids, active = w.active,
			}
		end
	end
	return data
end

-- the work area a layout was made for: saved with it, or (older layouts) where its docked
-- windows begin and end, when that is close to a bar
local function layoutWS(data)
	local ws = data.ws
	if type(ws) == "table" and tonumber(ws.top) and tonumber(ws.bottom) then
		return { top = tonumber(ws.top), bottom = tonumber(ws.bottom) }
	end
	local top, bot
	for _, d in pairs(data.windows) do
		if type(d) == "table" and d.visible and not d.floating and tonumber(d.y) and tonumber(d.h) then
			local y, b = tonumber(d.y), tonumber(d.y) + tonumber(d.h)
			top = math.min(top or y, y)
			bot = math.max(bot or b, b)
		end
	end
	local band = 80 / ScrH()       -- bars at 200 % are ~50 px: farther than this is the player's own gap
	if not top or top > band or 1 - bot > band then return nil end
	return { top = top, bottom = 1 - bot }
end

-- a vertical fraction of the old work area → the same place in the present one
local function remapY(d, from, to)
	if not from or (math.abs(from.top - to.top) < 1e-4 and math.abs(from.bottom - to.bottom) < 1e-4) then return d end
	local oldH, newH = 1 - from.top - from.bottom, 1 - to.top - to.bottom
	if oldH <= 0.1 then return d end
	local y, h = tonumber(d.y) or 0, tonumber(d.h) or 0.2
	local out = table.Copy(d)
	out.y = to.top + (y - from.top) / oldH * newH
	out.h = h / oldH * newH
	return out
end

local function place(win, d)
	local sw, sh = ScrW(), ScrH()
	-- rounded, not floored: the fractions of a saved layout are not exact, and flooring took a
	-- pixel off a window at every save and restore (windows crept smaller session by session)
	local w = math.Clamp(math.Round((tonumber(d.w) or 0.2) * sw), win.minW, sw)
	local h = math.Clamp(math.Round((tonumber(d.h) or 0.2) * sh), win.minH, sh - TOP_Y - BOTTOM_H)
	local x = math.Clamp(math.Round((tonumber(d.x) or 0) * sw), 0, math.max(sw - w, 0))
	local y = math.Clamp(math.Round((tonumber(d.y) or 0) * sh), TOP_Y, math.max(sh - BOTTOM_H - h, TOP_Y))
	win:SetPos(x, y)
	win:SetSize(w, h)
	win.floating, win.undock, win.maximized = d.floating and true or false, nil, nil
	if d.visible ~= nil then
		win:SetVisible(d.visible and true or false)
		if d.visible then
			win:MakePopup()
			win:SetKeyboardInputEnabled(false)
		end
	end
end

function Dock.Apply(data)
	if type(data) ~= "table" or type(data.windows) ~= "table" then return false end
	-- layouts of the old format (free overlapping windows) do not suit docking
	if data.version ~= LAYOUT_VERSION then return false end

	-- 1) put the pages into their windows
	for key, d in pairs(data.windows) do
		if type(d) == "table" and type(d.pages) == "table" then
			local win = Dock.ByKey(key)
			for _, pid in ipairs(d.pages) do
				local page = Dock.pages[pid]
				if page and IsValid(page.win) then
					if not IsValid(win) then
						win = Dock.NewWindow({ key = key, w = 300, h = 300, floating = true })
						win:AddCloseButton()
					end
					if page.win ~= win and (win.dockable or #win.pages == 0) and page.win.dockable then
						local from = page.win
						from:DetachPage(pid)
						win:AdoptPage(page)
					end
				end
			end
		end
	end

	-- 2) sizes, visibility, active tabs (docked windows follow the bars of the present scale)
	local fromWS, toWS = layoutWS(data), currentWS()
	for key, d in pairs(data.windows) do
		local win = Dock.ByKey(key)
		if IsValid(win) and type(d) == "table" then
			place(win, d.floating and d or remapY(d, fromWS, toWS))
			if d.active and Dock.pages[d.active] and Dock.pages[d.active].win == win then
				win:SelectPage(d.active)
			end
		end
	end

	-- 3) remove empty windows
	for _, w in ipairs(copyList(Dock.windows)) do
		if IsValid(w) and #w.pages == 0 then w:Remove() end
	end

	-- 4) docked windows must not overlap: the extra ones are made floating
	-- (a layout saved on a larger screen: windows grow to their minimum width and overlap)
	normalize()
	local kept, forced = {}, 0
	for _, w in ipairs(Dock.windows) do
		if isTiled(w) then
			local rc = rectOf(w)
			for _, o in ipairs(kept) do
				if intersects(rc, o) then
					w.floating = true
					forced = forced + 1
					break
				end
			end
			if not w.floating then kept[#kept + 1] = rc end
		end
	end
	raiseFloating()

	if data.snap ~= nil then Dock.snap = data.snap and true or false end
	Dock.locked = data.locked and true or false
	Dock.placedWS = toWS
	return true, forced
end

function Dock.Save(name)
	name = SPeditor.SafeName(name)
	if name == "" then return false end
	ensureDir()
	file.Write(dir() .. "/" .. name .. ".json", util.TableToJSON(Dock.Capture(), true))
	return true
end

function Dock.Load(name)
	local raw = file.Read(dir() .. "/" .. SPeditor.SafeName(name) .. ".json", "DATA")
	return Dock.Apply(util.JSONToTable(raw or ""))
end

function Dock.List()
	local out = {}
	for _, f in ipairs(file.Find(dir() .. "/*.json", "DATA")) do
		local n = string.StripExtension(f)
		if n ~= "_last" then out[#out + 1] = n end
	end
	table.sort(out)
	return out
end

function Dock.SaveLast()
	if #Dock.windows == 0 then return end
	ensureDir()
	file.Write(dir() .. "/_last.json", util.TableToJSON(Dock.Capture(), true))
end

function Dock.RestoreLast()
	local raw = file.Read(dir() .. "/_last.json", "DATA")
	if not raw then return false end
	local ok, forced = Dock.Apply(util.JSONToTable(raw))
	-- the last layout does not fit this screen (docked windows overlap): the default one is better
	if ok and forced > 0 then
		Dock.Reset("default")
		return false
	end
	return ok
end

-- Layout presets. Windows and their pages:
--   left = { ase, ev }, primary, secondary, bottom = { scene, shadows }
-- leftF/secF — shares of the screen width, topF — the share of the height for the viewports.
local function preset(leftF, secF, topF, showSec, showBottom)
	return function()
		local sw, sh = ScrW(), ScrH()
		local G = 2                                  -- gap between windows
		local H = sh - TOP_Y - BOTTOM_H - G
		local data = { version = LAYOUT_VERSION, windows = {}, snap = Dock.snap, locked = false, ws = currentWS() }
		local function put(key, x, y, w, h, vis, pages, active)
			data.windows[key] = { x = x / sw, y = y / sh, w = w / sw, h = h / sh, visible = vis, floating = false, pages = pages, active = active }
		end
		-- shares of the screen, but not below the windows' minimum width: on narrow screens
		-- (1366, 1280, 1024 px) the left panel used to overlap the viewport
		local function minW(key, def)
			local w = Dock.ByKey(key)
			return IsValid(w) and w.minW or def
		end
		local leftW = math.max(math.floor(sw * leftF), minW("left", 300))
		put("left", 0, TOP_Y, leftW, H, true, { "ase", "ev" }, "ase")

		local x0 = leftW + G
		local restW = sw - x0
		local topH = showBottom and math.floor(H * topF) or H
		local secW = showSec and math.max(math.floor(sw * secF), minW("secondary", 220)) or 0
		if showSec then secW = math.max(math.min(secW, restW - G - minW("primary", 220)), minW("secondary", 220)) end
		local primW = restW - (showSec and (secW + G) or 0)
		put("primary", x0, TOP_Y, primW, topH, true, { "primary" }, "primary")
		put("secondary", x0 + primW + G, TOP_Y, math.max(secW, 220), topH, showSec, { "secondary" }, "secondary")
		put("bottom", x0, TOP_Y + topH + G, restW, math.max(H - topH - G, 120), showBottom, { "scene", "shadows" }, "scene")
		return data
	end
end

Dock.Presets = {
	default = preset(0.21, 0.39, 0.62, true, true),     -- like SFM: ASE on the left, two viewports, the bottom
	wide    = preset(0.21, 0.30, 0.78, false, true),    -- one large Primary
	compact = preset(0.24, 0.30, 1.00, true, false),    -- without the bottom window
}

function Dock.Reset(name)
	Dock.Apply((Dock.Presets[name or "default"] or Dock.Presets.default)())
end

-- "Layout" menu
function Dock.BuildMenu(m)
	local L = SPeditor.L
	m:AddOption(L("layout_default"), function() Dock.Reset("default") end)
	m:AddOption(L("layout_wide"), function() Dock.Reset("wide") end)
	m:AddOption(L("layout_compact"), function() Dock.Reset("compact") end)
	m:AddSpacer()
	m:AddOption(L("layout_save"), function()
		Derma_StringRequest(L("menu_layout"), L("layout_name_prompt"), "", function(name)
			if Dock.Save(name) then
				SPeditor.Notify("#layout_saved|" .. SPeditor.SafeName(name), 3)
			else
				SPeditor.Notify("#layout_bad_name", 1)
			end
		end)
	end)
	local sub = m:AddSubMenu(L("layout_load"))
	local names = Dock.List()
	if #names == 0 then
		local o = sub:AddOption(L("layout_none_saved"))
		if o.SetEnabled then o:SetEnabled(false) end
	else
		for _, n in ipairs(names) do
			sub:AddOption(n, function()
				if Dock.Load(n) then
					SPeditor.Notify("#layout_loaded|" .. n, 0)
				else
					SPeditor.Notify("#layout_failed|" .. n, 1)
				end
			end)
		end
	end
	m:AddSpacer()
	local snapOpt = m:AddOption(L("layout_snap"), function() Dock.snap = not Dock.snap end)
	snapOpt:SetChecked(Dock.snap)
	local lockOpt = m:AddOption(L("layout_lock"), function() Dock.SetLocked(not Dock.locked) end)
	lockOpt:SetChecked(Dock.locked)
end
