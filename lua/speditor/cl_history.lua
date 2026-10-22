-- Undo / Redo. Covers: move, rotate, bones, flexes, eyes, loading poses,
-- creating, duplicating and deleting objects (deleted ones are kept on the server in a "bin").
SPeditor.Client = SPeditor.Client or {}
local C = SPeditor.Client

local MAX = 100

-- A reference to an object that survives deletion / restoring: a restored
-- object has a new Entity but the same UID. History closures keep the ref, not the ent.
function C.Ref(ent)
	return { ent = ent, uid = IsValid(ent) and ent:GetNW2Int("SPeditor_UID", 0) or 0 }
end

function C.Deref(ref)
	if IsValid(ref.ent) then return ref.ent end
	if ref.uid ~= 0 then
		for _, e in ipairs(ents.GetAll()) do
			if e:GetNW2Int("SPeditor_UID", 0) == ref.uid and C.IsMine(e) then
				ref.ent = e
				return e
			end
		end
	end
	return nil
end
local undoStack, redoStack = {}, {}

-- Caption of a history step in the interface language: the dictionary key "hist_<label>"
-- (spaces -> "_"); "bone 12" — the shared key hist_bone and the number.
function C.HistoryLabel(label)
	local base, rest = string.match(label, "^(bone) (.+)$")
	local key = "hist_" .. string.gsub(base or label, " ", "_")
	local text = SPeditor.L(key)
	if text == key then return label end
	return rest and (text .. " " .. rest) or text
end

function C.PushHistory(label, undoFn, redoFn)
	undoStack[#undoStack + 1] = { label = label, undo = undoFn, redo = redoFn }
	if #undoStack > MAX then table.remove(undoStack, 1) end
	redoStack = {}
	hook.Run("SPeditor_HistoryPushed", label)     -- for SAeditor: "something in the scene was changed"
end

function C.Undo()
	local e = table.remove(undoStack)
	if not e then
		SPeditor.Notify("#undo_nothing", 0)
		return
	end
	e.undo()
	redoStack[#redoStack + 1] = e
	hook.Run("SPeditor_HistoryStep", e.label, true)
	SPeditor.Notify(SPeditor.L("undo_done") .. ": " .. C.HistoryLabel(e.label), 0)
end

function C.Redo()
	local e = table.remove(redoStack)
	if not e then
		SPeditor.Notify("#redo_nothing", 0)
		return
	end
	e.redo()
	undoStack[#undoStack + 1] = e
	hook.Run("SPeditor_HistoryStep", e.label, false)
	SPeditor.Notify(SPeditor.L("redo_done") .. ": " .. C.HistoryLabel(e.label), 0)
end

function C.ClearHistory()
	undoStack, redoStack = {}, {}
end

-- Merging a series of quick edits (sliders) into one history entry.
-- getBefore() is called only on the first edit of a series; restore(state) sends the state to the server.
local bursts = {}

function C.BurstEdit(key, label, getBefore, after, restore)
	local b = bursts[key]
	if not b then
		b = { before = getBefore() }
		bursts[key] = b
	end
	b.after = after

	timer.Create("SPeditor_Burst_" .. key, 0.6, 1, function()
		bursts[key] = nil
		local before, aft = b.before, b.after
		C.PushHistory(label,
			function() restore(before) end,
		function() restore(aft) end)
	end)
end

-- An action on a pose that can be undone: snapshot before, action, snapshot after
function C.SnapshotThen(ent, label, action)
	if not IsValid(ent) then return end
	local ref = C.Ref(ent)
	C.RequestPose(ent, function(before)
		if not IsValid(ent) then return end
		action()
		C.RequestPose(ent, function(after)
			if not IsValid(ent) or not before or not after then return end
			C.PushHistory(label,
				function() local e = C.Deref(ref) if e then C.SendPoseApply(e, before) end end,
			function() local e = C.Deref(ref) if e then C.SendPoseApply(e, after) end end)
		end)
	end)
end

SPeditor.Hook("SPeditor_SceneLoaded", "SPeditor.HistoryClear", function()
	C.ClearHistory()
end)
