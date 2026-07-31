-- User configuration with sensible defaults.
local M = {}

local defaults = {
  -- Executable used for all API access.
  glab_cmd = "glab",

  -- Start with resolved threads hidden everywhere (gutter, overview, picker).
  -- Toggle at runtime with `:GlabReviewToggleResolved`.
  hide_resolved = false,

  -- Award emojis offered in the fzf-lua reaction picker.
  -- Each entry is "<display> <api_name>"; only the api_name is sent to GitLab.
  emojis = {
    "👍 thumbsup",
    "👎 thumbsdown",
    "✅ white_check_mark",
    "🎉 tada",
    "👀 eyes",
    "🚀 rocket",
    "❤️ heart",
    "🤔 thinking",
  },

  -- Text meta-commands usable in the reaction input and in overview reply
  -- blocks. `award` adds an emoji to the targeted note; `resolve` toggles the
  -- thread's resolved state.
  meta_commands = {
    ["/react-check"] = { award = "white_check_mark" },
    ["/react-up"] = { award = "thumbsup" },
    ["/react-eyes"] = { award = "eyes" },
    ["/resolve"] = { resolve = true },
    ["/unresolve"] = { resolve = false },
  },

  overview = {
    -- How to open the overview window when it is not already visible:
    --   "vsplit"  vertical split (default)
    --   "split"   horizontal split
    --   "tab"     new tab page
    --   "current" reuse the current window
    open = "vsplit",
  },

  inline = {
    -- Whether comment bodies (virt_lines) are shown immediately after load.
    virt_text_default = true,
    -- Gutter sign placed on commented lines (diagnostics-style).
    sign_text = "▌",
    sign_hl = "DiagnosticSignInfo",
    virt_hl = "Comment",
    author_hl = "DiagnosticInfo",
  },

  -- Gutter hints marking the lines changed by the MR (relative to its base),
  -- gitsigns-style. Only affected lines are marked; there is no full-diff view.
  changes = {
    -- Whether change hints are shown immediately after load.
    enabled = true,
    -- Signs for added / changed (replacing a deletion) / deleted lines.
    add_sign = "▎",
    change_sign = "▎",
    delete_sign = "▁",
    add_hl = "DiagnosticSignOk",
    change_hl = "DiagnosticSignWarn",
    delete_hl = "DiagnosticSignError",
    -- Append the number of removed lines to a delete sign ("▁3", "▁+" for 10+),
    -- since removed content is invisible in the working tree. Only applied when
    -- `delete_sign` is a single cell wide.
    delete_count = true,
    -- Show the lines the MR removed as virtual text above where they were.
    -- Off by default: it pushes the code below each removal down. Toggle with
    -- `:GlabReviewToggleRemoved`.
    show_removed = false,
    removed_prefix = "- ",
    removed_hl = "DiffDelete",
  },

  -- Default key mappings, applied on setup(). Set `keymaps = false` to disable
  -- and map the public functions yourself.
  keymaps = {
    sync = "<leader>gms",
    overview = "<leader>gmo",
    toggle_inline = "<leader>gmt",
    toggle_resolved = "<leader>gmT",
    toggle_changes = "<leader>gmd",
    toggle_removed = "<leader>gmD",
    hunk = "<leader>gmh",
    -- Hunk motions: repeated often, so they get bracket keys rather than a
    -- leader chord. Accept a count (`3]h`).
    next_hunk = "]h",
    prev_hunk = "[h",
    comments = "<leader>gmc",
    changed = "<leader>gmf",
    react = "<leader>gmr",
    comment = "<leader>gmn",
    reply = "<leader>gmR",
    resolve = "<leader>gmx",
    suggest = "<leader>gmS",
    submit = "<leader>gma",
  },
}

local options = vim.deepcopy(defaults)

function M.setup(opts)
  options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  return options
end

function M.get()
  return options
end

return M
