-- Public entry point: setup(), user-facing commands, and the sync/load flow.
local config = require("glab-review.config")
local util = require("glab-review.util")
local state = require("glab-review.state")
local gitlab = require("glab-review.gitlab")

local M = {}

--- Fetch an MR + its discussions, rebuild state, and (re)render the UI.
--- Runs inside an async coroutine.
local function load_mr(iid)
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

  state.load(mr, discussions or {})

  local overview = require("glab-review.overview")
  local inline = require("glab-review.inline")
  overview.open()
  inline.refresh_all()

  local n_inline = 0
  for _, list in pairs(state.get().by_file) do
    n_inline = n_inline + #list
  end
  util.notify(("loaded !%d — %d threads, %d inline, %d unmapped"):format(
    iid, #state.get().general, n_inline, #state.get().unmapped))
end

--- Reload the currently loaded MR from the server (after a mutation).
M.reload = util.async(function()
  local cur = state.get()
  if not cur then
    return
  end
  load_mr(cur.mr.iid)
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

--- Always create a new comment on the current line or selected range.
function M.comment(line1, line2)
  require("glab-review.inline").create_at_cursor(line1, line2)
end

--- Reply to the thread under the cursor (overview thread or commented line).
function M.reply()
  require("glab-review.inline").reply_at_cursor()
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
  map(km.comments, M.comments, "glab-review: comment picker")
  map(km.changed, M.changed, "glab-review: changed files picker")
  map(km.react, M.react, "glab-review: react at cursor")
  map(km.comment, M.comment, "glab-review: new inline comment")
  map(km.reply, M.reply, "glab-review: reply to thread under cursor")
  -- Visual-mode: comment on the selected range (multi-line comment).
  if km.comment then
    vim.keymap.set("x", km.comment, ":GlabReviewComment<CR>", {
      desc = "glab-review: comment on selection",
      silent = true,
    })
  end
end

function M.setup(opts)
  config.setup(opts)
  require("glab-review.inline").setup()
  apply_keymaps()
end

return M
