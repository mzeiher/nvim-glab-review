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
--- Signs also carry the *text* of the old-side lines they stand in for, so the
--- content the MR removed can be shown in the buffer (it exists nowhere in the
--- working tree). Removed lines are paired 1:1 with the additions of a change
--- group; whatever is left over hangs off the trailing `delete` marker.
---
--- @param diff_text string  a unified diff body (as returned in `/diffs`)
--- @return table  list of { line = new_line (1-based),
---                          kind = "add"|"change"|"delete",
---                          removed = string[]|nil }
function M.changed_lines(diff_text)
  local signs = {}
  local new_ln
  local pending = {} -- text of deleted lines not yet "consumed" by an addition

  local function flush_delete()
    if #pending > 0 and new_ln then
      signs[#signs + 1] = { line = new_ln, kind = "delete", removed = pending }
    end
    pending = {}
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
        local sign = { line = new_ln, kind = #pending > 0 and "change" or "add" }
        if #pending > 0 then
          sign.removed = { table.remove(pending, 1) }
        end
        signs[#signs + 1] = sign
        new_ln = new_ln + 1
      elseif tag == "-" then
        pending[#pending + 1] = line:sub(2)
      end
      -- "\ No newline at end of file" and anything else is ignored
    end
  end
  flush_delete()
  return signs
end

--- Group change signs into the contiguous runs a reader thinks of as "one
--- change", for jumping between them.
---
--- Signs arrive in ascending line order; lines that touch (or repeat, as when a
--- delete marker lands on the line right after an addition) belong to the same
--- block. Diff hunks are deliberately not used here: a hunk starts three lines
--- of context before anything changed, so jumping to it would land the cursor on
--- unchanged code.
---
--- @param signs table  as returned by |M.changed_lines|
--- @return table  list of { first = line, last = line } in ascending order
function M.blocks(signs)
  local out = {}
  for _, s in ipairs(signs) do
    local last = out[#out]
    if last and s.line <= last.last + 1 then
      last.last = math.max(last.last, s.line)
    else
      out[#out + 1] = { first = s.line, last = s.line }
    end
  end
  return out
end

--- Split a unified diff into hunks, keeping each hunk's raw body.
---
--- Used for the on-demand hunk preview: the working tree only holds the new
--- side, so the removed lines are shown from here instead of from the buffer.
--- `new_last` is the last new-side line the hunk covers, so a cursor line can
--- be matched to its hunk; for a hunk that only deletes, the range collapses to
--- the line the deletion sits in front of.
---
--- @param diff_text string  a unified diff body (as returned in `/diffs`)
--- @return table  list of { header, new_start, new_last, lines = string[] }
function M.hunks(diff_text)
  local hunks = {}
  local cur
  for line in (diff_text .. "\n"):gmatch("(.-)\n") do
    local c = line:match("^@@ %-%d+,?%d* %+(%d+),?%d* @@")
    if c then
      local start = tonumber(c)
      cur = { header = line, new_start = start, new_last = start, lines = {} }
      hunks[#hunks + 1] = cur
    elseif cur then
      local tag = line:sub(1, 1)
      if tag == " " or tag == "+" or tag == "-" then
        cur.lines[#cur.lines + 1] = line
        if tag ~= "-" then
          cur.new_last = cur.new_last + 1
        end
      end
    end
  end
  for _, h in ipairs(hunks) do
    -- new_last counted one past the hunk's last new-side line.
    h.new_last = math.max(h.new_start, h.new_last - 1)
  end
  return hunks
end

--- The hunk covering new-side line `line`, or nil.
--- @param hunks table  as returned by |M.hunks|
--- @param line integer 1-based new-side line number
function M.hunk_at(hunks, line)
  for _, h in ipairs(hunks or {}) do
    if line >= h.new_start and line <= h.new_last then
      return h
    end
  end
  return nil
end

return M
