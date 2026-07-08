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

--- Create a discussion with a prebuilt diff `position`.
function M.create_positioned(iid, body, position)
  return glab.api_await(("%s/%d/discussions"):format(BASE, iid), {
    method = "POST",
    body = { body = body, position = position },
  })
end

--- Create a single-line inline discussion anchored to `path`:`new_line`.
--- Lines the MR did not change must also carry their old-side position
--- (GitLab requires both `old_line` and `new_line` there); pass `old_line`
--- as nil only for lines added by the MR. `old_path` covers renames.
function M.create_inline(iid, body, path, new_line, diff_refs, old_line, old_path)
  return M.create_positioned(iid, body, {
    position_type = "text",
    base_sha = diff_refs.base_sha,
    head_sha = diff_refs.head_sha,
    start_sha = diff_refs.start_sha,
    new_path = path,
    old_path = old_path or path,
    new_line = new_line,
    old_line = old_line,
  })
end

--- Approve the MR. Passing `sha` (the head commit you reviewed) makes GitLab
--- reject the approval with a 409 if the MR moved on in the meantime.
function M.approve(iid, sha)
  return glab.api_await(("%s/%d/approve"):format(BASE, iid), {
    method = "POST",
    body = sha and { sha = sha } or nil,
  })
end

--- Revoke the current user's approval of the MR.
function M.unapprove(iid)
  return glab.api_await(("%s/%d/unapprove"):format(BASE, iid), { method = "POST" })
end

--- Set the current user's reviewer state to "requested changes" (blocks the
--- merge). There is no REST endpoint for this — it exists only as a GraphQL
--- mutation (GitLab 16.11+), which needs the full project path.
function M.request_changes(project_path, iid)
  local q = ('mutation { mergeRequestRequestChanges(input: { projectPath: "%s", iid: "%d" }) { errors } }')
    :format(project_path, iid)
  local err, res = glab.graphql_await(q)
  if err then
    return err
  end
  if res and res.errors and res.errors[1] then
    return res.errors[1].message or "GraphQL error"
  end
  local errs = res
    and res.data
    and res.data.mergeRequestRequestChanges
    and res.data.mergeRequestRequestChanges.errors
  if errs and errs[1] then
    return table.concat(errs, "; ")
  end
  return nil
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
