# godot-mcp-native

Drop-in Godot 4 editor plugin that runs a built-in MCP server, so Claude and other AI clients can control the editor with no Python, Node or extra setup.

> **Status: early release (v0.1.0).** Tested on Godot 4.7.2. It uses editor APIs that arrived around Godot 4.5, so older 4.x versions are not expected to work and have not been tested.

## How it works

```
Claude  <--MCP over HTTP (localhost)-->  Godot editor plugin (GDScript)
```

The plugin runs a small HTTP server inside the editor and speaks MCP directly. There is no separate server process to install or keep running.

## Install

**From the Godot Asset Library:** open the **AssetLib** tab in the editor, search for *Godot MCP Native*, download and install it.

**Manually:** copy `addons/godot_mcp_native/` from this repository into your project's `addons/` folder.

Then:

1. Open **Project > Project Settings > Plugins** and enable **Godot MCP Native**.
2. Open the **MCP** panel at the bottom of the editor and click the copy button for your client.

### Claude Code

Click **Copy Claude Code command** and run it in a terminal. It looks like:

```
claude mcp add --transport http godot-native http://127.0.0.1:6550/mcp
```

### Claude Desktop

Click **Copy Claude Desktop config** and merge it into `claude_desktop_config.json`, then restart Claude Desktop. If you already have other servers configured, use **Copy Claude Desktop entry only** and paste the block inside your existing `mcpServers` section. Claude Desktop starts local servers over stdio, so the config uses the `mcp-remote` bridge, which needs Node.js.

## Tools

**Inspect**

| Tool | What it does |
|---|---|
| `ping` | Confirms the editor is reachable; returns Godot version and project name |
| `get_scene_info` | Open scenes, the scene being edited, root node, node count, play state |
| `get_hierarchy` | Node tree of the edited scene (name, type, path, script) |
| `get_node_properties` | Editor-visible properties of a node |
| `list_files` | List project files, optionally by extension |

**Edit the open scene** (all undoable with Ctrl+Z)

| Tool | What it does |
|---|---|
| `create_node` | Create a node of any Godot node class, optionally with initial properties |
| `set_property` | Set a node property (Godot text form, JSON arrays for vectors/colors, `res://` paths for resources) |
| `delete_node` | Delete a node and its children (not the scene root) |
| `rename_node` / `reparent_node` / `duplicate_node` | Restructure the scene tree |
| `instantiate_scene` | Add an instance of another scene as a child |
| `set_transform` | Set position, rotation and scale of a 2D or 3D node |

**Scenes**

| Tool | What it does |
|---|---|
| `new_scene` | Create a scene file with a root node and open it |
| `open_scene` | Open an existing scene |
| `save_scene` | Save the edited scene, or save a new scene to a `res://` path |

**Scripts**

| Tool | What it does |
|---|---|
| `list_scripts` / `view_script` | List `.gd` files; read a script (line ranges supported) |
| `create_script` | Create a script, from a template or full source |
| `update_script` / `edit_script` | Replace a whole script, or an exact piece of text in it |
| `attach_script` | Attach or detach a script on a node |

Script tools report compile errors straight away (`compiles`, `compile_errors`).

**Project settings, input and resources**

| Tool | What it does |
|---|---|
| `list_project_settings` / `get_project_setting` / `set_project_setting` | Read and change project settings (saved to project.godot) |
| `list_input_actions` / `add_input_action` / `remove_input_action` | Manage the Input Map |
| `create_resource` / `get_resource_properties` / `set_resource_property` | Create and edit `.tres` resources (materials, themes, shapes, ...) |

**Run and debug**

| Tool | What it does |
|---|---|
| `play_scene` / `stop_scene` | Run the edited scene, the main scene or a `res://` scene; stop it |
| `get_output_log` | Recent log messages from the editor and the running game (filter with `source`) |
| `get_game_screenshot` | Image of what the running game is drawing |

Node paths are relative to the root of the scene being edited. Godot types such as `Vector3` or `Color` are returned in Godot text form, e.g. `"Vector3(1, 2, 3)"`.

## The game bridge

The running game is a separate process, so the plugin adds a small autoload (`GodotMcpNativeBridge`) to `project.godot` while it is enabled. It talks to the editor over Godot's debugger channel to provide game screenshots and game log output, and does nothing in exported builds. Disabling the plugin removes the autoload. If you export the project, remove the autoload (or the addon) first.

## Known limits

- **Undo:** scene edits go through the editor's undo/redo. Script files, project settings, input map changes and resource files are written straight to disk and are **not** undoable; use version control (git) to roll those back.
- **No deleting files.** The tools can create and edit files but never delete them.
- **GDScript only.** C# scripts are not supported by the script tools.
- **Editor only.** Tools work while the editor is open; the server is not part of exported games.
- **Plugin files are protected.** The plugin's own scripts and settings can't be changed through the tools.
- **Screenshots** show what the game's main viewport is drawing, downscaled by default.

## Security

The server binds to `127.0.0.1` only and rejects requests whose `Host` or `Origin` is not local. It can still modify your project, so only enable the plugin in projects you are comfortable letting your AI client edit.

**Port:** the server uses port 6550 by default. To run several Godot projects at once, give each its own port in the MCP panel (saved in that project's `project.godot`), or leave it and the plugin takes the next free port. After changing the port, re-copy the setup command for your AI client.

**Call log:** the MCP panel lists every tool call the AI makes (time, tool, short arguments, result and duration), so you can see what it is doing. Blocked calls are shown in orange.

**Read-only mode:** the MCP panel has a *Read-only mode* switch. While it is on, only tools that look but don't touch (reading scenes, scripts, settings, logs, screenshots) work; everything that changes the project or runs the game is refused. The switch is stored in your editor settings (not the project), and only a person can flip it, not the AI client. Read-only tools are marked with `readOnlyHint` in the tool list.

## Developing

Open this repository's root folder in Godot 4.7 (Project Manager > Import). `project.godot`, `scenes/` and `scripts/` are a minimal test project and are excluded from release archives by `.gitattributes`.

Quick check with the plugin enabled: open <http://127.0.0.1:6550/health> in a browser.

## License

MIT
