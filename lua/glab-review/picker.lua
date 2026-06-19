-- fzf-lua pickers: merge-request selection, comment navigation, emoji choice.
local state = require("glab-review.state")
local util = require("glab-review.util")
local config = require("glab-review.config")

local M = {}

local function fzf()
  local ok, mod = pcall(require, "fzf-lua")
  if not ok then
    util.err("fzf-lua is required but not installed")
    return nil
  end
  return mod
end

-- Entries are encoded as "<index>\t<label>"; fzf displays only the label
-- (via --with-nth) and we recover the index from the selected line.
local DELIM = "\t"

local function run(entries, prompt, on_index)
  local f = fzf()
  if not f then
    return
  end
  f.fzf_exec(entries, {
    prompt = prompt,
    fzf_opts = {
      ["--delimiter"] = DELIM,
      ["--with-nth"] = "2..",
      ["--no-multi"] = "",
    },
    actions = {
      ["default"] = function(selected)
        local line = selected and selected[1]
        if not line then
          return
        end
        local idx = tonumber(line:match("^(%d+)" .. DELIM))
        if idx then
          on_index(idx)
        end
      end,
    },
  })
end

--- Pick from a list of MRs; calls `on_select(iid)`.
function M.pick_mr(mrs, on_select)
  local entries = {}
  for i, mr in ipairs(mrs) do
    local author = mr.author and mr.author.username or "?"
    local draft = mr.draft and "[draft] " or ""
    entries[i] = ("%d%s!%d  %s%s  [@%s]"):format(i, DELIM, mr.iid, draft, mr.title, author)
  end
  run(entries, "Merge requests> ", function(idx)
    local mr = mrs[idx]
    if mr then
      on_select(mr.iid)
    end
  end)
end

--- Pick any comment of the loaded MR and jump to its location.
function M.pick_comment()
  local cur = state.get()
  if not cur then
    return
  end

  -- Build a flat, indexed list of jump targets.
  local targets = {}
  local entries = {}

  local function add(label, target)
    local i = #targets + 1
    targets[i] = target
    entries[i] = i .. DELIM .. label
  end

  -- Inline comments grouped by file.
  for path, list in pairs(cur.by_file) do
    for _, item in ipairs(list) do
      local author = item.note.author and item.note.author.username or "?"
      add(
        ("  %s:%d  @%s  %s"):format(path, item.line, author, util.snippet(item.note.body)),
        { kind = "inline", path = path, line = item.line }
      )
    end
  end

  -- General threads (live in the overview buffer).
  for _, d in ipairs(cur.general) do
    local n = d.notes[1]
    local author = n.author and n.author.username or "?"
    local mark = d.resolved and "✓ " or ""
    add(
      ("  %s💬 @%s  %s"):format(mark, author, util.snippet(n.body)),
      { kind = "general", discussion_id = d.id }
    )
  end

  -- Unmapped (outdated) inline comments — body preview only.
  for _, d in ipairs(cur.unmapped) do
    local n = d.notes[1]
    local author = n.author and n.author.username or "?"
    local p = n.position or {}
    add(
      ("  ⚠ outdated %s  @%s  %s"):format(p.new_path or p.old_path or "?", author, util.snippet(n.body)),
      { kind = "unmapped", body = n.body }
    )
  end

  if #entries == 0 then
    util.notify("no comments on this MR")
    return
  end

  run(entries, "Comments> ", function(idx)
    local t = targets[idx]
    if not t then
      return
    end
    if t.kind == "inline" then
      M.jump_to_inline(t.path, t.line)
    elseif t.kind == "general" then
      require("glab-review.overview").jump_to_discussion(t.discussion_id)
    else
      util.notify(t.body)
    end
  end)
end

--- Open `path` (resolved against the repo root) and place the cursor on `line`.
function M.jump_to_inline(path, line)
  local root = util.git_root()
  local full = root and (root .. "/" .. path) or path
  vim.cmd.edit(vim.fn.fnameescape(full))
  pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
  vim.cmd("normal! zz")
end

-- Status label/icon for a `/diffs` entry.
local function change_status(c)
  if c.new_file then
    return "A", "new"
  elseif c.deleted_file then
    return "D", "deleted"
  elseif c.renamed_file then
    return "R", "renamed"
  end
  return "M", "modified"
end

--- Picker over the files changed in the MR. `<Enter>` opens the selection;
--- `<Alt-q>`/`<Ctrl-q>` send it to the quickfix list. `files` is the `/diffs` list.
function M.pick_changed_files(files)
  local f = fzf()
  if not f then
    return
  end
  local root = util.git_root()

  local items = {} -- parallel to entries: { path, full, exists, status }
  local entries = {}
  for _, c in ipairs(files) do
    local path = c.new_path or c.old_path
    if path then
      local letter, status = change_status(c)
      local full = root and (root .. "/" .. path) or path
      local exists = vim.uv.fs_stat(full) ~= nil
      local i = #items + 1
      items[i] = { path = path, full = full, exists = exists, status = status }
      entries[i] = ("%d%s%s  %s"):format(i, DELIM, letter, path)
    end
  end

  if #entries == 0 then
    util.notify("no changed files on this MR")
    return
  end

  -- Map a list of selected fzf lines back to item tables.
  local function selected_items(selected)
    local out = {}
    for _, line in ipairs(selected or {}) do
      local idx = tonumber(line:match("^(%d+)" .. DELIM))
      if idx and items[idx] then
        out[#out + 1] = items[idx]
      end
    end
    return out
  end

  local function open(selected)
    local picked = selected_items(selected)
    local opened = 0
    for _, it in ipairs(picked) do
      if it.exists then
        vim.cmd.edit(vim.fn.fnameescape(it.full))
        opened = opened + 1
      else
        util.notify(("skipped %s (%s, not on disk)"):format(it.path, it.status))
      end
    end
    if opened == 0 and #picked > 0 then
      util.notify("nothing to open (selected files not on disk)")
    end
  end

  local function to_quickfix(selected)
    local picked = selected_items(selected)
    local qf = {}
    for _, it in ipairs(picked) do
      qf[#qf + 1] = {
        filename = it.full,
        lnum = 1,
        col = 1,
        text = it.status,
        valid = it.exists and 1 or 0,
      }
    end
    if #qf == 0 then
      return
    end
    vim.fn.setqflist({}, " ", { title = "MR changed files", items = qf })
    vim.cmd("copen")
  end

  f.fzf_exec(entries, {
    prompt = "Changed files> ",
    fzf_opts = {
      ["--delimiter"] = DELIM,
      ["--with-nth"] = "2..",
      ["--multi"] = "",
    },
    actions = {
      ["default"] = open,
      -- fzf-lua's default files picker binds send-to-quickfix to alt-q; mirror
      -- it here (with ctrl-q kept as an alias) so this picker behaves the same.
      ["alt-q"] = to_quickfix,
      ["ctrl-q"] = to_quickfix,
    },
  })
end

--- Pick an award emoji; calls `on_select(api_name)`.
function M.pick_emoji(on_select)
  local f = fzf()
  if not f then
    return
  end
  local emojis = config.get().emojis
  local entries = {}
  local names = {}
  for i, e in ipairs(emojis) do
    entries[i] = i .. DELIM .. e
    names[i] = e:match("(%S+)$") -- api name is the last token
  end
  run(entries, "React> ", function(idx)
    if names[idx] then
      on_select(names[idx])
    end
  end)
end

return M
