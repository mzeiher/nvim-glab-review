-- Unified-diff parsing helpers.
local M = {}

--- Map new-side line numbers to their old-side position, mirroring how GitLab
--- derives diff line codes (`<sha1(path)>_<old>_<new>`).
---
--- Context and added lines live on the new side and are recorded; deleted
--- lines advance only the old-side counter. For an added line the old position
--- is the current (not-yet-consumed) old line, matching GitLab.
---
--- @param diff_text string  a unified diff body (as returned in `/diffs`)
--- @return table  map[new_line] = old_position
function M.new_line_map(diff_text)
  local map = {}
  local old_ln, new_ln
  for line in (diff_text .. "\n"):gmatch("(.-)\n") do
    local a, c = line:match("^@@ %-(%d+),?%d* %+(%d+),?%d* @@")
    if a then
      old_ln, new_ln = tonumber(a), tonumber(c)
    elseif old_ln then
      local tag = line:sub(1, 1)
      if tag == " " then
        map[new_ln] = old_ln
        old_ln, new_ln = old_ln + 1, new_ln + 1
      elseif tag == "+" then
        map[new_ln] = old_ln
        new_ln = new_ln + 1
      elseif tag == "-" then
        old_ln = old_ln + 1
      end
      -- "\ No newline at end of file" and anything else is ignored
    end
  end
  return map
end

--- Old-side line number of a new-side line, for building comment positions.
---
--- GitLab's discussions API addresses added lines with `new_line` only, but
--- lines unchanged by the MR need BOTH `old_line` and `new_line`. This walks
--- the hunks tracking the old/new counters; for new-side lines outside any
--- hunk the old line is extrapolated from the surrounding hunks' offset.
---
--- @param diff_text string  a unified diff body (as returned in `/diffs`)
--- @param new_line integer  1-based new-side line number
--- @return integer|nil old_line  nil when the MR added that line
function M.old_line_of(diff_text, new_line)
  local offset = 0 -- old - new, valid in unchanged regions between hunks
  local old_ln, new_ln
  for line in (diff_text .. "\n"):gmatch("(.-)\n") do
    local a, c = line:match("^@@ %-(%d+),?%d* %+(%d+),?%d* @@")
    if a then
      old_ln, new_ln = tonumber(a), tonumber(c)
      if new_line < new_ln then
        break -- target sits in the unchanged region before this hunk
      end
    elseif old_ln then
      local tag = line:sub(1, 1)
      if tag == " " then
        if new_ln == new_line then
          return old_ln
        end
        old_ln, new_ln = old_ln + 1, new_ln + 1
      elseif tag == "+" then
        if new_ln == new_line then
          return nil -- added by the MR: no old-side counterpart
        end
        new_ln = new_ln + 1
      elseif tag == "-" then
        old_ln = old_ln + 1
      end
      offset = old_ln - new_ln
    end
  end
  return new_line + offset
end

--- Classify the changed new-side lines of a unified diff for gutter hints.
---
--- Walks the hunks tracking the new-side line counter. Added lines that follow
--- (and "replace") deleted lines are reported as `change`; additions with no
--- pending deletion are `add`; deleted lines with no replacement surface as a
--- single `delete` marker anchored at the new-side line that now sits where the
--- removed content was (the following line, or the last line at EOF).
---
--- @param diff_text string  a unified diff body (as returned in `/diffs`)
--- @return table  list of { line = new_line (1-based), kind = "add"|"change"|"delete" }
function M.changed_lines(diff_text)
  local signs = {}
  local new_ln
  local pending_del = 0 -- deleted lines not yet "consumed" by an addition

  local function flush_delete()
    if pending_del > 0 and new_ln then
      signs[#signs + 1] = { line = new_ln, kind = "delete" }
    end
    pending_del = 0
  end

  for line in (diff_text .. "\n"):gmatch("(.-)\n") do
    local c = line:match("^@@ %-%d+,?%d* %+(%d+),?%d* @@")
    if c then
      flush_delete()
      new_ln = tonumber(c)
    elseif new_ln then
      local tag = line:sub(1, 1)
      if tag == " " then
        flush_delete()
        new_ln = new_ln + 1
      elseif tag == "+" then
        local kind = pending_del > 0 and "change" or "add"
        if pending_del > 0 then
          pending_del = pending_del - 1
        end
        signs[#signs + 1] = { line = new_ln, kind = kind }
        new_ln = new_ln + 1
      elseif tag == "-" then
        pending_del = pending_del + 1
      end
      -- "\ No newline at end of file" and anything else is ignored
    end
  end
  flush_delete()
  return signs
end

return M
