-- In-memory model of the currently loaded merge request.
--
-- Holds the raw MR metadata plus indexes derived from its discussions so the
-- UI modules can look things up cheaply:
--   * general      : discussions with no diff position (shown in the overview)
--   * by_file      : map repo-relative path -> { {discussion, note, line, side}, ... }
--   * unmapped     : positioned discussions whose line could not be resolved
--   * note_index   : map note_id -> { discussion, note } for award/reaction lookup
local M = {}

--- @class GlabState
--- @field mr table|nil           raw merge request object from the API
--- @field diff_refs table|nil    { base_sha, head_sha, start_sha }
--- @field discussions table      raw discussions list
--- @field general table
--- @field by_file table
--- @field unmapped table
--- @field note_index table

--- @type GlabState|nil
local current = nil

function M.clear()
  current = nil
end

function M.get()
  return current
end

function M.is_loaded()
  return current ~= nil
end

local function first_note(discussion)
  return discussion.notes and discussion.notes[1] or nil
end

--- A discussion is "inline" when its first note carries a diff position.
local function position_of(discussion)
  local n = first_note(discussion)
  return n and n.position or nil
end

--- Resolve the buffer line (1-based) a positioned note points at, plus which
--- side of the diff it belongs to. Returns nil when it cannot be mapped (e.g.
--- an outdated position on a superseded diff).
local function resolve_line(position)
  if not position then
    return nil
  end
  -- Prefer the new side (added/context lines in the current revision).
  if position.new_line then
    return position.new_line, "new", position.new_path
  end
  if position.old_line then
    return position.old_line, "old", position.old_path
  end
  return nil
end

--- Build the derived indexes from a raw MR object + discussions list.
function M.load(mr, discussions)
  current = {
    mr = mr,
    diff_refs = mr.diff_refs,
    discussions = discussions or {},
    general = {},
    by_file = {},
    unmapped = {},
    note_index = {},
  }

  for _, discussion in ipairs(current.discussions) do
    for _, note in ipairs(discussion.notes or {}) do
      if note.id then
        current.note_index[note.id] = { discussion = discussion, note = note }
      end
    end

    local pos = position_of(discussion)
    if not pos then
      -- System notes (label changes etc.) carry no body worth showing.
      local n = first_note(discussion)
      if n and not n.system then
        table.insert(current.general, discussion)
      end
    else
      local line, side, path = resolve_line(pos)
      if line and path then
        current.by_file[path] = current.by_file[path] or {}
        table.insert(current.by_file[path], {
          discussion = discussion,
          note = first_note(discussion),
          line = line,
          side = side,
          path = path,
        })
      else
        table.insert(current.unmapped, discussion)
      end
    end
  end

  return current
end

--- Lookup helpers used by the UI modules.
function M.inline_for_path(path)
  if not current then
    return {}
  end
  return current.by_file[path] or {}
end

function M.note(note_id)
  return current and current.note_index[note_id] or nil
end

return M
