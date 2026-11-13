import Foundation
import RisingKitCore

/// `RisingKit --mcp`: 표준 입출력으로 MCP(JSON-RPC 2.0, 한 줄에 메시지 하나)를 말한다.
/// 도구 호출은 실행 중인 Rising Kit 앱으로 넘긴다.
enum MCPServer {
    private static let tools: [[String: Any]] = [
        [
            "name": "list_windows",
            "description": "List open windows of regular apps (app, title, frame, display, minimized, focused) and the displays with their usable areas. Displays are numbered from 0, left to right. Coordinates are in points with the origin at the top-left of the primary display.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "place_window",
            "description": "Move and resize a window. Pick the window with `app` (name or bundle id; omit for the frontmost app) and optionally `title` (substring). Give `placement` (a preset; on the window's current display unless `display` is set), `display` alone (move there keeping proportions), or an explicit x/y/width/height. Returns the frame the window actually ended up with, which can differ from the request when the app enforces a minimum size.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "app": ["type": "string", "description": "App name or bundle id. Omit to use the frontmost app."],
                    "title": ["type": "string", "description": "Substring of the window title. Omit to use the app's focused window."],
                    "placement": ["type": "string", "enum": Placement.allCases.map(\.rawValue)],
                    "display": ["type": "number", "description": "Target display index from list_windows."],
                    "x": ["type": "number"], "y": ["type": "number"],
                    "width": ["type": "number"], "height": ["type": "number"],
                    "activate": ["type": "boolean", "description": "Also bring the window to the front. Default false."],
                ] as [String: Any],
            ],
        ],
        [
            "name": "audio_balance",
            "description": "Read or fix the left/right balance of the current audio output. `status` reports it (0.0 left, 0.5 center, 1.0 right), `center` resets it to the center once, `lock`/`unlock` turn automatic re-centering on or off.",
            "inputSchema": [
                "type": "object",
                "properties": ["action": ["type": "string", "enum": ["status", "center", "lock", "unlock"]]],
            ],
        ],
        [
            "name": "pdf_to_png",
            "description": "Convert PDF files to PNG images. A one-page PDF becomes `name.png` beside it; a multi-page PDF becomes a `name-png/` folder with one PNG per page. Existing files are never overwritten. Returns the written paths.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "paths": ["type": "array", "items": ["type": "string"], "description": "Absolute paths of PDF files."],
                    "dpi": ["type": "number", "description": "Resolution. Defaults to the app setting (150)."],
                ] as [String: Any],
                "required": ["paths"],
            ],
        ],
        [
            "name": "scrum_draft",
            "description": "Build a daily stand-up draft from the user's own git commits: what was done on the previous working day (Friday through Sunday when run on Monday) and what has been committed so far today, grouped by project as `project - subject` lines under date headers like `[26.11.12 (목)]`. Only commits authored by the user are included, and only from the repositories selected in Rising Kit's settings (all discovered repositories when none were chosen). Pass `repositories` (keys like `owner/name`, listed in the result's `available`) to use a different set for this call. Read-only.",
            "inputSchema": [
                "type": "object",
                "properties": ["repositories": ["type": "array", "items": ["type": "string"]]],
            ],
        ],
        [
            "name": "tidy_files",
            "description": "Tidy old screenshots and downloads into month folders (nothing is deleted). `preview` lists what would move, `run` moves them, `undo` puts back what the last run moved. Screenshots older than 7 days go to a `스크린샷 모음/YYYY-MM` folder beside them; download items older than 30 days go to `~/Downloads/지난 다운로드/YYYY-MM`.",
            "inputSchema": [
                "type": "object",
                "properties": ["action": ["type": "string", "enum": ["preview", "run", "undo"]]],
            ],
        ],
        [
            "name": "system_usage",
            "description": "Read-only snapshot of memory and CPU: memory used/total, swap, memory pressure, overall CPU percent over the last ~5 seconds, and the top apps by memory and by CPU (helper processes are summed into their parent app; per-app CPU is per core, so it can exceed 100).",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "weather",
            "description": "Current weather and a forecast of up to 4 days for the city shown in the menu bar (temperatures in Celsius, source: MET Norway). Pass `city` to switch the menu bar to another city first.",
            "inputSchema": [
                "type": "object",
                "properties": ["city": ["type": "string", "description": "City name to switch to, e.g. \"부산\" or \"Tokyo\". Omit to keep the current city."]],
            ],
        ],
        [
            "name": "run_command",
            "description": "Run a Rising Kit command by id, exactly as its hotkey would: e.g. `map.toggle` opens the display map, `launcher.toggle` the launcher, `window.leftHalf` places the frontmost window, `layout:NAME` applies a layout. Ids come from list_shortcuts.",
            "inputSchema": ["type": "object", "properties": ["command": ["type": "string"]], "required": ["command"]],
        ],
        [
            "name": "list_shortcuts",
            "description": "List every command with its current global hotkey and its default. Includes window placements, the launcher, the display map, and one command per saved layout (`layout:NAME`) and zone (`zone:NAME`).",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "set_shortcut",
            "description": "Change the global hotkey of a command. `shortcut` is modifiers joined by + and one key, e.g. \"ctrl+opt+1\" or \"cmd+shift+f5\" (keys: letters, digits, left/right/up/down, return, delete, space, tab, f1-f12). Pass \"\" to remove the hotkey or \"default\" to restore the default. Fails if another command already uses the combination.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "Command id from list_shortcuts."],
                    "shortcut": ["type": "string"],
                ] as [String: Any],
                "required": ["command", "shortcut"],
            ],
        ],
        [
            "name": "list_layouts",
            "description": "List saved layouts (which app window goes on which display, as fractions of that display's usable area) and custom zones, with their hotkeys.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "save_layout",
            "description": "Save a named window layout, replacing one with the same name. Without `items` it captures the windows currently visible on screen. With `items` it stores exactly what you describe; each app must be running so it can be identified. Bind it to a hotkey afterwards with set_shortcut on `layout:NAME`. To make a hotkey that sends ONE app's window to a spot (e.g. \"KakaoTalk to the top-right quarter of display 2\"), save a layout with a single item and `activate: true`, then bind it: top-right quarter = {x:0.5, y:0, width:0.5, height:0.5}; displays are numbered from 0, so the user's \"display 2\" is display 1.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "activate": ["type": "boolean", "description": "Also bring the moved windows to the front when the layout is applied. Use for single-app hotkeys."],
                    "items": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "app": ["type": "string", "description": "App name or bundle id."],
                                "title": ["type": "string", "description": "Exact window title, to tell apart several windows of one app. Optional."],
                                "display": ["type": "number", "description": "Display index, 0 = leftmost. Default 0."],
                                "rect": [
                                    "type": "object",
                                    "description": "Fractions 0-1 of the display's usable area, e.g. left half = {x:0, y:0, width:0.5, height:1}.",
                                    "properties": ["x": ["type": "number"], "y": ["type": "number"],
                                                   "width": ["type": "number"], "height": ["type": "number"]],
                                    "required": ["x", "y", "width", "height"],
                                ] as [String: Any],
                            ] as [String: Any],
                            "required": ["app", "rect"],
                        ] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any],
                "required": ["name"],
            ],
        ],
        [
            "name": "apply_layout",
            "description": "Apply a saved layout now. Returns how many windows moved and which apps were skipped because they are not running or have no open window.",
            "inputSchema": ["type": "object", "properties": ["name": ["type": "string"]], "required": ["name"]],
        ],
        [
            "name": "delete_layout",
            "description": "Delete a saved layout and its hotkey.",
            "inputSchema": ["type": "object", "properties": ["name": ["type": "string"]], "required": ["name"]],
        ],
        [
            "name": "save_zone",
            "description": "Define a custom placement for the frontmost window: a rectangle given as fractions of a display's usable area. Omit `display` to use whichever display the window is on. Bind it to a hotkey with set_shortcut on `zone:NAME`.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "display": ["type": "number"],
                    "rect": [
                        "type": "object",
                        "properties": ["x": ["type": "number"], "y": ["type": "number"],
                                       "width": ["type": "number"], "height": ["type": "number"]],
                        "required": ["x", "y", "width", "height"],
                    ] as [String: Any],
                ] as [String: Any],
                "required": ["name", "rect"],
            ],
        ],
        [
            "name": "delete_zone",
            "description": "Delete a custom zone and its hotkey.",
            "inputSchema": ["type": "object", "properties": ["name": ["type": "string"]], "required": ["name"]],
        ],
    ]

    static func run() -> Never {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty, let data = line.data(using: .utf8),
                  let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            // id 가 없으면 알림이므로 응답하지 않는다
            guard let id = message["id"] else { continue }
            let params = message["params"] as? [String: Any] ?? [:]

            switch message["method"] as? String {
            case "initialize":
                reply(id, result: [
                    "protocolVersion": params["protocolVersion"] as? String ?? "2024-11-05",
                    "capabilities": ["tools": [String: Any]()],
                    "serverInfo": ["name": "rising-kit", "version": "0.11.2"],
                ])
            case "ping":
                reply(id, result: [String: Any]())
            case "tools/list":
                reply(id, result: ["tools": tools])
            case "tools/call":
                let response = Control.send([
                    "tool": params["name"] as? String ?? "",
                    "arguments": params["arguments"] as? [String: Any] ?? [:],
                ])
                if let error = response["error"] as? String {
                    reply(id, result: ["content": [["type": "text", "text": error]], "isError": true])
                } else {
                    let result = response["result"] ?? [String: Any]()
                    let text = (try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    reply(id, result: ["content": [["type": "text", "text": text]]])
                }
            default:
                send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found"]])
            }
        }
        exit(0)
    }

    private static func reply(_ id: Any, result: [String: Any]) {
        send(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private static func send(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}
