-- User commands. Loading is lazy: requiring the module only happens when a
-- command runs, so merely having the plugin on the runtimepath is cheap.
if vim.g.loaded_glab_review then
  return
end
vim.g.loaded_glab_review = true

if vim.fn.has("nvim-0.10") == 0 then
  vim.notify("[glab-review] requires Neovim 0.10+", vim.log.levels.ERROR)
  return
end

local function cmd(name, fn, desc)
  vim.api.nvim_create_user_command(name, function()
    require("glab-review")[fn]()
  end, { desc = desc })
end

cmd("GlabReviewSync", "sync", "Sync MRs for the current branch and pick one")
cmd("GlabReviewOverview", "open_overview", "Open the MR overview (description + threads)")
cmd("GlabReviewToggleInline", "toggle_inline", "Toggle inline comment virtual text")
cmd("GlabReviewComments", "comments", "Pick and jump to any MR comment")
cmd("GlabReviewChanged", "changed", "Pick changed files (open or send to quickfix)")
cmd("GlabReviewReact", "react", "React to the comment under the cursor")
cmd("GlabReviewComment", "comment", "Create an inline comment on the current line")
