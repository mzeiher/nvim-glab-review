-- Submit a review verdict on the loaded MR: approve, request changes, or
-- just leave a general comment (plus unapprove to take an approval back).
local state = require("glab-review.state")
local gitlab = require("glab-review.gitlab")
local util = require("glab-review.util")

local M = {}

-- "group/project" path of the MR, needed for GraphQL calls. Derived from
-- `references.full` ("group/project!42"), falling back to the web URL.
local function project_path(mr)
  local full = mr.references and mr.references.full or ""
  local p = full:match("^(.+)!%d+$")
  return p or (mr.web_url or ""):match("^https?://[^/]+/(.-)/%-/merge_requests")
end

local ACTIONS = {
  { label = "Approve", done = "approved" },
  { label = "Request changes", done = "changes requested" },
  { label = "Comment", done = "commented" },
  { label = "Unapprove", done = "approval revoked" },
}

--- Pick a verdict, optionally attach a comment, and send both. Any pending
--- drafts are published first, with the comment as the review's summary note.
function M.submit()
  local cur = state.get()
  local mr = cur and cur.mr
  if not cur or not mr then
    util.notify("no MR loaded — run sync first")
    return
  end
  local head_sha = cur.diff_refs and cur.diff_refs.head_sha
  local pending = state.draft_count()

  local actions = vim.deepcopy(ACTIONS)
  if pending > 0 then
    table.insert(actions, { label = "Publish pending", done = "review published" })
  end

  vim.ui.select(actions, {
    prompt = ("Review !%d: %s%s"):format(
      mr.iid,
      mr.title or "",
      pending > 0 and (" — %d pending"):format(pending) or ""
    ),
    format_item = function(a)
      return a.label
    end,
  }, function(action)
    if not action then
      return
    end
    local prompt = action.label == "Comment" and "Comment > " or "Comment (optional) > "
    vim.ui.input({ prompt = prompt }, function(input)
      if input == nil then
        return -- aborted
      end
      local body = vim.trim(input)
      if action.label == "Comment" and body == "" then
        util.notify("empty comment — nothing sent")
        return
      end
      util.async(function()
        -- Ask the server what is pending rather than trusting the last sync:
        -- drafts outlive a session, and a load that failed once leaves the
        -- cached count at zero — approving on that would publish nothing.
        local ferr, live = gitlab.get_drafts(mr.iid)
        if ferr and not gitlab.endpoint_missing(ferr) then
          -- Guessing either way is worse than stopping: a stale zero approves
          -- over pending comments, a stale count blocks the verdict entirely.
          util.err("could not check for pending comments, nothing sent: " .. ferr)
          return
        end
        local n = live and #live or 0
        -- Taking an approval back is not the end of a review, so it leaves the
        -- pending comments pending; every other verdict releases them.
        local publish = n > 0 and action.label ~= "Unapprove"
        if action.label == "Publish pending" and n == 0 then
          util.notify("nothing pending — the review was already published")
          return
        end

        -- Publish before the verdict: an approval must never land while the
        -- comments it was based on are still pending. With drafts waiting, the
        -- comment rides along as the review's summary note.
        if publish then
          local perr = gitlab.publish_drafts(mr.iid, body)
          if perr then
            util.err("failed to publish pending comments: " .. perr)
            return
          end
        elseif body ~= "" then
          local err = gitlab.create_discussion(mr.iid, body)
          if err then
            util.err(err)
            return
          end
        end
        local err
        if action.label == "Approve" then
          -- Tie the approval to the head we reviewed; GitLab rejects it
          -- with a 409 if the MR gained commits since the last sync.
          err = gitlab.approve(mr.iid, head_sha)
        elseif action.label == "Unapprove" then
          err = gitlab.unapprove(mr.iid)
        elseif action.label == "Request changes" then
          local pp = project_path(mr)
          if not pp then
            err = "cannot determine the project path of this MR"
          else
            err = gitlab.request_changes(pp, mr.iid)
          end
        end
        if err then
          util.err(err)
          return
        end
        local published = publish and (" (%d comment(s) published)"):format(n) or ""
        util.notify(("!%d: %s%s"):format(mr.iid, action.done, published))
        require("glab-review").reload()
      end)()
    end)
  end)
end

return M
