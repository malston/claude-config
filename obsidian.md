# Obsidian CLI (Prefer for Vault Operations)

Use `obsidian <command> vault=<VaultName>` instead of Read/Edit/Write for vault note operations. Requires Obsidian app running.

Key commands:

- `obsidian read file="NoteName"` — read by wikilink name
- `obsidian append file="NoteName" content="text"` — append without reading first
- `obsidian search:context query="text" limit=N` — search with context
- `obsidian tasks todo daily` — today's incomplete tasks
- `obsidian backlinks file="NoteName"` — incoming links
- `obsidian tags file="NoteName"` — tags for a file

When to still use Read/Edit/Write:

- Complex multi-edit operations
- Frontmatter YAML modifications
- Files outside the vault
- When Obsidian isn't running
