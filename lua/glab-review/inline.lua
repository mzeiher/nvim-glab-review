-- Inline (positioned) comments rendered as gutter signs + toggleable virtual
-- text, plus creation of new inline comments from a code line.
local state = require("glab-review.state")
local config = require("glab-review.config")
local util = require("glab-review.util")
local gitlab = require("glab-review.gitlab")

local M = {}

local ns
local augroup
local show_bodies = true

function M.setup()
  ns = vim.api.nvim_create_namespace("glab-review-inline")
  show_bodies = config.get().inline.virt_text_default
  augroup = vim.api.nvim_create_augroup("glab-review-inline", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufEnter" }, {
    group = augroup,
    callback = function(ev)
      if state.is_loaded() then
        M.place(ev.buf)
      end
    end,
  })
end

-- Build the virt_lines block (a list of lines, each a list of {text, hl}
-- chunks) describing every note in a discussion.
local function virt_lines_for(item)
  local cfg = config.get().inline
  local lines = {}
  for i, note in ipairs(item.discussion.notes or {}) do
    if not note.system then
      local author = note.author and note.author.username or "?"
      local prefix = i == 1 and (cfg.sign_text .. " ") or "   ↳ "
      table.insert(lines, {
        { prefix .. "@" .. author .. ": ", cfg.author_hl },
      })
      for _, bl in ipairs(vim.split(note.body or "", "\n", { plain = true })) do
        table.insert(lines, { { "   " .. bl, cfg.virt_hl } })
      end
    end
  end
  if item.discussion.resolved then
    table.insert(lines, { { "   ✓ resolved", cfg.author_hl } })
  end
  return lines
end

--- Place signs / virtual text for the loaded MR in buffer `bufnr`.
function M.place(bufnr, root)
  if not ns or not state.is_loaded() then
    return
  end
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return
  end
  local path = util.repo_relative(name, root)
  if not path then
    return
  end
  local items = state.inline_for_path(path)

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  if #items == 0 then
    return
  end

  local cfg = config.get().inline
  local n_lines = vim.api.nvim_buf_line_count(bufnr)
  for _, item in ipairs(items) do
    local row = item.line - 1
    if row >= 0 and row < n_lines then
      local opts = {
        sign_text = cfg.sign_text,
        sign_hl_group = cfg.sign_hl,
        priority = 200,
      }
      if show_bodies then
        opts.virt_lines = virt_lines_for(item)
        opts.virt_lines_above = false
      end
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row, 0, opts)
    end
  end
end

--- Re-render every loaded buffer that maps to a commented file.
function M.refresh_all()
  if not ns then
    M.setup()
  end
  local root = util.git_root()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      M.place(bufnr, root)
    end
  end
end

--- Toggle the comment bodies (signs always remain).
function M.toggle()
  show_bodies = not show_bodies
  M.refresh_all()
  util.notify("inline comment bodies " .. (show_bodies and "shown" or "hidden"))
end

-- Post a reply to an existing thread. `label` is shown in the input prompt.
local function reply_to(iid, discussion_id, label)
  vim.ui.input({ prompt = ("Reply to %s > "):format(label) }, function(input)
    if not input or vim.trim(input) == "" then
      return
    end
    util.async(function()
      local err = gitlab.reply(iid, discussion_id, input)
      if err then
        util.err("failed to reply: " .. err)
        return
      end
      util.notify("reply added")
      require("glab-review").reload()
    end)()
  end)
end

-- Create a brand-new inline thread anchored at path:line.
local function create_new(iid, path, line, diff_refs)
  if not diff_refs or not diff_refs.head_sha then
    util.err("MR has no diff refs; cannot anchor an inline comment")
    return
  end
  vim.ui.input({ prompt = ("Inline comment on %s:%d > "):format(path, line) }, function(input)
    if not input or vim.trim(input) == "" then
      return
    end
    util.async(function()
      local err = gitlab.create_inline(iid, input, path, line, diff_refs)
      if err then
        util.err("failed to create inline comment: " .. err)
        return
      end
      util.notify("inline comment added")
      require("glab-review").reload()
    end)()
  end)
end

-- Create a multi-line inline thread spanning new-side lines [line1, line2].
-- Needs the file's diff to compute GitLab line codes for the range endpoints.
local function create_multiline(iid, path, line1, line2, diff_refs)
  if not diff_refs or not diff_refs.head_sha then
    util.err("MR has no diff refs; cannot anchor an inline comment")
    return
  end
  util.async(function()
    local err, files = require("glab-review.gitlab").get_changes(iid)
    if err then
      util.err(err)
      return
    end
    local diff_text
    for _, c in ipairs(files or {}) do
      if c.new_path == path or c.old_path == path then
        diff_text = c.diff
        break
      end
    end
    if not diff_text then
      util.err(("%s is not part of this MR's changes"):format(path))
      return
    end

    local map = require("glab-review.diff").new_line_map(diff_text)
    local old1, old2 = map[line1], map[line2]
    if not old1 or not old2 then
      util.err("selected range is not within the MR diff for this file")
      return
    end

    local sha = util.sha1(path)
    local function code(old, new)
      return ("%s_%d_%d"):format(sha, old, new)
    end

    local input = util.await(function(resume)
      vim.ui.input({ prompt = ("Comment on %s:%d-%d > "):format(path, line1, line2) }, resume)
    end)
    if not input or vim.trim(input) == "" then
      return
    end

    local position = {
      position_type = "text",
      base_sha = diff_refs.base_sha,
      head_sha = diff_refs.head_sha,
      start_sha = diff_refs.start_sha,
      new_path = path,
      old_path = path,
      new_line = line2,
      line_range = {
        start = { line_code = code(old1, line1), type = "new" },
        ["end"] = { line_code = code(old2, line2), type = "new" },
      },
    }
    local e2 = require("glab-review.gitlab").create_positioned(iid, input, position)
    if e2 then
      util.err("failed to create inline comment: " .. e2)
      return
    end
    util.notify(("inline comment added (%d-%d)"):format(line1, line2))
    require("glab-review").reload()
  end)()
end

--- Always create a NEW inline thread on the line(s) under the cursor /
--- selection. A single line creates a single-line thread; a multi-line range
--- (`line1 ~= line2`) creates one comment spanning the range. To reply to an
--- existing thread, use `reply_at_cursor` instead.
function M.create_at_cursor(line1, line2)
  local cur = state.get()
  if not cur then
    util.notify("no MR loaded — run sync first")
    return
  end
  local bufname = vim.api.nvim_buf_get_name(0)
  local path = util.repo_relative(bufname)
  if not path then
    util.err("current buffer is not inside the repo")
    return
  end

  if line1 and line2 and line2 > line1 then
    create_multiline(cur.mr.iid, path, line1, line2, cur.diff_refs)
  else
    local line = line1 or vim.api.nvim_win_get_cursor(0)[1]
    create_new(cur.mr.iid, path, line, cur.diff_refs)
  end
end

--- Reply to the thread under the cursor. Works on a thread in the overview
--- buffer, or on a commented code line (picking one when several threads share
--- the line).
function M.reply_at_cursor()
  local cur = state.get()
  if not cur then
    util.notify("no MR loaded — run sync first")
    return
  end
  local iid = cur.mr.iid

  -- In the overview buffer, reply to the thread under the cursor.
  local ov = require("glab-review.overview").discussion_at_cursor()
  if ov then
    reply_to(iid, ov.discussion_id, "this thread")
    return
  end

  local path = util.repo_relative(vim.api.nvim_buf_get_name(0))
  if not path then
    util.err("no comment under the cursor to reply to")
    return
  end
  local line = vim.api.nvim_win_get_cursor(0)[1]

  local existing = {}
  for _, item in ipairs(state.inline_for_path(path)) do
    if item.line == line then
      existing[#existing + 1] = item
    end
  end

  if #existing == 0 then
    util.notify("no comment on this line to reply to")
  elseif #existing == 1 then
    reply_to(iid, existing[1].discussion.id, ("%s:%d"):format(path, line))
  else
    vim.ui.select(existing, {
      prompt = "Reply to which thread?",
      format_item = function(item)
        local author = item.note.author and item.note.author.username or "?"
        return ("@%s: %s"):format(author, util.snippet(item.note.body))
      end,
    }, function(choice)
      if choice then
        reply_to(iid, choice.discussion.id, ("%s:%d"):format(path, line))
      end
    end)
  end
end

return M
