#if canImport(UIKit)
import Foundation
import HappyCore
import HappyWire

/// Static demo fixtures and rich seeded data for exploring every Happy UI/UX feature offline.
enum DemoData {
    static let nowMs: Double = (Date().timeIntervalSince1970 * 1000).rounded()

    static func ago(_ minutes: Double) -> Double {
        (Date().timeIntervalSince1970 * 1000 - minutes * 60_000).rounded()
    }

    static let ridoyThumb = "1QcSHQRnh493V4dIh4eXh1h4kJUI"
    static let adaThumb = "HBkSHYSIeHiPiHh8eJd4eTN0EEQG"
    static let botThumb = "HwgKPJxwd3dweHiHiHdwgAf3iA"

    static func healthJSON(isCloud: Bool) -> JSONValue {
        .object([
            "ready": .bool(true),
            "ok": .bool(true),
            "version": .object(["protocol": .number(27)]),
            "instanceId": .string(isCloud ? "demo0000-0000-7000-8000-000000000001" : "demo0000-0000-7000-8000-000000000002"),
            "capabilities": .object([
                "vaults": .bool(true),
                "plugins": .bool(isCloud),
                "pipelines": .bool(isCloud),
                "feed": .bool(true),
                "feedSubjectFilter": .bool(true),
                "artifactCovers": .bool(true),
                "dailyUsage": .bool(true),
                "collaborativeDocuments": .bool(true),
                "userEnvironment": .bool(true),
                "surfaceEditing": .bool(true),
                "artifactSecretActions": .bool(true),
            ]),
        ])
    }

    static func configJSON(name: String) -> JSONValue {
        .object([
            "config": .object([
                "node": .object([
                    "name": .string(name),
                    "avatar": .object(["thumbhash": .string(botThumb)]),
                ]),
                "defaults": .object([
                    "providerId": .string("claude"),
                    "modelId": .string("anthropic/claude-sonnet-4-5"),
                    "permissionMode": .string("auto"),
                ]),
                "models": .object([
                    "anthropic/claude-opus-4-5": .object([
                        "name": .string("Claude Opus 4.5"),
                        "efforts": .array([.string("low"), .string("medium"), .string("high")]),
                        "defaultEffort": .string("high"),
                        "serviceTiers": .array([.string("standard"), .string("priority")]),
                        "serviceTierOptions": .array([
                            .object(["id": .null, "label": .string("Standard")]),
                            .object(["id": .string("priority"), "label": .string("Fast")]),
                        ]),
                        "contextWindow": .number(200_000),
                        "autoCompactWindow": .number(165_000),
                    ]),
                    "anthropic/claude-sonnet-4-5": .object([
                        "name": .string("Claude Sonnet 4.5"),
                        "efforts": .array([.string("low"), .string("medium"), .string("high")]),
                        "defaultEffort": .string("medium"),
                        "serviceTiers": .array([.string("standard"), .string("priority")]),
                        "serviceTierOptions": .array([
                            .object(["id": .null, "label": .string("Standard")]),
                            .object(["id": .string("priority"), "label": .string("Fast")]),
                        ]),
                        "contextWindow": .number(200_000),
                        "autoCompactWindow": .number(165_000),
                    ]),
                    "openai/gpt-5-codex": .object([
                        "name": .string("GPT-5 Codex"),
                        "efforts": .array([.string("medium"), .string("high")]),
                        "defaultEffort": .string("medium"),
                        "contextWindow": .number(256_000),
                        "autoCompactWindow": .number(210_000),
                    ]),
                ]),
                "providers": .object([
                    "claude": .object([
                        "name": .string("Claude Max"),
                        "type": .string("claude"),
                        "enabled": .bool(true),
                        "hidden": .bool(false),
                        "models": .array([
                            .object(["id": .string("anthropic/claude-opus-4-5"), "enabled": .bool(true)]),
                            .object(["id": .string("anthropic/claude-sonnet-4-5"), "enabled": .bool(true)]),
                        ]),
                    ]),
                    "codex": .object([
                        "name": .string("OpenAI Codex"),
                        "type": .string("codex"),
                        "enabled": .bool(true),
                        "hidden": .bool(false),
                        "models": .array([
                            .object(["id": .string("openai/gpt-5-codex"), "enabled": .bool(true)]),
                        ]),
                    ]),
                ]),
            ]),
        ])
    }

    static var usersJSON: JSONValue {
        .object([
            "users": .array([
                .object(["id": .string("ridoy"), "name": .string("Ridoy"), "photo": .object(["thumbhash": .string(ridoyThumb)]), "version": .string("1"), "updatedAt": .number(1)]),
                .object(["id": .string("ada"), "name": .string("Ada"), "photo": .object(["thumbhash": .string(adaThumb)]), "version": .string("1"), "updatedAt": .number(1)]),
                .object(["id": .string("bo"), "name": .string("Bo"), "photo": .null, "version": .string("1"), "updatedAt": .number(1)]),
                .object(["id": .string("olga"), "name": .string("Olga"), "photo": .null, "version": .string("1"), "updatedAt": .number(1)]),
            ]),
        ])
    }

    static func usageJSON() -> JSONValue {
        let now = Date().timeIntervalSince1970 * 1000
        let fiveHourReset = now + 2.5 * 3600 * 1000
        let weeklyReset = now + 4 * 86400 * 1000
        return .object([
            "providers": .array([
                .object([
                    "providerId": .string("claude"),
                    "refreshedAt": .number(now - 60_000),
                    "usage": .object([
                        "planName": .string("Max 20×"),
                        "capturedAt": .number(now - 60_000),
                        "exhausted": .bool(false),
                        "windows": .object([
                            "fiveHour": .object(["usedPercent": .number(34), "resetsAt": .number(fiveHourReset), "capturedAt": .number(now - 60_000)]),
                            "weekly": .object(["usedPercent": .number(58), "resetsAt": .number(weeklyReset), "capturedAt": .number(now - 60_000)]),
                        ]),
                    ]),
                ]),
                .object([
                    "providerId": .string("codex"),
                    "refreshedAt": .number(now - 120_000),
                    "usage": .object([
                        "planName": .string("Pro"),
                        "capturedAt": .number(now - 120_000),
                        "exhausted": .bool(false),
                        "windows": .object([
                            "fiveHour": .object(["usedPercent": .number(18), "resetsAt": .number(fiveHourReset), "capturedAt": .number(now - 120_000)]),
                            "weekly": .object(["usedPercent": .number(27), "resetsAt": .number(weeklyReset), "capturedAt": .number(now - 120_000)]),
                        ]),
                    ]),
                ]),
            ]),
            "day": .object([
                "claude": .object([
                    "anthropic/claude-sonnet-4-5": .object(["input": .number(142_000), "output": .number(38_500), "cacheRead": .number(680_000), "cacheWrite": .number(44_000)]),
                    "anthropic/claude-opus-4-5": .object(["input": .number(64_000), "output": .number(19_200), "cacheRead": .number(210_000), "cacheWrite": .number(18_000)]),
                ]),
                "codex": .object([
                    "openai/gpt-5-codex": .object(["input": .number(48_000), "output": .number(16_400), "cacheRead": .number(95_000), "cacheWrite": .number(8_000)]),
                ]),
            ]),
            "week": .object([
                "claude": .object([
                    "anthropic/claude-sonnet-4-5": .object(["input": .number(980_000), "output": .number(265_000), "cacheRead": .number(4_200_000), "cacheWrite": .number(310_000)]),
                    "anthropic/claude-opus-4-5": .object(["input": .number(410_000), "output": .number(128_000), "cacheRead": .number(1_450_000), "cacheWrite": .number(140_000)]),
                ]),
                "codex": .object([
                    "openai/gpt-5-codex": .object(["input": .number(320_000), "output": .number(98_000), "cacheRead": .number(640_000), "cacheWrite": .number(54_000)]),
                ]),
            ]),
            "month": .object([
                "claude": .object([
                    "anthropic/claude-sonnet-4-5": .object(["input": .number(3_850_000), "output": .number(1_040_000), "cacheRead": .number(18_400_000), "cacheWrite": .number(1_220_000)]),
                    "anthropic/claude-opus-4-5": .object(["input": .number(1_620_000), "output": .number(510_000), "cacheRead": .number(6_100_000), "cacheWrite": .number(490_000)]),
                ]),
                "codex": .object([
                    "openai/gpt-5-codex": .object(["input": .number(1_240_000), "output": .number(380_000), "cacheRead": .number(2_800_000), "cacheWrite": .number(210_000)]),
                ]),
            ]),
        ])
    }

    static func dailyUsageJSON(days: Int, timeZone: String) -> JSONValue {
        let tz = TimeZone(identifier: timeZone) ?? .current
        let totalDays = min(max(days, 30), 120)
        var entries: [JSONValue] = []
        let today = Date()
        var since = UsageDates.day(today, in: tz)
        for offset in stride(from: totalDays - 1, through: 0, by: -1) {
            guard let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: -offset, to: today) else { continue }
            let dayString = UsageDates.day(date, in: tz)
            if offset == totalDays - 1 { since = dayString }
            // Deterministic varied activity so the heatmap has realistic contrast.
            let seed = (offset * 37 + 13) % 10
            if seed == 0 { continue }
            let mult = (seed % 5) + 1
            entries.append(.object([
                "date": .string(dayString),
                "byProvider": .object([
                    "claude": .object([
                        "anthropic/claude-sonnet-4-5": .object([
                            "input": .number(Double(38_000 * mult)),
                            "output": .number(Double(11_000 * mult)),
                            "cacheRead": .number(Double(180_000 * mult)),
                            "cacheWrite": .number(Double(12_000 * mult)),
                        ]),
                    ]),
                    "codex": .object([
                        "openai/gpt-5-codex": .object([
                            "input": .number(Double(12_000 * ((seed % 3) + 1))),
                            "output": .number(Double(4_200 * ((seed % 3) + 1))),
                            "cacheRead": .number(Double(30_000 * ((seed % 3) + 1))),
                            "cacheWrite": .number(Double(2_500 * ((seed % 3) + 1))),
                        ]),
                    ]),
                ]),
            ]))
        }
        return .object(["since": .string(since), "days": .array(entries)])
    }

    static let pluginCatalogJSON = #"""
    {"plugins":[
      {"id":"github","name":"GitHub","description":"Repositories, issues and pull requests, for agents to read and act on.","version":"1.0.0",
       "image":{"digest":"github","mime":"image/png","thumbhash":null},
       "tools":[{"name":"list_repositories","summary":"Lists the repositories the installation can reach."},
                {"name":"get_issue","summary":"Reads one issue with its comments."},
                {"name":"create_pull_request","summary":"Opens a pull request from a branch."}],
       "auth":{"required":true,"methods":[
         {"id":"install","label":"GitHub App","type":"oauth","scopes":["contents:read","metadata:read"]},
         {"id":"token","label":"Access token","type":"fields","fields":[
           {"key":"token","label":"Personal access token","help":"Demo token — any value works offline.","required":true,"secret":true,"multiline":false}]}]}},
      {"id":"linear","name":"Linear","description":"Issues, projects and cycles.","version":"0.4.2",
       "image":{"digest":"linear","mime":"image/png","thumbhash":null},
       "tools":[{"name":"search_issues","summary":"Finds issues by text."}],"auth":{"required":false,"methods":[]}},
      {"id":"sentry","name":"Sentry","description":"Errors and performance from production.","version":"2.1.0",
       "image":{"digest":"sentry","mime":"image/png","thumbhash":null},
       "tools":[{"name":"list_issues","summary":"Lists unresolved issues."}],
       "auth":{"required":true,"methods":[
         {"id":"key","label":"Auth token","type":"fields","fields":[
           {"key":"token","label":"Auth token","help":"Demo token — any value works offline.","required":true,"secret":true,"multiline":false},
           {"key":"org","label":"Organization slug","help":"","required":true,"secret":false,"multiline":false}]}]}}
    ]}
    """#

    static let slashCommands: [JSONValue] = [
        .object(["name": .string("review"), "hasArguments": .bool(true), "description": .string("Review recent workspace changes")]),
        .object(["name": .string("plan"), "hasArguments": .bool(true), "description": .string("Draft an implementation plan"), "kind": .string("skill")]),
        .object(["name": .string("test"), "hasArguments": .bool(false), "description": .string("Run the test suite and summarize failures")]),
        .object(["name": .string("ship"), "hasArguments": .bool(false), "description": .string("Prepare release notes and checklist"), "kind": .string("skill")]),
    ]

    static let skillsJSON: JSONValue = .object([
        "skills": .array([
            .object(["name": .string("plan"), "description": .string("Draft a step-by-step architecture plan"), "hasArguments": .bool(true)]),
            .object(["name": .string("ship"), "description": .string("Run release verification and notes"), "hasArguments": .bool(false)]),
            .object(["name": .string("genui-demo"), "description": .string("Generate interactive GenUI widgets"), "hasArguments": .bool(true)]),
        ]),
        "nextPageCursor": .null,
    ])

    static func systemMonitorJSON() -> JSONValue {
        let now = Date().timeIntervalSince1970 * 1000
        let points: [JSONValue] = (0..<24).map { idx in
            let t = now - Double(23 - idx) * 5_000
            let cpu = 22.0 + Double((idx * 7) % 19)
            return .object([
                "sampledAt": .number(t),
                "cpuPercent": .number(cpu),
                "memoryUsedBytes": .number(18.4 * 1024 * 1024 * 1024 + Double(idx) * 24_000_000),
                "diskReadBytesPerSecond": .number(Double(1_200_000 + idx * 140_000)),
                "diskWriteBytesPerSecond": .number(Double(420_000 + idx * 55_000)),
            ])
        }
        return .object([
            "host": .object([
                "hostname": .string("ridoy-studio-mac"),
                "platform": .string("darwin"),
                "arch": .string("arm64"),
                "osName": .string("macOS 26.1"),
                "uptimeSeconds": .number(412_900),
            ]),
            "cpu": .object([
                "model": .string("Apple M3 Max"),
                "logicalCores": .number(14),
                "usagePercent": .number(31.4),
                "perCoreUsagePercent": .array([48, 36, 41, 29, 25, 19, 34, 42, 22, 18, 28, 31, 35, 32].map { .number(Double($0)) }),
                "loadAverage": .array([.number(2.41), .number(2.18), .number(1.94)]),
                "speedMhz": .number(4056),
                "temperatureCelsius": .number(54.2),
            ]),
            "memory": .object([
                "totalBytes": .number(36 * 1024 * 1024 * 1024),
                "usedBytes": .number(18.9 * 1024 * 1024 * 1024),
                "availableBytes": .number(17.1 * 1024 * 1024 * 1024),
                "cachedBytes": .number(7.4 * 1024 * 1024 * 1024),
                "swapTotalBytes": .number(2 * 1024 * 1024 * 1024),
                "swapUsedBytes": .number(128 * 1024 * 1024),
            ]),
            "gpu": .object([
                "name": .string("Apple M3 Max 30-Core GPU"),
                "vendor": .string("Apple"),
                "usagePercent": .number(14.5),
                "memoryTotalBytes": .number(24 * 1024 * 1024 * 1024),
                "memoryUsedBytes": .number(4.2 * 1024 * 1024 * 1024),
                "temperatureCelsius": .number(49.0),
                "powerWatts": .number(11.6),
            ]),
            "disks": .array([
                .object([
                    "mountPoint": .string("/"),
                    "device": .string("/dev/disk3s1s1"),
                    "fileSystem": .string("apfs"),
                    "totalBytes": .number(1000 * 1024 * 1024 * 1024),
                    "usedBytes": .number(468 * 1024 * 1024 * 1024),
                    "availableBytes": .number(532 * 1024 * 1024 * 1024),
                ]),
            ]),
            "diskIO": .object([
                "readBytesPerSecond": .number(3_400_000),
                "writeBytesPerSecond": .number(1_150_000),
            ]),
            "processes": .object([
                "total": .number(312),
                "threads": .number(1840),
                "items": .array([
                    .object(["pid": .number(1042), "name": .string("happy-agent"), "user": .string("ridoy"), "state": .string("running"), "cpuPercent": .number(14.2), "memoryBytes": .number(420_000_000), "threads": .number(18)]),
                    .object(["pid": .number(2188), "name": .string("swift-frontend"), "user": .string("ridoy"), "state": .string("running"), "cpuPercent": .number(9.8), "memoryBytes": .number(1_280_000_000), "threads": .number(12)]),
                    .object(["pid": .number(904), "name": .string("claude-code"), "user": .string("ridoy"), "state": .string("sleeping"), "cpuPercent": .number(4.1), "memoryBytes": .number(310_000_000), "threads": .number(9)]),
                    .object(["pid": .number(512), "name": .string("tailcatd"), "user": .string("ridoy"), "state": .string("sleeping"), "cpuPercent": .number(1.3), "memoryBytes": .number(88_000_000), "threads": .number(6)]),
                ]),
            ]),
            "history": .object([
                "intervalSeconds": .number(5),
                "points": .array(points),
            ]),
            "sampledAt": .number(now),
        ])
    }

    static func genUIFolderURL() -> URL? {
        Bundle.main.url(forResource: "GenUI", withExtension: nil)
    }

    static func genUIDocument(named name: String) -> Data? {
        guard let folder = genUIFolderURL() else { return nil }
        return try? Data(contentsOf: folder.appendingPathComponent("\(name).render.json"))
    }

    static func genUIAsset(named relativePath: String) -> Data? {
        guard let folder = genUIFolderURL() else { return nil }
        return try? Data(contentsOf: folder.appendingPathComponent(relativePath))
    }

    static func makeDemoDocumentUpdate() -> [UInt8] {
        let doc = YDoc(clientID: 1)
        let editor = DocumentEditor(doc: doc)
        let blocks: [DocumentBlock] = [
            DocumentBlock(
                id: "b1", type: "heading",
                props: ["level": .number(1), "isToggleable": .bool(false), "backgroundColor": .string("default"), "textColor": .string("default"), "textAlignment": .string("left")],
                content: .inline([DocumentRun("Happy iOS Architecture Spec")])
            ),
            DocumentBlock(
                id: "b2", type: "paragraph",
                props: ["backgroundColor": .string("default"), "textColor": .string("default"), "textAlignment": .string("left")],
                content: .inline([
                    DocumentRun("This collaborative document is backed by an "),
                    DocumentRun("in-memory Yjs YDoc", marks: ["bold": .object([])]),
                    DocumentRun(" so you can edit, indent, toggle checklists, and inspect revision history offline."),
                ])
            ),
            DocumentBlock(
                id: "b3", type: "heading",
                props: ["level": .number(2), "isToggleable": .bool(false), "backgroundColor": .string("default"), "textColor": .string("default"), "textAlignment": .string("left")],
                content: .inline([DocumentRun("Core Modules")])
            ),
            DocumentBlock(
                id: "b4", type: "bulletListItem",
                props: ["backgroundColor": .string("default"), "textColor": .string("default"), "textAlignment": .string("left")],
                content: .inline([DocumentRun("HappyCore", marks: ["code": .object([])]), DocumentRun(" — Sync engines, Yjs, Outbox, and Models")])
            ),
            DocumentBlock(
                id: "b5", type: "bulletListItem",
                props: ["backgroundColor": .string("default"), "textColor": .string("default"), "textAlignment": .string("left")],
                content: .inline([DocumentRun("HappyLayout", marks: ["code": .object([])]), DocumentRun(" — Pure geometric frame layout engine")])
            ),
            DocumentBlock(
                id: "b6", type: "checkListItem",
                props: ["checked": .bool(true), "backgroundColor": .string("default"), "textColor": .string("default"), "textAlignment": .string("left")],
                content: .inline([DocumentRun("Offline demo transport & seeded state")])
            ),
            DocumentBlock(
                id: "b7", type: "checkListItem",
                props: ["checked": .bool(false), "backgroundColor": .string("default"), "textColor": .string("default"), "textAlignment": .string("left")],
                content: .inline([DocumentRun("Explore every screen, sheet, and GenUI card")])
            ),
            DocumentBlock(
                id: "b8", type: "codeBlock",
                props: ["language": .string("swift")],
                content: .inline([DocumentRun("let transport = DemoAgentServer(isCloud: true)\n// Zero external network calls")])
            ),
        ]
        editor.reconcile(blocks)
        return doc.encodeStateAsUpdate()
    }
}
#endif

