-- Vanilla UI — "Vanilla UI+ Derma Skin" by Qude
-- (https://steamcommunity.com/sharedfiles/filedetails/?id=3818111525).
-- Adapted for SPeditor: the skin is registered under its own name and is active only
-- inside the editor. Left out of the original: its console variables and settings panel, the
-- spawn menu / context menu / tool HUD / world tip / notice restyling, the replacement of
-- surface.PlaySound and derma.GetDefaultSkin. The accent follows Interface settings
-- (gmfm_ui_accent), animations follow gmfm_ui_anim, click sounds gmfm_ui_sounds.
-- Two variants: the navy original and pure black (SPeditor.SkinArg.variant = "black").
-- Added: SKIN.SPeditor — how the editor's own windows, tabs, menu bar and status bar look.
local ARG = SPeditor.SkinArg or {}
local SKIN_NAME = ARG.name or "SPeditor.vanillaui"
local TINT = ( ARG.variant == "black" ) and 1 or 0

local function Step( speed )
	if ( GetConVarNumber( "gmfm_ui_anim" ) == 0 ) then return 1 end
	return math.min( FrameTime() * speed, 1 )
end

local function C( r, g, b, a ) return Color( r, g, b, a or 255 ) end

local P = {
	text       = C( 255, 255, 255 ),
	textDim    = C( 220, 235, 255, 210 ),
	textMuted  = C( 160, 180, 210, 190 ),
	textOff    = C( 255, 255, 255,  70 ),
	panel      = C(   7,   8,  11, 214 ),
	panelLite  = C(  12,  14,  22, 158 ),
	panelSolid = C(  10,  12,  20, 246 ),
	row        = C( 255, 255, 255,  10 ),
	btnNormal  = C(  22,  24,  32, 205 ),
	btnDisabled= C(  18,  20,  28, 120 ),
	tabBG      = C(  12,  14,  22, 235 ),
	tabTop     = C(  20,  24,  33, 248 ),
	tip        = C(   7,   8,  11, 240 ),
	border     = C( 255, 255, 255,  22 ),
	borderSoft = C( 255, 255, 255,  12 ),
	scroll     = C( 255, 255, 255,  40 ),

	blue       = C(  35, 135, 237 ),
	blueText   = C( 126, 200, 255 ),
	blueBorder = C(  35, 135, 237, 217 ),
	blueDim    = C(  35, 135, 237, 140 ),
	blueHover  = C(  35, 135, 237,  82 ),
	blueActive = C(  35, 135, 237, 120 ),
	btnHover   = C(  35, 135, 237,  78 ),
	btnDown    = C(  35, 135, 237, 120 ),
	green      = C(  60, 200, 140 ),
	greenText  = C( 125, 232, 160 ),
	greenBorder= C(  60, 200, 140, 120 ),
	greenHover = C(  60, 200, 140,  64 ),
	greenActive= C(  60, 200, 140, 115 ),
	greenSoft  = C(  60, 200, 140,  38 ),
}

local SURFACES = {
	[ 0 ] = { panel = { 7, 8, 11 }, lite = { 12, 14, 22 }, solid = { 10, 12, 20 }, btn = { 22, 24, 32 }, btnOff = { 18, 20, 28 }, tab = { 12, 14, 22 }, tabTop = { 20, 24, 33 }, tip = { 7, 8, 11 } },
	[ 1 ] = { panel = { 0, 0, 0 },  lite = { 10, 10, 10 }, solid = { 8, 8, 8 },    btn = { 20, 20, 20 }, btnOff = { 14, 14, 14 }, tab = { 8, 8, 8 },    tabTop = { 24, 24, 24 }, tip = { 0, 0, 0 } },
}

local function setC( col, r, g, b, a )
	col.r, col.g, col.b = r, g, b
	if ( a ) then col.a = a end
end

local function MixWhite( r, g, b, f )
	return math.floor( r + ( 255 - r ) * f ),
	       math.floor( g + ( 255 - g ) * f ),
	       math.floor( b + ( 255 - b ) * f )
end

local function RebuildPalette()
	local acc = SPeditor.UI.AccentOverride and SPeditor.UI.AccentOverride()
	local r,  g,  b  = 35, 135, 237
	if ( acc ) then r, g, b = acc.r, acc.g, acc.b end
	local r2, g2, b2 = 60, 200, 140
	setC( P.blue,       r, g, b, 255 )
	setC( P.blueBorder, r, g, b, 217 )
	setC( P.blueDim,    r, g, b, 140 )
	setC( P.blueHover,  r, g, b,  82 )
	setC( P.blueActive, r, g, b, 120 )
	setC( P.btnHover,   r, g, b,  78 )
	setC( P.btnDown,    r, g, b, 120 )
	local br, bg, bb = MixWhite( r, g, b, 0.45 )
	setC( P.blueText, br, bg, bb, 255 )

	setC( P.green,       r2, g2, b2, 255 )
	setC( P.greenBorder, r2, g2, b2, 120 )
	setC( P.greenHover,  r2, g2, b2,  64 )
	setC( P.greenActive, r2, g2, b2, 115 )
	setC( P.greenSoft,   r2, g2, b2,  38 )
	local lr, lg, lb = MixWhite( r2, g2, b2, 0.35 )
	setC( P.greenText, lr, lg, lb, 255 )

	-- in the editor the panels lie over other windows, not over the game: a little denser
	local op    = 0.92
	local s     = SURFACES[ TINT ]
	local glass = false
	local function Surface( col, rgb, solidA, glassK )
		setC( col, rgb[ 1 ], rgb[ 2 ], rgb[ 3 ], glass and math.floor( 255 * op * glassK ) or solidA )
	end
	setC( P.panel,     s.panel[ 1 ], s.panel[ 2 ], s.panel[ 3 ], math.floor( 255 * op ) )
	setC( P.panelLite, s.lite[ 1 ],  s.lite[ 2 ],  s.lite[ 3 ],  math.floor( 255 * op * 0.74 ) )
	Surface( P.panelSolid,  s.solid,  246, 0.92 )
	Surface( P.btnNormal,   s.btn,    205, 0.85 )
	Surface( P.btnDisabled, s.btnOff, 120, 0.50 )
	Surface( P.tabBG,       s.tab,    235, 0.95 )
	Surface( P.tabTop,      s.tabTop, 248, 1.00 )
	Surface( P.tip,         s.tip,    240, 1.00 )
end

RebuildPalette()

local function Fill( x, y, w, h, c )
	surface.SetDrawColor( c.r, c.g, c.b, c.a )
	surface.DrawRect( x, y, w, h )
end

local ARC_CACHE = {}
local function ArcPixels( r )
	local list = ARC_CACHE[ r ]
	if ( list ) then return list end
	list = {}
	local n = 8
	for py = 0, r - 1 do
		for px = 0, r - 1 do
			local hit = 0
			for sy = 0, n - 1 do
				for sx = 0, n - 1 do
					local dx = r - ( px + ( sx + 0.5 ) / n )
					local dy = r - ( py + ( sy + 0.5 ) / n )
					local d = math.sqrt( dx * dx + dy * dy )
					if ( d <= r and d > r - 1 ) then hit = hit + 1 end
				end
			end
			local cov = hit / ( n * n )
			if ( cov >= 0.03 ) then list[ #list + 1 ] = { px, py, cov } end
		end
	end
	ARC_CACHE[ r ] = list
	return list
end

local function BorderEdges( x, y, w, h, r, c )
	r = math.min( r, math.floor( w / 2 ), math.floor( h / 2 ) )
	surface.SetDrawColor( c.r, c.g, c.b, c.a )
	surface.DrawRect( x + r, y, w - r * 2, 1 )
	surface.DrawRect( x + r, y + h - 1, w - r * 2, 1 )
	surface.DrawRect( x, y + r, 1, h - r * 2 )
	surface.DrawRect( x + w - 1, y + r, 1, h - r * 2 )
	if ( r <= 0 ) then return end
	local rx, by = x + w - 1, y + h - 1
	for _, p in ipairs( ArcPixels( r ) ) do
		local px, py = p[ 1 ], p[ 2 ]
		surface.SetDrawColor( c.r, c.g, c.b, c.a * p[ 3 ] )
		surface.DrawRect( x + px, y + py, 1, 1 )
		surface.DrawRect( rx - px, y + py, 1, 1 )
		surface.DrawRect( x + px, by - py, 1, 1 )
		surface.DrawRect( rx - px, by - py, 1, 1 )
	end
end

local function Outline( w, h, c )
	BorderEdges( 0, 0, w, h, 4, c )
end

local function Anim( panel, key, target, speed )
	key = "VUIPLUS_a_" .. key
	local cur = panel[ key ] or 0
	cur = Lerp( Step( speed or 14 ), cur, target )
	panel[ key ] = cur
	return cur
end

local function Alpha( c, frac )
	return Color( c.r, c.g, c.b, math.Clamp( math.floor( c.a * frac ), 0, 255 ) )
end

local function TextShift( panel, amount )
	if ( not ( panel.GetTextInset and panel.SetTextInset ) ) then return end
	if ( panel.VUIPLUS_tiX == nil ) then
		local x, y = panel:GetTextInset()
		panel.VUIPLUS_tiX, panel.VUIPLUS_tiY = x or 0, y or 0
	end
	local want = panel.VUIPLUS_tiX + math.Round( amount )
	if ( panel:GetTextInset() ~= want ) then
		panel:SetTextInset( want, panel.VUIPLUS_tiY )
	end
end

local function ThickLine( x1, y1, x2, y2, th, c )
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt( dx * dx + dy * dy )
	if ( len < 0.5 ) then return end
	local nx, ny = -dy / len * th * 0.5, dx / len * th * 0.5
	draw.NoTexture()
	surface.SetDrawColor( c.r, c.g, c.b, c.a )
	surface.DrawPoly( { { x = x1 + nx, y = y1 + ny }, { x = x2 + nx, y = y2 + ny }, { x = x2 - nx, y = y2 - ny }, { x = x1 - nx, y = y1 - ny } } )
	surface.DrawPoly( { { x = x1 - nx, y = y1 - ny }, { x = x2 - nx, y = y2 - ny }, { x = x2 + nx, y = y2 + ny }, { x = x1 + nx, y = y1 + ny } } )
end

local function XMark( cx, cy, s, th, c )
	ThickLine( cx - s, cy - s, cx + s, cy + s, th, c )
	ThickLine( cx - s, cy + s, cx + s, cy - s, th, c )
end

local function CheckMark( cx, cy, s, c )
	local th = math.max( 2, s * 0.5 )
	ThickLine( cx - s * 0.9, cy + s * 0.05, cx - s * 0.2, cy + s * 0.7, th, c )
	ThickLine( cx - s * 0.2, cy + s * 0.7, cx + s * 0.95, cy - s * 0.6, th, c )
end

local function Triangle( cx, cy, s, dir, c )
	draw.NoTexture()
	surface.SetDrawColor( c.r, c.g, c.b, c.a )
	if ( dir > 0 ) then
		surface.DrawPoly( { { x = cx, y = cy - s }, { x = cx + s, y = cy + s }, { x = cx - s, y = cy + s } } )
	else
		surface.DrawPoly( { { x = cx - s, y = cy - s }, { x = cx + s, y = cy - s }, { x = cx, y = cy + s } } )
	end
end

local function TriangleH( cx, cy, s, dir, c )
	draw.NoTexture()
	surface.SetDrawColor( c.r, c.g, c.b, c.a )
	if ( dir > 0 ) then
		surface.DrawPoly( { { x = cx - s, y = cy - s }, { x = cx + s, y = cy }, { x = cx - s, y = cy + s } } )
	else
		surface.DrawPoly( { { x = cx + s, y = cy - s }, { x = cx + s, y = cy + s }, { x = cx - s, y = cy } } )
	end
end
local function Circle( cx, cy, r, c )
	local segs = 26
	local poly = {}
	for i = 0, segs do
		local a = math.rad( ( i / segs ) * 360 )
		poly[ i + 1 ] = { x = cx + math.cos( a ) * r, y = cy + math.sin( a ) * r }
	end
	draw.NoTexture()
	surface.SetDrawColor( c.r, c.g, c.b, c.a )
	surface.DrawPoly( poly )
end

local function CheckBoxPaint( panel, w, h )
	local on = panel.GetChecked and panel:GetChecked()
	local enabled = ( not panel.IsEnabled ) or panel:IsEnabled()
	local hovered = panel.Hovered or ( panel.IsHovered and panel:IsHovered() )
	local a = Anim( panel, "chk", on and 1 or 0, 18 )

	draw.RoundedBox( 4, 0, 0, w, h, P.panelSolid )
	if ( a > 0.01 ) then
		draw.RoundedBox( 4, 0, 0, w, h, Alpha( P.green, a * ( enabled and 1 or 0.45 ) ) )
	end

	local border = Color( 255, 255, 255, 60 )
	if ( not enabled ) then border = Color( 255, 255, 255, 25 )
	elseif ( hovered and not on ) then border = P.blueBorder end
	Outline( w, h, border )

	if ( a > 0.3 ) then
		local s = math.min( w, h ) * 0.3
		local ca = math.floor( 255 * math.min( 1, ( a - 0.3 ) / 0.6 ) )
		CheckMark( w * 0.5, h * 0.46, s, Color( 255, 255, 255, ca ) )
	end
end

local SKIN = {}
SKIN.PrintName = "Vanilla UI+ Derma Skin"
SKIN.Author    = "Vanilla UI+"

SKIN.colTooltipText            = P.text
SKIN.colTextEntryText          = P.text
SKIN.colTextEntryTextHighlight = P.blueActive
SKIN.colTextEntryTextCursor    = P.blue

-- click sounds of the original (the GMod main menu sounds); hover sounds are left out —
-- in the editor the cursor crosses dozens of buttons
-- (a sound of one's own from Interface settings replaces them: UI.UISound, cl_ui_soundpick.lua)
local SND = { accept = "garrysmod/ui_click.wav", back = "garrysmod/ui_return.wav" }
SKIN.SPeditorSounds = true

local function UISound( kind )
	if ( kind == "focus" ) then return end
	if ( SPeditor.UI.UISound ) then return SPeditor.UI.UISound( kind, SND[ kind ] or SND.accept ) end
	if ( GetConVarNumber( "gmfm_ui_sounds" ) == 0 ) then return end
	surface.PlaySound( SND[ kind ] or SND.accept )
end

local function UIEdges( panel, click, noHover )
	local off = ( panel.GetDisabled and panel:GetDisabled() ) or ( panel.IsEnabled and not panel:IsEnabled() )
	if ( not noHover ) then
		local hov = ( not off ) and panel:IsHovered() or false
		if ( hov and not panel.VUIPLUS_sndH and not input.IsMouseDown( MOUSE_LEFT ) ) then UISound( "focus" ) end
		panel.VUIPLUS_sndH = hov
	end
	if ( not click ) then return end
	local down = ( not off ) and panel.Depressed and true or false
	if ( down and not panel.VUIPLUS_sndD ) then UISound( click ) end
	panel.VUIPLUS_sndD = down
end

local FRAME_BORDER  = Color( 255, 255, 255, 26 )
local FRAME_DIVIDER = Color( 255, 255, 255, 18 )

function SKIN:PaintFrame( panel, w, h )
	draw.RoundedBox( 8, 0, 0, w, h, P.panel )
	BorderEdges( 0, 0, w, h, 8, FRAME_BORDER )
	local titled = ( isfunction( panel.GetTitle ) and panel:GetTitle() ~= "" ) or ( IsValid( panel.btnClose ) and panel.btnClose:IsVisible() )
	if ( titled ) then Fill( 1, 24, w - 2, 1, FRAME_DIVIDER ) end
end

function SKIN:PaintWindowCloseButton( panel, w, h )
	if ( panel.m_bBackground == false ) then return end
	UIEdges( panel, "back" )
	local on  = panel:IsEnabled()
	local hov = panel.Hovered and on
	draw.RoundedBox( 4, 2, 3, w - 4, h - 6, hov and Color( 200, 60, 60, 235 ) or Color( 255, 255, 255, on and 16 or 8 ) )
	XMark( w * 0.5, h * 0.5, 3.5, 2, on and ( hov and P.text or P.textDim ) or P.textOff )
end

function SKIN:PaintWindowMinimizeButton( panel, w, h )
	if ( panel.m_bBackground == false ) then return end
	local on  = panel:IsEnabled()
	local hov = panel.Hovered and on
	draw.RoundedBox( 4, 2, 3, w - 4, h - 6, hov and P.btnHover or Color( 255, 255, 255, on and 16 or 8 ) )
	Fill( w * 0.5 - 4, h * 0.5 + 2, 8, 2, on and ( hov and P.text or P.textDim ) or P.textOff )
end

function SKIN:PaintWindowMaximizeButton( panel, w, h )
	if ( panel.m_bBackground == false ) then return end
	local on  = panel:IsEnabled()
	local hov = panel.Hovered and on
	draw.RoundedBox( 4, 2, 3, w - 4, h - 6, hov and P.btnHover or Color( 255, 255, 255, on and 16 or 8 ) )
	local c = on and ( hov and P.text or P.textDim ) or P.textOff
	surface.SetDrawColor( c.r, c.g, c.b, c.a )
	surface.DrawOutlinedRect( w * 0.5 - 4, h * 0.5 - 4, 8, 8 )
end

function SKIN:PaintMenuBar( panel, w, h )
	Fill( 0, 0, w, h, P.panelSolid )
	Fill( 0, h - 1, w, 1, P.border )
end

function SKIN:PaintPanel( panel, w, h )
	if ( panel.GetPaintBackground and not panel:GetPaintBackground() ) then return end
	draw.RoundedBox( 4, 0, 0, w, h, P.panelLite )
end

function SKIN:PaintListBox( panel, w, h )
	draw.RoundedBox( 4, 0, 0, w, h, P.panelLite )
end

local TAB_STEP, TAB_GAP, TAB_R        = 8, 6, 8
local TAB_PADX, TAB_ICONGAP, TAB_PADR = 12, 7, 14
-- the compact size of the original (editor sheets are small)
local TAB_H, TAB_TEXTY                = 34, 6

local function Mix( a, b, t, alpha )
	return Color( Lerp( t, a.r, b.r ), Lerp( t, a.g, b.g ), Lerp( t, a.b, b.b ), alpha or Lerp( t, a.a, b.a ) )
end

function SKIN:PaintPropertySheet( panel, w, h )
	local ts = panel.tabScroller
	if ( IsValid( ts ) and not panel.VUIPLUS_TabsSet ) then
		panel.VUIPLUS_TabsSet = true
		if ( isfunction( ts.SetOverlap ) ) then ts:SetOverlap( -TAB_GAP ) end
		if ( isfunction( ts.DockMargin ) ) then ts:DockMargin( 8, 0, 8, 0 ) end

		local oPL = panel.PerformLayout
		panel.PerformLayout = function( s, ... )
			local top = TAB_H + ( isfunction( s.GetPadding ) and s:GetPadding() or 8 )
			if ( istable( s.Items ) ) then
				for _, v in pairs( s.Items ) do
					local p = v.Panel
					if ( IsValid( p ) and not p.NoStretchY ) then
						local x, y = p:GetPos()
						if ( y ~= top ) then p:SetPos( x, top ) end
					end
				end
			end
			if ( isfunction( oPL ) ) then return oPL( s, ... ) end
		end

		ts:InvalidateLayout( true )
		panel:InvalidateLayout( true )
	end

	local off = 0
	local tab = isfunction( panel.GetActiveTab ) and panel:GetActiveTab()
	if ( IsValid( tab ) ) then off = math.max( 0, tab:GetTall() - TAB_STEP ) end
	local bh = h - off
	if ( bh < 4 ) then return end

	draw.RoundedBox( TAB_R, 0, off, w, bh, P.panel )
	BorderEdges( 0, off, w, bh, TAB_R, FRAME_BORDER )
end

local function SetupTab( panel )
	if ( panel.VUIPLUS_Sized ) then return end
	panel.VUIPLUS_Sized = true

	local oPL = panel.PerformLayout

	panel.GetTabHeight = function() return TAB_H end

	panel.ApplySchemeSettings = function( s )
		local inset = TAB_PADX
		if ( IsValid( s.Image ) ) then inset = TAB_PADX + s.Image:GetWide() + TAB_ICONGAP end
		s:SetTextInset( inset, TAB_TEXTY )
		local cw = s:GetContentSize()
		local tw = cw + TAB_PADR
		if ( s:GetWide() ~= tw or s:GetTall() ~= TAB_H ) then s:SetSize( tw, TAB_H ) end
		if ( istable( DLabel ) and isfunction( DLabel.ApplySchemeSettings ) ) then DLabel.ApplySchemeSettings( s ) end
	end

	panel.PerformLayout = function( s )
		if ( isfunction( oPL ) ) then oPL( s ) end
		if ( IsValid( s.Image ) ) then
			local ih = s.Image:GetTall()
			s.Image:SetPos( TAB_PADX, math.floor( ( TAB_H - TAB_STEP - ih ) * 0.5 ) )
		end
	end

	panel:InvalidateLayout( true )
end

function SKIN:PaintActiveTab( panel, w, h )
	local body = h - TAB_STEP
	local fill = Mix( P.tabTop, P.green, 0.10, P.tabTop.a )

	draw.RoundedBoxEx( TAB_R, 0, 0, w, body, fill, true, true, false, false )
	Fill( 0, body - 2, w, 2, P.green )
end

function SKIN:PaintTab( panel, w, h )
	SetupTab( panel )
	if ( panel.IsActive and panel:IsActive() ) then return self:PaintActiveTab( panel, w, h ) end
	UIEdges( panel, "accept" )

	local e  = Anim( panel, "tab", ( panel.IsHovered and panel:IsHovered() ) and 1 or 0 )
	local y  = 3
	local bh = h - TAB_STEP - y

	draw.RoundedBoxEx( TAB_R, 0, y, w, bh, P.tabBG, true, true, false, false )
	if ( e > 0.01 ) then
		draw.RoundedBoxEx( TAB_R, 0, y, w, bh, Alpha( P.blue, 0.20 * e ), true, true, false, false )
		local uw = math.floor( w * e )
		Fill( math.floor( ( w - uw ) * 0.5 ), y + bh - 2, uw, 2, Alpha( P.blue, e ) )
	end
end

function SKIN:PaintButton( panel, w, h )
	if ( panel.GetPaintBackground and not panel:GetPaintBackground() ) then return end
	UIEdges( panel, "accept" )

	if ( panel:GetDisabled() ) then
		draw.RoundedBox( 4, 0, 0, w, h, P.btnDisabled )
		Outline( w, h, P.borderSoft )
		return
	end

	draw.RoundedBox( 4, 0, 0, w, h, P.btnNormal )

	local hov = Anim( panel, "btn", panel:IsHovered() and 1 or 0 )
	if ( panel.Depressed or ( panel.IsDown and panel:IsDown() ) ) then
		draw.RoundedBox( 4, 0, 0, w, h, P.btnDown )
	elseif ( hov > 0.01 ) then
		draw.RoundedBox( 4, 0, 0, w, h, Alpha( P.btnHover, hov ) )
	end

	Outline( w, h, P.borderSoft )
	if ( hov > 0.01 ) then Outline( w, h, Alpha( P.blueBorder, hov ) ) end
end

local function TextEntrySideIcons( panel )
	if ( panel.VUIPLUS_LangChecked ) then return end
	panel.VUIPLUS_LangChecked = true
	if ( not isfunction( panel.SetDrawLanguageIDAtLeft ) ) then return end
	for _, c in ipairs( panel:GetChildren() ) do
		if ( IsValid( c ) and c:GetDock() == RIGHT ) then
			panel:SetDrawLanguageIDAtLeft( true )
			return
		end
	end
end

function SKIN:PaintTextEntry( panel, w, h )
	TextEntrySideIcons( panel )
	if ( panel.m_bBackground ) then
		draw.RoundedBox( 4, 0, 0, w, h, P.panelSolid )
		Outline( w, h, panel:HasFocus() and P.blueBorder or P.border )
	end

	local ph = panel.GetPlaceholderText and panel:GetPlaceholderText()
	local txt = panel:GetText()
	if ( isstring( ph ) and ph:Trim() ~= "" and ( not txt or txt == "" ) ) then
		if ( ph:StartsWith( "#" ) ) then ph = ph:sub( 2 ) end
		panel:SetText( language.GetPhrase( ph ) )
		panel:DrawTextEntryText( P.textMuted, P.blueActive, P.blue )
		panel:SetText( txt or "" )
		return
	end

	panel:DrawTextEntryText( P.text, P.blueActive, P.blue )
end

function SKIN:PaintTree( panel, w, h )
	draw.RoundedBox( 4, 0, 0, w, h, P.panelLite )
end

function SKIN:PaintSelection( panel, w, h )
	draw.RoundedBox( 4, 0, 0, w, h, P.greenActive )
end

function SKIN:PaintTreeNodeButton( panel, w, h )
	UIEdges( panel, "accept" )
	local tw = 0
	if ( panel.GetTextSize ) then tw = select( 1, panel:GetTextSize() ) or 0 end
	local x = 38

	local selected = panel.m_bSelected and 1 or 0
	local sel = Anim( panel, "tnsel", selected )
	local hov = Anim( panel, "tnhov", ( panel.Hovered and selected == 0 ) and 1 or 0 )

	local vm = math.max( 1, math.floor( h * 0.16 ) )
	local bh = h - vm * 2

	if ( sel > 0.01 ) then
		draw.RoundedBox( 4, x, vm, tw + 8, bh, Alpha( P.greenActive, sel ) )
		Fill( x, ( h - bh * sel ) * 0.5, 3, bh * sel, Alpha( P.green, sel ) )
	end
	if ( hov > 0.01 ) then
		draw.RoundedBox( 4, x, vm, tw + 8, bh, Alpha( P.blueHover, hov ) )
		Fill( x, ( h - bh * hov ) * 0.5, 3, bh * hov, Alpha( P.blue, hov ) )
	end

	TextShift( panel, 5 * math.max( sel, hov ) )
end

function SKIN:PaintListViewLine( panel, w, h )
	local vm = math.max( 1, math.floor( h * 0.14 ) )
	if ( panel.IsSelected and panel:IsSelected() ) then
		draw.RoundedBox( 4, 1, vm, w - 2, h - vm * 2, P.greenActive )
	elseif ( panel.Hovered ) then
		draw.RoundedBox( 4, 1, vm, w - 2, h - vm * 2, P.blueHover )
	elseif ( panel.m_bAlt ) then
		Fill( 0, 0, w, h, P.row )
	end
end

function SKIN:PaintListView( panel, w, h )
	if ( not panel.m_bBackground ) then return end
	draw.RoundedBox( 4, 0, 0, w, h, P.panelLite )
end

function SKIN:PaintCategoryList( panel, w, h )
	draw.RoundedBox( 4, 0, 0, w, h, P.panelLite )
end

function SKIN:PaintCollapsibleCategory( panel, w, h )
	local hh = ( panel.GetHeaderHeight and panel:GetHeaderHeight() ) or 20
	if ( h <= hh ) then
		draw.RoundedBox( 4, 0, 0, w, h, P.panelSolid )
		Fill( 0, 0, 2, h, P.blue )
		return
	end
	draw.RoundedBoxEx( 4, 0, 0, w, hh, P.panelSolid, true, true, false, false )
	Fill( 0, 0, 2, hh, P.blue )
	draw.RoundedBoxEx( 4, 0, hh, w, h - hh, P.panelLite, false, false, true, true )
end

function SKIN:PaintCategoryButton( panel, w, h )
	UIEdges( panel, "accept" )
	local selected = ( panel.Depressed or panel.m_bSelected ) and 1 or 0
	local sel = Anim( panel, "cbsel", selected )
	local hov = Anim( panel, "cbhov", ( panel.Hovered and selected == 0 ) and 1 or 0 )

	local vm = math.max( 1, math.floor( h * 0.16 ) )
	local bh = h - vm * 2

	if ( sel > 0.01 ) then
		draw.RoundedBox( 4, 0, vm, w, bh, Alpha( P.greenActive, sel ) )
		Fill( 0, ( h - bh * sel ) * 0.5, 3, bh * sel, Alpha( P.green, sel ) )
	end
	if ( hov > 0.01 ) then
		draw.RoundedBox( 4, 0, vm, w, bh, Alpha( P.blueHover, hov ) )
		Fill( 0, ( h - bh * hov ) * 0.5, 3, bh * hov, Alpha( P.blue, hov ) )
	end

	TextShift( panel, 6 * math.max( sel, hov ) )
end

function SKIN:PaintComboBox( panel, w, h )
	UIEdges( panel, "accept" )
	local open = panel.IsMenuOpen and panel:IsMenuOpen()
	local hov = Anim( panel, "cmb", ( panel:IsHovered() or open ) and 1 or 0 )
	draw.RoundedBox( 4, 0, 0, w, h, P.panelSolid )
	if ( hov > 0.01 ) then draw.RoundedBox( 4, 0, 0, w, h, Alpha( P.blueHover, hov * 0.6 ) ) end
	Outline( w, h, P.border )
	if ( hov > 0.01 ) then Outline( w, h, Alpha( P.blueBorder, hov ) ) end
end

function SKIN:PaintComboDownArrow( panel, w, h )
	Triangle( w * 0.5, h * 0.5 + 1, 3, -1, P.textDim )
end

function SKIN:PaintMenu( panel, w, h )
	draw.RoundedBox( 4, 0, 0, w, h, P.panelSolid )
	Outline( w, h, P.border )
end

function SKIN:PaintMenuOption( panel, w, h )
	UIEdges( panel, "accept" )
	local on = ( panel.m_bBackground and ( panel.Hovered or panel.Highlight ) ) and 1 or 0
	local hov = Anim( panel, "mo", on, 18 )
	if ( hov > 0.01 ) then
		draw.RoundedBox( 4, 2, 0, w - 4, h, Alpha( P.blueHover, hov ) )
		Fill( 2, ( h - h * hov ) * 0.5, 3, h * hov, Alpha( P.blue, hov ) )
	end
	if ( panel.GetChecked and panel:GetChecked() ) then Fill( 0, 0, 2, h, P.green ) end
end

function SKIN:PaintMenuSpacer( panel, w, h )
	Fill( 6, h * 0.5, w - 12, 1, P.border )
end

function SKIN:PaintCheckBox( panel, w, h )
	UIEdges( panel, ( panel.GetChecked and panel:GetChecked() ) and "back" or "accept", true )
	CheckBoxPaint( panel, w, h )
end

function SKIN:PaintNumSlider( panel, w, h )
	local y = math.floor( h * 0.5 ) - 1
	Fill( 8, y, w - 16, 2, Color( 255, 255, 255, 28 ) )
	local sl = panel.Slider or panel
	local frac = 0
	if ( sl.GetSlideX ) then frac = math.Clamp( sl:GetSlideX() or 0, 0, 1 ) end
	if ( frac > 0 ) then Fill( 8, y, math.floor( ( w - 16 ) * frac ), 2, P.blueDim ) end
end

function SKIN:PaintSliderKnob( panel, w, h )
	local enabled = ( not panel.IsEnabled ) or panel:IsEnabled()
	local hov = Anim( panel, "knob", ( enabled and ( panel.Hovered or panel.Depressed ) ) and 1 or 0 )
	local cx, cy = w * 0.5, h * 0.5
	local r = math.min( w, h ) * 0.5 - 1
	Circle( cx, cy, r, Color( 255, 255, 255, 45 + math.floor( 95 * hov ) ) )
	Circle( cx, cy, r - 1.5, enabled and P.blue or Color( 90, 100, 120, 200 ) )
	if ( panel.Depressed ) then Circle( cx, cy, r * 0.35, Color( 255, 255, 255, 230 ) ) end
end

function SKIN:PaintExpandButton( panel, w, h )
	local hov = panel.Hovered
	draw.RoundedBox( 4, 0, 0, w, h, hov and Alpha( P.blueHover, 1 ) or P.btnNormal )
	Outline( w, h, P.borderSoft )
	local c = hov and P.text or P.textDim
	local cx, cy = math.floor( w * 0.5 ), math.floor( h * 0.5 )
	Fill( cx - 3, cy, 7, 1, c )
	if ( not ( panel.GetExpanded and panel:GetExpanded() ) ) then
		Fill( cx, cy - 3, 1, 7, c )
	end
end

function SKIN:PaintVScrollBar( panel, w, h )
	draw.RoundedBox( 2, w * 0.5 - 2, 0, 4, h, Color( 255, 255, 255, 10 ) )
end

function SKIN:PaintScrollBarGrip( panel, w, h )
	local col = Alpha( P.blue, 0.45 )
	if ( not panel:IsEnabled() ) then col = Color( 255, 255, 255, 18 )
	elseif ( panel.Depressed ) then col = P.green
	elseif ( panel.Hovered ) then col = Alpha( P.blue, 0.80 ) end
	draw.RoundedBox( 4, 2, 1, w - 4, h - 2, col )
end

local function ArrowColour( panel )
	local on = panel:IsEnabled()
	local c = ( on and panel.Depressed ) and P.green or P.blueText
	local a = on and ( ( panel.Depressed or panel.Hovered ) and 255 or 150 ) or 60
	return Color( c.r, c.g, c.b, a )
end

function SKIN:PaintButtonUp( panel, w, h )
	if ( panel.m_bBackground == false ) then return end
	Triangle( w * 0.5, h * 0.5 - 1, 4, 1, ArrowColour( panel ) )
end

function SKIN:PaintButtonDown( panel, w, h )
	if ( panel.m_bBackground == false ) then return end
	Triangle( w * 0.5, h * 0.5 + 1, 4, -1, ArrowColour( panel ) )
end

function SKIN:PaintProgress( panel, w, h )
	local frac = 0
	if ( panel.GetFraction ) then frac = math.Clamp( panel:GetFraction() or 0, 0, 1 ) end
	panel.VUIPLUS_pf = Lerp( Step( 9 ), panel.VUIPLUS_pf or frac, frac )
	local shown = panel.VUIPLUS_pf

	local bh = math.min( h, 8 )
	local y  = math.floor( ( h - bh ) * 0.5 )
	local r  = math.floor( bh * 0.5 )

	draw.RoundedBox( r + 1, 0, y - 1, w, bh + 2, Alpha( P.blue, 0.20 ) )
	draw.RoundedBox( r, 1, y, w - 2, bh, Color( 255, 255, 255, 18 ) )

	local fw = math.floor( ( w - 4 ) * shown )
	if ( fw < 1 ) then return end
	fw = math.max( fw, bh - 2 )

	for i = 3, 1, -1 do
		local g = i
		draw.RoundedBox( r + g, 2 - g, y + 1 - g, fw + g * 2, bh - 2 + g * 2, Alpha( P.blue, 0.035 ) )
	end
	draw.RoundedBox( r, 2, y + 1, fw, bh - 2, Alpha( P.blue, 0.95 ) )
end

function SKIN:PaintMenuRightArrow( panel, w, h )
	TriangleH( w * 0.5 + 1, h * 0.5, 3, 1, panel.Hovered and P.text or P.textDim )
end

function SKIN:PaintNumberUp( panel, w, h )
	if ( panel.m_bBackground == false ) then return end
	local a = panel:IsEnabled() and ( panel.Hovered and 255 or 150 ) or 60
	Triangle( w * 0.5, h * 0.5, 3, 1, Color( P.blueText.r, P.blueText.g, P.blueText.b, a ) )
end

function SKIN:PaintNumberDown( panel, w, h )
	if ( panel.m_bBackground == false ) then return end
	local a = panel:IsEnabled() and ( panel.Hovered and 255 or 150 ) or 60
	Triangle( w * 0.5, h * 0.5, 3, -1, Color( P.blueText.r, P.blueText.g, P.blueText.b, a ) )
end

function SKIN:PaintHScrollBar( panel, w, h )
	draw.RoundedBox( 2, 0, h * 0.5 - 2, w, 4, Color( 255, 255, 255, 10 ) )
end

function SKIN:PaintButtonLeft( panel, w, h )
	if ( panel.m_bBackground == false ) then return end
	draw.RoundedBox( 4, 0, 0, w, h, P.panelSolid )
	Outline( w, h, panel.Depressed and P.green or ( panel.Hovered and P.blueBorder or P.borderSoft ) )
	TriangleH( w * 0.5 - 1, h * 0.5, 4, -1, ArrowColour( panel ) )
end

function SKIN:PaintButtonRight( panel, w, h )
	if ( panel.m_bBackground == false ) then return end
	draw.RoundedBox( 4, 0, 0, w, h, P.panelSolid )
	Outline( w, h, panel.Depressed and P.green or ( panel.Hovered and P.blueBorder or P.borderSoft ) )
	TriangleH( w * 0.5 + 1, h * 0.5, 4, 1, ArrowColour( panel ) )
end

function SKIN:PaintRadioButton( panel, w, h )
	UIEdges( panel, "accept", true )
	local cx, cy = w * 0.5, h * 0.5
	local r = math.min( w, h ) * 0.5
	local enabled = ( not panel.IsEnabled ) or panel:IsEnabled()
	local hovered = panel.Hovered or ( panel.IsHovered and panel:IsHovered() )

	local ring = Color( 255, 255, 255, 60 )
	if ( not enabled ) then ring = Color( 255, 255, 255, 25 )
	elseif ( hovered ) then ring = P.blueBorder end
	Circle( cx, cy, r, ring )
	Circle( cx, cy, r - 1, P.panelSolid )
	if ( panel.GetChecked and panel:GetChecked() ) then
		Circle( cx, cy, math.max( 2, r * 0.45 ), enabled and P.green or Alpha( P.green, 0.4 ) )
	end
end

function SKIN:PaintShadow( panel, w, h )
	draw.RoundedBox( 8, 2, 3, w, h, Color( 0, 0, 0, 60 ) )
end

function SKIN:PaintTreeNode( panel, w, h )
	if ( not isfunction( panel.GetShowLines ) or not panel:GetShowLines() ) then return end
	Fill( 9, 0, 1, h - 9, P.borderSoft )
end

function SKIN:PaintTooltip( panel, w, h )
	draw.RoundedBox( 8, 0, 0, w, h, P.tip )
	if ( h > 14 ) then Fill( 0, 6, 2, h - 12, P.blue ) end
end

---------------------------------------------------------------------------
-- SPeditor chrome (cl_ui_theme.lua, UI.PaintChrome)
---------------------------------------------------------------------------
SKIN.SPeditor = {
	TextColors = { MenuBar = P.text, StatusBar = P.text, StatusDim = P.textMuted },
}

function SKIN.SPeditor.Window( skin, win, w, h, info )
	local e, th = info.edge, info.tabH
	local r = info.tiled and 6 or 8
	draw.RoundedBox( r, 0, 0, w, h, P.panelSolid )
	BorderEdges( 0, 0, w, h, r, info.tiled and FRAME_BORDER or P.blueDim )
	if ( info.onTop ) then Fill( r, 1, w - r * 2, 2, P.green ) end

	for _, t in ipairs( info.tabs ) do
		local x, tw = t.x, t.w
		local y, bh = e + 1, th - 1
		if ( t.on ) then
			draw.RoundedBoxEx( 6, x, y, tw, bh, Mix( P.tabTop, P.green, 0.10, 255 ), true, true, false, false )
			Fill( x, y + bh - 2, tw, 2, P.green )
			SPeditor.UI.DrawTabLabel( t, y, bh - 1, P.text, 255 )
		else
			local hov = Anim( t.page, "wtab", t.hot and 1 or 0 )
			draw.RoundedBoxEx( 6, x, y, tw, bh, P.tabBG, true, true, false, false )
			if ( hov > 0.01 ) then
				draw.RoundedBoxEx( 6, x, y, tw, bh, Alpha( P.blue, 0.20 * hov ), true, true, false, false )
				local uw = math.floor( tw * hov )
				Fill( x + math.floor( ( tw - uw ) * 0.5 ), y + bh - 2, uw, 2, Alpha( P.blue, hov ) )
			end
			SPeditor.UI.DrawTabLabel( t, y, bh - 1, hov > 0.5 and P.text or P.textDim, 150 + math.floor( 105 * hov ) )
		end
	end
end

function SKIN.SPeditor.CloseButton( skin, b, w, h )
	skin:PaintWindowCloseButton( b, w, h )
end

function SKIN.SPeditor.MenuBar( skin, bar, w, h )
	Fill( 0, 0, w, h, P.panelSolid )
	Fill( 0, h - 1, w, 1, P.border )
end

function SKIN.SPeditor.MenuButton( skin, b, w, h )
	local hov = Anim( b, "mb", ( b:IsHovered() or b._menuOpen ) and 1 or 0, 18 )
	if ( hov <= 0.01 ) then return end
	draw.RoundedBox( 4, 1, 2, w - 2, h - 4, Alpha( P.blueHover, hov ) )
	local uw = math.floor( ( w - 8 ) * hov )
	Fill( math.floor( ( w - uw ) * 0.5 ), h - 4, uw, 2, Alpha( P.blue, hov ) )
end

function SKIN.SPeditor.StatusBar( skin, bar, w, h )
	Fill( 0, 0, w, h, P.panelSolid )
	Fill( 0, 0, w, 1, P.border )
end

-- the accent may change in Interface settings
SKIN.SPeditorRefresh = RebuildPalette

derma.DefineSkin( SKIN_NAME, "Vanilla UI", SKIN )

local function TintLeaves( tbl, col )
	if ( not istable( tbl ) ) then return end
	for k, v in pairs( tbl ) do
		if ( istable( v ) ) then
			if ( v.r and v.g and v.b ) then tbl[ k ] = col else TintLeaves( v, col ) end
		end
	end
end

local function BuildColours()
	-- the text colours are built on SPeditor's copy of the stock skin, not on the shared Default
	local def = SPeditor.UI.BaseSkin and SPeditor.UI.BaseSkin()
	if ( not def or not def.Colours ) then return false end

	local Col = table.Copy( def.Colours )
	if ( Col.Label ) then
		Col.Label.Default, Col.Label.Bright, Col.Label.Highlight = P.text, P.text, P.text
		Col.Label.Dark = P.textDim
	end
	if ( Col.Button ) then
		Col.Button.Normal, Col.Button.Hover, Col.Button.Down = P.text, P.text, P.text
		Col.Button.Disabled = P.textOff
	end
	if ( Col.Window ) then
		Col.Window.TitleActive   = P.text
		Col.Window.TitleInactive = P.textDim
	end
	if ( istable( Col.Tab ) ) then
		if ( istable( Col.Tab.Active ) ) then
			Col.Tab.Active.Normal   = P.text
			Col.Tab.Active.Hover    = P.text
			Col.Tab.Active.Down     = P.text
			Col.Tab.Active.Disabled = P.textOff
		end
		if ( istable( Col.Tab.Inactive ) ) then
			Col.Tab.Inactive.Normal   = Color( 170, 190, 225, 166 )
			Col.Tab.Inactive.Hover    = P.text
			Col.Tab.Inactive.Down     = P.text
			Col.Tab.Inactive.Disabled = P.textOff
		end
	end
	TintLeaves( Col.Tree, P.textDim )
	if ( Col.Category ) then
		if ( Col.Category.Header )        then Col.Category.Header = P.text end
		if ( Col.Category.Header_Closed ) then Col.Category.Header_Closed = P.textDim end
		if ( Col.Category.Line ) then
			Col.Category.Line.Text          = P.text
			Col.Category.Line.Text_Hover    = P.text
			Col.Category.Line.Text_Selected = P.text
			Col.Category.Line.Text_Disabled = P.textOff
		end
		if ( Col.Category.LineAlt ) then
			Col.Category.LineAlt.Text          = P.text
			Col.Category.LineAlt.Text_Hover    = P.text
			Col.Category.LineAlt.Text_Selected = P.text
			Col.Category.LineAlt.Text_Disabled = P.textOff
		end
	end
	Col.TooltipText = P.text

	SKIN.Colours = Col
	return true
end

BuildColours()
