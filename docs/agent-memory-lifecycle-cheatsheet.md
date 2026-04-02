# AI Agent Memory Lifecycle Cheatsheet

AI coding agents forget everything between sessions -- and even mid-session when the context window compacts. Four complementary systems fix this by hooking into different moments of the Claude Code session lifecycle, each capturing a different type of knowledge.

Companion to the [interactive session lifecycle explorer](./html/agent-memory-lifecycle.html).

---

## The Four Layers at a Glance

| Layer               | What It Captures                                        | How It Captures                                            | How You Query It                                                | Persistence                                          | Token Cost |
| ------------------- | ------------------------------------------------------- | ---------------------------------------------------------- | --------------------------------------------------------------- | ---------------------------------------------------- | ---------- |
| **beads** (`bd`)    | Work items, dependencies, decisions, project facts      | Agent-initiated CLI commands                               | `bd ready`, `bd show`, `bd memories`                            | Dolt embedded DB (`.beads/`)                         | ~1000-2000 |
| **auto-memory**     | User preferences, behavioral feedback, brainstorm state | Agent-initiated markdown file writes                       | Auto-loaded at session start via MEMORY.md                      | Markdown files (`~/.claude/projects/<path>/memory/`) | ~300-500   |
| **claude-mem**      | Tool call observations, session summaries               | Automatic -- PostToolUse hook on every tool call           | MCP: `search()` -> `timeline()` -> `get_observations()`         | Observation DB via worker service (localhost:37777)  | ~200-400   |
| **episodic-memory** | Full conversation transcripts                           | Passive -- indexes saved transcripts at next session start | MCP: `search()` for semantic/text, `read()` for full transcript | Indexed transcript database                          | 0 (async)  |

### Session Lifecycle Swim-Lane

Each column is a session event. A box means that layer fires at that event.

```text
               Session    User       Post       Pre-       Stop    Session
               Start      Prompt     ToolUse    Compact            End
                 │          │          │          │          │        │
─────────────────┼──────────┼──────────┼──────────┼──────────┼────────┼────
                 │          │          │          │          │        │
  beads        ┌──────┐                         ┌──────┐
               │  bd  │  ·····agent-initiated····│  bd  │
               │prime │  ·····bd create/close····│prime │
               └──────┘                         └──────┘
                 │          │          │          │          │        │
─────────────────┼──────────┼──────────┼──────────┼──────────┼────────┼────
                 │          │          │          │          │        │
  auto-memory  ┌──────┐
               │MEMORY│  ·····agent-initiated····
               │.md   │  ·····write pref files···
               │loaded│
               └──────┘
                 │          │          │          │          │        │
─────────────────┼──────────┼──────────┼──────────┼──────────┼────────┼────
                 │          │          │          │          │        │
  claude-mem   ┌──────┐  ┌──────┐  ┌──────┐              ┌──────┐ ┌──────┐
               │worker│  │session│  │record│              │summa-│ │persis│
               │start │  │-init │  │obser-│              │rize  │ │t to  │
               │+load │  │      │  │vation│              │      │ │  DB  │
               └──────┘  └──────┘  └──────┘              └──────┘ └──────┘
                 │          │          │          │          │        │
─────────────────┼──────────┼──────────┼──────────┼──────────┼────────┼────
                 │          │          │          │          │        │
  episodic-    ┌──────┐
  memory       │async │  (indexes transcripts from previous session)
               │ sync │
               └──────┘
                 │          │          │          │          │        │
─────────────────┴──────────┴──────────┴──────────┴──────────┴────────┴────
```

**claude-mem** is the most active layer -- it hooks into five of seven events. **beads** bookends the session (prime at start, re-prime before compaction). **auto-memory** loads once and is written to on demand. **episodic-memory** operates only at session boundaries, costing zero tokens during active work.

---

## Session Lifecycle Event Map

A Claude Code session fires events at predictable moments. Each event triggers zero or more memory layers. This section walks through every event in order, showing what fires and what it does.

### SessionStart

Triggers: `startup`, `clear`, `compact`, `resume`

Four layers fire -- three synchronously (blocking), one asynchronously (background):

| Order | System          | Hook Type | Blocking?  | Action                                                               | Token Cost |
| ----- | --------------- | --------- | ---------- | -------------------------------------------------------------------- | ---------- |
| 1     | episodic-memory | command   | No (async) | Background sync of conversation index                                | 0          |
| 2     | claude-mem      | command   | Yes        | Start worker service, load recent observations                       | ~200-400   |
| 3     | auto-memory     | built-in  | Yes        | Load MEMORY.md index + referenced markdown files                     | ~300-500   |
| 4     | beads           | command   | Yes        | `bd prime`: workflow instructions + ready work + `bd remember` facts | ~1000-2000 |

Total startup injection: ~1500-2900 tokens across all four layers. On a 200K context window, that is about 1-1.5%.

### UserPromptSubmit

Triggers on every user message. Only claude-mem responds.

| System     | Hook Type    | Action                                  |
| ---------- | ------------ | --------------------------------------- |
| claude-mem | session-init | Prepares turn state, keeps worker alive |

### PostToolUse

Triggers after every tool call. Only claude-mem responds.

| System     | Hook Type   | Action                                                 |
| ---------- | ----------- | ------------------------------------------------------ |
| claude-mem | observation | Records observation: tool name, input, output, context |

This is the hook that makes claude-mem fundamentally different from the other three layers. It fires on every Read, Edit, Bash, Grep -- the complete action stream. This is why claude-mem can answer "what files did we change last session?" while episodic-memory cannot.

### Agent-Initiated Actions

No hook trigger -- the agent decides to do these during normal work.

| System      | When                                   | What Happens                                                        |
| ----------- | -------------------------------------- | ------------------------------------------------------------------- |
| beads       | Agent creates/updates/closes work      | `bd create`, `bd update --claim`, `bd close` -- issue state in Dolt |
| beads       | Agent stores a fact                    | `bd remember "fact" --key slug` -- persists in Dolt config          |
| auto-memory | Agent captures a preference/correction | Writes markdown file to `~/.claude/projects/<path>/memory/`         |
| TaskCreate  | Agent tracks session progress          | Ephemeral checklist (disappears at session end)                     |

### PreCompact

Before context compaction. Only beads responds -- `bd prime` re-fires to re-inject workflow context.

| System | Hook Type | Action                                                            |
| ------ | --------- | ----------------------------------------------------------------- |
| beads  | command   | `bd prime`: re-injects workflow instructions + ready work + facts |

auto-memory and claude-mem context survive compaction natively (loaded at system prompt level). Beads needs re-injection because `bd prime` output enters as tool output, which gets compacted.

### Stop

Agent stops generating. Only claude-mem responds.

| System     | Hook Type | Action                                  |
| ---------- | --------- | --------------------------------------- |
| claude-mem | summary   | Generates a session summary observation |

### SessionEnd

Session cleanup. Only claude-mem responds.

| System     | Hook Type | Action                                                                                 |
| ---------- | --------- | -------------------------------------------------------------------------------------- |
| claude-mem | persist   | HTTP POST to worker service at localhost:37777 to persist observations to the database |

### Between Sessions

No hook -- happens passively. Claude Code writes the conversation transcript to disk. Episodic-memory indexes it at the next SessionStart via async sync. This is why episodic-memory's capture is delayed -- it is always one session behind.

---

## Layer Deep Dives

Each layer follows a consistent template: what it stores, how it hooks in, how data enters, where it lives, how to query it, what it costs, and what breaks.

### Beads (bd)

**What it stores:** Work items with blocking dependencies, architectural decisions (`--type=decision`), persistent project facts (`bd remember`). Issues have hash-based IDs (e.g., `technical-cheatsheets-c37`), priorities 0-4, and types (task, bug, feature, epic, chore, decision).

**Hook integration:** Two hooks -- SessionStart and PreCompact. Both run `bd prime` which outputs workflow instructions, the current ready-work list, and all `bd remember` entries. Synchronous (blocking).

**Capture mechanism:** Agent-initiated. The agent explicitly runs `bd create`, `bd update`, `bd close`, `bd remember`. Nothing is captured automatically.

**Storage:** Dolt embedded database in `.beads/` directory. SQL-backed with cell-level merge for conflict resolution. Auto-commits each write to Dolt history.

**Query patterns:**

| Action              | Command                        |
| ------------------- | ------------------------------ |
| Find unblocked work | `bd ready --json`              |
| List open issues    | `bd list --status=open --json` |
| View issue details  | `bd show <id> --json`          |
| Search by keyword   | `bd search "query"`            |
| List stored facts   | `bd memories`                  |
| Search facts        | `bd memories <keyword>`        |

**Token cost:** ~1000-2000 tokens at startup via `bd prime`. Zero per-query cost (CLI output goes to the agent, not injected into context).

**Failure modes:**

| Failure                   | Symptom                           | Recovery                                          |
| ------------------------- | --------------------------------- | ------------------------------------------------- |
| `bd` not installed        | Command not found                 | `brew install beads`                              |
| `bd init` not run         | No `.beads/` directory            | `bd init` (or `bd init --stealth` for docs repos) |
| Stale issues accumulating | `bd ready` returns too many items | `bd stale` to find old issues, close or defer     |
| Dolt corruption           | bd commands error on SQL          | `bd doctor`, or re-init from backup               |

### Auto-Memory

**What it stores:** User preferences (`user` type), behavioral corrections (`feedback` type), in-progress brainstorm state (`project` type). Each memory is a markdown file with YAML frontmatter (name, description, type fields).

**Hook integration:** None -- built into Claude Code. MEMORY.md index and referenced files are loaded into the system prompt automatically at session start.

**Capture mechanism:** Agent-initiated. The agent writes a markdown file to `~/.claude/projects/<path>/memory/` and updates the MEMORY.md index.

**Storage:** Markdown files on disk. One file per memory, indexed by MEMORY.md. MEMORY.md is capped at 200 lines (truncated beyond that).

**Query patterns:** No explicit query needed -- auto-loaded at session start. The agent can also read specific memory files with the Read tool if needed.

**Token cost:** ~300-500 tokens at startup (varies with file count, ~200-300 per file).

**Failure modes:**

| Failure                   | Symptom                                          | Recovery                                      |
| ------------------------- | ------------------------------------------------ | --------------------------------------------- |
| Stale project notes       | Outdated info loaded every session               | Delete the stale `.md` file, update MEMORY.md |
| MEMORY.md > 200 lines     | Late entries silently truncated                  | Consolidate entries, keep index concise       |
| Conflicting with bd prime | bd prime says "no MEMORY.md", CLAUDE.md says yes | CLAUDE.md routing rules take precedence       |

### Claude-Mem

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
search(query)           -> index with IDs (~50-100 tokens/result)
    |
timeline(anchor=ID)     -> context around interesting results
    |
get_observations([IDs]) -> full details for filtered IDs
```

Also: `smart_search(query)` for tree-sitter AST-based code symbol search, `smart_outline(file)` for structural file outlines.

**Token cost:** ~200-400 tokens at startup (context summary injection). Per-query cost varies with result count.

**Failure modes:**

| Failure                    | Symptom                              | Recovery                                          |
| -------------------------- | ------------------------------------ | ------------------------------------------------- |
| Worker service not running | Observations not recorded            | Restart session (SessionStart hook restarts it)   |
| PostToolUse hook disabled  | No observations captured during work | Check `.claude/settings.json` for hook config     |
| Observation DB corruption  | Search returns errors                | Delete DB, observations rebuild over new sessions |

### Episodic Memory

**What it stores:** Full conversation transcripts indexed for semantic and text search.

**Hook integration:** One hook -- SessionStart (async). Runs `episodic-memory sync --background` which indexes conversation files Claude Code has written to disk since the last sync.

**Capture mechanism:** Passive. Claude Code writes conversation transcripts to disk automatically. Episodic-memory indexes them in the background at the next session start. It never fires during active work.

**Storage:** Indexed transcript database managed by the episodic-memory plugin.

**Query patterns:**

| Tool                             | Purpose                                                                                |
| -------------------------------- | -------------------------------------------------------------------------------------- |
| `search(query)`                  | Semantic + text search across all conversations. Returns ranked results with snippets. |
| `read(path, startLine, endLine)` | Read full conversation transcript. Use pagination for large conversations.             |

**Token cost:** 0 at startup (async sync adds no tokens). Per-query cost varies.

**Failure modes:**

| Failure                    | Symptom                                      | Recovery                                             |
| -------------------------- | -------------------------------------------- | ---------------------------------------------------- |
| Sync not running           | Recent conversations not searchable          | `episodic-memory sync` manually                      |
| Conversation files missing | Search returns no results for known sessions | Check Claude Code conversation storage directory     |
| Index out of date          | Search misses recent work                    | Wait for next SessionStart sync, or trigger manually |

---

## Capture vs Query Quick Reference

### "I need to find X"

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

### Claude-Mem vs Episodic Memory

| You're thinking...                | Use             | Why                                        |
| --------------------------------- | --------------- | ------------------------------------------ |
| "We fixed a bug like this before" | claude-mem      | Recorded the tool calls and outcome        |
| "We talked about two approaches"  | episodic-memory | The conversation had the reasoning         |
| "What files did we change?"       | claude-mem      | Observations track every tool use          |
| "Why did we choose B over A?"     | episodic-memory | Rationale lived in the discussion          |
| "Did we already try Y?"           | claude-mem      | Captured the attempt and result            |
| "Mark said something about Z"     | episodic-memory | Verbal instruction, not an observed action |

Claude-mem is a lab notebook (what you did). Episodic-memory is a meeting transcript (what you discussed).

The difference comes from how they hook in: claude-mem hooks into PostToolUse (watches every action in real-time). Episodic-memory hooks into SessionStart (indexes saved transcripts after the fact). Different capture mechanisms produce different retrieval strengths.

### "I have knowledge X"

| Knowledge Type         | Where to Store | Command                                   |
| ---------------------- | -------------- | ----------------------------------------- |
| Work item              | beads          | `bd create --title="..." --type=task`     |
| Architectural decision | beads          | `bd create --title="..." --type=decision` |
| Stable project fact    | beads          | `bd remember "fact" --key slug`           |
| User preference        | auto-memory    | Write `user` type markdown file           |
| Behavioral correction  | auto-memory    | Write `feedback` type markdown file       |
| Brainstorm state       | auto-memory    | Write `project` type markdown file        |

---

## Routing Decision Guide

```text
What kind of knowledge is this?
│
├── Work to be done?
│   ├── Spans sessions or has dependencies ────> bd create
│   └── Single-session progress tracking ──────> TaskCreate (ephemeral)
│
├── A fact about this project?
│   ├── Stable (rarely changes) ──────────────> bd remember
│   └── Volatile (brainstorm in flux) ────────> auto-memory project type
│
├── About how I work?
│   ├── A correction ("don't do X") ──────────> auto-memory feedback type
│   └── A preference ("I like Y") ────────────> auto-memory user type
│
├── A decision we made?
│   ├── Project-scoped ───────────────────────> bd create --type=decision
│   └── Cross-project ───────────────────────> auto-memory feedback type
│
└── None of the above?
    └── Probably doesn't need persisting. Let it go.
```

**When you pick wrong:** If you stored something and can't find it, check the other obvious candidate. The layers have minimal overlap, so the fallback search space is small.

**When it fits two places:** Route by lifecycle. If it has open/close semantics (work to be done), it goes in beads. If it is a static truth, it goes in `bd remember` or auto-memory depending on scope (project-scoped vs cross-project).
## Failure Taxonomy

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

## Token Budget

| Component                      | Tokens             | Source                                |
| ------------------------------ | ------------------ | ------------------------------------- |
| System prompt + skills catalog | ~15,000-20,000     | Built-in (varies with enabled skills) |
| Global CLAUDE.md               | ~2,800             | User rules + memory routing           |
| Project CLAUDE.md              | ~400-1,200         | Per-project (beads adds ~500)         |
| Auto-memory files              | ~300-500           | MEMORY.md + 2-3 referenced files      |
| Claude-mem context             | ~200-400           | Recent observations summary           |
| `bd prime`                     | ~1,000-2,000       | Workflow + ready work + memories      |
| **Total startup**              | **~19,700-26,900** | **~10-13% of 200K window**            |

- Keep `bd remember` entries under 15 per project (`bd memories` to review, `bd forget <key>` to prune)
- Keep MEMORY.md under 200 lines (entries beyond 200 are truncated)
- Use `bd stale` periodically to close old issues (reduces `bd prime` ready-work output)
- Auto-memory `project` type notes should be migrated to beads epics once they become actionable work

More memory context means better recall but less room for work. The sweet spot is 12-15% of the context window for memory, leaving 85%+ for the actual task.
