-- Gutter hints for the lines changed by the loaded MR (added / changed /
-- deleted relative to the MR's base), shown as gitsigns-style signs. Only the
-- affected lines are marked — there is no full-diff view. Anchored 1:1 by
-- new-side line number, so signs are accurate when the working tree matches the
-- MR head commit (same caveat as inline comments).
local state = require("glab-review.state")
local config = require("glab-review.config")
local util = require("glab-review.util")

local M = {}

local ns
local augroup
local enabled = true

function M.setup()
  ns = vim.api.nvim_create_namespace("glab-review-changes")
  enabled = config.get().changes.enabled
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
  if not enabled then
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
    local row = math.min(s.line, n_lines) - 1
    if st and row >= 0 then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row, 0, {
        sign_text = st.text,
        sign_hl_group = st.hl,
        -- Below inline-comment signs (priority 200) so a commented line keeps
        -- its comment marker when both want the gutter.
        priority = 190,
      })
    end
  end
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

return M
