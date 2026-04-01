# tdd-pr Skill Design

A Claude Code skill that takes a GitHub issue from zero to green tests on a branch, with code review, then hands off to the appropriate PR workflow.

## Invocation

```bash
/tdd-pr <gh_issue> [branch] [--auto]
```

- `gh_issue` -- GitHub issue number or URL (required)
- `branch` -- branch name to create or checkout (optional; auto-generated from issue title if omitted)
- `--auto` -- skip the review pause, auto-select and invoke the hand-off skill

## Phases

### Phase 1: Setup

1. Fetch issue details via `gh issue view <gh_issue> --json title,body,labels`
2. Parse issue for acceptance criteria, affected files/areas, and scope
3. If issue lacks clear acceptance criteria: stop, present what was found, ask user to clarify before proceeding
4. Create or checkout the target branch:
   - If `branch` arg provided: create or checkout that branch
   - If omitted: generate branch name from issue (e.g., `issue-123-add-widget-validation`)
   - If branch already has commits: continue from current state, do not reset

**Output:** Branch ready, list of acceptance criteria to implement.

### Phase 2: TDD Loop

Delegates to `superpowers:test-driven-development` for each acceptance criterion.

For each criterion:

1. **RED** -- Write a failing test that demonstrates the desired behavior
2. **Verify RED** -- Run the test suite, confirm the new test fails for the right reason
3. **GREEN** -- Write the minimal code to make the test pass
4. **Verify GREEN** -- Run the full test suite, confirm all tests pass with pristine output
5. **REFACTOR** -- Clean up implementation while staying green

Repeat for each acceptance criterion in the issue.

**Failure mode:** If the same criterion fails 3 RED-to-GREEN cycles (test written but implementation can't pass it), stop and ask the user for help. Summarize what was attempted and what's blocking.

**Output:** All acceptance criteria covered by passing tests, implementation complete.

### Phase 3: Review Checkpoint

Skipped entirely if `--auto` flag is set.

1. Create a single WIP commit with all changes
2. Run the `code-reviewer` agent on the diff (branch vs base branch)
3. Present a summary to the user:
   - What was implemented (mapped to acceptance criteria)
   - Test results (pass count, coverage if available)
   - Code review findings (issues, suggestions)
4. Wait for user input:
   - "proceed" or similar -- move to Phase 4
   - Specific feedback -- address it, re-run review, re-present summary
   - "stop" -- leave work on branch, user takes over manually

**Output:** Reviewed, committed code on branch, user approval to proceed.

### Phase 4: Hand-off

1. Compute diff stats: files changed, lines added/removed
2. Apply hand-off heuristic:
   - If diff touches **3 or fewer files** AND **100 or fewer lines changed**: suggest `/commit-push-pr`
   - Otherwise: suggest `/git-workflow`
3. Present the suggestion to the user with the reasoning
4. User confirms or overrides the choice
5. Invoke the selected skill

If `--auto` flag is set: auto-select based on the heuristic and invoke without asking.

**Output:** Hand-off to PR workflow skill.

## What This Skill Does NOT Do

- Write PR descriptions (git-workflow handles that)
- Run breaking change analysis (git-workflow handles that)
- Manage CI/CD checks (git-workflow handles that)
- Make architectural decisions (implements what the issue specifies)

## Skill Metadata

```yaml
name: tdd-pr
description: >
  Use when asked to implement a GitHub issue using TDD, or when the user
  invokes /tdd-pr. Takes a GitHub issue from zero to green tests on a branch,
  runs code review, then hands off to the appropriate PR workflow.
```

## Dependencies

| Dependency                                  | Phase                   | Plugin / Install                                                                          |
| ------------------------------------------- | ----------------------- | ----------------------------------------------------------------------------------------- |
| `superpowers:test-driven-development` skill | Phase 2                 | `superpowers@superpowers-marketplace` plugin (enabled via settings.json `enabledPlugins`) |
| `superpowers:code-reviewer` agent           | Phase 3                 | Same `superpowers@superpowers-marketplace` plugin                                         |
| `/git-workflow` command                     | Phase 4 (large changes) | `git-pr-workflows@claude-code-workflows` plugin                                           |
| `/commit-push-pr` command                   | Phase 4 (small changes) | `commit-commands@claude-plugins-official` plugin                                          |
| `gh` CLI                                    | Phase 1                 | `brew install gh` (not a plugin -- system dependency)                                     |
