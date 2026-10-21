# godot-mcp-native

Drop-in Godot 4 editor plugin that runs a built-in MCP server, so Claude and other AI clients can control the editor with no Python, Node or extra setup.

> **Status: early development (v0.1.0).** The server, MCP protocol layer and a `ping` tool work end to end, plus read tools, undoable scene write tools, script tools and run control. Game screenshots and output from the running game are next.

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
| `create_node` | Create a node of any Godot node class, optionally with initial properties |
| `set_property` | Set a node property (supports Godot text form, JSON arrays for vectors/colors, `res://` paths for resources) |
| `delete_node` | Delete a node and its children (not the scene root) |
| `save_scene` | Save the edited scene, or save a new scene to a `res://` path |

| `list_scripts` | List `.gd` files in the project |
| `view_script` | Read a script (line ranges supported) |
| `create_script` | Create a script, from a template or full source |
| `update_script` | Replace a whole script file |
| `edit_script` | Replace an exact piece of text in a script |
| `attach_script` | Attach or detach a script on a node |
| `play_scene` | Run the edited scene, the main scene, or a `res://` scene |
| `stop_scene` | Stop the running scene |
| `get_output_log` | Recent log messages from the editor and the running game (filter with `source`) |
| `get_game_screenshot` | Image of what the running game is drawing |

Scene changes go through the editor's undo/redo, so **Ctrl+Z** reverts what the AI did. Script file changes are written to disk and are not part of that history, so use version control (git) to roll them back. The plugin's own scripts are protected from modification.

The running game is a separate process, so the plugin adds a small autoload (`GodotMcpNativeBridge`) to `project.godot` while it is enabled. It talks to the editor over Godot's debugger channel to provide game screenshots and game log output, and does nothing in exported builds. Disabling the plugin removes the autoload. If you export the project, remove the autoload (or the addon) first.

Node paths are relative to the root of the scene being edited. Godot types such as `Vector3` or `Color` are returned in Godot text form, e.g. `"Vector3(1, 2, 3)"`.

## Security

The server binds to `127.0.0.1` only and rejects requests whose `Host` or `Origin` is not local. It can still modify your project, so only enable the plugin in projects you are comfortable letting your AI client edit.

## Developing

Open this repository's root folder in Godot 4.7 (Project Manager > Import). `project.godot` is a minimal test project and is excluded from release archives by `.gitattributes`.

Quick check with the plugin enabled: open <http://127.0.0.1:6550/health> in a browser.

## License

MIT
