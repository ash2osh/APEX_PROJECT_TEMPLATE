# SQLcl MCP R0 Client Configurations

Use an absolute SQLcl executable path and add `-R`, `0`, `-mcp` in that order. Preserve unrelated settings. Never place database passwords in these files; SQLcl uses saved connections from the SQLcl connection store.

## Contents

- [Project-local discovery](#project-local-discovery)
- [Codex](#codex)
- [Claude Desktop](#claude-desktop)
- [Claude Code](#claude-code)
- [Antigravity/Gemini](#antigravitygemini)
- [TNS and Java environment](#tns-and-java-environment)
- [Verification after every client change](#verification-after-every-client-change)

## Project-local discovery

Keep `.agents/skills/sqlcl-mcp-r0/` as the canonical project skill. Use thin
native entry points so each client discovers the same guidance without copying
the full skill:

| Client | Project instructions | Native skill wrapper |
|---|---|---|
| Codex and Agent Skills clients | `AGENTS.md` | `.agents/skills/sqlcl-mcp-r0/SKILL.md` |
| Claude Code | `CLAUDE.md` | `.claude/skills/sqlcl-mcp-r0/SKILL.md` |

The Codex and Claude Code project instructions import or point to `AGENTS.md`;
each skill entry point resolves to the canonical `.agents` skill. Restart or
reload an existing client session after changing discovery files.

Find your local SQLcl executable path with `which sql` (Linux/macOS) or
`where sql` (Windows) before editing any client config below.

## Codex

Linux/macOS: edit `~/.codex/config.toml`. Keep the existing server table and set:

```toml
[mcp_servers.sqlcl]
command = "/absolute/path/to/sql"
args = ["-R", "0", "-mcp"]
```

Restart the Codex app or MCP session after changing the file.

## Claude Desktop

Typical locations:

- Linux: `~/.config/Claude/claude_desktop_config.json`
- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`

Add or update only the `sqlcl` server:

```json
{
  "mcpServers": {
    "sqlcl": {
      "command": "/absolute/path/to/sql",
      "args": ["-R", "0", "-mcp"]
    }
  }
}
```

If TNS resolution is required, add only a non-secret environment path:

```json
"env": {
  "TNS_ADMIN": "/absolute/path/to/tns-admin"
}
```

Restart Claude Desktop and inspect its MCP log if the server does not appear.

## Claude Code

Preferred command-line registration:

```bash
claude mcp add sqlcl /absolute/path/to/sql -- -R 0 -mcp
claude mcp list
```

For a project-scoped configuration, use `.mcp.json` at the repository root:

```json
{
  "mcpServers": {
    "sqlcl": {
      "command": "/absolute/path/to/sql",
      "args": ["-R", "0", "-mcp"]
    }
  }
}
```

Some Claude Code installations store user-scoped servers in `~/.claude.json` with a different surrounding JSON shape. Preserve that shape and change only the existing SQLcl `args` array. Use `claude mcp list` to confirm the effective registration.

## Antigravity/Gemini

Typical Gemini CLI location:

- Linux/macOS: `~/.gemini/config/mcp_config.json`
- Windows: `%USERPROFILE%\.gemini\config\mcp_config.json`

Add the standard MCP registry if it is absent:

```json
{
  "mcpServers": {
    "sqlcl": {
      "command": "/absolute/path/to/sql",
      "args": ["-R", "0", "-mcp"]
    }
  }
}
```

## TNS and Java environment

MCP clients may not inherit interactive-shell variables. If required, add `TNS_ADMIN`, `JAVA_HOME`, or a UTF-8 JVM option in the client’s `env` block without putting credentials there:

```json
"env": {
  "TNS_ADMIN": "/absolute/path/to/network-admin",
  "JAVA_HOME": "/absolute/path/to/jre-17"
}
```

Prefer SQLcl’s saved connection store (`conn -save name -savepwd ...`). Never print or copy the connection store, wallet, password, token, or private key into an agent prompt, skill, or repository.

## Verification after every client change

1. Parse the configuration with its native parser.
2. Confirm the SQLcl command path exists and run `sql -V`.
3. Confirm the exact argument sequence is `-R`, `0`, `-mcp`.
4. Restart the client so stale child processes do not hide the change.
5. Run the harmless capability probe from the main skill and record the effective result.
