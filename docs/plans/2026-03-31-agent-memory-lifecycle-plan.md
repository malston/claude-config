# AI Agent Memory Lifecycle Cheatsheet -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create an event-driven reference for Claude Code's four-layer memory system (beads, auto-memory, claude-mem, episodic-memory) with an interactive HTML companion that lets users explore the session lifecycle.

**Architecture:** Two deliverables -- a markdown cheatsheet (`agent-memory-lifecycle-cheatsheet.md`) and a single-file HTML companion (`html/agent-memory-lifecycle.html`). The cheatsheet follows the progressive structure of existing cheatsheets (see `context-engineering-cheatsheet.md` for style reference). The HTML companion follows the dark-theme, single-file pattern (see `html/parallel-dispatch.html` for CSS variables, typography, and layout).

**Tech Stack:** Markdown, vanilla HTML/CSS/JS (no build tools, no external JS dependencies). Google Fonts (Fraunces, Outfit, IBM Plex Mono) loaded via CDN per existing companion convention.

**Spec:** `docs/specs/2026-03-31-agent-memory-lifecycle-design.md`

**Style reference files:**

- Cheatsheet structure/voice: `context-engineering-cheatsheet.md`, `parallel-agent-execution-cheatsheet.md`
- HTML design system: `html/parallel-dispatch.html` (CSS custom properties, typography, layout, dark theme)

---

### Task 1: Cheatsheet -- Sections 1-2 (Opening Hook + Four Layers at a Glance)

**Files:**

- Create: `agent-memory-lifecycle-cheatsheet.md`

This task creates the file and writes the conceptual foundation: what the problem is and what the four layers are.

- [ ] **Step 1: Write Section 1 (Opening Hook)**

Create `agent-memory-lifecycle-cheatsheet.md` with the H1 title, a 2-sentence opening paragraph, and the companion link.

```markdown
# AI Agent Memory Lifecycle Cheatsheet

AI coding agents forget everything between sessions -- and even mid-session when the context window compacts. Four complementary systems fix this by hooking into different moments of the Claude Code session lifecycle, each capturing a different type of knowledge.

Companion to the [interactive session lifecycle explorer](./html/agent-memory-lifecycle.html).

---
```

- [ ] **Step 2: Write Section 2 (The Four Layers at a Glance)**

Add the `## The Four Layers at a Glance` section with two elements:

First, a comparison table with these exact columns and rows:

| Layer               | What It Captures                                        | How It Captures                                            | How You Query It                                                | Persistence                                          | Token Cost |
| ------------------- | ------------------------------------------------------- | ---------------------------------------------------------- | --------------------------------------------------------------- | ---------------------------------------------------- | ---------- |
| **beads** (`bd`)    | Work items, dependencies, decisions, project facts      | Agent-initiated CLI commands                               | `bd ready`, `bd show`, `bd memories`                            | Dolt embedded DB (`.beads/`)                         | ~1000-2000 |
| **auto-memory**     | User preferences, behavioral feedback, brainstorm state | Agent-initiated markdown file writes                       | Auto-loaded at session start via MEMORY.md                      | Markdown files (`~/.claude/projects/<path>/memory/`) | ~300-500   |
| **claude-mem**      | Tool call observations, session summaries               | Automatic -- PostToolUse hook on every tool call           | MCP: `search()` -> `timeline()` -> `get_observations()`         | Observation DB via worker service (localhost:37777)  | ~200-400   |
| **episodic-memory** | Full conversation transcripts                           | Passive -- indexes saved transcripts at next session start | MCP: `search()` for semantic/text, `read()` for full transcript | Indexed transcript database                          | 0 (async)  |

Second, an ASCII swim-lane diagram showing which layers are active at each lifecycle phase. Use this structure:

```text
  Session          User           Tool          Pre-           Session
  Start           Prompt          Use          Compact          End
    │                │              │              │              │
    │                │              │              │              │
    ▼                ▼              ▼              ▼              ▼
┌────────┐                                    ┌────────┐
│ beads  │          ·····agent-initiated·····  │ beads  │
│  prime │                                    │  prime │
└────────┘                                    └────────┘
┌────────┐
│  auto  │
│ memory │
│  load  │
└────────┘
┌────────┐     ┌────────┐     ┌────────┐                   ┌────────┐
│claude- │     │claude- │     │claude- │                   │claude- │
│mem     │     │mem     │     │mem     │                   │mem     │
│context │     │session │     │observe │                   │persist │
└────────┘     └────────┘     └────────┘                   └────────┘
┌────────┐
│episodic│
│  sync  │
│(async) │
└────────┘
```

The exact diagram will need refinement for monospace alignment during implementation. The key requirement is that readers can scan left-to-right across the session lifecycle and see which layers are active at each event.

- [ ] **Step 3: Proofread and verify formatting**

Read the file back. Check:

- ASCII diagram renders correctly in monospace
- Table columns align
- Section headers use `##` / `###` hierarchy
- Opening paragraph matches the voice of `context-engineering-cheatsheet.md` (direct, no filler)

- [ ] **Step 4: Commit**

```bash
git add agent-memory-lifecycle-cheatsheet.md
git commit -m "Add agent memory lifecycle cheatsheet: opening + four layers overview"
```

---

### Task 2: Cheatsheet -- Section 3 (Session Lifecycle Event Map)

**Files:**

- Modify: `agent-memory-lifecycle-cheatsheet.md`

The core of the cheatsheet. Walk through every event in chronological order.

- [ ] **Step 1: Write the SessionStart event block**

Add `## Session Lifecycle Event Map` and the SessionStart subsection:

```markdown
## Session Lifecycle Event Map

A Claude Code session fires events at predictable moments. Each event triggers zero or more memory layers. This section walks through every event in order, showing what fires and what it does.

### SessionStart

Triggers: `startup`, `clear`, `compact`, `resume`

Four layers fire at session start -- three synchronously (blocking), one asynchronously (background):
```

Then the table from the spec:

| Order | System          | Hook Type | Blocking?  | Action                                                               | Token Cost |
| ----- | --------------- | --------- | ---------- | -------------------------------------------------------------------- | ---------- |
| 1     | episodic-memory | command   | No (async) | Background sync of conversation index                                | 0          |
| 2     | claude-mem      | command   | Yes        | Start worker service, load recent observations                       | ~200-400   |
| 3     | auto-memory     | built-in  | Yes        | Load MEMORY.md index + referenced markdown files                     | ~300-500   |
| 4     | beads           | command   | Yes        | `bd prime`: workflow instructions + ready work + `bd remember` facts | ~1000-2000 |

Follow with a 2-sentence note: total startup injection is ~1500-2900 tokens across all four layers. On a 200K context window, this is about 1-1.5%.

- [ ] **Step 2: Write the mid-session events (UserPromptSubmit, PostToolUse, Agent-Initiated Actions)**

Three subsections:

**UserPromptSubmit** -- triggers on every user message. Only claude-mem responds (session-init hook, keeps worker alive). One sentence + one-row table.

**PostToolUse** -- triggers after every tool call. Only claude-mem responds (records observation: tool name, input, output, context). This is the hook that makes claude-mem different from the other layers -- explain that it sees every Read, Edit, Bash, Grep, the complete action stream. This is why claude-mem can answer "what files did we change?" while episodic-memory cannot.

**Agent-Initiated Actions** -- no hook trigger, agent decides to do these. Table:

| System      | When                                   | What Happens                                                        |
| ----------- | -------------------------------------- | ------------------------------------------------------------------- |
| beads       | Agent creates/updates/closes work      | `bd create`, `bd update --claim`, `bd close` -- issue state in Dolt |
| beads       | Agent stores a fact                    | `bd remember "fact" --key slug` -- persists in Dolt config          |
| auto-memory | Agent captures a preference/correction | Writes markdown file to `~/.claude/projects/<path>/memory/`         |
| TaskCreate  | Agent tracks session progress          | Ephemeral checklist (disappears at session end)                     |

- [ ] **Step 3: Write the late-session events (PreCompact, Stop, SessionEnd, Between Sessions)**

Four subsections:

**PreCompact** -- beads fires `bd prime` again to re-inject workflow context before compaction. Explain why: auto-memory and claude-mem context survive compaction natively (system prompt level), but `bd prime` output is injected as tool output which gets compacted.

**Stop** -- claude-mem generates a session summary observation. One sentence + one-row table.

**SessionEnd** -- claude-mem persists observations via HTTP POST to worker service. One sentence + one-row table.

**Between Sessions** -- Claude Code writes the conversation transcript to disk. Episodic-memory indexes it at the next SessionStart. This is why episodic-memory uses a SessionStart hook for async sync -- it's catching up on transcripts written since the last session.

- [ ] **Step 4: Proofread and verify formatting**

Read the full Section 3. Check:

- Event order matches the spec exactly
- All tables have consistent column structure
- Explanatory text between tables follows the cheatsheet voice (direct, "why" alongside "how")
- No event from the spec is missing

- [ ] **Step 5: Commit**

```bash
git add agent-memory-lifecycle-cheatsheet.md
git commit -m "Add session lifecycle event map section"
```

---

### Task 3: Cheatsheet -- Section 4 (Layer Deep Dives)

**Files:**

- Modify: `agent-memory-lifecycle-cheatsheet.md`

Four subsections, one per layer, each following the same template.

- [ ] **Step 1: Write the deep dive template intro and beads subsection**

Add `## Layer Deep Dives` with a one-sentence intro explaining the consistent template.

Write `### Beads (bd)` with these subsections (use bold labels, not H4):

**What it stores:** Work items with blocking dependencies, architectural decisions (`--type=decision`), persistent project facts (`bd remember`). Issues have hash-based IDs (e.g., `technical-cheatsheets-c37`), priorities 0-4, and types (task, bug, feature, epic, chore, decision).

**Hook integration:** Two hooks -- SessionStart and PreCompact. Both run `bd prime` which outputs workflow instructions, the current ready-work list, and all `bd remember` entries. Synchronous (blocking).

**Capture mechanism:** Agent-initiated. The agent explicitly runs `bd create`, `bd update`, `bd close`, `bd remember`. Nothing is captured automatically.

**Storage:** Dolt embedded database in `.beads/` directory. SQL-backed with cell-level merge for conflict resolution. Auto-commits each write to Dolt history.

**Query patterns:** Table of essential commands:

| Action              | Command                        |
| ------------------- | ------------------------------ |
| Find unblocked work | `bd ready --json`              |
| List open issues    | `bd list --status=open --json` |
| View issue details  | `bd show <id> --json`          |
| Search by keyword   | `bd search "query"`            |
| List stored facts   | `bd memories`                  |
| Search facts        | `bd memories <keyword>`        |

**Token cost:** ~1000-2000 tokens at startup via `bd prime`. Zero per-query cost (CLI output goes to the agent, not injected into context).

**Failure modes:** Table:

| Failure                   | Symptom                           | Recovery                                          |
| ------------------------- | --------------------------------- | ------------------------------------------------- |
| `bd` not installed        | Command not found                 | `brew install beads`                              |
| `bd init` not run         | No `.beads/` directory            | `bd init` (or `bd init --stealth` for docs repos) |
| Stale issues accumulating | `bd ready` returns too many items | `bd stale` to find old issues, close or defer     |
| Dolt corruption           | bd commands error on SQL          | `bd doctor`, or re-init from backup               |

- [ ] **Step 2: Write the auto-memory deep dive**

Write `### Auto-Memory` with the same template:

**What it stores:** User preferences (`user` type), behavioral corrections (`feedback` type), in-progress brainstorm state (`project` type). Each memory is a markdown file with YAML frontmatter (name, description, type fields).

**Hook integration:** None -- built into Claude Code. MEMORY.md index and referenced files are loaded into the system prompt automatically at session start.

**Capture mechanism:** Agent-initiated. The agent writes a markdown file to `~/.claude/projects/<path>/memory/` and updates the MEMORY.md index.

**Storage:** Markdown files on disk. One file per memory, indexed by MEMORY.md. MEMORY.md is capped at 200 lines (truncated beyond that).

**Query patterns:** No explicit query needed -- auto-loaded at session start. The agent can also read specific memory files with the Read tool if needed.

**Token cost:** ~300-500 tokens at startup (varies with file count, ~200-300 per file).

**Failure modes:** Table:

| Failure                   | Symptom                                          | Recovery                                      |
| ------------------------- | ------------------------------------------------ | --------------------------------------------- |
| Stale project notes       | Outdated info loaded every session               | Delete the stale `.md` file, update MEMORY.md |
| MEMORY.md > 200 lines     | Late entries silently truncated                  | Consolidate entries, keep index concise       |
| Conflicting with bd prime | bd prime says "no MEMORY.md", CLAUDE.md says yes | CLAUDE.md routing rules take precedence       |

- [ ] **Step 3: Write the claude-mem deep dive**

Write `### Claude-Mem` with the same template:

**What it stores:** Tool call observations (what tool ran, input, output, context), session summaries, semantic snapshots of work performed.

**Hook integration:** Five hooks -- the most of any layer:

| Hook             | Trigger                 | Action                                           |
| ---------------- | ----------------------- | ------------------------------------------------ |
| SessionStart     | startup, clear, compact | Start worker service, inject recent observations |
| UserPromptSubmit | Every user message      | session-init, keep worker alive                  |
| PostToolUse      | After every tool call   | Record observation                               |
| Stop             | Agent stops generating  | Generate session summary                         |
| SessionEnd       | Session cleanup         | Persist to DB via HTTP POST                      |

The PostToolUse hook is the differentiator. It fires on every Read, Edit, Bash, Grep, Write -- the complete action stream. This is why claude-mem can answer "what files did we change?" while episodic-memory cannot.

**Capture mechanism:** Automatic. The PostToolUse hook records observations silently. No agent action needed.

**Storage:** Observation database accessed via worker service at `localhost:37777`.

**Query patterns:** Three-layer retrieval workflow:

```text
search(query)           → index with IDs (~50-100 tokens/result)
    │
timeline(anchor=ID)     → context around interesting results
    │
get_observations([IDs]) → full details for filtered IDs
```

Also: `smart_search(query)` for tree-sitter AST-based code symbol search, `smart_outline(file)` for structural file outlines.

**Token cost:** ~200-400 tokens at startup (context summary injection). Per-query cost varies with result count.

**Failure modes:** Table:

| Failure                    | Symptom                              | Recovery                                          |
| -------------------------- | ------------------------------------ | ------------------------------------------------- |
| Worker service not running | Observations not recorded            | Restart session (SessionStart hook restarts it)   |
| PostToolUse hook disabled  | No observations captured during work | Check `.claude/settings.json` for hook config     |
| Observation DB corruption  | Search returns errors                | Delete DB, observations rebuild over new sessions |

- [ ] **Step 4: Write the episodic-memory deep dive**

Write `### Episodic Memory` with the same template:

**What it stores:** Full conversation transcripts indexed for semantic and text search.

**Hook integration:** One hook -- SessionStart (async). Runs `episodic-memory sync --background` which indexes conversation files Claude Code has written to disk since the last sync.

**Capture mechanism:** Passive. Claude Code writes conversation transcripts to disk automatically. Episodic-memory indexes them in the background at the next session start. It never fires during active work.

**Storage:** Indexed transcript database managed by the episodic-memory plugin.

**Query patterns:** Two MCP tools:

| Tool                             | Purpose                                                                                |
| -------------------------------- | -------------------------------------------------------------------------------------- |
| `search(query)`                  | Semantic + text search across all conversations. Returns ranked results with snippets. |
| `read(path, startLine, endLine)` | Read full conversation transcript. Use pagination for large conversations.             |

**Token cost:** 0 at startup (async sync adds no tokens). Per-query cost varies.

**Failure modes:** Table:

| Failure                    | Symptom                                      | Recovery                                             |
| -------------------------- | -------------------------------------------- | ---------------------------------------------------- |
| Sync not running           | Recent conversations not searchable          | `episodic-memory sync` manually                      |
| Conversation files missing | Search returns no results for known sessions | Check Claude Code conversation storage directory     |
| Index out of date          | Search misses recent work                    | Wait for next SessionStart sync, or trigger manually |

- [ ] **Step 5: Proofread all four deep dives**

Read the full Section 4. Check:

- All four subsections follow the exact same template order (stores, hooks, capture, storage, query, cost, failures)
- Command examples are accurate (match actual CLI/MCP tool names)
- No placeholder text or "see above" references

- [ ] **Step 6: Commit**

```bash
git add agent-memory-lifecycle-cheatsheet.md
git commit -m "Add layer deep dives: beads, auto-memory, claude-mem, episodic-memory"
```

---

### Task 4: Cheatsheet -- Sections 5-6 (Quick Reference + Routing Decision Guide)

**Files:**

- Modify: `agent-memory-lifecycle-cheatsheet.md`

- [ ] **Step 1: Write Section 5 (Capture vs Query Quick Reference)**

Add `## Capture vs Query Quick Reference` with three tables.

**First table -- "I need to find X":**

| I need to...                             | Layer           | Command                             |
| ---------------------------------------- | --------------- | ----------------------------------- |
| Find unblocked work                      | beads           | `bd ready --json`                   |
| See what I was working on                | beads           | `bd list --status=in_progress`      |
| Recover what we tried last session       | claude-mem      | `search("what we tried")`           |
| Find why we chose approach B             | episodic-memory | `search("chose approach B")`        |
| Check my coding style preferences        | auto-memory     | (auto-loaded at session start)      |
| Find a similar bug fix from last month   | claude-mem      | `search("bug fix <description>")`   |
| Recall a conversation about architecture | episodic-memory | `search("architecture discussion")` |
| Look up a project fact                   | beads           | `bd memories <keyword>`             |

**Second table -- Claude-mem vs Episodic-Memory heuristic:**

| You're thinking...                | Use             | Why                                        |
| --------------------------------- | --------------- | ------------------------------------------ |
| "We fixed a bug like this before" | claude-mem      | Recorded the tool calls and outcome        |
| "We talked about two approaches"  | episodic-memory | The conversation had the reasoning         |
| "What files did we change?"       | claude-mem      | Observations track every tool use          |
| "Why did we choose B over A?"     | episodic-memory | Rationale lived in the discussion          |
| "Did we already try Y?"           | claude-mem      | Captured the attempt and result            |
| "Mark said something about Z"     | episodic-memory | Verbal instruction, not an observed action |

Follow with the one-liner: "Claude-mem is a lab notebook (what you did). Episodic-memory is a meeting transcript (what you discussed)."

And the hook-level explanation: "Claude-mem hooks into PostToolUse (watches every action). Episodic-memory hooks into SessionStart (indexes saved transcripts). Different capture mechanisms produce different retrieval strengths."

**Third table -- "I have knowledge X":**

| Knowledge Type         | Where to Store | Command                                   |
| ---------------------- | -------------- | ----------------------------------------- |
| Work item              | beads          | `bd create --title="..." --type=task`     |
| Architectural decision | beads          | `bd create --title="..." --type=decision` |
| Stable project fact    | beads          | `bd remember "fact" --key slug`           |
| User preference        | auto-memory    | Write `user` type markdown file           |
| Behavioral correction  | auto-memory    | Write `feedback` type markdown file       |
| Brainstorm state       | auto-memory    | Write `project` type markdown file        |

- [ ] **Step 2: Write Section 6 (Routing Decision Guide)**

Add `## Routing Decision Guide` with an ASCII decision tree:

```text
What kind of knowledge is this?
│
├─ Work to be done?
│  ├─ Spans sessions or has dependencies ──► bd create
│  └─ Single-session progress tracking ───► TaskCreate (ephemeral)
│
├─ A fact about this project?
│  ├─ Stable (rarely changes) ────────────► bd remember
│  └─ Volatile (brainstorm in flux) ──────► auto-memory project type
│
├─ About how I work?
│  ├─ A correction ("don't do X") ────────► auto-memory feedback type
│  └─ A preference ("I like Y") ──────────► auto-memory user type
│
├─ A decision we made?
│  ├─ Project-scoped ─────────────────────► bd create --type=decision
│  └─ Cross-project ──────────────────────► auto-memory feedback type
│
└─ None of the above?
   └─ Probably doesn't need persisting. Let it go.
```

Follow with edge case guidance:

- "When you pick wrong": If you stored something and can't find it, check the other obvious candidate. The layers have minimal overlap, so the fallback search space is small.
- "When it fits two places": Route by lifecycle. If it has open/close semantics (work), it goes in beads. If it's a static truth, it goes in `bd remember` or auto-memory depending on scope.

- [ ] **Step 3: Proofread and verify formatting**

Read Sections 5-6. Check:

- All three query/routing tables have consistent column structure
- ASCII decision tree renders correctly in monospace
- No commands reference tools that don't exist

- [ ] **Step 4: Commit**

```bash
git add agent-memory-lifecycle-cheatsheet.md
git commit -m "Add capture vs query reference and routing decision guide"
```

---

### Task 5: Cheatsheet -- Sections 7-8 (Failure Taxonomy + Token Budget)

**Files:**

- Modify: `agent-memory-lifecycle-cheatsheet.md`

- [ ] **Step 1: Write Section 7 (Failure Taxonomy)**

Add `## Failure Taxonomy` with a comprehensive table:

| Failure                         | Layer               | Symptom                                       | Detection                                                            | Recovery                                                        |
| ------------------------------- | ------------------- | --------------------------------------------- | -------------------------------------------------------------------- | --------------------------------------------------------------- |
| Hook doesn't fire               | any                 | Missing context at session start              | Check `.claude/settings.local.json`                                  | Re-run `bd setup claude` or reinstall plugin                    |
| Worker service down             | claude-mem          | Observations not recorded during session      | `curl localhost:37777` returns connection refused                    | Restart session (SessionStart restarts it)                      |
| Stale auto-memories             | auto-memory         | Outdated info loaded every session            | Review MEMORY.md manually                                            | Delete stale files, update index                                |
| bd not initialized              | beads               | `bd` commands fail with "no .beads/"          | `bd doctor`                                                          | `bd init` or `bd init --stealth`                                |
| Compaction loses work context   | beads               | Agent forgets which issue it was working on   | Check `bd list --status=in_progress` after compaction                | PreCompact hook re-injects; if missing, run `bd prime` manually |
| Transcript not indexed          | episodic-memory     | Recent conversations not in search results    | Search returns only old results                                      | `episodic-memory sync` manually                                 |
| Conflicting memory instructions | beads + auto-memory | Agent confused about whether to use MEMORY.md | bd prime says "no MEMORY.md", CLAUDE.md says "yes for user/feedback" | CLAUDE.md routing rules always take precedence over tool output |
| Observation DB corruption       | claude-mem          | `search()` returns errors                     | Errors in MCP tool results                                           | Delete DB; observations rebuild over new sessions               |
| MEMORY.md truncated             | auto-memory         | Late index entries silently lost              | Index exceeds 200 lines                                              | Consolidate -- keep under 200 lines                             |

- [ ] **Step 2: Write Section 8 (Token Budget)**

Add `## Token Budget` with the full accounting table:

| Component                      | Tokens             | Source                                |
| ------------------------------ | ------------------ | ------------------------------------- |
| System prompt + skills catalog | ~15,000-20,000     | Built-in (varies with enabled skills) |
| Global CLAUDE.md               | ~2,800             | User rules + memory routing           |
| Project CLAUDE.md              | ~400-1,200         | Per-project (beads adds ~500)         |
| Auto-memory files              | ~300-500           | MEMORY.md + 2-3 referenced files      |
| Claude-mem context             | ~200-400           | Recent observations summary           |
| `bd prime`                     | ~1,000-2,000       | Workflow + ready work + memories      |
| **Total startup**              | **~19,700-26,900** | **~10-13% of 200K window**            |

Follow with optimization guidance:

- Keep `bd remember` entries under 15 per project (`bd memories` to review, `bd forget <key>` to prune)
- Keep MEMORY.md under 200 lines (entries beyond 200 are truncated)
- Use `bd stale` periodically to close old issues (reduces `bd prime` ready-work output)
- Auto-memory `project` type notes should be migrated to beads epics once they become actionable work

Close the section -- and the cheatsheet -- with the tradeoff framing: "More memory context means better recall but less room for work. The sweet spot is ~12-15% of the context window for memory, leaving 85%+ for the actual task."

- [ ] **Step 3: Proofread the full cheatsheet**

Read the entire file from top to bottom. Check:

- All 8 sections present in order
- Progressive build: layers overview -> lifecycle events -> layer details -> quick reference -> routing -> failures -> budget
- Consistent table formatting throughout
- ASCII diagrams render in monospace
- No references to tools or commands that don't exist
- Voice matches existing cheatsheets (direct, "why" alongside "how")

- [ ] **Step 4: Commit**

```bash
git add agent-memory-lifecycle-cheatsheet.md
git commit -m "Add failure taxonomy and token budget sections, completing cheatsheet"
```

---

### Task 6: HTML Companion -- Scaffold + Timeline View

**Files:**

- Create: `html/agent-memory-lifecycle.html`

Build the HTML scaffold and the default Timeline View feature.

- [ ] **Step 1: Create the HTML file with full CSS design system**

Create `html/agent-memory-lifecycle.html` with:

- DOCTYPE, meta viewport, title: "Agent Memory Lifecycle Explorer"
- Google Fonts link (Fraunces, Outfit, IBM Plex Mono) -- same as `parallel-dispatch.html`
- Full CSS custom properties block copied from `parallel-dispatch.html` (all 24 color variables: `--bg`, `--bg-raised`, `--bg-card`, `--bg-card-hover`, `--bg-inset`, `--border`, `--border-active`, `--text`, `--text-body`, `--text-dim`, `--text-muted`, `--red`, `--red-dim`, `--orange`, `--orange-dim`, `--amber`, `--amber-dim`, `--emerald`, `--emerald-dim`, `--blue`, `--blue-dim`, `--cyan`, `--cyan-dim`)
- Global reset (`* { margin: 0; padding: 0; box-sizing: border-box; }`)
- Body styles matching parallel-dispatch.html
- Container with `max-width: 1140px`
- Header with eyebrow ("CLAUDE CODE MEMORY ARCHITECTURE"), H1 ("Session Lifecycle Explorer"), and subtitle paragraph
- Header `::after` gradient line (cyan)

- [ ] **Step 2: Add navigation tabs**

Three tab buttons below the header:

1. "Timeline" (default active)
2. "Layer Explorer"
3. "Query Router"

CSS for tabs:

- Tab bar: flex, gap, bottom border
- Active tab: cyan text, cyan bottom border (2px)
- Inactive tab: text-dim, no border, hover to text-body
- Font: IBM Plex Mono, 13px, uppercase, letter-spacing 2px

JavaScript:

- `state.activeTab` tracks which tab is shown
- `switchTab(tabName)` hides all tab content divs, shows the selected one, updates active tab styling
- Three content divs: `#timeline-view`, `#layer-explorer`, `#query-router`

- [ ] **Step 3: Build the Timeline View data model**

Define the session lifecycle events as a JavaScript data structure:

```javascript
const EVENTS = [
  {
    id: "session-start",
    name: "SessionStart",
    triggers: "startup, clear, compact, resume",
    layers: [
      {
        layer: "episodic-memory",
        action: "Background sync of conversation index",
        blocking: false,
        tokens: 0,
        color: "amber",
      },
      {
        layer: "claude-mem",
        action: "Start worker service, load recent observations",
        blocking: true,
        tokens: "200-400",
        color: "blue",
      },
      {
        layer: "auto-memory",
        action: "Load MEMORY.md index + referenced files",
        blocking: true,
        tokens: "300-500",
        color: "emerald",
      },
      {
        layer: "beads",
        action: "bd prime: workflow + ready work + memories",
        blocking: true,
        tokens: "1000-2000",
        color: "cyan",
      },
    ],
  },
  {
    id: "user-prompt",
    name: "UserPromptSubmit",
    triggers: "every user message",
    layers: [
      {
        layer: "claude-mem",
        action: "session-init hook, keep worker alive",
        blocking: true,
        tokens: 0,
        color: "blue",
      },
    ],
  },
  {
    id: "post-tool-use",
    name: "PostToolUse",
    triggers: "after every tool call",
    layers: [
      {
        layer: "claude-mem",
        action: "Record observation: tool name, input, output, context",
        blocking: true,
        tokens: 0,
        color: "blue",
      },
    ],
  },
  {
    id: "agent-actions",
    name: "Agent-Initiated",
    triggers: "agent decides (no hook)",
    layers: [
      {
        layer: "beads",
        action: "bd create/update/close -- issue state changes",
        blocking: false,
        tokens: 0,
        color: "cyan",
      },
      {
        layer: "auto-memory",
        action: "Write preference/feedback markdown file",
        blocking: false,
        tokens: 0,
        color: "emerald",
      },
    ],
  },
  {
    id: "pre-compact",
    name: "PreCompact",
    triggers: "before context compaction",
    layers: [
      {
        layer: "beads",
        action: "bd prime re-fires to survive compaction",
        blocking: true,
        tokens: "1000-2000",
        color: "cyan",
      },
    ],
  },
  {
    id: "stop",
    name: "Stop",
    triggers: "agent stops generating",
    layers: [
      {
        layer: "claude-mem",
        action: "Generate session summary observation",
        blocking: true,
        tokens: 0,
        color: "blue",
      },
    ],
  },
  {
    id: "session-end",
    name: "SessionEnd",
    triggers: "session cleanup",
    layers: [
      {
        layer: "claude-mem",
        action: "HTTP POST to worker service -- persist observations",
        blocking: false,
        tokens: 0,
        color: "blue",
      },
    ],
  },
  {
    id: "between-sessions",
    name: "Between Sessions",
    triggers: "passive (no hook)",
    layers: [
      {
        layer: "episodic-memory",
        action: "Indexes transcript at next SessionStart",
        blocking: false,
        tokens: 0,
        color: "amber",
      },
    ],
  },
];

const LAYER_COLORS = {
  beads: "cyan",
  "auto-memory": "emerald",
  "claude-mem": "blue",
  "episodic-memory": "amber",
};
```

- [ ] **Step 4: Render the Timeline View**

The timeline view has two parts:

**Event bar** -- horizontal row of clickable event cards across the top. Each card shows:

- Event name (bold, --text color)
- Trigger text below (--text-dim, small)
- Colored dots for each layer that fires at this event (using LAYER_COLORS)
- Active card gets `--bg-card-hover` background and `--border-active` border

**Detail panel** -- below the event bar. When an event is clicked, shows:

- Event name as H3
- "Triggers: {triggers}" in text-dim
- A card per layer that fires, each containing:
  - Layer name with colored dot
  - Action description
  - Blocking badge (green "sync" or amber "async")
  - Token cost badge (if > 0)

Default state: SessionStart selected (the most interesting event).

CSS for event cards:

- `display: flex; gap: 12px; overflow-x: auto; padding-bottom: 8px;`
- Each card: `--bg-card` background, `--border` border, border-radius 8px, padding 16px, min-width 140px, cursor pointer
- Hover: `--bg-card-hover`
- Active: `--border-active` border, subtle box-shadow

CSS for detail panel:

- `--bg-raised` background, border-radius 12px, padding 24px, margin-top 24px
- Layer cards inside: `--bg-card` background, flex column, gap 8px

- [ ] **Step 5: Test in browser**

Open `html/agent-memory-lifecycle.html` in a browser. Verify:

- Dark theme renders correctly
- All 8 events show in the event bar
- Clicking each event updates the detail panel
- SessionStart shows all 4 layers
- PostToolUse shows only claude-mem
- Colored dots match the layer colors
- Token costs display correctly
- Responsive: cards wrap on narrow viewports

- [ ] **Step 6: Commit**

```bash
git add html/agent-memory-lifecycle.html
git commit -m "Add HTML companion scaffold with timeline view"
```

---

### Task 7: HTML Companion -- Layer Explorer

**Files:**

- Modify: `html/agent-memory-lifecycle.html`

- [ ] **Step 1: Define layer data model**

Add a `LAYERS` constant with full detail per layer:

```javascript
const LAYERS = [
  {
    id: "beads",
    name: "Beads (bd)",
    color: "cyan",
    description: "Durable work tracking with dependency awareness",
    captures: "Work items, dependencies, decisions, project facts",
    hooks: ["SessionStart (bd prime)", "PreCompact (bd prime)"],
    captureMethod: "Agent-initiated CLI commands",
    storage: "Dolt embedded DB (.beads/)",
    queryCommands: [
      "bd ready --json",
      "bd list --status=open",
      "bd show <id>",
      "bd memories <keyword>",
    ],
    tokenCost: "~1000-2000 at startup",
    failures: [
      "bd not installed",
      "bd init not run",
      "Stale issues accumulating",
    ],
    lossIfDisabled:
      "No persistent work tracking, no dependency-aware task discovery, no cross-session project facts",
  },
  {
    id: "auto-memory",
    name: "Auto-Memory",
    color: "emerald",
    description: "User preferences and behavioral feedback",
    captures: "User prefs, style corrections, brainstorm state",
    hooks: ["None (built-in, loads at session start)"],
    captureMethod: "Agent-initiated markdown file writes",
    storage: "Markdown files (~/.claude/projects/<path>/memory/)",
    queryCommands: ["Auto-loaded via MEMORY.md index"],
    tokenCost: "~300-500 at startup",
    failures: ["Stale project notes", "MEMORY.md > 200 lines truncated"],
    lossIfDisabled:
      "Agent forgets your preferences, repeats corrected mistakes, loses brainstorm state",
  },
  {
    id: "claude-mem",
    name: "Claude-Mem",
    color: "blue",
    description: "Automatic observation recording of all tool use",
    captures: "Tool call observations, session summaries",
    hooks: [
      "SessionStart",
      "UserPromptSubmit",
      "PostToolUse",
      "Stop",
      "SessionEnd",
    ],
    captureMethod: "Automatic -- PostToolUse hook on every tool call",
    storage: "Observation DB via worker service (localhost:37777)",
    queryCommands: [
      "search(query)",
      "timeline(anchor=ID)",
      "get_observations([IDs])",
    ],
    tokenCost: "~200-400 at startup",
    failures: ["Worker service down", "PostToolUse hook disabled"],
    lossIfDisabled:
      'Cannot search past actions, no "what files did we change?" capability, no session summaries',
  },
  {
    id: "episodic-memory",
    name: "Episodic Memory",
    color: "amber",
    description: "Searchable conversation history",
    captures: "Full conversation transcripts",
    hooks: ["SessionStart (async background sync)"],
    captureMethod: "Passive -- indexes saved transcripts",
    storage: "Indexed transcript database",
    queryCommands: ["search(query)", "read(path)"],
    tokenCost: "0 (async sync)",
    failures: ["Sync not running", "Index out of date"],
    lossIfDisabled:
      'Cannot search past discussions, no "why did we choose X?" capability, lose conversation context',
  },
];
```

- [ ] **Step 2: Render the Layer Explorer view**

Four layer cards, each toggleable. Layout:

- Grid of 4 cards (2x2 on desktop, 1 column on mobile)
- Each card has:
  - Colored left border (4px, using layer color)
  - Layer name (H3) with toggle switch in top-right corner
  - Description text
  - Sections for: Captures, Hooks, Query Commands, Token Cost, Failure Modes
  - Each section uses bold label + content text
  - Query commands shown as inline code spans

Toggle behavior:

- Toggle switch: simple CSS toggle (circle slides left/right, background changes from layer color to --text-muted)
- When toggled OFF: card fades to 30% opacity, shows a "loss" banner at top in --red-dim background with the `lossIfDisabled` text
- Default: all four layers ON

- [ ] **Step 3: Test in browser**

Open and verify:

- All 4 layer cards render with correct colors
- Toggle switches work (on/off state changes visually)
- Toggling OFF shows the loss banner
- Toggling back ON restores full card
- Cards are responsive (2x2 -> 1-col on narrow)

- [ ] **Step 4: Commit**

```bash
git add html/agent-memory-lifecycle.html
git commit -m "Add layer explorer with toggle and loss-if-disabled display"
```

---

### Task 8: HTML Companion -- Query Router

**Files:**

- Modify: `html/agent-memory-lifecycle.html`

- [ ] **Step 1: Define query routing data**

```javascript
const QUERY_ROUTES = [
  {
    category: "I need to find...",
    queries: [
      {
        question: "Unblocked work to do next",
        layer: "beads",
        command: "bd ready --json",
        why: "Beads tracks work items with blocking dependencies",
      },
      {
        question: "What I was working on",
        layer: "beads",
        command: "bd list --status=in_progress",
        why: "Beads persists issue status across sessions",
      },
      {
        question: "How we solved a similar problem",
        layer: "claude-mem",
        command: 'search("similar problem description")',
        why: "Claude-mem recorded the tool calls and outcomes",
      },
      {
        question: "Why we chose approach B over A",
        layer: "episodic-memory",
        command: 'search("chose approach B")',
        why: "The rationale lived in the conversation, not the actions",
      },
      {
        question: "My coding style preferences",
        layer: "auto-memory",
        command: "(auto-loaded at session start)",
        why: "User preferences are stored as auto-memory files",
      },
      {
        question: "What files we changed last session",
        layer: "claude-mem",
        command: 'search("files changed")',
        why: "PostToolUse hook recorded every file operation",
      },
      {
        question: "A conversation about architecture",
        layer: "episodic-memory",
        command: 'search("architecture discussion")',
        why: "Episodic-memory indexes full conversation transcripts",
      },
      {
        question: "A stable project fact",
        layer: "beads",
        command: "bd memories <keyword>",
        why: "bd remember stores persistent key-value facts",
      },
    ],
  },
  {
    category: "I need to store...",
    queries: [
      {
        question: "A new work item",
        layer: "beads",
        command: 'bd create --title="..." --type=task',
        why: "Beads tracks work with dependencies and priorities",
      },
      {
        question: "An architectural decision",
        layer: "beads",
        command: 'bd create --title="..." --type=decision',
        why: "Decision type captures project-scoped choices",
      },
      {
        question: "A stable project fact",
        layer: "beads",
        command: 'bd remember "fact" --key slug',
        why: "bd remember persists and auto-injects via bd prime",
      },
      {
        question: "A user preference",
        layer: "auto-memory",
        command: "Write user type markdown file",
        why: "User preferences are cross-project and auto-loaded",
      },
      {
        question: "A behavioral correction",
        layer: "auto-memory",
        command: "Write feedback type markdown file",
        why: "Feedback memories prevent repeating corrected mistakes",
      },
      {
        question: "Brainstorm state (not yet actionable)",
        layer: "auto-memory",
        command: "Write project type markdown file",
        why: "Project notes hold volatile exploration state",
      },
    ],
  },
];
```

- [ ] **Step 2: Render the Query Router view**

Two-panel layout:

**Left panel -- question list:**

- Two sections: "I need to find..." and "I need to store..."
- Each question is a clickable row with:
  - Question text (--text-body)
  - Small colored dot indicating the target layer
- Active row: --bg-card-hover background, --border-active left border

**Right panel -- answer detail:**

- Shows when a question is selected:
  - Layer name with colored badge
  - Command in a code block (--bg-inset background, IBM Plex Mono font)
  - "Why this layer?" explanation text (--text-dim)

Default state: first question selected ("Unblocked work to do next").

CSS:

- Two-panel: `display: grid; grid-template-columns: 1fr 1fr; gap: 24px;`
- On mobile (< 768px): single column, answer panel below
- Question rows: `padding: 12px 16px; cursor: pointer; border-left: 3px solid transparent;`
- Active row: `border-left-color: var(--<layer-color>); background: var(--bg-card-hover);`

- [ ] **Step 3: Test in browser**

Open and verify:

- Both "find" and "store" categories render with all questions
- Clicking a question highlights it and shows the answer panel
- Colored dots match the correct layer
- Command code blocks are readable
- Layout is responsive (2-col -> 1-col)

- [ ] **Step 4: Final full-page test**

Test all three tabs:

- Timeline: click through all 8 events, verify detail panels
- Layer Explorer: toggle each layer on/off, verify loss banners
- Query Router: click through all 14 questions, verify answers
- Tab switching: verify state resets appropriately between tabs

- [ ] **Step 5: Commit**

```bash
git add html/agent-memory-lifecycle.html
git commit -m "Add query router, completing HTML companion"
```

---

### Task 9: Update CLAUDE.md and Final Integration

**Files:**

- Modify: `CLAUDE.md` (project root)

- [ ] **Step 1: Add the new cheatsheet to the Content section**

Add an entry to the Content list in `CLAUDE.md` in alphabetical position:

```markdown
- **agent-memory-lifecycle-cheatsheet.md** -- AI agent memory lifecycle: four-layer system (beads, auto-memory, claude-mem, episodic-memory), session event map, capture vs query patterns, routing decision guide, failure taxonomy, token budget. Links to interactive session lifecycle explorer (agent-memory-lifecycle.html)
```

- [ ] **Step 2: Final end-to-end review**

Read both deliverables in full:

1. `agent-memory-lifecycle-cheatsheet.md` -- verify all 8 sections, consistent formatting, no broken markdown
2. `html/agent-memory-lifecycle.html` -- open in browser, test all 3 tabs, verify dark theme, responsive layout

Check cross-references:

- Cheatsheet opening links to `./html/agent-memory-lifecycle.html` -- verify the path is correct
- HTML companion content matches cheatsheet content (same events, same layers, same commands)

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "Add agent memory lifecycle cheatsheet to project content index"
```
