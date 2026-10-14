-- Steam 2004 Derma Skin (authors: Valve, Maks1mDiamond).
-- Adapted for SPeditor: the skin is registered under its own name and is active
-- only inside the editor (without the original's global hooks, sounds and windows).
local ARG = SPeditor.SkinArg or {}

local surface = surface
local Color = Color

local render = render

local IsValid = IsValid

local clamp = math.Clamp
local ceil = math.ceil

local drawTexturedRect = surface.DrawTexturedRect

local scrW = ScrW()
local scrH = ScrH()
hook.Add("OnScreenSizeChanged", "SPeditor.Steam2004.ScreenSize", function()
	scrW = ScrW()
	scrH = ScrH()
end)

SKIN = {}

SKIN.PrintName		= "Steam 2004 Derma Skin"
SKIN.Author			= "Valve, Maks1mDiamond"
SKIN.DermaVersion	= 1
SKIN.GwenTexture	= Material(ARG.tex or "speditor/skins/steam2004.png")

SKIN.bg_color					= Color( 101, 100, 105, 255 )
SKIN.bg_color_sleep				= Color( 70, 70, 70, 255 )
SKIN.bg_color_dark				= Color( 55, 57, 61, 255 )
SKIN.bg_color_bright			= Color( 220, 220, 220, 255 )
SKIN.frame_border				= Color( 50, 50, 50, 255 )

SKIN.fontFrame					= "DermaDefault"

SKIN.control_color				= Color( 120, 120, 120, 255 )
SKIN.control_color_highlight	= Color( 150, 150, 150, 255 )
SKIN.control_color_active		= Color( 110, 150, 250, 255 )
SKIN.control_color_bright		= Color( 255, 200, 100, 255 )
SKIN.control_color_dark			= Color( 100, 100, 100, 255 )

SKIN.bg_alt1					= Color( 50, 50, 50, 255 )
SKIN.bg_alt2					= Color( 55, 55, 55, 255 )

SKIN.listview_hover				= Color( 70, 70, 70, 255 )
SKIN.listview_selected			= Color( 100, 170, 220, 255 )

SKIN.text_bright				= Color( 255, 255, 255, 255 )
SKIN.text_normal				= Color( 180, 180, 180, 255 )
SKIN.text_dark					= Color( 20, 20, 20, 255 )
SKIN.text_highlight				= Color( 255, 20, 20, 255 )

SKIN.texGradientUp				= Material( "gui/gradient_up" )
SKIN.texGradientDown			= Material( "gui/gradient_down" )

SKIN.combobox_selected			= SKIN.listview_selected

SKIN.panel_transback			= Color( 255, 255, 255, 50 )
SKIN.tooltip					= Color( 255, 245, 175, 255 )

SKIN.colPropertySheet			= Color( 170, 170, 170, 255 )
SKIN.colTab						= SKIN.colPropertySheet
SKIN.colTabInactive				= Color( 140, 140, 140, 255 )
SKIN.colTabShadow				= Color( 0, 0, 0, 170 )
SKIN.colTabText					= Color( 255, 255, 255, 255 )
SKIN.colTabTextInactive			= Color( 0, 0, 0, 200 )
SKIN.fontTab					= "DermaDefault"

SKIN.colCollapsibleCategory		= Color( 255, 255, 255, 20 )

SKIN.colCategoryText			= Color( 255, 255, 255, 255 )
SKIN.colCategoryTextInactive	= Color( 200, 200, 200, 255 )
SKIN.fontCategoryHeader			= "TabLarge"

SKIN.colNumberWangBG				= Color( 255, 240, 150, 255 )
SKIN.colTextEntryBG					= Color(62, 70, 55)
SKIN.colTextEntryBorder				= Color( 20, 20, 20, 255 )
SKIN.colTextEntryText				= Color(216, 222, 211, 255)
SKIN.colTextEntryTextHighlight		= Color(149, 136, 49, 255)
SKIN.colTextEntryTextCursor			= Color(216, 222, 211, 255)
SKIN.colTextEntryTextPlaceholder	= Color(160, 170, 149, 255)

SKIN.colNumSliderNotch			= Color( 0, 0, 0, 100 )

SKIN.colMenuBG					= Color( 255, 255, 255, 200 )
SKIN.colMenuBorder				= Color( 0, 0, 0, 200 )

SKIN.colButtonText				= Color( 255, 255, 255, 255 )
SKIN.colButtonTextDisabled		= Color( 255, 255, 255, 55 )
SKIN.colButtonBorder			= Color( 20, 20, 20, 255 )
SKIN.colButtonBorderHighlight	= Color( 255, 255, 255, 50 )
SKIN.colButtonBorderShadow		= Color( 0, 0, 0, 100 )

SKIN.tex = {}

SKIN.tex.Checkbox_Checked			= GWEN.CreateTextureNormal( 448, 32, 15, 15 )
SKIN.tex.TreePlus					= GWEN.CreateTextureNormal( 448, 96, 15, 15 )
SKIN.tex.TreeMinus					= GWEN.CreateTextureNormal( 464, 96, 15, 15 )
SKIN.tex.Menu_Check					= GWEN.CreateTextureNormal( 448, 112, 15, 15 )

SKIN.tex.Window = {}

SKIN.tex.Window.Close			= GWEN.CreateTextureNormal( 32, 448, 31, 24 )
SKIN.tex.Window.Maxi			= GWEN.CreateTextureNormal( 32 + 96 * 2, 448, 31, 24 )
SKIN.tex.Window.Restore			= GWEN.CreateTextureNormal( 32 + 96 * 2, 448 + 32, 31, 24 )
SKIN.tex.Window.Mini			= GWEN.CreateTextureNormal( 32 + 96, 448, 31, 24 )

SKIN.tex.Scroller = {}

SKIN.tex.Scroller.LeftButton_Normal		= GWEN.CreateTextureBorder( 464, 208, 15, 15, 2, 2, 2, 2 )
SKIN.tex.Scroller.UpButton_Normal		= GWEN.CreateTextureBorder( 464, 208 + 16, 15, 15, 2, 2, 2, 2 )
SKIN.tex.Scroller.RightButton_Normal	= GWEN.CreateTextureBorder( 464, 208 + 32, 15, 15, 2, 2, 2, 2 )
SKIN.tex.Scroller.DownButton_Normal		= GWEN.CreateTextureBorder( 464, 208 + 48, 15, 15, 2, 2, 2, 2 )

SKIN.tex.Menu = {}
SKIN.tex.Menu.RightArrow = GWEN.CreateTextureNormal( 464, 112, 15, 15 )

SKIN.tex.Input = {}

SKIN.tex.Input.ComboBox = {}
SKIN.tex.Input.ComboBox.Button = {}
SKIN.tex.Input.ComboBox.Button.Normal	= GWEN.CreateTextureNormal( 496, 272, 15, 15 )

SKIN.tex.Input.UpDown = {}
SKIN.tex.Input.UpDown.Up = {}
SKIN.tex.Input.UpDown.Up.Normal		= GWEN.CreateTextureCentered( 384, 112, 7, 7 )
SKIN.tex.Input.UpDown.Down = {}
SKIN.tex.Input.UpDown.Down.Normal	= GWEN.CreateTextureCentered( 384, 120, 7, 7 )

SKIN.Colours = {}

SKIN.Colours.Window = {}
SKIN.Colours.Window.TitleActive		= color_white
SKIN.Colours.Window.TitleInactive	= Color(136, 145, 128)

SKIN.Colours.Button = {}
SKIN.Colours.Button.Normal			= color_white
SKIN.Colours.Button.Hover			= color_white
SKIN.Colours.Button.Down			= color_white
SKIN.Colours.Button.Disabled		= Color(40, 46, 34)

SKIN.Colours.Tab = {}
SKIN.Colours.Tab.Active = {}
SKIN.Colours.Tab.Active.Normal		= Color(196, 181, 80)
SKIN.Colours.Tab.Active.Hover		= Color(196, 181, 80)
SKIN.Colours.Tab.Active.Down		= Color(196, 181, 80)
SKIN.Colours.Tab.Active.Disabled	= Color(160, 170, 149)

SKIN.Colours.Tab.Inactive = {}
SKIN.Colours.Tab.Inactive.Normal	= color_white
SKIN.Colours.Tab.Inactive.Hover		= color_white
SKIN.Colours.Tab.Inactive.Down		= color_white
SKIN.Colours.Tab.Inactive.Disabled	= Color(160, 170, 149)

SKIN.Colours.Label = {}
SKIN.Colours.Label.Default			= Color(160, 170, 149)
SKIN.Colours.Label.Bright			= color_white
SKIN.Colours.Label.Dark				= Color(216, 222, 211)
SKIN.Colours.Label.Highlight		= Color(196, 181, 80)

SKIN.Colours.Tree = {}
SKIN.Colours.Tree.Lines				= Color(160, 170, 149)
SKIN.Colours.Tree.Normal			= Color(216, 222, 211)
SKIN.Colours.Tree.Hover				= Color(160, 170, 149) --* reused on controlhelp text from dform
SKIN.Colours.Tree.Selected			= color_white

SKIN.Colours.Properties = {}
SKIN.Colours.Properties.Line_Normal			= Color(255, 0, 255)  --! unused colors
SKIN.Colours.Properties.Line_Selected		= color_white			--! ^
SKIN.Colours.Properties.Line_Hover			= color_black			--! ^
SKIN.Colours.Properties.Title				= Color(196, 181, 80)
SKIN.Colours.Properties.Column_Normal		= color_black			--! is this unused??
SKIN.Colours.Properties.Column_Selected		= Color(149, 136, 49)
SKIN.Colours.Properties.Column_Hover		= pink					--! unused
SKIN.Colours.Properties.Column_Disabled		= color_transparent
SKIN.Colours.Properties.Border				= Color(40, 46, 34)
SKIN.Colours.Properties.Label_Normal		= color_white
SKIN.Colours.Properties.Label_Selected		= color_white
SKIN.Colours.Properties.Label_Hover			= color_black			--! unused
SKIN.Colours.Properties.Label_Disabled		= Color(160, 170, 149)

SKIN.Colours.Category = {}
SKIN.Colours.Category.Header				= color_white
SKIN.Colours.Category.Header_Closed			= Color(136, 145, 128)
SKIN.Colours.Category.Line = {}
SKIN.Colours.Category.Line.Text				= Color(216, 222, 211)
SKIN.Colours.Category.Line.Text_Hover		= color_white
SKIN.Colours.Category.Line.Text_Selected	= color_white
SKIN.Colours.Category.Line.Button			= color_transparent
SKIN.Colours.Category.Line.Button_Hover		= Color(40, 46, 34)
SKIN.Colours.Category.Line.Button_Selected	= Color(149, 136, 49)
SKIN.Colours.Category.LineAlt = {}
SKIN.Colours.Category.LineAlt.Text				= Color(216, 222, 211)
SKIN.Colours.Category.LineAlt.Text_Hover		= color_white
SKIN.Colours.Category.LineAlt.Text_Selected		= color_white
SKIN.Colours.Category.LineAlt.Button			= Color(0, 0, 0, 40)
SKIN.Colours.Category.LineAlt.Button_Hover		= Color(40, 46, 34)
SKIN.Colours.Category.LineAlt.Button_Selected	= Color(149, 136, 49)

SKIN.Colours.TooltipText = color_white

SKIN.Colours.ListBox = {}
SKIN.Colours.ListBox.EvenHovered	= Color(0, 0, 0, 50)
SKIN.Colours.ListBox.OddHovered		= color_transparent
SKIN.Colours.ListBox.EvenLine		= Color(0, 0, 0, 50)
SKIN.Colours.ListBox.OddLine		= color_transparent
SKIN.Colours.ListBox.Selected		= Color(149, 136, 49)

SKIN.Colours.SkinExclusive = {}
SKIN.Colours.SkinExclusive.Background				= Color(76, 88, 68)
SKIN.Colours.SkinExclusive.BackgroundInside			= Color(62, 70, 55)

SKIN.Colours.SkinExclusive.Border = {}
SKIN.Colours.SkinExclusive.Border.LightSide			= Color(136, 145, 128)
SKIN.Colours.SkinExclusive.Border.DarkSide			= Color(40, 46, 34)

SKIN.Colours.SkinExclusive.TextShadow				= Color(117, 128, 111)

SKIN.Colours.SkinExclusive.ScrollBar				= Color(90, 106, 80)
SKIN.Colours.SkinExclusive.SliderBackgroundInside	= Color(31, 31, 31)
SKIN.Colours.SkinExclusive.Selection				= Color(149, 136, 49)

SKIN.Colours.SkinExclusive.Progress					= Color(160, 170, 149)
SKIN.Colours.SkinExclusive.Progress2				= Color(196, 181, 80)

SKIN.Colours.SkinExclusive.Checkbox					= Color(196, 181, 80)
SKIN.Colours.SkinExclusive.CheckboxDisabled			= Color(255, 255, 255, 75)

SKIN.Colours.SkinExclusive.TitleIconActive			= color_white
SKIN.Colours.SkinExclusive.TitleIconInactive		= Color(255, 255, 255, 100)

SKIN.Colours.SkinExclusive.WindowButtons			= Color(135, 144, 127)
SKIN.Colours.SkinExclusive.WindowButtonsDisabled	= Color(135, 144, 127, 100)

SKIN.Colours.SkinExclusive.ComboArrow				= Color(176, 174, 174)
SKIN.Colours.SkinExclusive.ComboArrowDisabled		= Color(176, 174, 174, 50)

SKIN.SkinExclusive = {}
SKIN.SkinExclusive.ProgressbarStyle = "classic"
SKIN.SkinExclusive.ShowDisabledWindowButtons = "false"

SKIN.SkinExclusive.ContrastChecker = {}
SKIN.SkinExclusive.ContrastChecker.Enabled = "true"		-- only checks the background color on DTree, Panel (not the DFrame ones)
SKIN.SkinExclusive.ContrastChecker.DarkMode = "true"

SKIN.SkinExclusive.ReplaceCustomBackground = "false"	-- replaces the background on DTree & Panel

SKIN.SkinExclusive.TitleIcon = "speditor/skins/steam2004_icon.png"

SKIN.SkinExclusive.Blur = {}
SKIN.SkinExclusive.Blur.Alpha = "0"						-- blur from h0l-d4 (other solutions sucks)
SKIN.SkinExclusive.Blur.Quality = ".3"					-- blur intensity (min 0 max 2, float)

SKIN.SkinExclusive.Border = "true"
SKIN.SkinExclusive.OpaqueButtons = "false"				-- this one is for transparent backgrounds
SKIN.SkinExclusive.MenuBar = "true"
SKIN.SkinExclusive.InactiveTabAltColor = "false"

SKIN.SkinExclusive.bottomRightGripet = "speditor/skins/steam2004_grip.png"
SKIN.SkinExclusive.bottomRightGripetOffset = "5"

SKIN.SkinExclusive.Opaque = {}							-- shouldnt be changed manually, part of the changeOpacity function


--! compatibility for pac3
local function junkFunction(s)
	local bgCol = SKIN.Colours.SkinExclusive.Background
	return function(x, y, w, h, col)
		surface.SetDrawColor(col or bgCol or Color(76, 88, 68))
		surface.DrawRect(x, y, w, h)
	end
end

SKIN.tex.Tab_Control = junkFunction()
SKIN.tex.CategoryList = {
	["Outer"] = junkFunction(),
	["Header"] = junkFunction()
}
SKIN.tex.Menu_Strip = junkFunction()
SKIN.tex.Shadow = function(x, y, w, h)
	surface.SetDrawColor(255, 255, 255)
	surface.DrawRect(x, y, w, h)

	surface.SetDrawColor(0, 0, 0)
	local str = "looks like this derma skin is using global SKIN table instead of self..."
	surface.SetFont("DefaultFixed")
	local tW, _ = surface.GetTextSize(str)
	surface.DrawRect(x, y - 16, tW, 16)
	surface.SetTextColor(255, 255, 255)
	surface.SetTextPos(x, y - 16)
	surface.DrawText(str)
end



local function stringToBoolean(v) -- ui skin manager doesnt support boolean & number (without decimals) values yet
	if v == "true" then
		return true
	elseif v == "false" then
		return false
	end
end

local function getParent(parent, matchName) -- if it works then it works
	local p
	repeat
		p = parent:GetParent()
		if p then
			parent = p
		else
			return
		end
	until parent:GetName() == matchName
	return parent
end

local function getLineThickness(sself) -- up to 3
	if stringToBoolean(sself.SkinExclusive.Border) then
		return 1
	else
		return 0
	end
end

local function minimumContrastToPass(sself, color)
	if not stringToBoolean(sself.SkinExclusive.ContrastChecker.Enabled) then
		return true
	elseif stringToBoolean(sself.SkinExclusive.ReplaceCustomBackground) then
		return
	end

	local _, s, v = ColorToHSV(color)

	local dark = stringToBoolean(sself.SkinExclusive.ContrastChecker.DarkMode)

	if dark and s < .75 and v < .5 then
		return true
	elseif not dark and v > .75 then
		return true
	end
end

local function changeOpacity(sself, color) --! expensive, the skin table is globally shared instead of per panel or paint which probably isnt good for multiple different colours
	if stringToBoolean(sself.SkinExclusive.OpaqueButtons) then
		local o = sself.SkinExclusive.Opaque --! youre storing in single global table, try storing in panel instead
		local matchColor = o == color -- looks wrong
		if o.a and o.a == 255 and matchColor then
			return o
		else
			local c = color or sself.Colours.SkinExclusive.Background
			sself.SkinExclusive.Opaque = Color(c.r, c.g, c.b, 255)
			return sself.SkinExclusive.Opaque
		end
	else
		return color
	end
end



local blur = Material("pp/blurscreen")
local function drawBlur(sself, panel, w, h) -- code snippet taken from H0L-D4
	local bAlpha = tonumber(sself.SkinExclusive.Blur.Alpha)
	if bAlpha <= 0 then return end
	local bQuality = tonumber(sself.SkinExclusive.Blur.Quality)
	local quality = 5 * bQuality

	local x, y = panel:LocalToScreen()
	local rx, ry = 0, 0

	surface.SetMaterial(blur)
	for i = 1, clamp(ceil(quality), 1, 10) do
		local mul = clamp(5 / quality, 1, 3)
		blur:SetFloat("$blur", ((i * mul) / 3) * 2)
		blur:Recompute()

		render.UpdateScreenEffectTexture()

		render.SetScissorRect(rx + x, ry + y, rx + x + w, ry + y + h, true)
		surface.SetDrawColor(255, 255, 255, bAlpha)
		drawTexturedRect(x * -1, y * -1, scrW, scrH)
		render.SetScissorRect(0, 0, 0, 0, false)
	end
end
-- local function drawBlur(sself, panel, w, h) -- for paint library
-- 	local bAlpha = tonumber(sself.SkinExclusive.Blur.Alpha)
-- 	if bAlpha <= 0 then return end

-- 	local x, y = panel:LocalToScreen()

-- 	local bg = Color(255, 255, 255, bAlpha)
-- 	-- local mat = paint.blur.getBlurMaterial("steam2004Blur", 0, 8, 2)
-- 	local mat = paint.blur.getBlurMaterial()
-- 	paint.rects.drawRect(x, y, w, h, bg, mat, x / scrW, y / scrH, (x + w) / scrW, (y + h) / scrH)
-- end

local function drawVGUIRect(sself, x, y, w, h, bgColor)
	bgColor = bgColor or sself.Colours.SkinExclusive.Background
	local bLight = sself.Colours.SkinExclusive.Border.LightSide
	local bDark = sself.Colours.SkinExclusive.Border.DarkSide
	local lt = getLineThickness(sself)
	surface.SetDrawColor(bgColor)
	surface.DrawRect(x + lt, y + lt, w - lt * 2, h - lt * 2)

	surface.SetDrawColor(bLight)
	surface.DrawRect(x, y, w - lt, lt)					--top
	surface.DrawRect(x, y + lt, lt, h - lt * 2)					--left

	surface.SetDrawColor(bDark)
	surface.DrawRect(x + w - lt, y, lt, h - lt)	--right
	surface.DrawRect(x, y + h - lt, w, lt)				--bottom
end

local function drawVGUIRectAlt(sself, x, y, w, h, invert, bgColor)
	local lt = getLineThickness(sself)
	if bgColor then
		surface.SetDrawColor(bgColor)
	else
		surface.SetDrawColor(sself.Colours.SkinExclusive.Background)
	end
	surface.DrawRect(x + lt, y + lt, w - lt * 2, h - lt * 2)

	local c1, c2
	if invert then
		c1 = sself.Colours.SkinExclusive.Border.DarkSide
		c2 = sself.Colours.SkinExclusive.Border.LightSide
	else
		c1 = sself.Colours.SkinExclusive.Border.LightSide
		c2 = sself.Colours.SkinExclusive.Border.DarkSide
	end
	surface.SetDrawColor(c1)
	surface.DrawRect(x, y, w, lt)							--top
	surface.DrawRect(x, y + lt, lt, h - lt * 2)				--left

	surface.SetDrawColor(c2)
	surface.DrawRect(x + w - lt, y + lt, lt, h - lt * 2)	--right
	surface.DrawRect(x, y + h - lt, w, lt)					--bottom
end



function SKIN:PaintPanel( panel, w, h )
	if not panel.m_bBackground then return end
	if panel:GetName() == "NoticePanel" then
		drawVGUIRect(self, 0, 0, w, h)
	elseif panel.m_bgColor and minimumContrastToPass(self, panel.m_bgColor) then
		drawVGUIRectAlt(self, 0, 0, w, h, true, panel.m_bgColor)
	else
		drawVGUIRectAlt(self, 0, 0, w, h, true, self.Colours.SkinExclusive.BackgroundInside)
	end
end

function SKIN:PaintShadow( panel, w, h )
	return
end

function SKIN:PaintFrame( panel, w, h )
	local focus = panel:HasHierarchicalFocus()

	local customTitleIcon = self.SkinExclusive.TitleIcon
	if customTitleIcon ~= "" then
		local titleIcon = panel.imgIcon
		if IsValid(titleIcon) then
			local tia = self.Colours.SkinExclusive.TitleIconActive
			local tii = self.Colours.SkinExclusive.TitleIconInactive
			local tigic = titleIcon:GetImageColor()
			if focus and tigic ~= tia then
				panel.imgIcon:SetImageColor(tia)
			elseif not focus and tigic ~= tii then
				panel.imgIcon:SetImageColor(tii)
			end
		else
			panel:SetIcon(customTitleIcon)
			titleIcon = panel.imgIcon
		end
	end

	local title = panel.lblTitle
	if IsValid(title) then
		local textColor = title:GetTextColor()
		if not focus and textColor ~= self.Colours.Window.TitleInactive then -- dframe title text color doesnt change depending on the focus by default (is this intentional?)
			title:SetTextColor(self.Colours.Window.TitleInactive)
		elseif focus and textColor ~= self.Colours.Window.TitleActive then
			title:SetTextColor(self.Colours.Window.TitleActive)
		end
	end

	drawBlur(self, panel, w, h)
	drawVGUIRect(self, 0, 0, w, h)

	local gripet = self.SkinExclusive.bottomRightGripet
	if gripet ~= "" and panel:GetSizable() then
		local texture = Material(gripet)
		local tex = texture:GetTexture("$basetexture") --* make it colourable
		local texW, texH = tex:Width(), tex:Height()
		local offset = tonumber(self.SkinExclusive.bottomRightGripetOffset) --v1=5, v2=2
		surface.SetMaterial(texture)
		surface.SetDrawColor(color_white)
		if stringToBoolean(self.SkinExclusive.Border) then
			drawTexturedRect(w - texW - offset - 1, h - texH - offset - 1, texW, texH)
		else
			drawTexturedRect(w - texW - offset, h - texH - offset, texW, texH)
		end
	end
end



function SKIN:PaintButton( panel, w, h )
	if not panel.m_bBackground then return end

	if panel.Depressed or panel:IsSelected() or panel:GetToggle() then
		drawVGUIRectAlt(self, 0, 0, w, h, true, changeOpacity(self))
	elseif panel:GetDisabled() then
		drawVGUIRect(self, 0, 0, w, h)

		local text = panel:GetText()
		surface.SetTextColor(self.Colours.SkinExclusive.TextShadow)
		surface.SetFont(panel:GetFont())
		local tW, tH = surface.GetTextSize(text)
		local offset = 1
		surface.SetTextPos(w / 2 - tW / 2 + offset, h / 2 - tH / 2 + offset)
		surface.DrawText(text)
	else
		drawVGUIRect(self, 0, 0, w, h, changeOpacity(self))
	end
end



function SKIN:PaintTree( panel, w, h )
	if not panel.m_bBackground then return end

	if panel.m_bgColor and minimumContrastToPass(self, panel.m_bgColor) then
		drawVGUIRectAlt(self, 0, 0, w, h, true, panel.m_bgColor)
	else
		drawVGUIRectAlt(self, 0, 0, w, h, true, self.Colours.SkinExclusive.BackgroundInside)
	end
end

function SKIN:PaintExpandButton( panel, w, h )
	local pad = 4

	local dtree = getParent(panel, "DTree")
	local dprop = getParent(panel, "DProperties")
	local deprop = getParent(panel, "DEntityProperties")

	if dtree then
		if dtree.m_bgColor and minimumContrastToPass(self, dtree.m_bgColor) then
			surface.SetDrawColor(dtree.m_bgColor)
		else
			surface.SetDrawColor(self.Colours.SkinExclusive.BackgroundInside)
		end
	else
		surface.SetDrawColor(self.Colours.SkinExclusive.BackgroundInside)
	end
	if not dprop and not deprop then
		surface.DrawRect(pad / 2, pad / 2, w - pad, h - pad)
	end

	if not panel:GetExpanded() then
		self.tex.TreePlus( 0, 0, w, h, self.Colours.Tree.Lines )
	else
		self.tex.TreeMinus( 0, 0, w, h, self.Colours.Tree.Lines )
	end
end



local function drawCheckbox(sself, w, h, color)
	local pad = 1
	local lt = getLineThickness(sself)

	surface.SetDrawColor(changeOpacity(sself, color))
	surface.DrawRect(pad + lt, pad + lt, w - lt * 2 - pad * 2, h - lt * 2 - pad * 2)

	surface.SetDrawColor(sself.Colours.SkinExclusive.Border.DarkSide)
	surface.DrawRect(pad, pad, w - pad * 2 - lt, lt)
	surface.DrawRect(pad, pad + lt, lt, h - pad * 2 - lt * 2)

	surface.SetDrawColor(sself.Colours.SkinExclusive.Border.LightSide)
	surface.DrawRect(w - pad - lt, pad, lt, h - pad * 2 - lt)
	surface.DrawRect(pad, h - pad - lt, w - pad * 2, lt)
end

function SKIN:PaintCheckBox( panel, w, h )
	if panel:GetDisabled() then
		drawCheckbox(self, w, h, self.Colours.SkinExclusive.Background)
	else
		drawCheckbox(self, w, h, self.Colours.SkinExclusive.BackgroundInside)
	end
	if panel:GetChecked() then
		if panel:GetDisabled() then
			self.tex.Checkbox_Checked(0, 0, w, h, self.Colours.SkinExclusive.CheckboxDisabled)
		else
			self.tex.Checkbox_Checked(0, 0, w, h, self.Colours.SkinExclusive.Checkbox)
		end
	end
end

function SKIN:PaintRadioButton( panel, w, h )
	if panel:GetDisabled() then
		drawCheckbox(self, w, h, self.Colours.SkinExclusive.Background)
	else
		drawCheckbox(self, w, h, self.Colours.SkinExclusive.BackgroundInside)
	end
	if panel:GetChecked() then
		if panel:GetDisabled() then
			surface.SetDrawColor(self.Colours.SkinExclusive.CheckboxDisabled)
		else
			surface.SetDrawColor(self.Colours.SkinExclusive.Checkbox)
		end
		surface.DrawRect(4, 4, w - 8, h - 8)
	end
end

function SKIN:PaintTextEntry( panel, w, h )
	if panel.m_bBackground then
		if panel:GetDisabled() then
			drawVGUIRectAlt(self, 0, 0, w, h, true)
		else
			drawVGUIRectAlt(self, 0, 0, w, h, true, changeOpacity(self, self.Colours.SkinExclusive.BackgroundInside))
		end
	end

	-- Hack on a hack, but this produces the most close appearance to what it will actually look if text was actually there
	local gPlaceholderText = panel:GetPlaceholderText()
	local gPlaceholderColor = panel:GetPlaceholderColor()
	local gText = panel:GetText()
	local gHighlightColor = panel:GetHighlightColor()
	local gCursorColor = panel:GetCursorColor()
	if panel.GetPlaceholderText and panel.GetPlaceholderColor and gPlaceholderText and gPlaceholderText:Trim() ~= "" and gPlaceholderColor and (not gText or gText == "") then
		local oldText = gText

		local str = gPlaceholderText
		if str:StartWith("#") then str = str:sub(2) end
		str = language.GetPhrase(str)

		panel:SetText(str)
		panel:DrawTextEntryText(gPlaceholderColor, gHighlightColor, gCursorColor)
		panel:SetText(oldText)

		return
	end

	panel:DrawTextEntryText(panel:GetTextColor(), gHighlightColor, gCursorColor)
end



function SKIN:PaintMenu( panel, w, h )
	drawBlur(self, panel, w, h)
	drawVGUIRect(self, 0, 0, w, h)
	if panel:GetDrawColumn() then
		local lt = getLineThickness(self)
		surface.SetDrawColor(self.Colours.SkinExclusive.BackgroundInside)
		surface.DrawRect(lt, lt, 24 - lt, h - lt * 2)
	end
end

function SKIN:PaintMenuSpacer( panel, w, h )
	local lt = getLineThickness(self)
	if stringToBoolean(self.SkinExclusive.DarkMode) then
		surface.SetDrawColor(self.Colours.SkinExclusive.Border.LightSide)
		surface.DrawRect(0, 0, w - lt, h)
	else
		surface.SetDrawColor(self.Colours.SkinExclusive.Border.DarkSide)
		surface.DrawRect(lt, 0, w - lt, h)
	end
end

function SKIN:PaintMenuOption( panel, w, h )
	local lt = getLineThickness(self)
	-- if panel.m_bBackground and not panel:IsEnabled() then
	if panel.m_bBackground and (panel.Hovered or panel.Highlight) and panel:IsEnabled() then
		surface.SetDrawColor(self.Colours.Category.Line.Button_Selected)
		surface.DrawRect(lt, lt, w - lt * 2, h - lt * 2)
	end

	if panel:GetChecked() then
		self.tex.Menu_Check(5, h / 2 - 7, 15, 15, self.Colours.Label.Dark)
	end
end

function SKIN:PaintMenuRightArrow( panel, w, h )
	self.tex.Menu.RightArrow(0, 0, w, h, self.Colours.Label.Dark)
end



local function drawPropertySheet(sself, x, y, w, h, tabX, tabW, pnlCanvasX, tabScrollerW)
	local bgColor = sself.Colours.SkinExclusive.Background
	local bLight = sself.Colours.SkinExclusive.Border.LightSide
	local bDark = sself.Colours.SkinExclusive.Border.DarkSide
	local lt = getLineThickness(sself)

	surface.SetDrawColor(bgColor)
	surface.DrawRect(x + lt, y + lt, w - lt * 2, h - lt * 2)

	surface.SetDrawColor(bDark)
	surface.DrawRect(x + w - lt, y, lt, h - lt)				--right
	surface.DrawRect(x, y + h - lt, w, lt)					--bottom

	surface.SetDrawColor(bLight)
	surface.DrawRect(x, y + lt, lt, h - lt * 2)				--left

	--top
	local secondLeftLineWidth = clamp(tabX + pnlCanvasX + 3, 0, tabScrollerW)
	local firstRightLineWidth = clamp(tabScrollerW - tabW - tabX - pnlCanvasX + 4 - lt, 0, tabScrollerW)

	if secondLeftLineWidth >= tabScrollerW or firstRightLineWidth >= tabScrollerW then
		surface.DrawRect(0, y, tabScrollerW + 6 - lt, lt)
	else
		surface.DrawRect(0, y, 3, lt)						--first left line
		surface.DrawRect(tabScrollerW + 3, y, 3 - lt, lt)	--second right line

		if secondLeftLineWidth > 0 then
			surface.DrawRect(3, y, secondLeftLineWidth, lt)
		end

		if firstRightLineWidth > 0 then
			local firstRightLineX = clamp(pnlCanvasX + tabX + tabW, 3, math.huge)
			surface.DrawRect(firstRightLineX, y, firstRightLineWidth, lt)
		end
	end
end

function SKIN:PaintPropertySheet( panel, w, h )
	-- TODO: Tabs at bottom, left, right

	local ActiveTab = panel:GetActiveTab()
	local Offset = 0
	if ActiveTab then Offset = ActiveTab:GetTall() - 8 end

	local tabScroller = panel.tabScroller
	local pnlCanvasX
	if tabScroller or ActiveTab then
		pnlCanvasX = tabScroller.pnlCanvas or ActiveTab:GetParent()
	end

	drawBlur(self, panel, w, h)
	if ActiveTab and tabScroller then
		local tabX = ActiveTab:GetX()
		local tabW = ActiveTab:GetWide()

		drawPropertySheet(self, 0, Offset, w, h - Offset, tabX, tabW, pnlCanvasX:GetX(), tabScroller:GetWide())
	else
		drawVGUIRect(self, 0, Offset, w, h - Offset)
	end
end

local function drawTabs(sself, panel, w, h, active)
	local lt = getLineThickness(sself)
	local subtractTabWidth = 6
	w = w - subtractTabWidth
	local posX = subtractTabWidth / 2
	local posY = 0
	if active then
		h = h - 8
	else
		posY = 2
	end
	local x, y = posX + lt, posY + lt
	local dw, dh = w - (lt * 2), h - posY
	if not active and stringToBoolean(sself.SkinExclusive.InactiveTabAltColor) then
		surface.SetDrawColor(sself.Colours.SkinExclusive.BackgroundInside)
	else
		surface.SetDrawColor(sself.Colours.SkinExclusive.Background)
	end
	surface.DrawRect(x, y, dw, dh)										--base

	surface.SetDrawColor(sself.Colours.SkinExclusive.Border.LightSide)	--left
	surface.DrawRect(posX, posY + lt, lt, h - posY)
	if active then														--top
		surface.DrawRect(posX, posY, w, lt)
	else
		surface.DrawRect(posX, posY, w - lt, lt)
	end

	surface.SetDrawColor(sself.Colours.SkinExclusive.Border.DarkSide)	--right
	if active then
		surface.DrawRect(posX + w - lt, posY + lt, lt, h - posY)
	else
		surface.DrawRect(posX + w - lt, posY, lt, h - posY)
	end
end

function SKIN:PaintTab( panel, w, h )
	if panel:IsActive() then
		return self:PaintActiveTab( panel, w, h )
	end
	drawTabs(self, panel, w, h)
end

function SKIN:PaintActiveTab( panel, w, h )
	drawTabs(self, panel, w, h, true)
end



local function drawWindowButtons(sself, panel, w, h, name)
	if not panel.m_bBackground then return end

	local buttonHeight = 17
	local size = -2
	local pos = {
		["Mini"] = 0,
		["Maxi"] = 1,
		["Close"] = 2
	}

	local frame = getParent(panel, "DFrame")

	local cWB = sself.Colours.SkinExclusive.WindowButtons
	local cWBD = sself.Colours.SkinExclusive.WindowButtonsDisabled
	local SDWB = stringToBoolean(sself.SkinExclusive.ShowDisabledWindowButtons)

	if frame and not frame:HasHierarchicalFocus() then
		if SDWB then
			if panel:GetDisabled() then
				sself.tex.Window[name](0, 0, w, h, cWBD)
			else
				sself.tex.Window[name](0, 0, w, h, cWB)
			end
		elseif not panel:GetDisabled() then
			sself.tex.Window[name](0, 0, w, h, cWB)
		end
	elseif panel:GetDisabled() then
		if SDWB then
			drawVGUIRectAlt(sself, pos[name], buttonHeight / 4, w + size, buttonHeight)
			sself.tex.Window[name](0, 0, w, h, cWBD)
		end
	elseif panel.Depressed or panel:IsSelected() then
		drawVGUIRectAlt(sself, pos[name], buttonHeight / 4, w + size, buttonHeight, true, changeOpacity(sself))
		sself.tex.Window[name](1, 1, w, h, cWB)
	else
		drawVGUIRectAlt(sself, pos[name], buttonHeight / 4, w + size, buttonHeight, false, changeOpacity(sself))
		sself.tex.Window[name](0, 0, w, h, cWB)
	end
end

function SKIN:PaintWindowCloseButton( panel, w, h )
	drawWindowButtons(self, panel, w, h, "Close")
end

function SKIN:PaintWindowMinimizeButton( panel, w, h )
	drawWindowButtons(self, panel, w, h, "Mini")
end

function SKIN:PaintWindowMaximizeButton( panel, w, h )
	drawWindowButtons(self, panel, w, h, "Maxi")
end



function SKIN:PaintVScrollBar( panel, w, h )
	surface.SetDrawColor(self.Colours.SkinExclusive.ScrollBar)
	surface.DrawRect(0, 0, w, h)
end

function SKIN:PaintHScrollBar( panel, w, h )
	surface.SetDrawColor(self.Colours.SkinExclusive.ScrollBar)
	surface.DrawRect(0, 0, w, h)
end

function SKIN:PaintScrollBarGrip( panel, w, h )
	drawVGUIRect(self, 0, 0, w, h, changeOpacity(self))
end

local function drawScrollButtons(sself, panel, w, h, direction)
	if not panel.m_bBackground then return end

	if panel.Depressed or panel:IsSelected() then
		drawVGUIRectAlt(sself, 0, 0, w, h, true, changeOpacity(sself))
		sself.tex.Scroller[direction .. "Button_Normal"](1, 1, w, h, sself.Colours.SkinExclusive.ComboArrow)
	elseif panel:GetDisabled() then
		sself.tex.Scroller[direction .. "Button_Normal"](0, 0, w, h, sself.Colours.SkinExclusive.ComboArrowDisabled)
	else
		drawVGUIRectAlt(sself, 0, 0, w, h, false, changeOpacity(sself))
		sself.tex.Scroller[direction .. "Button_Normal"](0, 0, w, h, sself.Colours.SkinExclusive.ComboArrow)
	end
end

function SKIN:PaintButtonDown( panel, w, h )
	drawScrollButtons(self, panel, w, h, "Down")
end
function SKIN:PaintButtonUp( panel, w, h )
	drawScrollButtons(self, panel, w, h, "Up")
end
function SKIN:PaintButtonLeft( panel, w, h )
	drawScrollButtons(self, panel, w, h, "Left")
end
function SKIN:PaintButtonRight( panel, w, h )
	drawScrollButtons(self, panel, w, h, "Right")
end



function SKIN:PaintComboDownArrow( panel, w, h )
	self.tex.Input.ComboBox.Button.Normal(0, 0, w, h, self.Colours.SkinExclusive.ComboArrow)
end

function SKIN:PaintComboBox( panel, w, h )
	if panel:GetDisabled() then
		drawVGUIRectAlt(self, 0, 0, w, h, true, color_transparent)
	else
		drawVGUIRectAlt(self, 0, 0, w, h, true, changeOpacity(self, self.Colours.SkinExclusive.BackgroundInside))
	end
end



function SKIN:PaintListBox( panel, w, h )
	drawVGUIRectAlt(self, 0, 0, w, h, true, self.Colours.SkinExclusive.BackgroundInside)
end



local function drawNumberWang(sself, panel, w, h, name)
	if panel:GetDisabled() then
		sself.tex.Input.UpDown[name].Normal(0, 0, w, h, sself.Colours.SkinExclusive.ComboArrowDisabled)
	elseif panel.Depressed then
		sself.tex.Input.UpDown[name].Normal(0, 1, w, h, sself.Colours.SkinExclusive.ComboArrow)
	else
		sself.tex.Input.UpDown[name].Normal(0, 0, w, h, sself.Colours.SkinExclusive.ComboArrow)
	end
end

function SKIN:PaintNumberUp( panel, w, h )
	drawNumberWang(self, panel, w, h, "Up")
end
function SKIN:PaintNumberDown( panel, w, h )
	drawNumberWang(self, panel, w, h, "Down")
end



function SKIN:PaintTreeNode( panel, w, h )
	if not panel.m_bDrawLines then return end

	surface.SetDrawColor( self.Colours.Tree.Lines )

	if panel.m_bLastChild then
		surface.DrawRect( 9, 0, 1, 7 )
		surface.DrawRect( 9, 7, 9, 1 )
	else
		surface.DrawRect( 9, 0, 1, h )
		surface.DrawRect( 9, 7, 9, 1 )
	end
end

function SKIN:PaintTreeNodeButton( panel, _, h )
	if not panel.m_bSelected then return end
	local w, _ = panel:GetTextSize()
	surface.SetDrawColor(self.Colours.SkinExclusive.Selection)
	surface.DrawRect(38, 0, w + 6, h)
end

function SKIN:PaintSelection( panel, w, h )
	surface.SetDrawColor(self.Colours.SkinExclusive.Selection)
	surface.DrawRect(0, 0, w, h)
end



function SKIN:PaintSliderKnob( panel, w, h )
	if panel:GetParent() and panel:GetParent():GetName() == "DColorCube" then
		surface.SetDrawColor(color_black)
		surface.DrawCircle(w / 2, h / 2, 5, 0, 0, 0, 200)
		surface.DrawCircle(w / 2, h / 2, 6, color_white)
	elseif panel:GetDisabled() then
		drawVGUIRectAlt(self, 4, 1, 8, h + 1, true)
	else
		drawVGUIRect(self, 4, 1, 8, h + 1, changeOpacity(self))
	end
end

local function PaintNotches( x, y, w, h, num )
	if not num then return end
	local space = w / num

	if ( space < 2 ) then -- Ensure at least 1 px between each notch
		space = 2
		num = w / space
	end

	for i = 0, ceil( num ) do
		surface.DrawRect( x + i * space, y + 4, 1, 5 )
	end
end

function SKIN:PaintNumSlider( panel, w, h )
	drawVGUIRectAlt(self, 8, h / 2 - 1, w - 15, 4, true, self.Colours.SkinExclusive.SliderBackgroundInside)
	PaintNotches( 8, h / 2 - 1 + 4, w - 16, 1, panel:GetNotches() )
end



function SKIN:PaintProgress( panel, w, h )
	local progressStyle = self.SkinExclusive.ProgressbarStyle

	if progressStyle == "flat" then
		local p = 1
		local pa = p + 2
		surface.SetDrawColor(self.Colours.SkinExclusive.Progress)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(self.Colours.SkinExclusive.Background)
		surface.DrawRect(p, p, w - p * 2, h - p * 2)
		surface.SetDrawColor(self.Colours.SkinExclusive.Progress)
		surface.DrawRect(pa, pa, (w - pa * 2) * panel:GetFraction(), h - pa * 2)
	elseif progressStyle == "classic" then
		drawVGUIRectAlt(self, 0, 0, w, h, true, changeOpacity(self, self.Colours.SkinExclusive.BackgroundInside))
		surface.SetDrawColor(self.Colours.SkinExclusive.Progress2)
		if panel:GetFraction() < 0.01 then return end

		local p = 4
		local actualWidth = (w - p * 2) * panel:GetFraction()
		local segmentWidth = 8
		local progressPadding = p - 1
		local prog = p
		repeat
			surface.DrawRect(prog, p, segmentWidth, h - p * 2)
			prog = prog + segmentWidth + progressPadding
		until prog > actualWidth
	end
end



function SKIN:PaintCollapsibleCategory( panel, w, h )
	local headerHeight = panel:GetHeaderHeight()
	if h <= headerHeight then
		drawVGUIRect(self, 0, 0, w, h, changeOpacity(self))

		-- Little hack, draw the ComboBox's dropdown arrow to tell the player the category is collapsed and not empty
		if not panel:GetExpanded() then
			self.tex.Input.ComboBox.Button.Normal(w - 18, h / 2 - 8 + 1, 15, 15, self.Colours.Category.Header_Closed)
		end
	else
		drawVGUIRect(self, 0, 0, w, headerHeight, changeOpacity(self))
	end
end

function SKIN:PaintCategoryList( panel, w, h )
	if panel:GetName() == "DForm" and self.SkinExclusive.ReplaceCustomBackground then
		drawVGUIRectAlt(self, 0, 0, w, h, true, self.Colours.SkinExclusive.BackgroundInside)
	else
		drawVGUIRectAlt(self, 0, 0, w, h, true, panel:GetBackgroundColor())
	end
end

function SKIN:PaintCategoryButton( panel, w, h )
	if panel.AltLine then
		if panel.Depressed or panel.m_bSelected then
			surface.SetDrawColor( self.Colours.Category.LineAlt.Button_Selected )
		elseif panel.Hovered then
			surface.SetDrawColor( self.Colours.Category.LineAlt.Button_Hover )
		else
			surface.SetDrawColor( self.Colours.Category.LineAlt.Button )
		end
	else
		if panel.Depressed or panel.m_bSelected then
			surface.SetDrawColor( self.Colours.Category.Line.Button_Selected )
		elseif panel.Hovered then
			surface.SetDrawColor( self.Colours.Category.Line.Button_Hover )
		else
			surface.SetDrawColor( self.Colours.Category.Line.Button )
		end
	end
	surface.DrawRect( 0, 0, w, h )
end

function SKIN:PaintListViewLine( panel, w, h )
	if panel:IsSelected() then
		surface.SetDrawColor(self.Colours.ListBox.Selected)
		surface.DrawRect(0, 0, w, h)
	elseif panel.Hovered and panel.m_bAlt then
		surface.SetDrawColor(self.Colours.ListBox.EvenHovered)
		surface.DrawRect(0, 0, w, h)
	elseif panel.Hovered then
		surface.SetDrawColor(self.Colours.ListBox.OddHovered)
		surface.DrawRect(0, 0, w, h)
	elseif panel.m_bAlt then
		surface.SetDrawColor(self.Colours.ListBox.EvenLine)
		surface.DrawRect(0, 0, w, h)
	else
		surface.SetDrawColor(self.Colours.ListBox.OddLine)
		surface.DrawRect(0, 0, w, h)
	end
end

function SKIN:PaintListView( panel, w, h )
	if not panel.m_bBackground then return end

	drawVGUIRectAlt(self, 0, 0, w, h, true, self.Colours.SkinExclusive.BackgroundInside)
end



function SKIN:PaintTooltip( panel, w, h )
	drawBlur(self, panel, w, h)
	drawVGUIRect(self, 0, 0, w, h)
end

function SKIN:PaintMenuBar( panel, w, h )
	if stringToBoolean(self.SkinExclusive.MenuBar) then
		drawBlur(self, panel, w, h)
		surface.SetDrawColor(self.Colours.SkinExclusive.Background)
		surface.DrawRect(0, 0, w, h)
	end
end

derma.DefineSkin(ARG.name or "SPeditor.steam2004", "Steam 2004", SKIN)