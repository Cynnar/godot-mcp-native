# godot-mcp-native

Drop-in Godot 4 editor plugin that runs a built-in MCP server, so Claude and other AI clients can control the editor with no Python, Node or extra setup.

> **Status: early development (v0.1.0).** The server, MCP protocol layer and a `ping` tool work end to end, plus the first read-only editor tools. Write tools (create/modify nodes, scripts, run/stop, screenshots) are next.

## How it works

```
Claude  <--MCP over HTTP (localhost)-->  Godot editor plugin (GDScript)
```

The plugin runs a small HTTP server inside the editor and speaks MCP directly. There is no separate server process to install or keep running.

## Install

1. Copy `addons/godot_mcp_native/` into your project's `addons/` folder.
2. Open **Project > Project Settings > Plugins** and enable **Godot MCP Native**.
3. Open the **MCP** panel at the bottom of the editor and click the copy button for your client.

### Claude Code

Click **Copy Claude Code command** and run it in a terminal. It looks like:

```
claude mcp add --transport http godot-native http://127.0.0.1:6550/mcp
```

### Claude Desktop

Click **Copy Claude Desktop config** and merge it into `claude_desktop_config.json`, then restart Claude Desktop. Claude Desktop starts local servers over stdio, so the config uses the `mcp-remote` bridge, which needs Node.js.

## Tools

| Tool | What it does |
|---|---|
| `ping` | Confirms the editor is reachable; returns Godot version and project name |
| `get_scene_info` | Open scenes, the scene being edited, root node, node count, play state |
| `get_hierarchy` | Node tree of the edited scene (name, type, path, script) |
| `get_node_properties` | Editor-visible properties of a node |

Node paths are relative to the root of the scene being edited. Godot types such as `Vector3` or `Color` are returned in Godot text form, e.g. `"Vector3(1, 2, 3)"`.

## Security

The server binds to `127.0.0.1` only and rejects requests whose `Host` or `Origin` is not local. It can still modify your project, so only enable the plugin in projects you are comfortable letting your AI client edit.

## Developing

Open this repository's root folder in Godot 4.7 (Project Manager > Import). `project.godot` is a minimal test project and is excluded from release archives by `.gitattributes`.

Quick check with the plugin enabled: open <http://127.0.0.1:6550/health> in a browser.

## License

MIT
