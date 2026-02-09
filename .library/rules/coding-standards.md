# Coding Standards

## Golang (go)

- Always follow these tips for writing clear, idiomatic Go code: <https://go.dev/doc/effective_go>
- Always follow the official Golang coding best practices and style guidelines located here: <https://google.github.io/styleguide/go/>,
  here: <https://google.github.io/styleguide/go/decisions>, and here: <https://google.github.io/styleguide/go/best-practices>

  | Document            | Link                                                    | Primary Audience    | [Normative] | [Canonical] |
  | ------------------- | ------------------------------------------------------- | ------------------- | ----------- | ----------- |
  | **Style Guide**     | <https://google.github.io/styleguide/go/guide>          | Everyone            | Yes         | Yes         |
  | **Style Decisions** | <https://google.github.io/styleguide/go/decisions>      | Readability Mentors | Yes         | No          |
  | **Best Practices**  | <https://google.github.io/styleguide/go/best-practices> | Anyone interested   | No          | No          |

## Bash Scripting

- See the enabled **bash** skill for shell scripting standards (shebang portability, defensive patterns)

## JavaScript/TypeScript Tooling

- ALWAYS use `bun` instead of `npm` for package management and script execution when available

## Claude Code Configuration

- Use `claudeup local` to manage local extensions (agents, commands, skills, hooks, rules, output-styles)
- `claudeup local list` - show all items and their enabled status
- `claudeup local enable <category> <items...>` - enable items (supports wildcards like `gsd-*`)
- `claudeup local disable <category> <items...>` - disable items
- `claudeup local install <category> <path>` - install items from external paths
- `claudeup local view <category> <item>` - view item contents
- Items live in `~/.claude/.library/<category>/` with symlinks in `~/.claude/<category>/` when enabled
