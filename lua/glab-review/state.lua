-- In-memory model of the currently loaded merge request.
--
-- Holds the raw MR metadata plus indexes derived from its discussions so the
-- UI modules can look things up cheaply:
--   * general      : discussions with no diff position (shown in the overview)
--   * by_file      : map repo-relative path -> { {discussion, note, line, side}, ... }
--   * unmapped     : positioned discussions whose line could not be resolved
--   * note_index   : map note_id -> { discussion, note } for award/reaction lookup
--   * changes      : map repo-relative path -> changed-line signs (gutter hints)
--   * hunks        : map repo-relative path -> parsed diff hunks (for previews)
--
-- Pending draft notes (the unpublished review) are indexed the same way, into
-- `drafts_by_file` and `drafts_by_discussion` (replies staged onto a thread).
--
-- The lookup helpers honour one view filter, `hide_resolved`, so a reviewer can
-- mute threads that are already settled without reloading.
local M = {}

local diff = require("glab-review.diff")

--- @class GlabState
--- @field mr table|nil           raw merge request object from the API
--- @field diff_refs table|nil    { base_sha, head_sha, start_sha }
--- @field discussions table      raw discussions list
--- @field general table
--- @field by_file table
--- @field unmapped table
--- @field note_index table
--- @field changes table
--- @field hunks table
--- @field drafts table
--- @field drafts_by_file table
--- @field drafts_by_discussion table

--- @type GlabState|nil
local current = nil

-- View filter: when true, resolved threads are omitted from every lookup
-- helper, so they disappear from the gutter, the overview and the picker.
local hide_resolved = false

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

--- The buffer line, diff side and path a `position` points at, or nil. Both
--- halves come from the same side of the diff, so callers never pair a new
--- path with an old line.
function M.locate(position)
  return resolve_line(position)
end

--- Build the derived indexes from a raw MR object + discussions list. `changes`
--- is the raw `/diffs` file list (optional); each file's unified diff is parsed
--- into changed-line gutter hints keyed by path. `drafts` is the pending
--- draft-note list (optional).
function M.load(mr, discussions, changes, drafts)
  current = {
    mr = mr,
    diff_refs = mr.diff_refs,
    discussions = discussions or {},
    general = {},
    by_file = {},
    unmapped = {},
    note_index = {},
    changes = {},
    hunks = {},
    drafts = drafts or {},
    drafts_by_file = {},
    drafts_by_discussion = {},
  }

  for _, c in ipairs(changes or {}) do
    local path = c.new_path or c.old_path
    if path and c.diff and c.diff ~= "" then
      current.changes[path] = diff.changed_lines(c.diff)
      current.hunks[path] = diff.hunks(c.diff)
    end
  end

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

  for _, draft in ipairs(current.drafts) do
    local line, side, path = resolve_line(draft.position)
    -- A reply belongs under its thread even when it carries the thread's
    -- position; only a standalone draft is anchored to a line of its own.
    if draft.discussion_id then
      local list = current.drafts_by_discussion[draft.discussion_id] or {}
      table.insert(list, draft)
      current.drafts_by_discussion[draft.discussion_id] = list
    elseif line and path then
      current.drafts_by_file[path] = current.drafts_by_file[path] or {}
      table.insert(current.drafts_by_file[path], {
        draft = draft,
        line = line,
        side = side,
        path = path,
      })
    end
  end

  return current
end

-- ---------------------------------------------------------------------------
-- View filter
-- ---------------------------------------------------------------------------

--- Hide (true) or show (false) resolved threads in every lookup helper.
function M.set_hide_resolved(v)
  hide_resolved = v and true or false
end

function M.hide_resolved()
  return hide_resolved
end

--- Whether a discussion passes the current view filter.
function M.visible(discussion)
  return not (hide_resolved and discussion.resolved)
end

--- How many threads the filter is currently hiding (0 when it is off).
function M.hidden_count()
  if not current or not hide_resolved then
    return 0
  end
  local n = 0
  for _, d in ipairs(current.discussions) do
    if d.resolved then
      n = n + 1
    end
  end
  return n
end

-- ---------------------------------------------------------------------------
-- Lookup helpers used by the UI modules (all filtered)
-- ---------------------------------------------------------------------------

function M.inline_for_path(path)
  if not current then
    return {}
  end
  local out = {}
  for _, item in ipairs(current.by_file[path] or {}) do
    if M.visible(item.discussion) then
      out[#out + 1] = item
    end
  end
  return out
end

--- General (non-positioned) threads, as rendered in the overview.
function M.general()
  if not current then
    return {}
  end
  return vim.tbl_filter(M.visible, current.general)
end

--- How many general threads the filter is hiding from the overview.
function M.general_hidden()
  if not current then
    return 0
  end
  return #current.general - #M.general()
end

--- Changed-line signs ({line, kind, removed}) for a repo-relative path.
function M.changes_for_path(path)
  if not current then
    return {}
  end
  return current.changes[path] or {}
end

--- Parsed diff hunks for a repo-relative path, for the hunk preview.
function M.hunks_for_path(path)
  if not current then
    return {}
  end
  return current.hunks[path] or {}
end

function M.note(note_id)
  return current and current.note_index[note_id] or nil
end

-- ---------------------------------------------------------------------------
-- Pending drafts
-- ---------------------------------------------------------------------------

--- Standalone drafts ({draft, line, side, path}) anchored in a repo-relative path.
function M.drafts_for_path(path)
  if not current then
    return {}
  end
  return current.drafts_by_file[path] or {}
end

--- Drafts staged as replies to `discussion_id`.
function M.draft_replies(discussion_id)
  if not current then
    return {}
  end
  return current.drafts_by_discussion[discussion_id] or {}
end

--- Every pending draft, in the order the API returned them.
function M.drafts()
  return current and current.drafts or {}
end

function M.draft_count()
  return current and #current.drafts or 0
end

-- Session mode: when on, new comments are queued as drafts instead of posted.
local draft_mode = true

function M.set_draft_mode(v)
  draft_mode = v and true or false
end

function M.draft_mode()
  return draft_mode
end

--- Whether a command should draft, given its bang. A bang inverts the mode.
function M.drafting(bang)
  return (bang == true) ~= draft_mode
end

return M
