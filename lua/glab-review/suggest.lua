-- GitLab code suggestions: turn the current line / visual selection into a
-- ```suggestion``` comment the author can apply with one click.
--
-- The selected lines are copied into a scratch buffer wrapped in a
-- ```suggestion:-N+0``` fence anchored at the LAST selected line (N lines
-- above it through itself are replaced). The user edits the replacement in
-- place, optionally adds comment text above the fence, and :w posts the whole
-- buffer as the note body.
local state = require("glab-review.state")
local util = require("glab-review.util")

local M = {}

local ns

--- Open the suggestion editor for buffer lines [line1, line2] of the current
--- code buffer (both default to the cursor line).
function M.suggest_at(line1, line2)
  local cur = state.get()
  if not cur then
    util.notify("no MR loaded — run sync first")
    return
  end
  if not cur.diff_refs or not cur.diff_refs.head_sha then
    util.err("MR has no diff refs; cannot anchor a suggestion")
    return
  end
  local src = vim.api.nvim_get_current_buf()
  local path = util.repo_relative(vim.api.nvim_buf_get_name(src))
  if not path then
    util.err("current buffer is not inside the repo")
    return
  end
  line1 = line1 or vim.api.nvim_win_get_cursor(0)[1]
  line2 = line2 or line1
  local selected = vim.api.nvim_buf_get_lines(src, line1 - 1, line2, false)

  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, ("glab-review://suggest/%s:%d-%d"):format(path, line1, line2))
  local content = { ("```suggestion:-%d+0"):format(line2 - line1) }
  vim.list_extend(content, selected)
  content[#content + 1] = "```"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modified = false

  ns = ns or vim.api.nvim_create_namespace("glab-review-suggest")
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
    virt_lines = {
      {
        {
          ("Suggestion for %s:%d-%d — edit the replacement inside the fence, add comment text above it. :w posts, :q! aborts."):format(
            path,
            line1,
            line2
          ),
          "Comment",
        },
      },
    },
    virt_lines_above = true,
  })

  local iid, diff_refs = cur.mr.iid, cur.diff_refs
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      if vim.trim(body) == "" then
        util.notify("empty suggestion — not posted")
        return
      end
      -- Cleared optimistically so :wq works; posting happens async below.
      vim.bo[buf].modified = false
      util.async(function()
        local err = require("glab-review.inline").post_inline(iid, path, line2, body, diff_refs)
        if err then
          util.err("failed to post suggestion: " .. err)
          return
        end
        util.notify("suggestion posted")
        if vim.api.nvim_buf_is_valid(buf) then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
        require("glab-review").reload()
      end)()
    end,
  })

  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_height(0, math.max(6, math.min(#content + 2, 15)))
  -- Cursor on the first replacement line, ready to edit.
  vim.api.nvim_win_set_cursor(0, { math.min(2, #content), 0 })
end

return M
