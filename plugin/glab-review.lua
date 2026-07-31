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
cmd("GlabReviewToggleResolved", "toggle_resolved", "Show/hide resolved threads everywhere")
cmd("GlabReviewToggleChanges", "toggle_changes", "Toggle change-hint gutter signs")
cmd("GlabReviewToggleRemoved", "toggle_removed", "Toggle the MR's removed lines shown inline")
cmd("GlabReviewHunk", "hunk", "Preview the MR diff hunk at the cursor (incl. removed lines)")

-- Count-aware motions: `:3GlabReviewNextHunk` skips ahead three changes.
local function motion(name, fn, desc)
  vim.api.nvim_create_user_command(name, function(o)
    require("glab-review")[fn](o.count > 0 and o.count or 1)
  end, { count = true, desc = desc })
end

motion("GlabReviewNextHunk", "next_hunk", "Jump to the next block of lines changed by the MR")
motion("GlabReviewPrevHunk", "prev_hunk", "Jump to the previous block of lines changed by the MR")
cmd("GlabReviewComments", "comments", "Pick and jump to any MR comment")
cmd("GlabReviewChanged", "changed", "Pick changed files (open or send to quickfix)")
cmd("GlabReviewReact", "react", "React to the comment under the cursor")

-- Range-aware: a visual selection comments on the whole range (multi-line).
vim.api.nvim_create_user_command("GlabReviewComment", function(o)
  if o.range == 2 then
    require("glab-review").comment(o.line1, o.line2)
  else
    require("glab-review").comment()
  end
end, { range = true, desc = "Create a new comment on the current line or selection" })

cmd("GlabReviewReply", "reply", "Reply to the thread under the cursor")
cmd("GlabReviewResolve", "resolve", "Toggle resolved state of the discussion under the cursor")
cmd("GlabReviewSubmit", "submit", "Submit a review verdict: approve, request changes, or comment")

-- Range-aware: a visual selection suggests a replacement for the whole range.
vim.api.nvim_create_user_command("GlabReviewSuggest", function(o)
  if o.range == 2 then
    require("glab-review").suggest(o.line1, o.line2)
  else
    require("glab-review").suggest()
  end
end, { range = true, desc = "Suggest a code change for the current line or selection" })
