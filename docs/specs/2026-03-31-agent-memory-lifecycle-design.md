# AI Agent Memory Lifecycle Cheatsheet -- Design Spec

An event-driven reference for Claude Code's four-layer memory system: beads (work tracking), auto-memory (preferences/feedback), claude-mem (observations), and episodic-memory (conversation search). Traces the full session lifecycle showing which layers fire at each event, what they capture, and how to query them. Includes an interactive HTML companion that lets users click through session events and explore layer interactions.

## Audience

Claude Code power users who want to understand and adopt a multi-layer memory architecture for their agent workflows. Not abstracted to general patterns -- names the specific tools throughout. Readers are comfortable with CLI tools, hooks, and MCP concepts.

## Relationship to Existing Cheatsheets

- **ai-agent-architecture-cheatsheet.md** covers agent memory conceptually (short-term, long-term, episodic types)
- **context-engineering-cheatsheet.md** covers the four context operations (write/select/compress/isolate) at the prompt level
- This cheatsheet sits below both: the concrete event-driven mechanics of how memory actually flows through a Claude Code session, with specific hooks, commands, and token costs

## Structure

### Section 1: Opening Hook

1-2 sentence framing of the problem: agents forget everything between sessions and even mid-session during compaction. Four complementary systems fix this by hooking into different moments of the session lifecycle.

Link to interactive HTML companion.

### Section 2: The Four Layers at a Glance

Comparison table introducing all four layers. Columns:

| Column           | Purpose                                                |
| ---------------- | ------------------------------------------------------ |
| Layer            | Name (beads, auto-memory, claude-mem, episodic-memory) |
| What it captures | One-line description of the data type                  |
| How it captures  | Hook-driven vs agent-initiated vs background           |
| How you query it | Primary retrieval command or mechanism                 |
| Persistence      | Where data lives and how long                          |
| Token cost       | Startup injection overhead                             |

This table establishes the mental model before any event-level detail. Include a simple ASCII diagram showing the four layers as parallel tracks alongside a session timeline arrow.

```text
Session Start ──── Work ──── Compact ──── Work ──── Stop
     │                │          │           │        │
  ┌──┴──┐          ┌──┴──┐   ┌──┴──┐     ┌──┴──┐  ┌─┴──┐
  │bd   │          │bd   │   │bd   │     │bd   │  │    │
  │auto │          │c-mem│   │prime│     │c-mem│  │c-m │
  │c-mem│          │     │   │     │     │     │  │    │
  │epi  │          │     │   │     │     │     │  │    │
  └─────┘          └─────┘   └─────┘     └─────┘  └────┘
```

(Actual diagram to be refined during implementation -- the point is showing which layers are active at which lifecycle moments.)

### Section 3: Session Lifecycle Event Map

The core of the cheatsheet. A chronological walk through every event in a Claude Code session, showing what fires and what it does.

Events in order:

**SessionStart** (triggers: startup, clear, compact, resume)

| Order | System          | Hook type | Blocking?  | Action                                                             | Token cost |
| ----- | --------------- | --------- | ---------- | ------------------------------------------------------------------ | ---------- |
| 1     | episodic-memory | command   | No (async) | Background sync of conversation index                              | 0          |
| 2     | claude-mem      | command   | Yes        | Start worker service, load context                                 | ~200-400   |
| 3     | auto-memory     | built-in  | Yes        | Load MEMORY.md index + referenced files                            | ~300-500   |
| 4     | beads           | command   | Yes        | `bd prime`: workflow instructions + ready work + bd remember facts | ~1000-2000 |

**UserPromptSubmit** (triggers: every user message)

| System     | Action                                                       |
| ---------- | ------------------------------------------------------------ |
| claude-mem | session-init hook -- prepares turn state, keeps worker alive |

**PostToolUse** (triggers: after every tool call)

| System     | Action                                                 |
| ---------- | ------------------------------------------------------ |
| claude-mem | Records observation: tool name, input, output, context |

This is the hook that makes claude-mem fundamentally different from the other layers. It sees every Read, Edit, Bash, Grep -- the complete action stream.

**Agent-Initiated Actions** (no hook trigger -- agent decides to do these)

| System      | When                                   | What happens                                                                   |
| ----------- | -------------------------------------- | ------------------------------------------------------------------------------ |
| beads       | Agent creates/updates/closes work      | `bd create`, `bd update --claim`, `bd close` -- issue state changes in Dolt DB |
| beads       | Agent stores a fact                    | `bd remember "fact" --key slug` -- persists in Dolt config                     |
| auto-memory | Agent captures a preference/correction | Writes markdown file to `~/.claude/projects/<path>/memory/`                    |
| TaskCreate  | Agent tracks session progress          | Ephemeral checklist (disappears at session end)                                |

**PreCompact** (triggers: before context compaction)

| System | Action                                                                       |
| ------ | ---------------------------------------------------------------------------- |
| beads  | `bd prime` re-fires -- re-injects workflow context so it survives compaction |

Note: auto-memory and claude-mem context survive compaction natively (system prompt level). Beads needs re-injection because `bd prime` output is injected as tool output, which gets compacted.

**Stop** (triggers: agent stops generating)

| System     | Action                                |
| ---------- | ------------------------------------- |
| claude-mem | Generates session summary observation |

**SessionEnd** (triggers: session cleanup)

| System     | Action                                                                              |
| ---------- | ----------------------------------------------------------------------------------- |
| claude-mem | HTTP POST to worker service at localhost:37777 -- persists observations to database |

**Between Sessions** (no hook -- happens passively)

| System          | What happens                                         |
| --------------- | ---------------------------------------------------- |
| Claude Code     | Writes conversation transcript to disk               |
| episodic-memory | Indexes transcript at next SessionStart (async sync) |

Include an ASCII timeline diagram showing all events on a horizontal axis with the four layers as swim lanes, marking which events activate which lanes.

### Section 4: Layer Deep Dives

One subsection per layer. Each follows a consistent template:

**Template:**

- **What it stores** -- data model description
- **Hook integration** -- which hooks, sync vs async, what triggers them
- **Capture mechanism** -- how data enters the system (automatic vs explicit)
- **Storage backend** -- where data lives, format, durability characteristics
- **Query patterns** -- how to retrieve data, with command examples
- **Token cost** -- startup injection and per-query overhead
- **Failure modes** -- what breaks, how to detect, how to recover

#### 4a: Beads (`bd`)

- Stores: work items with dependencies, decisions, persistent facts
- Hooks: SessionStart (`bd prime`), PreCompact (`bd prime`)
- Capture: agent-initiated via CLI commands
- Storage: Dolt embedded database in `.beads/`
- Query: `bd ready`, `bd list`, `bd show`, `bd search`, `bd memories`
- Token cost: ~1000-2000 at startup (prime output)
- Failure modes: bd not installed, bd init not run, Dolt corruption, stale issues accumulating

#### 4b: Auto-Memory

- Stores: user preferences, behavioral feedback, brainstorm state
- Hooks: none (built-in to Claude Code, loads at session start automatically)
- Capture: agent-initiated writes to markdown files with YAML frontmatter
- Storage: markdown files in `~/.claude/projects/<path>/memory/`
- Query: auto-loaded via MEMORY.md index at session start (no explicit query needed)
- Token cost: ~300-500 at startup (depends on file count)
- Failure modes: stale project notes, bloated MEMORY.md (>200 lines truncated), conflicting instructions with bd prime

#### 4c: Claude-Mem

- Stores: tool call observations, session summaries, semantic snapshots
- Hooks: SessionStart (worker start + context load), UserPromptSubmit (session-init), PostToolUse (record observation), Stop (summarize), SessionEnd (persist)
- Capture: automatic -- PostToolUse hook records every tool invocation silently
- Storage: observation database accessed via worker service (localhost:37777)
- Query: MCP tools -- `search(query)` -> `timeline(anchor=ID)` -> `get_observations([IDs])`
- Token cost: ~200-400 at startup (context summary injection)
- Failure modes: worker service not running, PostToolUse hook disabled, observation DB corruption

#### 4d: Episodic Memory

- Stores: full conversation transcripts indexed for semantic search
- Hooks: SessionStart (async background sync)
- Capture: passive -- indexes Claude Code's saved conversation files after the fact
- Storage: indexed transcript database (managed by episodic-memory plugin)
- Query: MCP tools -- `search(query)` for semantic/text search, `read(path)` for full transcript
- Token cost: 0 at startup (async sync adds no tokens)
- Failure modes: sync not running, conversation files missing, index out of date

### Section 5: Capture vs Query Quick Reference

Two tables for daily use:

**"I need to find X" -- Query Guide:**

| I need to...                             | Layer           | Command/Action                      |
| ---------------------------------------- | --------------- | ----------------------------------- |
| Find unblocked work                      | beads           | `bd ready --json`                   |
| See what I was working on                | beads           | `bd list --status=in_progress`      |
| Recover what we tried last session       | claude-mem      | `search("what we tried")`           |
| Find why we chose approach B             | episodic-memory | `search("chose approach B")`        |
| Check my coding style preferences        | auto-memory     | (auto-loaded, check MEMORY.md)      |
| Find a similar bug fix from last month   | claude-mem      | `search("bug fix <description>")`   |
| Recall a conversation about architecture | episodic-memory | `search("architecture discussion")` |
| Look up a project fact                   | beads           | `bd memories <keyword>`             |

**Claude-mem vs Episodic-Memory Heuristic:**

| You're thinking...                | Use             | Why                                     |
| --------------------------------- | --------------- | --------------------------------------- |
| "We fixed a bug like this before" | claude-mem      | It recorded the tool calls and outcome  |
| "We talked about two approaches"  | episodic-memory | The conversation had the reasoning      |
| "What files did we change?"       | claude-mem      | Observations track every tool use       |
| "Why did we choose B over A?"     | episodic-memory | Rationale lived in discussion           |
| "Did we already try Y?"           | claude-mem      | It captured the attempt                 |
| "Mark said something about Z"     | episodic-memory | Verbal instruction, not observed action |

One-liner: claude-mem is a lab notebook (what you did). Episodic-memory is a meeting transcript (what you discussed).

**"I have knowledge X" -- Routing Guide:**

| Knowledge type         | Where to store | Command                                   |
| ---------------------- | -------------- | ----------------------------------------- |
| Work item              | beads          | `bd create --title="..." --type=task`     |
| Architectural decision | beads          | `bd create --title="..." --type=decision` |
| Stable project fact    | beads          | `bd remember "fact" --key slug`           |
| User preference        | auto-memory    | Write `user` type markdown file           |
| Behavioral correction  | auto-memory    | Write `feedback` type markdown file       |
| Brainstorm state       | auto-memory    | Write `project` type markdown file        |

### Section 6: Routing Decision Guide

ASCII decision tree for "where does this knowledge go?"

```text
Is it work to be done?
  ├─ Yes: Does it span sessions? ──► bd create
  │       └─ No (single session) ──► TaskCreate (ephemeral)
  │
Is it a fact about this project?
  ├─ Yes: Will it change often?
  │       ├─ No (stable) ──► bd remember
  │       └─ Yes (volatile brainstorm) ──► auto-memory project type
  │
Is it about how I work?
  ├─ Yes: Is it a correction? ──► auto-memory feedback type
  │       └─ A preference? ──► auto-memory user type
  │
Is it a decision we made?
  └─ Yes: Project-scoped? ──► bd create --type=decision
          └─ Cross-project? ──► auto-memory feedback type
```

Include edge cases and "when you pick wrong" guidance. The fallback rule: if you stored it somewhere and can't find it, check the other obvious candidate.

### Section 7: Failure Taxonomy

Table of failure modes across all four layers:

| Failure                  | Layer               | Symptom                               | Detection                            | Recovery                                |
| ------------------------ | ------------------- | ------------------------------------- | ------------------------------------ | --------------------------------------- |
| Hook doesn't fire        | any                 | Missing context at session start      | Check `.claude/settings.local.json`  | Re-run setup command                    |
| Worker service down      | claude-mem          | Observations not recorded             | `curl localhost:37777` returns error | Restart session                         |
| Stale memories           | auto-memory         | Outdated info loaded                  | Review MEMORY.md manually            | Delete stale files                      |
| bd not initialized       | beads               | `bd` commands fail                    | `bd doctor`                          | `bd init`                               |
| Compaction loses context | beads               | Agent forgets current work            | Check `bd list --status=in_progress` | PreCompact hook should re-inject        |
| Transcript not indexed   | episodic-memory     | Recent conversations not searchable   | Search returns stale results         | `episodic-memory sync` manually         |
| Conflicting instructions | beads + auto-memory | Agent confused about MEMORY.md policy | bd prime says no, CLAUDE.md says yes | CLAUDE.md routing rules take precedence |

### Section 8: Token Budget

Full accounting table:

| Component              | Tokens             | Source                      |
| ---------------------- | ------------------ | --------------------------- |
| System prompt + skills | ~15,000-20,000     | Built-in                    |
| Global CLAUDE.md       | ~2,800             | User rules                  |
| Project CLAUDE.md      | ~400-1,200         | Per-project                 |
| Auto-memory files      | ~300-500           | MEMORY.md + files           |
| Claude-mem context     | ~200-400           | Recent observations         |
| bd prime               | ~1,000-2,000       | Workflow + ready + memories |
| **Total startup**      | **~19,700-26,900** | **~10-13% of 200K window**  |

Include guidance on optimization: pruning `bd remember` entries, keeping MEMORY.md under 200 lines, using `bd stale` to clean old issues.

Close with the tradeoff framing: more memory context = better recall but less room for work. The sweet spot is ~12-15% of the context window for memory, leaving 85%+ for actual work.

## HTML Companion: Session Lifecycle Explorer

Single-file HTML tool (`html/agent-memory-lifecycle.html`) matching the existing companion pattern (dark theme, CSS variables from parallel-dispatch.html).

### Interactive Features

**Timeline View (default):**

- Horizontal timeline showing session events (SessionStart, UserPromptSubmit, PostToolUse, PreCompact, Stop, SessionEnd)
- Four swim lanes (one per layer) below the timeline
- Click an event to highlight which layers fire and see details in a panel
- Each event shows: what triggers it, which hooks run, what gets captured/injected, token cost

**Layer Explorer:**

- Toggle layers on/off to see the system with different combinations
- When a layer is disabled, show what you lose (e.g., disable episodic-memory -> lose conversation search)
- Each layer card shows: hook integration, capture mechanism, query commands, failure modes

**Query Router (decision tree, not live search):**

- Select from common question patterns ("I need to find...", "I need to store...")
- Decision tree routes to the correct layer and shows the specific command
- Example: select "find unblocked work" -> highlights beads layer -> shows `bd ready --json`
- Example: select "why did we choose X?" -> highlights episodic-memory -> shows `search("chose X")`

### Design Constraints

- Single HTML file, no external dependencies (vanilla JS, embedded CSS)
- Dark theme matching existing companions (CSS variables from parallel-dispatch.html color system)
- Responsive layout
- All content self-contained -- works offline from `file://` protocol
