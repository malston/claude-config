---
description: Add a memory to CLAUDE.md at user, project, or local scope
allowed-tools: Read, Edit, AskUserQuestion
---

Add a memory or instruction to a CLAUDE.md file. The user provides content to remember, and you integrate it intelligently.

## Arguments

The command accepts: `/update-memory [scope] <content>`

- `scope` (optional): `user`, `project`, or `local`
  - `user` → `~/.claude/CLAUDE.md` (global, applies to all projects)
  - `project` → `.claude/CLAUDE.md` (project-specific, checked into git)
  - `local` → `.claude/CLAUDE.local.md` (local only, gitignored)
- `content`: The memory/instruction to add

## Step 1: Parse Arguments

Extract scope and content from the user's input. Examples:

- `/update-memory user always use bun instead of npm` → scope=user, content="always use bun instead of npm"
- `/update-memory prefer tabs over spaces` → scope=none, content="prefer tabs over spaces"

## Step 2: Determine Target File

If scope was provided, use it. Otherwise, ask:

```
Which CLAUDE.md file should I update?

- **user** (~/.claude/CLAUDE.md) - Global instructions for all projects
- **project** (.claude/CLAUDE.md) - Project-specific, shared with team via git
- **local** (.claude/CLAUDE.local.md) - Personal, local-only, gitignored
```

## Step 3: Read Target File

Read the target CLAUDE.md file to understand its structure, sections, and style.

## Step 4: Determine Placement

Analyze the content and find the most appropriate section:

- Tooling preferences → relevant "Tooling" or "Coding Standards" section
- Behavior preferences → "Our relationship" or similar section
- Code style → "Writing code" or "Coding Standards" section
- Testing preferences → "Testing" section
- Create a new section only if no existing section fits

## Step 5: Wordsmith and Integrate

Transform the user's input into the file's style:

- Match the tone (imperative, declarative, etc.)
- Match formatting (bullets, bold, caps patterns)
- Keep it concise - one line if possible
- Use existing patterns from the file

Example transformations:

- Input: "always use bun instead of npm"
- Output in bullet style: `- ALWAYS use \`bun\` instead of \`npm\` for package management`

## Step 6: Show Proposed Change

Present the change as a diff:

```
### Updating: [file path]

**Section:** [section name]
**Why here:** [brief reason]

\`\`\`diff
+ [the formatted addition]
\`\`\`
```

## Step 7: Apply with Confirmation

Ask if the user wants to apply the change. Only edit the file after approval.
