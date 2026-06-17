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

return M
