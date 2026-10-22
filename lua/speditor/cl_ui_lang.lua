--[[
SPeditor — interface languages (a0.7): the language menu and the tools for translators.

Languages other than English and Russian come from the community as language packs
(sh_lang.lua, SPeditor.AddLanguage). A translator starts from a template written by
Help → Language → Write a translation template (console: gmfm_lang_template <code>):
a ready lua file with every string of the editor, the already translated ones filled in.
gmfm_lang_missing <code> lists what is still untranslated after an update.
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI = SPeditor.UI
local L  = SPeditor.L

local DIR = "speditor/lang"

-- The language items of a menu: every built-in language and every installed pack
function UI.LanguageMenu(sub)
	local C = SPeditor.Client
	local cur = GetConVarString("gmfm_language")
	for _, l in ipairs(SPeditor.Languages) do
		local text = l.name
		if not l.builtin and l.author and l.author ~= "" then text = text .. "   (" .. l.author .. ")" end
		sub:AddOption(text, function()
			if cur == l.code then return end
			RunConsoleCommand("gmfm_language", l.code)
			timer.Simple(0.1, function() if C.active then UI.Rebuild() end end)
		end):SetChecked(cur == l.code)
	end
	sub:AddSpacer()
	sub:AddOption(L("lang_template") .. "…", function()
		Derma_StringRequest(L("lang_template"), L("lang_template_prompt"), cur ~= "en" and cur or "", function(code)
			UI.WriteLangTemplate(string.lower(string.Trim(code)))
		end)
	end):SetIcon("icon16/page_white_edit.png")
end

---------------------------------------------------------------------
-- The template
---------------------------------------------------------------------
local function quote(s)
	s = string.gsub(s, "\\", "\\\\")
	s = string.gsub(s, "\"", "\\\"")
	s = string.gsub(s, "\n", "\\n")
	s = string.gsub(s, "\t", "\\t")
	return "\"" .. s .. "\""
end

-- every English text of the guides (Help → How to use)
local function guideTexts()
	local set = {}
	local function add(s) if isstring(s) and s ~= "" then set[s] = true end end
	for _, g in pairs(UI.Guides or {}) do
		add(istable(g.title) and g.title.en)
		for _, b in ipairs(g.blocks or {}) do
			local kind = b[1]
			if kind == "steps" then
				for _, s in ipairs(istable(b.en) and b.en or {}) do add(s) end
			elseif kind == "img" then
				add(b[3])
			else
				add(b[2])
			end
		end
	end
	-- texts drawn by the live demonstrations, seen while the guides were open
	for s in pairs(UI.GuideTextsSeen or {}) do add(s) end
	local list = {}
	for s in pairs(set) do list[#list + 1] = s end
	table.sort(list)
	return list
end

function SPeditor.LangTemplate(code)
	local info = SPeditor.LanguageInfo(code) or {}
	local dict = SPeditor.Lang[code] or {}
	local texts = SPeditor.LangText[code] or {}
	local en = SPeditor.Lang.en
	local keys = {}
	for k in pairs(en) do keys[#keys + 1] = k end
	table.sort(keys)

	local out, todo = {}, 0
	local function w(s) out[#out + 1] = s end
	w("-- GM:FM language pack: " .. (info.name or code) .. " (" .. code .. "), written by GM:FM " .. SPeditor.Version)
	w("--")
	w("-- 1. Translate the texts on the right. Keep %s, %d, %.1f and \\n exactly as they are:")
	w("--    GM:FM puts numbers and names there (a line that loses them is skipped).")
	w("--    Lines marked TODO are not translated yet; a line left in English stays English.")
	w("-- 2. Put this file into an addon of your own as  lua/speditor_lang/" .. code .. ".lua")
	w("--    (garrysmod/addons/<your_addon>/lua/speditor_lang/" .. code .. ".lua) and restart the map.")
	w("--    The language appears in SPeditor: Help → Language.")
	w("-- 3. Share the addon on the Workshop. On a server the server must have it installed too.")
	w("-- After an GM:FM update: gmfm_lang_missing " .. code .. " lists the new strings, and a new")
	w("-- template keeps everything you have translated.")
	w("")
	w("SPeditor.AddLanguage({")
	w("\tcode = " .. quote(code) .. ",")
	w("\tname = " .. quote(info.name or code) .. ",        -- the name of the language in that language")
	w("\tauthor = " .. quote(info.author or "") .. ",")
	w("\tversion = " .. quote(SPeditor.Version) .. ",")
	w((info.font and "\t" or "\t-- ") .. "font = " .. quote(info.font or "Meiryo") .. ",   -- a font that has the letters of the language, if Tahoma has not")
	w("\tstrings = {")
	for _, k in ipairs(keys) do
		local v = dict[k]
		if v then
			w("\t\t[" .. quote(k) .. "] = " .. quote(v) .. ",")
		else
			todo = todo + 1
			w("\t\t[" .. quote(k) .. "] = " .. quote(en[k]) .. ",   -- TODO")
		end
	end
	w("\t},")
	w("\t-- Help → How to use: each text by its English original")
	w("\ttexts = {")
	for _, s in ipairs(guideTexts()) do
		if texts[s] then
			w("\t\t[" .. quote(s) .. "] = " .. quote(texts[s]) .. ",")
		else
			todo = todo + 1
			w("\t\t[" .. quote(s) .. "] = " .. quote(s) .. ",   -- TODO")
		end
	end
	w("\t},")
	w("})")
	return table.concat(out, "\n") .. "\n", todo
end

function UI.WriteLangTemplate(code)
	if not isstring(code) or not string.match(code, "^%l%l[%l_%-]*$") or code == "en" then
		SPeditor.Notify(L("lang_code_bad"), 1)
		return
	end
	local text, todo = SPeditor.LangTemplate(code)
	file.CreateDir(DIR)
	local path = DIR .. "/" .. code .. ".txt"
	file.Write(path, text)
	SPeditor.Notify(string.format(L("lang_template_done"), "garrysmod/data/" .. path, todo), 2)
	print("[GM:FM] " .. string.format(L("lang_template_done"), "garrysmod/data/" .. path, todo))
end

concommand.Add("gmfm_lang_template", function(_, _, args)
	UI.WriteLangTemplate(string.lower(args[1] or GetConVarString("gmfm_language")))
end)

concommand.Add("gmfm_lang_missing", function(_, _, args)
	local code = string.lower(args[1] or GetConVarString("gmfm_language"))
	local list, total = SPeditor.LangMissing(code)
	print(string.format("[GM:FM] %s: %d / %d", code, total - #list, total))
	for _, k in ipairs(list) do print("  " .. k .. "    " .. tostring(SPeditor.Lang.en[k])) end
end)
