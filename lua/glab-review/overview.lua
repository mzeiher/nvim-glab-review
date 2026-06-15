-- The MR overview: a scratch buffer holding the (editable) description and all
-- general threads. Saving (`:w`) diffs the editable regions against what was
-- rendered and pushes the changes via the API.
local state = require("glab-review.state")
local gitlab = require("glab-review.gitlab")
local util = require("glab-review.util")

local M = {}

-- Region markers. The parser captures user input only inside the description,
-- reply, and new-comment regions; everything else (thread headers, existing
-- note bodies) is informational and ignored on save.
local DESC_START = "<!-- glab-review:description -->"
local NEW_START = "<!-- glab-review:new -->"
local END = "<!-- glab-review:end -->"
local function thread_start(id, resolved, resolvable)
  return ("<!-- glab-review:thread id=%s resolved=%s resolvable=%s -->"):format(
    id, tostring(resolved or false), tostring(resolvable or false))
end
local function reply_start(id)
  return ("<!-- glab-review:reply id=%s -->"):format(id)
end

-- Lua-pattern forms of the markers.
local P_DESC = "^<!%-%- glab%-review:description %-%->$"
local P_THREAD = "^<!%-%- glab%-review:thread id=(%S+)"
local P_REPLY = "^<!%-%- glab%-review:reply id=(%S+) %-%->$"
local P_NEW = "^<!%-%- glab%-review:new %-%->$"
local P_END = "^<!%-%- glab%-review:end %-%->$"

--- Pure: turn buffer lines into the editable regions. Testable in isolation.
--- Returns { description = {body=...}|nil, replies = {{id, body}}, new = {body=...}|nil }
function M.parse(lines)
  local result = { description = nil, replies = {}, new = nil }
  local mode = nil -- "desc" | "reply" | "new" | "ignore" | nil
  local buf = {}
  local cur_id = nil

  local function finalize()
    local body = table.concat(buf, "\n")
    if mode == "desc" then
      result.description = { body = body }
    elseif mode == "reply" then
      table.insert(result.replies, { id = cur_id, body = body })
    elseif mode == "new" then
      result.new = { body = body }
    end
    buf = {}
  end

  for _, line in ipairs(lines) do
    if line:match(P_DESC) then
      mode, buf = "desc", {}
    elseif line:match(P_NEW) then
      mode, buf = "new", {}
    elseif line:match(P_REPLY) then
      cur_id = line:match(P_REPLY)
      mode, buf = "reply", {}
    elseif line:match(P_THREAD) then
      mode = "ignore"
    elseif line:match(P_END) then
      finalize()
      mode = nil
    elseif mode == "desc" or mode == "reply" or mode == "new" then
      table.insert(buf, line)
    end
  end
  return result
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local bufnr = nil
local ctx = nil -- { iid, orig_description, thread_line = {id->lnum}, thread_note = {id->note_id}, line_owner = {lnum->{discussion_id,note_id}} }

local function render(mr, lines_out, c)
  local L = {}
  local function push(s)
    L[#L + 1] = s
    return #L
  end

  local title = mr.title or ""
  local author = mr.author and mr.author.username or "?"
  push(("# !%d  %s"):format(mr.iid, title))
  push(("%s · @%s · %s"):format(mr.state or "?", author, mr.web_url or ""))
  push("")

  push(DESC_START)
  local desc = (mr.description or ""):gsub("\r\n", "\n")
  c.orig_description = desc
  for _, dl in ipairs(vim.split(desc, "\n", { plain = true })) do
    push(dl)
  end
  push(END)
  push("")

  local cur = state.get()
  push(("## Threads (%d)"):format(#cur.general))
  push("")

  for _, d in ipairs(cur.general) do
    local note1 = d.notes[1]
    local start_ln = push(thread_start(d.id, d.resolved, d.resolvable))
    c.thread_line[d.id] = start_ln
    c.thread_note[d.id] = note1.id

    for i, note in ipairs(d.notes) do
      if not note.system then
        local na = note.author and note.author.username or "?"
        local ts = (note.created_at or ""):sub(1, 10)
        local res = (i == 1 and d.resolved) and "  ✓ resolved" or ""
        push((i == 1 and "### @%s · %s%s" or "#### ↳ @%s · %s%s"):format(na, ts, res))
        for _, bl in ipairs(vim.split(note.body or "", "\n", { plain = true })) do
          push(bl)
        end
        push("")
      end
    end

    push(reply_start(d.id))
    push("") -- input area (type a reply or a /meta-command here)
    local end_ln = push(END)
    push("")
    for ln = start_ln, end_ln do
      c.line_owner[ln] = { discussion_id = d.id, note_id = note1.id }
    end
  end

  push("## New comment")
  push("")
  push(NEW_START)
  push("") -- input area
  push(END)

  for _, l in ipairs(L) do
    lines_out[#lines_out + 1] = l
  end
end

local function find_win(b)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == b then
      return win
    end
  end
  return nil
end

local function ensure_buffer()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    return bufnr
  end
  bufnr = vim.api.nvim_create_buf(false, true)
  local cur = state.get()
  vim.api.nvim_buf_set_name(bufnr, ("glab-review://mr/%d/overview"):format(cur.mr.iid))
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "markdown"

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function()
      M.save()
    end,
  })
  return bufnr
end

local function do_render()
  local cur = state.get()
  ctx = { iid = cur.mr.iid, thread_line = {}, thread_note = {}, line_owner = {} }
  local lines = {}
  render(cur.mr, lines, ctx)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modified = false
end

--- Open (or focus) the overview buffer. Re-renders from state unless the buffer
--- has unsaved edits.
function M.open()
  if not state.is_loaded() then
    util.notify("no MR loaded — run sync first")
    return
  end
  ensure_buffer()
  if not vim.bo[bufnr].modified then
    do_render()
  end
  local win = find_win(bufnr)
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("vsplit")
    vim.api.nvim_win_set_buf(0, bufnr)
  end
end

--- Move the cursor to a general discussion's thread block.
function M.jump_to_discussion(discussion_id)
  M.open()
  if ctx and ctx.thread_line[discussion_id] then
    pcall(vim.api.nvim_win_set_cursor, 0, { ctx.thread_line[discussion_id], 0 })
    vim.cmd("normal! zt")
  end
end

--- If the cursor is in the overview buffer over a thread, return its ids.
function M.discussion_at_cursor()
  if not bufnr or vim.api.nvim_get_current_buf() ~= bufnr or not ctx then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  return ctx.line_owner[lnum]
end

--- BufWriteCmd handler: diff editable regions against the rendered state and
--- push changes. Marks the buffer unmodified immediately so `:w` succeeds.
function M.save()
  if not bufnr or not ctx then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local parsed = M.parse(lines)
  local saved_ctx = ctx
  vim.bo[bufnr].modified = false

  local reactions = require("glab-review.reactions")
  local iid = saved_ctx.iid

  -- Decide what work there is before spinning up the async flow.
  local jobs = {}
  if parsed.description and parsed.description.body ~= saved_ctx.orig_description then
    table.insert(jobs, { kind = "desc", body = parsed.description.body })
  end
  for _, r in ipairs(parsed.replies) do
    local body, metas = reactions.extract_metas(r.body)
    if body ~= "" or #metas > 0 then
      table.insert(jobs, { kind = "reply", id = r.id, body = body, metas = metas })
    end
  end
  if parsed.new then
    local body = reactions.extract_metas(parsed.new.body)
    if body ~= "" then
      table.insert(jobs, { kind = "new", body = body })
    end
  end

  if #jobs == 0 then
    util.notify("no changes to push")
    return
  end

  util.async(function()
    local errors = {}
    for _, job in ipairs(jobs) do
      if job.kind == "desc" then
        local err = gitlab.update_description(iid, job.body)
        if err then
          table.insert(errors, err)
        end
      elseif job.kind == "reply" then
        if job.body ~= "" then
          local err = gitlab.reply(iid, job.id, job.body)
          if err then
            table.insert(errors, err)
          end
        end
        for _, meta in ipairs(job.metas) do
          local err = reactions.apply_meta(meta, {
            iid = iid,
            discussion_id = job.id,
            note_id = saved_ctx.thread_note[job.id],
          })
          if err then
            table.insert(errors, err)
          end
        end
      elseif job.kind == "new" then
        local err = gitlab.create_discussion(iid, job.body)
        if err then
          table.insert(errors, err)
        end
      end
    end

    if #errors > 0 then
      util.err("save completed with errors: " .. table.concat(errors, "; "))
    else
      util.notify(("pushed %d change(s)"):format(#jobs))
    end
    require("glab-review").reload()
  end)()
end

return M
