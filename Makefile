# ABOUTME: Makefile for running Claude Code configuration commands.
# ABOUTME: Provides convenient targets for common operations using claudeup.

.PHONY: help sync list enable disable install upgrade plugins context setup

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

# Configuration management
sync: ## Sync symlinks based on enabled.json
	@claudeup local sync

list: ## List all items and their enabled status (use CATEGORY=agents to filter)
	@claudeup local list $(CATEGORY)

enable: ## Enable an item (requires CATEGORY and ITEM, e.g., make enable CATEGORY=agents ITEM=cl)
	@test -n "$(CATEGORY)" || (echo "Error: CATEGORY required (skills, commands, agents, rules, output-styles, hooks)" && exit 1)
	@test -n "$(ITEM)" || (echo "Error: ITEM required (item name or * for all)" && exit 1)
	@claudeup local enable $(CATEGORY) $(ITEM)

disable: ## Disable an item (requires CATEGORY and ITEM)
	@test -n "$(CATEGORY)" || (echo "Error: CATEGORY required (skills, commands, agents, rules, output-styles, hooks)" && exit 1)
	@test -n "$(ITEM)" || (echo "Error: ITEM required (item name or * for all)" && exit 1)
	@claudeup local disable $(CATEGORY) $(ITEM)

install: ## Install item from external path (requires CATEGORY and PATH)
	@test -n "$(CATEGORY)" || (echo "Error: CATEGORY required" && exit 1)
	@test -n "$(SOURCE)" || (echo "Error: SOURCE required (path to file or directory)" && exit 1)
	@claudeup local install $(CATEGORY) $(SOURCE)

# Auto-upgrade
upgrade: ## Check for and install Claude Code updates
	@./scripts/auto-upgrade-claude.sh

plugins: ## Update installed plugins
	@./scripts/auto-update-plugins.sh

# Status and diagnostics
context: ## Show context bar status
	@./scripts/context-bar.sh

mcp-servers: ## Find all MCP servers
	@./scripts/find-mcp-servers.sh

# Setup
setup: ## Run initial setup
	@./setup.sh

# Shortcuts for common operations
disable-all-agents: ## Disable all agents
	@claudeup local disable agents '*'

enable-all-agents: ## Enable all agents
	@claudeup local enable agents '*'

disable-all-skills: ## Disable all skills
	@claudeup local disable skills '*'

enable-all-skills: ## Enable all skills
	@claudeup local enable skills '*'
