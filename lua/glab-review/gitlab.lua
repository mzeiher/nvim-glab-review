-- High-level GitLab merge-request operations, expressed as coroutine-friendly
-- functions (call inside `util.async`; each returns `err, data`).
--
-- All endpoints use the `:fullpath` placeholder, which `glab` expands to the
-- current repo's URL-encoded project path.
local glab = require("glab-review.glab")
local util = require("glab-review.util")

local M = {}

local BASE = "projects/:fullpath/merge_requests"

--- Open MRs whose source branch matches `branch`.
function M.list_mrs(branch)
  local path = ("%s?state=opened&source_branch=%s&per_page=50"):format(BASE, util.urlencode(branch))
  return glab.api_await(path, { paginate = true })
end

--- Full MR object (includes `diff_refs` and `description`).
function M.get_mr(iid)
  return glab.api_await(("%s/%d"):format(BASE, iid), {})
end

--- All discussions (threads) for an MR, following pagination.
function M.get_discussions(iid)
  return glab.api_await(("%s/%d/discussions?per_page=100"):format(BASE, iid), { paginate = true })
end

--- Create a new top-level discussion (general thread) on the MR.
function M.create_discussion(iid, body)
  return glab.api_await(("%s/%d/discussions"):format(BASE, iid), {
    method = "POST",
    body = { body = body },
  })
end

--- Reply to an existing discussion.
function M.reply(iid, discussion_id, body)
  return glab.api_await(("%s/%d/discussions/%s/notes"):format(BASE, iid, discussion_id), {
    method = "POST",
    body = { body = body },
  })
end

--- Resolve or unresolve a (resolvable) discussion.
function M.set_resolved(iid, discussion_id, resolved)
  local path = ("%s/%d/discussions/%s?resolved=%s"):format(BASE, iid, discussion_id, tostring(resolved))
  return glab.api_await(path, { method = "PUT" })
end

--- Add an award emoji to a note.
function M.award(iid, note_id, name)
  return glab.api_await(("%s/%d/notes/%d/award_emoji"):format(BASE, iid, note_id), {
    method = "POST",
    body = { name = name },
  })
end

--- Create a positioned (inline) discussion anchored to `path`:`new_line`.
--- `diff_refs` comes from the loaded MR. Works for lines present in the MR
--- diff's new revision; context/unchanged lines may also need `old_line`.
function M.create_inline(iid, body, path, new_line, diff_refs)
  local position = {
    position_type = "text",
    base_sha = diff_refs.base_sha,
    head_sha = diff_refs.head_sha,
    start_sha = diff_refs.start_sha,
    new_path = path,
    old_path = path,
    new_line = new_line,
  }
  return glab.api_await(("%s/%d/discussions"):format(BASE, iid), {
    method = "POST",
    body = { body = body, position = position },
  })
end

--- Files changed in the MR. Returns the `/diffs` list: each entry has
--- new_path, old_path, new_file, renamed_file, deleted_file, ...
function M.get_changes(iid)
  return glab.api_await(("%s/%d/diffs?per_page=100"):format(BASE, iid), { paginate = true })
end

--- Update the MR description.
function M.update_description(iid, description)
  return glab.api_await(("%s/%d"):format(BASE, iid), {
    method = "PUT",
    body = { description = description },
  })
end

return M
