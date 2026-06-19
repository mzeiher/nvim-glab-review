-- Headless test of the paginated-response decoder.
-- `glab api --paginate` concatenates each page's JSON body, so a multi-page
-- list endpoint returns several arrays back-to-back. Run with `make test`, or:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/decode_stream_spec.lua"

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local util = require("glab-review.util")

local failures = 0
local function check(name, cond)
  if cond then
    io.write("ok   - " .. name .. "\n")
  else
    failures = failures + 1
    io.write("FAIL - " .. name .. "\n")
  end
end

-- 1. Single page decodes unchanged.
local ok, v = util.decode_json_stream('[{"id":1},{"id":2}]')
check("single page ok", ok)
check("single page elements", v and #v == 2 and v[1].id == 1 and v[2].id == 2)

-- 2. Two concatenated arrays merge into one list (the bug case).
ok, v = util.decode_json_stream('[{"id":1},{"id":2}][{"id":3}]')
check("two pages ok", ok)
check("two pages merged length", v and #v == 3)
check("two pages order preserved", v and v[1].id == 1 and v[2].id == 2 and v[3].id == 3)

-- 3. A `][` inside a string value must not be treated as a page boundary.
ok, v = util.decode_json_stream('[{"s":"a][b"}][{"s":"c"}]')
check("string-boundary ok", ok)
check("string-boundary merged", v and #v == 2 and v[1].s == "a][b" and v[2].s == "c")

-- 4. Empty trailing page (glab can emit `[]` for the last page) is harmless.
ok, v = util.decode_json_stream('[{"id":1}][]')
check("empty trailing page ok", ok)
check("empty trailing page length", v and #v == 1 and v[1].id == 1)

-- 5. A genuinely malformed body still reports failure.
ok = util.decode_json_stream('[{"id":1}')
check("malformed reports failure", not ok)

-- 6. A single object (non-paginated endpoint) round-trips.
ok, v = util.decode_json_stream('{"iid":42,"title":"x"}')
check("single object ok", ok and v.iid == 42 and v.title == "x")

if failures > 0 then
  io.write(("\n%d failure(s)\n"):format(failures))
  vim.cmd("cquit 1")
else
  io.write("\nall passed\n")
  vim.cmd("quit")
end
