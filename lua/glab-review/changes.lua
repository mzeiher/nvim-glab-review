-- Gutter hints for the lines changed by the loaded MR (added / changed /
-- deleted relative to the MR's base), shown as gitsigns-style signs. Only the
-- affected lines are marked — there is no full-diff view. Anchored 1:1 by
-- new-side line number, so signs are accurate when the working tree matches the
-- MR head commit (same caveat as inline comments).
--
-- The buffer shows the new side only, so lines the MR *removed* exist nowhere in
-- it. That content is reachable three ways, quietest first: the delete sign
-- carries how many lines went away, `preview_hunk()` shows the hunk in a float
-- on demand, and `toggle_removed()` inlines the removed lines as virtual text
-- above where they were (off by default — it shifts the code down while on).
local state = require("glab-review.state")
local config = require("glab-review.config")
local util = require("glab-review.util")

local M = {}

local ns
local augroup
local enabled = true
local show_removed = false

function M.setup()
  ns = vim.api.nvim_create_namespace("glab-review-changes")
  enabled = config.get().changes.enabled
  show_removed = config.get().changes.show_removed
  augroup = vim.api.nvim_create_augroup("glab-review-changes", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufEnter" }, {
    group = augroup,
    callback = function(ev)
      if state.is_loaded() then
        M.place(ev.buf)
      end
    end,
  })
end

--- Place change-hint signs for the loaded MR in buffer `bufnr`.
function M.place(bufnr, root)
  if not ns or not state.is_loaded() then
    return
  end
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  -- The two layers toggle independently: signs in the gutter, removed lines as
  -- virtual text. With both off there is nothing to draw.
  if not enabled and not show_removed then
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
  local signs = state.changes_for_path(path)
  if #signs == 0 then
    return
  end

  local cfg = config.get().changes
  local style = {
    add = { text = cfg.add_sign, hl = cfg.add_hl },
    change = { text = cfg.change_sign, hl = cfg.change_hl },
    delete = { text = cfg.delete_sign, hl = cfg.delete_hl },
  }
  local n_lines = vim.api.nvim_buf_line_count(bufnr)
  for _, s in ipairs(signs) do
    local st = style[s.kind]
    -- Clamp to the buffer (a delete at EOF anchors past the last line).
    local clamped = math.min(s.line, n_lines)
    local row = clamped - 1
    if st and row >= 0 then
      local opts = {
        -- Below inline-comment signs (priority 200) so a commented line keeps
        -- its comment marker when both want the gutter.
        priority = 190,
      }
      if enabled then
        opts.sign_text = M.sign_text(st.text, s, cfg)
        opts.sign_hl_group = st.hl
      end
      if show_removed and s.removed then
        opts.virt_lines = M.removed_virt_lines(s.removed, bufnr, cfg)
        -- Above the line that took the removed content's place — except for a
        -- delete clamped to EOF, where "above the last line" would be wrong.
        opts.virt_lines_above = s.line <= n_lines
      end
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row, 0, opts)
    end
  end
end

--- Virtual lines rendering the old-side text a change hint stands in for.
--- Tabs are expanded because virtual text does not honour 'tabstop'.
--- @return table  list of virt_line chunk lists
function M.removed_virt_lines(removed, bufnr, cfg)
  local ts = vim.bo[bufnr].tabstop
  local pad = string.rep(" ", ts > 0 and ts or 8)
  local out = {}
  for _, text in ipairs(removed) do
    out[#out + 1] = { { cfg.removed_prefix .. text:gsub("\t", pad), cfg.removed_hl } }
  end
  return out
end

--- Sign text for one change hint. A delete marker stands in for content that is
--- not in the buffer at all, so with `delete_count` it also reports how many
--- lines were removed there ("9+" for ten or more). The count is only appended
--- when it fits: 'signcolumn' cells are two columns wide.
--- @return string
function M.sign_text(text, sign, cfg)
  local n = sign.kind == "delete" and sign.removed and #sign.removed or 0
  if not cfg.delete_count or n == 0 or vim.fn.strdisplaywidth(text) > 1 then
    return text
  end
  return text .. (n > 9 and "+" or tostring(n))
end

--- Re-render every loaded buffer that maps to a changed file.
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

--- Toggle the change hints on/off.
function M.toggle()
  enabled = not enabled
  M.refresh_all()
  util.notify("change hints " .. (enabled and "shown" or "hidden"))
end

--- Toggle the removed lines as virtual text above where they were. Independent
--- of the gutter signs: while on, the code below each removal is pushed down by
--- as many lines as the MR deleted there.
function M.toggle_removed()
  show_removed = not show_removed
  M.refresh_all()
  util.notify("removed lines " .. (show_removed and "shown inline" or "hidden"))
end

--- Show the MR diff hunk around the cursor in a float: the added lines as they
--- are in the buffer plus the removed lines, which the working tree does not
--- have. Nothing is written into the buffer, so the code stays where it is.
function M.preview_hunk()
  if not state.is_loaded() then
    util.notify("no MR loaded — run sync first")
    return
  end
  local path = util.repo_relative(vim.api.nvim_buf_get_name(0))
  if not path then
    util.err("current buffer is not inside the repo")
    return
  end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local hunks = state.hunks_for_path(path)
  if #hunks == 0 then
    util.notify(("%s is not changed by this MR"):format(path))
    return
  end
  local hunk = require("glab-review.diff").hunk_at(hunks, line)
  if not hunk then
    util.notify("no MR change around this line")
    return
  end

  local lines = { hunk.header }
  vim.list_extend(lines, hunk.lines)
  -- Rendered as a `diff` buffer so +/- lines get the usual diff highlighting.
  -- Hover convention: the first call opens the float, a second one enters it
  -- (so a long hunk can be scrolled); it closes on cursor move otherwise.
  vim.lsp.util.open_floating_preview(lines, "diff", {
    border = "rounded",
    focus_id = "glab-review-hunk",
    title = (" %s "):format(path),
  })
end

return M
