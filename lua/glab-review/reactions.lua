-- Award-emoji reactions and `/meta-command` dispatch.
local state = require("glab-review.state")
local gitlab = require("glab-review.gitlab")
local config = require("glab-review.config")
local util = require("glab-review.util")

local M = {}

--- Parse a single trimmed line as a meta-command. Returns the action table
--- ({ award = name } or { resolve = bool }) or nil.
function M.parse_meta(line)
  local trimmed = vim.trim(line)
  return config.get().meta_commands[trimmed]
end

--- Split a body into (cleaned_body, metas) where meta-command lines are pulled
--- out into `metas` and removed from the returned body.
function M.extract_metas(body)
  local kept, metas = {}, {}
  for _, line in ipairs(vim.split(body or "", "\n", { plain = true })) do
    local meta = M.parse_meta(line)
    if meta then
      table.insert(metas, meta)
    else
      table.insert(kept, line)
    end
  end
  return vim.trim(table.concat(kept, "\n")), metas
end

--- Apply a single meta action against a target. Runs inside async; returns err.
--- `target` = { iid, discussion_id, note_id }
function M.apply_meta(meta, target)
  if meta.award and target.note_id then
    local err = gitlab.award(target.iid, target.note_id, meta.award)
    return err
  elseif meta.resolve ~= nil and target.discussion_id then
    local err = gitlab.set_resolved(target.iid, target.discussion_id, meta.resolve)
    return err
  end
  return nil
end

--- Resolve the comment under the cursor to a target table, or nil.
local function target_at_cursor()
  local cur = state.get()
  if not cur then
    util.notify("no MR loaded — run sync first")
    return nil
  end
  local iid = cur.mr.iid

  -- In the overview buffer, defer to its cursor->discussion mapping.
  local overview = require("glab-review.overview")
  local ov = overview.discussion_at_cursor()
  if ov then
    return { iid = iid, discussion_id = ov.discussion_id, note_id = ov.note_id }
  end

  -- Otherwise treat the current buffer as a code file with inline comments.
  local bufname = vim.api.nvim_buf_get_name(0)
  local path = util.repo_relative(bufname)
  if not path then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  for _, item in ipairs(state.inline_for_path(path)) do
    if item.line == line then
      return { iid = iid, discussion_id = item.discussion.id, note_id = item.note.id }
    end
  end
  return nil
end

--- Public: react (award emoji) to the comment under the cursor.
function M.react_at_cursor()
  local target = target_at_cursor()
  if not target then
    util.notify("no comment under the cursor")
    return
  end
  require("glab-review.picker").pick_emoji(function(name)
    util.async(function()
      local err = gitlab.award(target.iid, target.note_id, name)
      if err then
        util.err(err)
        return
      end
      util.notify("reacted :" .. name .. ":")
      require("glab-review").reload()
    end)()
  end)
end

return M
