.PHONY: test lint format

# Run the headless test suite (exits non-zero on failure).
test:
	nvim --headless -u NONE \
		-c "set rtp+=." \
		-c "luafile tests/overview_parse_spec.lua"

# Check formatting (requires stylua: https://github.com/JohnnyMorganz/StyLua).
lint:
	stylua --check lua plugin tests

# Apply formatting.
format:
	stylua lua plugin tests
