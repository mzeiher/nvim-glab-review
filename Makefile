.PHONY: test lint format

# Run the headless test suite (exits non-zero on failure).
test:
	@for spec in tests/*_spec.lua; do \
		echo "== $$spec =="; \
		nvim --headless -u NONE -c "set rtp+=." -c "luafile $$spec" || exit 1; \
	done

# Check formatting (requires stylua: https://github.com/JohnnyMorganz/StyLua).
lint:
	stylua --check lua plugin tests

# Apply formatting.
format:
	stylua lua plugin tests
