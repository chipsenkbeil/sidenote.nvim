.PHONY: help test lint fmt

NVIM ?= nvim

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
	@luacheck lua spec --globals vim describe it before_each after_each assert

fmt: ## Format the Lua sources
	@stylua lua spec
