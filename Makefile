# ABOUTME: Makefile for running Claude Code configuration commands.
# ABOUTME: Provides convenient targets for common operations using claudeup.

.PHONY: help setup \
        sync list enable disable install \
        upgrade update-plugins update-all \
        enable-all-agents disable-all-agents enable-all-skills disable-all-skills \
        mcp-servers marketplaces browse-marketplace show-plugin sync-profile install-plugin plugins plugins-installed available-plugins project-plugins user-plugins

# Valid categories for claudeup local commands
CATEGORIES := skills, commands, agents, hooks, output-styles

##@ General

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } \
		/^[a-zA-Z_-]+:.*?## / { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

setup: ## Run initial setup
	@./setup.sh

##@ Configuration Management (claudeup local)

sync: ## Sync symlinks based on enabled.json
	@claudeup local sync

list: ## List items and status (CATEGORY=agents to filter)
	@claudeup local list $(CATEGORY)

enable: ## Enable item (CATEGORY=agents ITEM=name)
	@test -n "$(CATEGORY)" || (echo "Error: CATEGORY required ($(CATEGORIES))" && exit 1)
	@test -n "$(ITEM)" || (echo "Error: ITEM required (item name or * for all)" && exit 1)
	@claudeup local enable $(CATEGORY) $(ITEM)

disable: ## Disable item (CATEGORY=agents ITEM=name)
	@test -n "$(CATEGORY)" || (echo "Error: CATEGORY required ($(CATEGORIES))" && exit 1)
	@test -n "$(ITEM)" || (echo "Error: ITEM required (item name or * for all)" && exit 1)
	@claudeup local disable $(CATEGORY) $(ITEM)

install: ## Install from path (CATEGORY=agents SOURCE=path)
	@test -n "$(CATEGORY)" || (echo "Error: CATEGORY required ($(CATEGORIES))" && exit 1)
	@test -n "$(SOURCE)" || (echo "Error: SOURCE required (path to file or directory)" && exit 1)
	@claudeup local install $(CATEGORY) $(SOURCE)

##@ Bulk Operations

enable-all-agents: ## Enable all agents
	@claudeup local enable agents '*'

disable-all-agents: ## Disable all agents
	@claudeup local disable agents '*'

enable-all-skills: ## Enable all skills
	@claudeup local enable skills '*'

disable-all-skills: ## Disable all skills
	@claudeup local disable skills '*'

##@ Updates

upgrade: ## Update Claude Code CLI
	@./scripts/auto-upgrade-claude.sh --force

update-plugins: ## Update installed plugins
	@./scripts/auto-update-plugins.sh --force

update-all: ## Update CLI, plugins, and marketplaces
	@./scripts/auto-update-all.sh --force

##@ Plugin & MCP Management

mcp-servers: ## List MCP servers from plugins
	@claude mcp list

marketplaces: ## List installed marketplaces
	@claude plugin marketplace list

browse-marketplace: ## Browse marketplace plugins (MARKETPLACE=name)
	@test -n "$(MARKETPLACE)" || (echo "Error: MARKETPLACE required (e.g., claude-code-workflows)" && exit 1)
	@claudeup plugin browse $(MARKETPLACE) --format table

show-plugin: ## Show plugin directory structure (PLUGIN=name@marketplace)
	@test -n "$(PLUGIN)" || (echo "Error: PLUGIN required (e.g., superpowers@claude-code-workflows)" && exit 1)
	@claudeup plugin show $(PLUGIN)

sync-profile: ## Install missing plugins from config/my-profile.json
	@python3 -c '\
import json, subprocess, sys; \
profile = json.load(open("config/my-profile.json")); \
installed = {p["id"] for p in json.loads(subprocess.run(["claude", "plugin", "list", "--json"], capture_output=True, text=True).stdout or "[]")}; \
missing = [p for p in profile.get("plugins", []) if p not in installed]; \
[print(f"Already installed: {len(installed)} plugins")] if not missing else None; \
[print(f"Installing {len(missing)} missing plugins...")] if missing else None; \
[(print(f"  Installing {p}..."), subprocess.run(["claude", "plugin", "install", p], capture_output=True)) for p in missing]; \
print("Profile synced.") if missing else print("Profile already in sync.")'

install-plugin: ## Install a plugin (PLUGIN=name@marketplace)
	@test -n "$(PLUGIN)" || (echo "Error: PLUGIN required (e.g., superpowers@claude-code-workflows)" && exit 1)
	@claude plugin install $(PLUGIN)

plugins: ## List installed plugins
	@claude plugin list

plugins-installed: ## List enabled plugins (table format)
	@command -v claudeup >/dev/null 2>&1 && claudeup plugin list --enabled --format table || \
		claude plugin list --json | jq -r '["ID", "SCOPE", "PATH"], (.[] | select(.enabled==true) | [.id, .scope, .installPath]) | @tsv' | column -t -s $$'\t'

available-plugins: ## List all plugins (installed and available)
	@command -v claudeup >/dev/null 2>&1 && claudeup plugin list --format table || \
		claude plugin list --json --available | jq -r '["NAME", "MARKETPLACE", "DESCRIPTION"], (.available[] | [.name, .marketplaceName, .description]) | @tsv' | column -t -s $$'\t'

project-plugins: ## List project-scoped plugins
	@claude plugin list --json | jq -r '["ID", "PATH"], (.[] | select(.enabled==true and .scope=="project") | [.id, .installPath]) | @tsv' | column -t -s $$'\t'

user-plugins: ## List user-scoped plugins
	@claude plugin list --json | jq -r '["ID", "PATH"], (.[] | select(.enabled==true and .scope=="user") | [.id, .installPath]) | @tsv' | column -t -s $$'\t'
