--[[
SPeditor — Help → Report a problem (a0.8). Reports like "the mouse pointer is bugged" could not be
acted on: nothing said what the game, the settings or the error were. The window builds one text
— what the player says happened, the errors the editor caught this session (both realms, see
sh_errors.lua), the game and editor settings that matter, the mounted addons — copies it and
opens the Bug Report discussion of the Workshop page to paste it there. Nothing is sent anywhere
by the editor itself.

  SPeditor.BuildReport(what)   the text of the report
  UI.OpenReport()              the window
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI   = SPeditor.UI
local L    = SPeditor.L
local COL  = UI.PAL
local Dock = SPeditor.Dock
local E    = SPeditor.Errors

local MAX_REPORT = 7000      -- a Steam discussion post holds about 8000 characters

local function osName()
	if system.IsWindows() then return "Windows" end
	if system.IsLinux() then return "Linux" end
	if system.IsOSX() then return "macOS" end
	return "?"
end

local function cv(name)
	local c = GetConVar(name)
	return c and c:GetString() or "-"
end

function SPeditor.BuildReport(what)
	local out = {}
	local function add(s) out[#out + 1] = s end
	add("SPeditor " .. tostring(SPeditor.Version) .. " — problem report")
	what = string.Trim(what or "")
	add("What happened: " .. (what ~= "" and what or "(not described)"))
	add("")
	add(string.format("Game: %s, %s, %s (%s), screen %dx%d, %s fps",
		game.GetMap(), game.SinglePlayer() and "single player" or ("server, " .. player.GetCount() .. " players"),
		osName(), tostring(rawget(_G, "BRANCH") or "?"), ScrW(), ScrH(), math.floor(1 / math.max(RealFrameTime(), 0.001))))
	add(string.format("Editor: %s, language %s, UI scale %s, theme %s, engine frame %s, render look %s, IK %s",
		(SPeditor.Client and SPeditor.Client.active) and "open" or "closed", cv("speditor_language"), cv("speditor_ui_scale"), cv("speditor_theme"),
		cv("speditor_render_engine"), cv("speditor_vp_look"), cv("speditor_ik")))
	local st = SPeditor.SelfTest and SPeditor.SelfTest.last
	if st then
		local failed = {}
		for _, s in ipairs(st.steps) do
			if not s.ok then failed[#failed + 1] = s.name .. " (" .. tostring(s.msg) .. ")" end
		end
		add(string.format("Self-test (%s): %d passed, %d failed%s", st.started or "?", st.ok, st.fail,
			#failed > 0 and (": " .. table.concat(failed, "; ")) or ""))
	end
	add("")
	local list = E and E.list or {}
	if #list == 0 then
		add("Errors: none caught this session")
	else
		add("Errors (" .. #list .. "):")
		for i, e in ipairs(list) do
			if i > 8 then
				add("…and " .. (#list - 8) .. " more")
				break
			end
			add(string.format("[%s] x%d %s", e.realm, e.count, e.msg))
			local n = 0
			for line in string.gmatch(e.stack or "", "[^\n]+") do
				n = n + 1
				if n > 5 then break end
				add("    " .. line)
			end
		end
	end
	add("")
	-- addons last: the list is long and is cut to what fits
	local names = {}
	for _, a in ipairs(engine.GetAddons()) do
		if a.mounted then names[#names + 1] = (a.title or "?") .. " (" .. tostring(a.wsid or "") .. ")" end
	end
	table.sort(names)
	local head = table.concat(out, "\n")
	local room = MAX_REPORT - #head - 40
	local shown = {}
	local used = 0
	for _, n in ipairs(names) do
		if used + #n + 2 > room then break end
		shown[#shown + 1] = n
		used = used + #n + 2
	end
	local tail = "Addons (" .. #names .. " mounted): " .. table.concat(shown, ", ")
	if #shown < #names then tail = tail .. ", …and " .. (#names - #shown) .. " more" end
	return head .. "\n" .. tail
end

---------------------------------------------------------------------
-- The window
---------------------------------------------------------------------
function UI.OpenReport()
	if Dock.ShowPage("report") then return end
	local W = 640
	local win, body = Dock.Create({ key = "report", id = "report", title = L("rep_title"), w = W, h = 620,
			x = math.floor(ScrW() / 2 - W / 2), y = 90, dockable = false, icon = "icon16/bug.png" })
	win.minW, win.minH = UI.S(480), UI.S(420)
	local baseRemove = win.OnRemove
	win.OnRemove = function(s)
		if baseRemove then baseRemove(s) end
		Dock.pages.report = nil
	end

	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(34))
	foot.Paint = function() end
	local function footBtn(text, icon, dock, w, fn)
		local b = vgui.Create("DButton", foot)
		b:Dock(dock)
		b:DockMargin(dock == LEFT and 8 or 4, 5, dock == RIGHT and 8 or 4, 5)
		b:SetWide(UI.S(w))
		b:SetText((icon and "  " or "") .. text)
		if icon then b:SetIcon(icon) end
		UI.StyleButton(b, nil, 3)
		b.DoClick = fn
		return b
	end

	local hint = UI.Label(body, L("rep_hint"), COL.TEXT)
	hint:SetWrap(true)
	hint:SetAutoStretchVertical(true)
	hint:DockMargin(10, 8, 10, 6)

	UI.Label(body, L("rep_what"), COL.TEXT):DockMargin(10, 2, 10, 2)
	local what = vgui.Create("DTextEntry", body)
	what:Dock(TOP)
	what:DockMargin(10, 0, 10, 6)
	what:SetTall(UI.S(64))
	what:SetMultiline(true)
	what:SetFont("SPeditor.Small")
	what:SetPlaceholderText(L("rep_what_ph"))

	local errHead = UI.Label(body, "", COL.TEXT)
	errHead:DockMargin(10, 2, 10, 2)
	local errs = vgui.Create("DListView", body)
	UI.StyleListView(errs)
	errs:Dock(TOP)
	errs:DockMargin(10, 0, 10, 6)
	errs:SetTall(UI.S(120))
	errs:SetMultiSelect(false)
	errs:AddColumn(L("rep_col_where")):SetFixedWidth(UI.S(60))
	errs:AddColumn(L("rep_col_times")):SetFixedWidth(UI.S(50))
	errs:AddColumn(L("rep_col_error"))

	UI.Label(body, L("rep_preview"), COL.TEXT):DockMargin(10, 2, 10, 2)
	local preview = vgui.Create("DTextEntry", body)
	preview:Dock(FILL)
	preview:DockMargin(10, 0, 10, 4)
	preview:SetMultiline(true)
	preview:SetFont("SPeditor.Small")
	preview:SetVerticalScrollbarEnabled(true)
	preview.AllowInput = function() return true end      -- read only; the text can still be selected

	local function refresh()
		if not IsValid(win) then return end
		errs:Clear()
		for _, e in ipairs(E.list) do
			local line = errs:AddLine(e.realm == "server" and L("rep_server") or L("rep_client"), e.count, e.msg)
			line:SetTooltip(e.msg .. "\n" .. (e.stack or ""))
		end
		errHead:SetText(string.format(L("rep_errors"), #E.list))
		preview:SetText(SPeditor.BuildReport(what:GetValue()))
	end
	what.OnChange = function() refresh() end
	win.SPRefresh = refresh

	footBtn(L("rep_copy"), "icon16/page_copy.png", LEFT, 150, function()
		SetClipboardText(SPeditor.BuildReport(what:GetValue()))
		SPeditor.Notify("#rep_copied", 2)
	end)
	footBtn(L("rep_open"), "icon16/world_go.png", LEFT, 190, function()
		gui.OpenURL(SPeditor.BugsURL or "https://steamcommunity.com/sharedfiles/filedetails/?id=3817852435")
	end)
	footBtn(L("about_close"), nil, RIGHT, 100, function() win:Remove() end)
	footBtn(L("rep_clear"), "icon16/bin.png", RIGHT, 130, function()
		E.Clear()
		refresh()
	end)
	refresh()
	return win
end

-- a caught error: the window updates; the player hears about it once in a while, not every frame
local nextNote = 0
SPeditor.Hook("SPeditor_ErrorLogged", "SPeditor.Report", function()
	local win = Dock.ByKey("report")
	if IsValid(win) and win.SPRefresh then win.SPRefresh() end
	if RealTime() < nextNote then return end
	nextNote = RealTime() + 60
	if SPeditor.Notify then SPeditor.Notify("#rep_caught", 1) end
end)

concommand.Add("speditor_report", function() UI.OpenReport() end)
