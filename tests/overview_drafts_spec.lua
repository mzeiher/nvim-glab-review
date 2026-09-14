-- Headless test that the overview tracks pending drafts by extmark, so an edit
-- above them cannot point `:GlabReviewDiscard` at the wrong one.
-- Run from the repo root with `make test`, or directly:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/overview_drafts_spec.lua"
-- Exits non-zero on failure.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local failures = 0
local function check(name, cond, got)
  if cond then
    io.write("ok   - " .. name .. "\n")
  else
    failures = failures + 1
    local at = got ~= nil and ("  [got " .. tostring(got) .. "]") or ""
    io.write("FAIL - " .. name .. at .. "\n")
  end
end

require("glab-review.config").setup({})
local state = require("glab-review.state")
local overview = require("glab-review.overview")

local mr = {
  iid = 7,
  title = "T",
  state = "opened",
  author = { username = "a" },
  web_url = "http://x",
  description = "desc",
  diff_refs = { base_sha = "b", head_sha = "h", start_sha = "s" },
}
local discussions = {
  {
    id = "t1",
    resolvable = true,
    resolved = false,
    notes = { { id = 1, body = "posted", author = { username = "alice" } } },
  },
}
local drafts = {
  { id = 5, note = "first pending", position = { new_path = "lua/a.lua", new_line = 3 } },
  { id = 6, note = "second pending" },
}

state.load(mr, discussions, nil, drafts)
overview.open()

local buf = vim.api.nvim_get_current_buf()
local function line_of(text)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:find(text, 1, true) then
      return i
    end
  end
end

check("the pending section is rendered", line_of("## Pending review (2)") ~= nil)

local second = line_of("second pending")
vim.api.nvim_win_set_cursor(0, { second, 0 })
check("cursor on a draft finds it", overview.draft_at_cursor() == 6, overview.draft_at_cursor())

-- Type a reply into the thread's region, which sits above the pending section.
local reply_at = line_of("glab-review:reply")
vim.api.nvim_buf_set_lines(buf, reply_at, reply_at, false, { "a", "reply", "of three lines" })

check("the draft moved down with the edit", line_of("second pending") == second + 3)
vim.api.nvim_win_set_cursor(0, { second + 3, 0 })
check("it is still the same draft", overview.draft_at_cursor() == 6, overview.draft_at_cursor())
vim.api.nvim_win_set_cursor(0, { second, 0 })
local stale = overview.draft_at_cursor()
check("the old line is no longer that draft", stale ~= 6, stale)

-- Deleting the edit again puts everything back where it was rendered.
vim.api.nvim_buf_set_lines(buf, reply_at, reply_at + 3, false, {})
vim.api.nvim_win_set_cursor(0, { second, 0 })
local back = overview.draft_at_cursor()
check("undoing the edit restores the mapping", back == 6, back)

-- A discarded draft must stop answering to the cursor even though the buffer
-- has unsaved edits and so is never re-rendered.
vim.api.nvim_buf_set_lines(buf, reply_at, reply_at, false, { "an edit" })
overview.forget_drafts({ 6 })
vim.api.nvim_win_set_cursor(0, { line_of("second pending"), 0 })
local forgotten = overview.draft_at_cursor()
check("a discarded draft is forgotten", forgotten == nil, forgotten)
vim.api.nvim_win_set_cursor(0, { line_of("first pending"), 0 })
local other = overview.draft_at_cursor()
check("the other draft is untouched", other == 5, other)

if failures > 0 then
  io.write(("\n%d failure(s)\n"):format(failures))
  vim.cmd("cquit 1")
else
  io.write("\nall passed\n")
  -- `quit` would only close the split the overview opened.
  vim.cmd("qall!")
end
