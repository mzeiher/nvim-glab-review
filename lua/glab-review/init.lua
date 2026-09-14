-- Public entry point: setup(), user-facing commands, and the sync/load flow.
local config = require("glab-review.config")
local util = require("glab-review.util")
local state = require("glab-review.state")
local gitlab = require("glab-review.gitlab")

local M = {}

-- Set once the instance has been shown not to have the drafts endpoint, so the
-- warning does not repeat on every reload. A request that merely failed does
-- not set it: the next load tries again and the configured mode stands.
local drafts_unavailable = false

--- Fetch an MR + its discussions, rebuild state, and (re)render the UI.
--- Runs inside an async coroutine.
local function load_mr(iid, opts)
  opts = opts or {}
  local err, mr = gitlab.get_mr(iid)
  if err then
    util.err(err)
    return
  end
  local derr, discussions = gitlab.get_discussions(iid)
  if derr then
    util.err(derr)
    return
  end
  -- Diffs power the change-hint gutter; a failure here is non-fatal (comments
  -- still load, just without change signs).
  local cerr, changes = gitlab.get_changes(iid)
  if cerr then
    util.notify("could not load diffs for change hints: " .. cerr, vim.log.levels.WARN)
    changes = nil
  end

  -- Pending drafts are the review you have not published yet. An instance
  -- without the endpoint loads everything else, but queueing comments there
  -- would fail on every send and lose the typed body, so drafting goes off.
  local drafts
  if not drafts_unavailable then
    local perr
    perr, drafts = gitlab.get_drafts(iid)
    if perr then
      drafts = nil
      if gitlab.endpoint_missing(perr) then
        drafts_unavailable = true
        state.set_draft_mode(false)
        local msg = "this instance has no draft notes — comments will post immediately"
        util.notify(msg, vim.log.levels.WARN)
      else
        util.notify("could not load pending drafts: " .. perr, vim.log.levels.WARN)
      end
    end
  end

  state.load(mr, discussions or {}, changes, drafts)

  local overview = require("glab-review.overview")
  local inline = require("glab-review.inline")
  -- On reload (post-mutation) re-render in place so focus stays in the buffer
  -- the user is working in; on an initial load, open and focus the overview.
  if opts.refresh then
    overview.refresh()
  else
    overview.open()
  end
  inline.refresh_all()
  require("glab-review.changes").refresh_all()

  local n_inline = 0
  for _, list in pairs(state.get().by_file) do
    n_inline = n_inline + #list
  end
  local hidden = state.hidden_count()
  local pending = state.draft_count()
  local hidden_note = hidden > 0 and (" (%d resolved hidden)"):format(hidden) or ""
  local pending_note = pending > 0 and (", %d pending"):format(pending) or ""
  util.notify(("loaded !%d — %d threads, %d inline, %d unmapped%s%s"):format(
    iid,
    #state.get().general,
    n_inline,
    #state.get().unmapped,
    hidden_note,
    pending_note))
end

--- Reload the currently loaded MR from the server (after a mutation).
M.reload = util.async(function()
  local cur = state.get()
  if not cur then
    return
  end
  load_mr(cur.mr.iid, { refresh = true })
end)

--- Explicit sync: list MRs for the current branch, pick one, load it.
M.sync = util.async(function()
  local branch, berr = util.git_branch()
  if not branch then
    util.err("could not determine git branch: " .. tostring(berr))
    return
  end

  local err, mrs = gitlab.list_mrs(branch)
  if err then
    util.err(err)
    return
  end
  if not mrs or #mrs == 0 then
    util.notify("no open MRs for branch '" .. branch .. "'")
    return
  end

  require("glab-review.picker").pick_mr(mrs, function(iid)
    util.async(load_mr)(iid)
  end)
end)

--- Open (or focus) the overview buffer for the loaded MR.
function M.open_overview()
  if not state.is_loaded() then
    util.notify("no MR loaded — run sync first")
    return
  end
  require("glab-review.overview").open()
end

--- Toggle inline comment bodies (virtual text).
function M.toggle_inline()
  require("glab-review.inline").toggle()
end

--- Toggle whether resolved threads are shown at all — in the gutter, the
--- overview and the comment picker — so settled discussions stop taking up
--- room while reviewing.
function M.toggle_resolved()
  state.set_hide_resolved(not state.hide_resolved())
  require("glab-review.inline").refresh_all()
  require("glab-review.overview").refresh()
  if state.hide_resolved() then
    util.notify(("resolved threads hidden (%d)"):format(state.hidden_count()))
  else
    util.notify("resolved threads shown")
  end
end

--- Toggle the change-hint gutter signs.
function M.toggle_changes()
  require("glab-review.changes").toggle()
end

--- Toggle the lines removed by the MR, shown inline as virtual text.
function M.toggle_removed()
  require("glab-review.changes").toggle_removed()
end

--- Preview the MR diff hunk around the cursor (shows the removed lines).
function M.hunk()
  require("glab-review.changes").preview_hunk()
end

--- Jump to the next block of lines changed by the MR (wraps).
function M.next_hunk(count)
  require("glab-review.changes").goto_hunk(1, count or vim.v.count1)
end

--- Jump to the previous block of lines changed by the MR (wraps).
function M.prev_hunk(count)
  require("glab-review.changes").goto_hunk(-1, count or vim.v.count1)
end

--- fzf-lua picker over every comment; jump to its location on select.
function M.comments()
  if not state.is_loaded() then
    util.notify("no MR loaded — run sync first")
    return
  end
  require("glab-review.picker").pick_comment()
end

--- Picker over the MR's changed files: open them or send them to quickfix.
M.changed = util.async(function()
  local cur = state.get()
  if not cur then
    util.notify("no MR loaded — run sync first")
    return
  end
  local err, files = gitlab.get_changes(cur.mr.iid)
  if err then
    util.err(err)
    return
  end
  require("glab-review.picker").pick_changed_files(files or {})
end)

--- React to the comment under the cursor (emoji picker / meta-command).
function M.react()
  require("glab-review.reactions").react_at_cursor()
end

--- Always create a new comment on the current line or selected range. `bang`
--- inverts the draft mode for this one comment.
function M.comment(line1, line2, bang)
  require("glab-review.inline").create_at_cursor(line1, line2, state.drafting(bang))
end

--- Reply to the thread under the cursor (overview thread or commented line).
function M.reply(bang)
  require("glab-review.inline").reply_at_cursor(state.drafting(bang))
end

--- Toggle the resolved state of the discussion under the cursor.
function M.resolve()
  require("glab-review.reactions").resolve_at_cursor()
end

--- Suggest a code change for the current line or selected range.
function M.suggest(line1, line2, bang)
  require("glab-review.suggest").suggest_at(line1, line2, state.drafting(bang))
end

--- Toggle whether new comments queue as drafts or post immediately.
function M.toggle_draft()
  state.set_draft_mode(not state.draft_mode())
  if not state.draft_mode() then
    util.notify("comments post immediately")
    return
  end
  util.notify("comments queue as drafts — :GlabReviewSubmit publishes them")
  -- Asking for drafting again is also asking to retry an endpoint that failed;
  -- the reload reports what is actually pending.
  local retry = drafts_unavailable
  drafts_unavailable = false
  if retry and state.is_loaded() then
    M.reload()
  end
end

-- The pending draft the cursor is on: a line in the overview's pending section,
-- or a drafted line in a code buffer.
local function draft_at_cursor()
  local id = require("glab-review.overview").draft_at_cursor()
  if id then
    return id
  end
  local path = util.repo_relative(vim.api.nvim_buf_get_name(0))
  if not path then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  for _, item in ipairs(state.drafts_for_path(path)) do
    if item.line == line then
      return item.draft.id
    end
  end
  return nil
end

--- Discard the pending draft under the cursor, or every one with `bang`.
M.discard = util.async(function(bang)
  local cur = state.get()
  if not cur then
    util.notify("no MR loaded — run sync first")
    return
  end
  local ids = {}
  if bang then
    if state.draft_count() == 0 then
      util.notify("no pending comments to discard")
      return
    end
    local question = ("Discard all %d pending comment(s)?"):format(state.draft_count())
    local choice = util.await(function(resume)
      vim.schedule(function()
        resume(vim.fn.confirm(question, "&Yes\n&No", 2))
      end)
    end)
    if choice ~= 1 then
      return
    end
    for _, d in ipairs(state.drafts()) do
      ids[#ids + 1] = d.id
    end
  else
    local id = draft_at_cursor()
    if not id then
      util.notify("no pending comment under the cursor")
      return
    end
    ids[1] = id
  end

  -- Keep going after a failure and reload regardless: stopping early would
  -- leave the drafts already deleted on the server showing in the UI.
  local done, failed, gone = 0, nil, {}
  for _, id in ipairs(ids) do
    local err = gitlab.delete_draft(cur.mr.iid, id)
    if err then
      failed = failed or err
    else
      done = done + 1
      gone[#gone + 1] = id
    end
  end
  require("glab-review.overview").forget_drafts(gone)
  if failed then
    util.err(("discarded %d of %d — %s"):format(done, #ids, failed))
  else
    util.notify(("discarded %d pending comment(s)"):format(done))
  end
  M.reload()
end)

--- Submit a review verdict: approve, request changes, or comment.
function M.submit()
  require("glab-review.submit").submit()
end

local function apply_keymaps()
  local km = config.get().keymaps
  if not km then
    return
  end
  local map = function(lhs, fn, desc)
    if lhs then
      vim.keymap.set("n", lhs, fn, { desc = desc, silent = true })
    end
  end
  map(km.sync, M.sync, "glab-review: sync MRs")
  map(km.overview, M.open_overview, "glab-review: open overview")
  map(km.toggle_inline, M.toggle_inline, "glab-review: toggle inline comments")
  map(km.toggle_resolved, M.toggle_resolved, "glab-review: toggle resolved threads")
  map(km.toggle_changes, M.toggle_changes, "glab-review: toggle change hints")
  map(km.toggle_removed, M.toggle_removed, "glab-review: toggle removed lines inline")
  map(km.hunk, M.hunk, "glab-review: preview MR diff hunk at cursor")
  map(km.next_hunk, M.next_hunk, "glab-review: next MR change")
  map(km.prev_hunk, M.prev_hunk, "glab-review: previous MR change")
  map(km.comments, M.comments, "glab-review: comment picker")
  map(km.changed, M.changed, "glab-review: changed files picker")
  map(km.react, M.react, "glab-review: react at cursor")
  map(km.comment, M.comment, "glab-review: new inline comment")
  map(km.reply, M.reply, "glab-review: reply to thread under cursor")
  map(km.resolve, M.resolve, "glab-review: resolve/unresolve thread under cursor")
  map(km.suggest, M.suggest, "glab-review: suggest change for current line")
  map(km.submit, M.submit, "glab-review: submit review verdict")
  map(km.toggle_draft, M.toggle_draft, "glab-review: toggle drafting of new comments")
  map(km.discard, M.discard, "glab-review: discard the pending comment at the cursor")
  -- Visual-mode: comment on / suggest a change for the selected range.
  if km.comment then
    vim.keymap.set("x", km.comment, ":GlabReviewComment<CR>", {
      desc = "glab-review: comment on selection",
      silent = true,
    })
  end
  if km.suggest then
    vim.keymap.set("x", km.suggest, ":GlabReviewSuggest<CR>", {
      desc = "glab-review: suggest change for selection",
      silent = true,
    })
  end
end

function M.setup(opts)
  config.setup(opts)
  state.set_hide_resolved(config.get().hide_resolved)
  state.set_draft_mode(config.get().draft)
  require("glab-review.inline").setup()
  require("glab-review.changes").setup()
  apply_keymaps()
end

return M
