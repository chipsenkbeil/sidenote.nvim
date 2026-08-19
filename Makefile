.PHONY: help test lint fmt fmt-check style check

NVIM ?= nvim
LUA_DIRS := lua spec harness plugin cli scripts

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

test: ## Run the test suite (FILE=path for a single spec or directory)
ifdef FILE
	@$(NVIM) -l spec/runner.lua $(FILE)
else
	@$(NVIM) -l spec/runner.lua
endif

lint: ## Static-check the Lua sources
	@luacheck $(LUA_DIRS) --globals vim describe it before_each after_each assert

fmt: ## Format the Lua sources
	@stylua $(LUA_DIRS)

fmt-check: ## Fail if any source is unformatted
	@stylua --check $(LUA_DIRS)

style: ## Audit the mechanical lua-style rules
	@$(NVIM) -l scripts/style_audit.lua $$(find $(LUA_DIRS) -name '*.lua')

check: test lint fmt-check style ## Everything CI runs
