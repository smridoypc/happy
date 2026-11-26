#if canImport(UIKit)
import CryptoKit
import Foundation
import HappyCore
import HappyWire

/// In-memory `BrowserStream` used by `AgentClient.download` so Vault file previews and downloads work completely offline.
final class DemoBrowserStream: BrowserStream, @unchecked Sendable {
    private let server: DemoAgentServer
    private var buffer = Data()
    private var pendingResponse: Data?
    private var closed = false
    private let lock = NSLock()

    init(server: DemoAgentServer) {
        self.server = server
    }

    func write(_ data: Data) async throws {
        let shouldHandle: String? = lock.withLock {
            buffer.append(data)
            guard let text = String(data: buffer, encoding: .utf8),
                  let range = text.range(of: "\r\n\r\n") else { return nil }
            let headerPart = String(text[..<range.lowerBound])
            buffer.removeAll()
            return headerPart
        }
        guard let headerPart = shouldHandle else { return }
        let firstLine = headerPart.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let parts = firstLine.split(separator: " ").map(String.init)
        let method = parts.count > 0 ? parts[0] : "GET"
        let path = parts.count > 1 ? parts[1] : "/"
        let response = try await server.request(method: method, path: path, credential: "demo", body: nil, headers: [:])
        var head = "HTTP/1.1 \(response.status) OK\r\nContent-Length: \(response.body.count)\r\n"
        for (k, v) in response.headers {
            head += "\(k): \(v)\r\n"
        }
        head += "Connection: close\r\n\r\n"
        var full = Data(head.utf8)
        full.append(response.body)
        lock.withLock { pendingResponse = full }
    }

    func read(maximumBytes: Int) async throws -> Data {
        for _ in 0..<100 {
            let chunk: Data? = lock.withLock {
                if closed { return Data() }
                guard var pending = pendingResponse else { return nil }
                if pending.isEmpty { return Data() }
                let count = min(maximumBytes, pending.count)
                let slice = pending.prefix(count)
                pending.removeFirst(count)
                pendingResponse = pending
                return Data(slice)
            }
            if let chunk { return chunk }
            try await Task.sleep(for: .milliseconds(10))
        }
        return Data()
    }

    func close() async {
        lock.withLock { closed = true }
    }
}

/// Stateful, 100% offline `AgentTransport` serving realistic demo data across Chat, GenUI,
/// Feed, Artifacts, Todos, Documents, Vaults, Pipelines, Plugins, Usage, Compute, and Settings.
actor DemoAgentServer: AgentTransport {
    static let cloud = DemoAgentServer(isCloud: true, displayName: "Acme Cloud (Demo)")
    static let localMac = DemoAgentServer(isCloud: false, displayName: "Ridoy's Mac (Demo)")

    let isCloud: Bool
    let displayName: String

    private var eventId = 10
    private var streams: [UUID: AsyncThrowingStream<Data, Error>.Continuation] = [:]
    private var keepalives: [UUID: Task<Void, Never>] = [:]
    private var pipelines = DemoPipelines()

    // Mutable demo state
    private var profileName = "Ridoy"
    private var instructionsText = "# Acme Engineering\n\nKeep UI transitions crisp, preserve offline-first caches, and test every edge case.\n\n## Conventions\n- Swift 6 strict concurrency\n- UIKit programmatic layout with HappyLayout\n"
    private var securityText = "Never send credentials outside the device.\nAlways require approval before running destructive shell commands.\n"

    private var bots: [JSONValue]
    private var tasks: [JSONValue]
    private var memberships: [JSONValue]
    private var surfaces: [JSONValue]
    private var conversations: [String: [JSONValue]] = [:]
    private var drafts: [String: JSONValue] = [:]
    private var modes: [String: JSONValue] = [:]
    private var pendingQuestions: [String: JSONValue] = [:]

    private var todos: [String: [TodoItem]] = [:]
    private var todoCounter = 100

    private var docSeq = 4
    private var docData: [UInt8] = DemoData.makeDemoDocumentUpdate()
    private var docUpdates: [JSONValue] = []

    private var vaultEntries: [VaultEntry] = []
    private var vaultFilesData: [String: [Int: Data]] = [:]
    private var vaultVersions: [String: [VaultVersion]] = [:]
    private var vaultUploads: [String: (size: Int, data: Data)] = [:]
    private var vaultSettings: VaultSettings

    private var feedItems: [JSONValue] = []
    private var feedClusters: [JSONValue] = []
    private var pluginInstallations: [[String: Any]] = [
        ["id": "inst-1", "plugin": "github", "pluginName": "GitHub", "ordinal": 1, "label": NSNull(), "status": "active", "reason": NSNull(), "authMethod": "token", "toolPrefix": "plugin_github_", "image": ["digest": "github", "mime": "image/png", "thumbhash": NSNull()], "available": true],
        ["id": "inst-2", "plugin": "linear", "pluginName": "Linear", "ordinal": 1, "label": "Product", "status": "active", "reason": NSNull(), "authMethod": NSNull(), "toolPrefix": "plugin_linear_", "image": ["digest": "linear", "mime": "image/png", "thumbhash": NSNull()], "available": true],
    ]
    private var nextInstallId = 3
    private var customProviders: [[String: Any]] = []
    private var computers: [[String: Any]] = []
    private var approvals: [[String: Any]] = []

    private static let genUINames = [
        "01-stats", "02-chart-line", "03-chart-bar", "04-chart-donut",
        "05-gallery-grid", "06-gallery-carousel", "07-list", "08-table",
        "09-steps", "10-choices", "11-release", "12-labels",
    ]

    init(isCloud: Bool, displayName: String) {
        self.isCloud = isCloud
        self.displayName = displayName

        let now = Date().timeIntervalSince1970 * 1000
        let ago: (Double) -> Double = { (now - $0 * 60_000).rounded() }

        if isCloud {
            bots = [
                .object([
                    "id": .string("cos"), "name": .string("Chief of Staff"), "version": .string("v1"), "systemKey": .string("chief_of_staff"), "status": .string("active"),
                    "avatar": .object(["thumbhash": .string(DemoData.botThumb)]),
                    "agent": .object(["id": .string("cos-agent"), "workspaceId": .string("w-ios"), "status": .string("idle")]),
                ]),
                .object([
                    "id": .string("research"), "name": .string("Research Assistant"), "version": .string("v1"), "status": .string("active"),
                    "avatar": .object(["thumbhash": .string(DemoData.adaThumb)]),
                    "agent": .object(["id": .string("research-agent"), "workspaceId": .string("w-ios"), "status": .string("idle"), "unread": .object(["reason": .string("finished")])]),
                ]),
                .object([
                    "id": .string("reviewer"), "name": .string("Code Reviewer"), "version": .string("v1"), "status": .string("active"),
                    "agent": .object(["id": .string("reviewer-agent"), "workspaceId": .string("w-api"), "status": .string("idle")]),
                ]),
            ]
            tasks = [
                .object([
                    "id": .string("t1"), "name": .string("Build iOS Demo Explorer"), "ownerUserId": .string("ridoy"), "status": .string("active"), "version": .string("v1"),
                    "agent": .object([
                        "id": .string("t1-agent"), "workspaceId": .string("w-ios"), "status": .string("idle"),
                        "unread": .object(["reason": .string("finished")]),
                        "subtasks": .array([
                            .object(["id": .string("t1-sub-agent"), "workspaceId": .string("w-ios"), "parentAgentId": .string("t1-agent"), "title": .string("Wire offline transport"), "status": .string("idle")]),
                        ]),
                    ]),
                ]),
                .object([
                    "id": .string("t2"), "name": .string("Refactor GenUI Charts"), "ownerUserId": .string("ada"), "status": .string("active"), "version": .string("v1"),
                    "agent": .object(["id": .string("t2-agent"), "workspaceId": .string("w-ios"), "status": .string("idle")]),
                ]),
                .object([
                    "id": .string("t3"), "name": .string("Ship Release v2026.11"), "ownerUserId": .string("ridoy"), "status": .string("active"), "version": .string("v1"),
                    "agent": .object(["id": .string("t3-agent"), "workspaceId": .string("w-api"), "status": .string("idle")]),
                ]),
            ]
            memberships = [.object(["taskId": .string("t1")]), .object(["taskId": .string("t2")]), .object(["taskId": .string("t3")])]
            surfaces = [
                .object(["id": .string("sprint-todos"), "name": .string("Sprint Checklist"), "type": .string("todo"), "members": .array([])]),
                .object(["id": .string("arch-spec"), "name": .string("Architecture Spec"), "type": .string("document"), "members": .array([])]),
                .object(["id": .string("workspace-vault"), "name": .string("Design & Specs"), "type": .string("vault"), "access": .string("write"), "defaultVault": .bool(true)]),
                .object(["id": .string("sys-mon"), "name": .string("Studio Mac Monitor"), "type": .string("system_monitor"), "members": .array([])]),
            ]
        } else {
            bots = [
                .object([
                    "id": .string("local-helper"), "name": .string("Local Assistant"), "version": .string("v1"), "status": .string("active"),
                    "agent": .object(["id": .string("local-helper-agent"), "workspaceId": .string("w-local"), "status": .string("idle")]),
                ]),
            ]
            tasks = [
                .object([
                    "id": .string("local-t1"), "name": .string("Debug Xcode Build"), "ownerUserId": .string("ridoy"), "status": .string("active"), "version": .string("v1"),
                    "agent": .object(["id": .string("local-t1-agent"), "workspaceId": .string("w-local"), "status": .string("idle"), "unread": .object(["reason": .string("finished")])]),
                ]),
                .object([
                    "id": .string("local-t2"), "name": .string("Profile Scroll FPS"), "ownerUserId": .string("ridoy"), "status": .string("active"), "version": .string("v1"),
                    "agent": .object(["id": .string("local-t2-agent"), "workspaceId": .string("w-local"), "status": .string("idle")]),
                ]),
            ]
            memberships = [.object(["taskId": .string("local-t1")]), .object(["taskId": .string("local-t2")])]
            surfaces = [
                .object(["id": .string("local-todos"), "name": .string("Local Tasks"), "type": .string("todo"), "members": .array([])]),
                .object(["id": .string("sys-mon"), "name": .string("Mac Monitor"), "type": .string("system_monitor"), "members": .array([])]),
            ]
        }

        vaultSettings = VaultSettings(
            surfaceId: "workspace-vault",
            retention: VaultRetention(maxVersions: nil, maxAgeDays: nil, keepAllDays: 30, thinning: [], trashDays: 30),
            updatedAt: ago(120),
            version: "vs-1"
        )

        // Seed todos
        let todoSurfaceId = isCloud ? "sprint-todos" : "local-todos"
        todos[todoSurfaceId] = [
            TodoItem(id: "td-h1", surfaceId: todoSurfaceId, authorUserId: "ridoy", text: "# In Progress", status: .active, orderKey: "a0", createdAt: ago(300), updatedAt: ago(300), version: "v1"),
            TodoItem(id: "td-1", surfaceId: todoSurfaceId, authorUserId: "ridoy", text: "Explore GenUI charts and interactive cards", status: .active, orderKey: "a1", createdAt: ago(240), updatedAt: ago(20), version: "v2"),
            TodoItem(id: "td-2", surfaceId: todoSurfaceId, authorUserId: "ada", text: "Test collaborative Yjs document editing", status: .active, orderKey: "a2", createdAt: ago(180), updatedAt: ago(15), version: "v3"),
            TodoItem(id: "td-3", surfaceId: todoSurfaceId, authorUserId: "ridoy", text: "Check Pipelines, Plugins, and Vault history", status: .active, orderKey: "a3", createdAt: ago(120), updatedAt: ago(10), version: "v4"),
            TodoItem(id: "td-h2", surfaceId: todoSurfaceId, authorUserId: "ridoy", text: "# Backlog", status: .active, orderKey: "b0", createdAt: ago(90), updatedAt: ago(90), version: "v5"),
            TodoItem(id: "td-4", surfaceId: todoSurfaceId, authorUserId: "bo", text: "Review System Monitor GPU & CPU graphs", status: .active, orderKey: "b1", createdAt: ago(60), updatedAt: ago(5), version: "v6"),
            TodoItem(id: "td-c1", surfaceId: todoSurfaceId, authorUserId: "ridoy", text: "Cut all live network connections", status: .completed, orderKey: nil, createdAt: ago(500), updatedAt: ago(40), completedAt: ago(40), version: "v7"),
            TodoItem(id: "td-c2", surfaceId: todoSurfaceId, authorUserId: "ada", text: "Fix Swift 6 build warnings", status: .completed, orderKey: nil, createdAt: ago(420), updatedAt: ago(30), completedAt: ago(30), version: "v8"),
        ]

        // Seed collaborative document history
        docUpdates = [
            .object(["seq": .number(1), "actor": .object(["userId": .string("ridoy"), "agentId": .null]), "source": .string("api"), "createdAt": .number(ago(240)), "size": .number(184)]),
            .object(["seq": .number(2), "actor": .object(["userId": .null, "agentId": .string("cos-agent")]), "source": .string("tool"), "createdAt": .number(ago(120)), "size": .number(96)]),
            .object(["seq": .number(3), "actor": .object(["userId": .string("ada"), "agentId": .null]), "source": .string("api"), "createdAt": .number(ago(45)), "size": .number(64)]),
        ]

        // Seed vault entries
        let specsFolder = VaultEntry(id: "vf-specs", surfaceId: "workspace-vault", parentId: nil, name: "Specs", kind: .folder, createdAt: ago(600), createdBy: VaultActor(userId: "ridoy"), updatedAt: ago(60), updatedBy: VaultActor(userId: "ridoy"), version: "ve-1")
        let releaseFolder = VaultEntry(id: "vf-rel", surfaceId: "workspace-vault", parentId: nil, name: "Releases", kind: .folder, createdAt: ago(500), createdBy: VaultActor(userId: "ada"), updatedAt: ago(30), updatedBy: VaultActor(userId: "ada"), version: "ve-2")
        let readmeContent = Data("# Happy Demo Workspace\n\nWelcome to the offline demo vault.\nYou can browse folders, preview Markdown and Swift files, inspect version history, create folders, rename items, and move items to Trash.\n".utf8)
        let swiftContent = Data("import Foundation\n\nstruct DemoFeature {\n    let name: String\n    let enabled: Bool\n}\n".utf8)
        let planContent = Data("# Launch Plan\n\n1. Verify GenUI rendering\n2. Inspect Feed & Artifacts\n3. Check Settings › Usage heatmap\n".utf8)
        let trashedContent = Data("Old scratch notes moved to trash.\n".utf8)

        let readmeEntry = VaultEntry(id: "vfile-readme", surfaceId: "workspace-vault", parentId: nil, name: "README.md", kind: .file, latestVersion: 2, size: readmeContent.count, mediaType: "text/markdown", createdAt: ago(400), createdBy: VaultActor(userId: "ridoy"), updatedAt: ago(25), updatedBy: VaultActor(userId: "ridoy"), version: "ve-3")
        let swiftEntry = VaultEntry(id: "vfile-swift", surfaceId: "workspace-vault", parentId: "vf-specs", name: "DemoConfig.swift", kind: .file, latestVersion: 1, size: swiftContent.count, mediaType: "text/x-swift", createdAt: ago(300), createdBy: VaultActor(agentId: "reviewer-agent"), updatedAt: ago(80), updatedBy: VaultActor(agentId: "reviewer-agent"), version: "ve-4")
        let planEntry = VaultEntry(id: "vfile-plan", surfaceId: "workspace-vault", parentId: "vf-rel", name: "Launch Plan.md", kind: .file, latestVersion: 2, size: planContent.count, mediaType: "text/markdown", createdAt: ago(200), createdBy: VaultActor(userId: "ada"), updatedAt: ago(15), updatedBy: VaultActor(userId: "ada"), version: "ve-5")
        let trashedEntry = VaultEntry(id: "vfile-trash", surfaceId: "workspace-vault", parentId: nil, name: "old-notes.txt", kind: .file, latestVersion: 1, size: trashedContent.count, mediaType: "text/plain", createdAt: ago(900), createdBy: VaultActor(userId: "bo"), updatedAt: ago(400), updatedBy: VaultActor(userId: "bo"), deletedAt: ago(100), version: "ve-6")

        vaultEntries = [specsFolder, releaseFolder, readmeEntry, swiftEntry, planEntry, trashedEntry]
        vaultFilesData["vfile-readme"] = [1: Data("# Happy Demo Workspace\n\nInitial draft.\n".utf8), 2: readmeContent]
        vaultFilesData["vfile-swift"] = [1: swiftContent]
        vaultFilesData["vfile-plan"] = [1: Data("# Launch Plan\n\nDraft v1.\n".utf8), 2: planContent]
        vaultFilesData["vfile-trash"] = [1: trashedContent]
        vaultVersions["vfile-readme"] = [
            VaultVersion(entryId: "vfile-readme", surfaceId: "workspace-vault", number: 2, size: readmeContent.count, pinned: true, createdAt: ago(25), actor: VaultActor(userId: "ridoy"), source: "api"),
            VaultVersion(entryId: "vfile-readme", surfaceId: "workspace-vault", number: 1, size: 39, pinned: false, createdAt: ago(400), actor: VaultActor(userId: "ridoy"), source: "api"),
        ]
        vaultVersions["vfile-swift"] = [
            VaultVersion(entryId: "vfile-swift", surfaceId: "workspace-vault", number: 1, size: swiftContent.count, pinned: false, createdAt: ago(80), actor: VaultActor(agentId: "reviewer-agent"), source: "tool"),
        ]
        vaultVersions["vfile-plan"] = [
            VaultVersion(entryId: "vfile-plan", surfaceId: "workspace-vault", number: 2, size: planContent.count, pinned: false, createdAt: ago(15), actor: VaultActor(userId: "ada"), source: "api"),
            VaultVersion(entryId: "vfile-plan", surfaceId: "workspace-vault", number: 1, size: 25, pinned: false, createdAt: ago(200), actor: VaultActor(userId: "ada"), source: "api"),
        ]

        // Seed feed
        func uuid(_ ms: Double, _ n: Int) -> String {
            let hex = String(format: "%012llx", UInt64(max(1, ms)))
            return "\(hex.prefix(8))-\(hex.suffix(4))-7000-8000-\(String(format: "%012x", n))"
        }
        func feedItem(_ n: Int, _ type: String, _ id: String, cluster: String, latest: String, todo: String? = nil, minutes: Double, created: Bool = false, updates: Int = 1, actors: [JSONValue], seen: Bool = false) -> JSONValue {
            var newest: [String: JSONValue] = ["type": .string(latest)]
            if let todo { newest["todoId"] = .string(todo) }
            let last = ago(minutes)
            return .object([
                "id": .string("feed-\(n)"),
                "version": .string(uuid(last, n)),
                "cursor": .string(uuid(last, n)),
                "subject": .object(["type": .string(type), "id": .string(id)]),
                "cluster": .string(cluster),
                "created": .bool(created),
                "updates": .number(Double(updates)),
                "actors": .array(actors),
                "actorCount": .number(Double(actors.count)),
                "latest": .object(newest),
                "firstAt": .number(last - 300_000),
                "lastAt": .number(last),
                "seenAt": seen ? .number(last + 1000) : .null,
            ])
        }
        let person: (String) -> JSONValue = { .object(["userId": .string($0), "agentId": .null]) }
        let agentActor: (String) -> JSONValue = { .object(["userId": .null, "agentId": .string($0)]) }

        feedItems = [
            feedItem(1, "task", isCloud ? "t1" : "local-t1", cluster: "task:t1", latest: "task.created", minutes: 4, created: true, updates: 2, actors: [agentActor(isCloud ? "t1-agent" : "local-t1-agent"), person("ridoy")]),
            feedItem(2, "artifact", "revenue", cluster: "bot:research", latest: "artifact.updated", minutes: 12, created: true, updates: 1, actors: [agentActor("research-agent"), person("ada")]),
            feedItem(3, "surface", todoSurfaceId, cluster: "team", latest: "todo.created", todo: "td-1", minutes: 24, updates: 3, actors: [person("ridoy"), person("ada")]),
            feedItem(4, "artifact", "genui-01-stats", cluster: "bot:research", latest: "artifact.created", minutes: 45, created: true, updates: 1, actors: [agentActor("research-agent")]),
            feedItem(5, "surface", "arch-spec", cluster: "team", latest: "document.edited", minutes: 90, updates: 4, actors: [person("ada"), person("ridoy")], seen: true),
        ]
        feedClusters = [
            .object(["cluster": .string("*"), "kind": .string("everything"), "state": .null, "lastAt": .number(now)]),
            .object(["cluster": .string("team"), "kind": .string("team"), "state": .string("subscribed"), "lastAt": .number(now)]),
            .object(["cluster": .string("bot:research"), "kind": .string("bot"), "state": .null, "lastAt": .number(now)]),
            .object(["cluster": .string("task:t1"), "kind": .string("task"), "state": .null, "lastAt": .number(now)]),
        ]

        // Seed computers & providers
        computers = [
            [
                "id": "comp-1",
                "name": "Ridoy MacBook Pro",
                "hostname": "ridoy-mbp.local",
                "os": "macos",
                "arch": "arm64",
                "version": "2026.11.2",
                "osVersion": "26.1",
                "shell": "/bin/zsh",
                "status": "online",
                "since": ago(1200),
                "lastSeenAt": ago(0.2),
                "description": "Primary macOS runner for Swift & Xcode builds",
                "access": "shared",
                "owner": NSNull(),
                "concurrency": 8,
                "maxConcurrency": 16,
                "agents": [["id": "t1-agent", "title": "Build iOS Demo Explorer"]],
                "boundary": ["available": true, "reason": NSNull()],
                "backend": "seatbelt",
                "host": ["cpuCores": 14, "totalMemoryBytes": 36 * 1024 * 1024 * 1024, "totalDiskBytes": 1000 * 1024 * 1024 * 1024],
            ],
            [
                "id": "comp-2",
                "name": "Linux CI Runner",
                "hostname": "runner-eu-01",
                "os": "linux",
                "arch": "x86_64",
                "version": "2026.11.2",
                "osVersion": "Ubuntu 24.04",
                "shell": "/bin/bash",
                "status": "online",
                "since": ago(4200),
                "lastSeenAt": ago(1),
                "description": "Docker & SwiftPM Linux test runner",
                "access": "private",
                "owner": "ridoy",
                "concurrency": 4,
                "maxConcurrency": 8,
                "agents": [],
                "boundary": ["available": true, "reason": NSNull()],
                "backend": "bubblewrap",
                "host": ["cpuCores": 8, "totalMemoryBytes": 16 * 1024 * 1024 * 1024, "totalDiskBytes": 500 * 1024 * 1024 * 1024],
            ],
        ]

        // Seed rich conversations
        let seeded = Self.makeConversations(ago: ago)
        conversations = seeded.conversations
        pendingQuestions = seeded.questions
    }

    private static func makeConversations(ago: (Double) -> Double) -> (conversations: [String: [JSONValue]], questions: [String: JSONValue]) {
        var conversations: [String: [JSONValue]] = [:]
        var pendingQuestions: [String: JSONValue] = [:]
        func msg(_ id: String, role: String, at: Double, content: [JSONValue], metadata: [String: JSONValue] = [:]) -> JSONValue {
            .object(["id": .string(id), "role": .string(role), "createdAt": .number(at), "metadata": .object(metadata), "content": .array(content)])
        }
        func text(_ value: String) -> JSONValue { .object(["type": .string("text"), "text": .string(value)]) }
        func run(_ id: String, started: Double, ended: Double, messages: [JSONValue]) -> JSONValue {
            .object(["id": .string(id), "status": .string("completed"), "startedAt": .number(started), "endedAt": .number(ended), "reason": .string("completed"), "messages": .array(messages)])
        }

        // 1. Chief of Staff (pipelines + scheduled runs)
        conversations["cos-agent"] = [
            run("cos-r1", started: ago(180), ended: ago(179), messages: [
                msg("cos-u1", role: "user", at: ago(180), content: [text("Run the nightly test sweep and summarize the preview deploy.")]),
                msg("cos-m1", role: "agent", at: ago(179), content: [text("Started **Nightly test sweep** and **Deploy preview**. I'll report back as each stage finishes.")]),
            ]),
            run("cos-r2", started: ago(90), ended: ago(89), messages: [
                msg("cos-u2", role: "user", at: ago(90), content: [text("Pipeline result: run r4 of pipeline \"Nightly test sweep\" failed in `tests`.")], metadata: [
                    "senderAgentId": .string("cos-agent"),
                    "senderAgentExplanation": .string("Pipeline \"Nightly test sweep\" run failed"),
                    "pipelineRun": .object(["runId": .string("r4"), "pipelineId": .string("sweep"), "pipelineName": .string("Nightly test sweep"), "version": .number(12), "state": .string("failed"), "summary": .string("tests: exception")]),
                ]),
                msg("cos-m2", role: "agent", at: ago(89), content: [text("Two tests failed in the sync shard. Tap the pipeline card above to inspect the node graph and logs.")]),
            ]),
            run("cos-r3", started: ago(15), ended: ago(14), messages: [
                msg("cos-u3", role: "user", at: ago(15), content: [text("Pipeline result: run r1 of \"Deploy preview\" is running.")], metadata: [
                    "senderAgentId": .string("cos-agent"),
                    "senderAgentExplanation": .string("Scheduled check: Deploy preview"),
                    "pipelineRun": .object(["runId": .string("r1"), "pipelineId": .string("deploy"), "pipelineName": .string("Deploy preview"), "version": .number(8), "state": .string("running")]),
                ]),
                msg("cos-m3", role: "agent", at: ago(14), content: [text("Preview build and database migrations are currently running. Feel free to ask me anything or switch models below!")]),
            ]),
        ]

        // 2. Research Assistant (GenUI interactive cards!)
        let genUICards: [(String, String)] = [
            ("01-stats", "System Metrics Overview"),
            ("02-chart-line", "Latency & Throughput"),
            ("03-chart-bar", "Weekly Token Breakdown"),
            ("10-choices", "Deployment Target Picker"),
        ]
        conversations["research-agent"] = genUICards.enumerated().map { idx, item in
            let offset = Double(60 - idx * 12)
            let artifactCall: JSONValue = .object([
                "type": .string("tool_call"),
                "id": .string("genui-call-\(idx)"),
                "name": .string("create_artifact"),
                "status": .string("completed"),
                "presentation": .object([
                    "type": .string("artifact"),
                    "artifactId": .string("genui-\(item.0)"),
                    "artifactType": .string("gen_ui"),
                    "title": .string(item.1),
                    "version": .number(1),
                    "shows": .string("latest"),
                ]),
            ])
            return run("res-r\(idx)", started: ago(offset), ended: ago(offset - 1), messages: [
                msg("res-u\(idx)", role: "user", at: ago(offset), content: [text("Show me \(item.1).")]),
                msg("res-m\(idx)", role: "agent", at: ago(offset - 1), content: [text("Here is the interactive **\(item.1)** card:"), artifactCall]),
            ])
        }

        // 3. Code Reviewer + Build iOS Demo Explorer (full tool calls, diffs, bash, web search, MCP)
        let richToolsRun = run("rev-r1", started: ago(35), ended: ago(34), messages: [
            msg("rev-u1", role: "user", at: ago(35), content: [text("Inspect the cache store test, fix the race condition, and show me the diff.")]),
            msg("rev-m1", role: "agent", at: ago(34), content: [
                text("I checked the repository and reproduced the timing issue in `StoreTests`."),
                .object([
                    "type": .string("tool_call"), "id": .string("tc-explore"), "name": .string("exec_command"), "status": .string("completed"),
                    "presentation": .object([
                        "type": .string("exploration"),
                        "operations": .array([
                            .object(["kind": .string("list"), "target": .string("Sources/Cache")]),
                            .object(["kind": .string("read"), "name": .string("Sources/Cache/Store.swift")]),
                            .object(["kind": .string("search"), "command": .string("rg -n evict Sources"), "query": .string("evict"), "path": .string("Sources")]),
                        ]),
                    ]),
                ]),
                .object([
                    "type": .string("tool_call"), "id": .string("tc-bash"), "name": .string("exec_command"), "status": .string("completed"),
                    "presentation": .object([
                        "type": .string("exec_command"),
                        "command": .string("swift test --filter StoreTests"),
                        "output": .string("Test Suite 'StoreTests' passed.\nExecuted 3 tests, with 0 failures in 0.014 seconds"),
                    ]),
                ]),
                .object([
                    "type": .string("tool_call"), "id": .string("tc-plan"), "name": .string("update_plan"), "status": .string("completed"),
                    "arguments": .object([
                        "explanation": .string("Hold eviction while active reads are in flight."),
                        "plan": .array([
                            .object(["step": .string("Reproduce eviction race"), "status": .string("completed")]),
                            .object(["step": .string("Guard eviction with pending set"), "status": .string("completed")]),
                            .object(["step": .string("Verify 10 consecutive runs"), "status": .string("completed")]),
                        ]),
                    ]),
                    "result": .object(["output": .string("Plan updated")]),
                ]),
                .object([
                    "type": .string("tool_call"), "id": .string("tc-diff"), "name": .string("apply_patch"), "status": .string("completed"),
                    "presentation": .object([
                        "type": .string("file_diff"),
                        "files": .array([
                            .object([
                                "path": .string("Sources/Cache/Store.swift"),
                                "kind": .string("update"),
                                "added": .number(4),
                                "deleted": .number(2),
                                "language": .string("swift"),
                                "hunks": .array([
                                    .object([
                                        "oldStart": .number(38), "newStart": .number(38),
                                        "lines": .array([
                                            .object(["kind": .string("context"), "text": .string("    func read(_ key: Key) async throws -> Entry {")]),
                                            .object(["kind": .string("delete"), "text": .string("        entry.touched = clock.now")]),
                                            .object(["kind": .string("delete"), "text": .string("        return entry")]),
                                            .object(["kind": .string("add"), "text": .string("        entries[key]?.touched = clock.now")]),
                                            .object(["kind": .string("add"), "text": .string("        pending.remove(key)")]),
                                            .object(["kind": .string("add"), "text": .string("        return entries[key] ?? entry")]),
                                            .object(["kind": .string("context"), "text": .string("    }")]),
                                        ]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ]),
                ]),
                .object([
                    "type": .string("tool_call"), "id": .string("tc-mcp"), "name": .string("mcp__linear__create_issue"), "status": .string("completed"),
                    "elevated": .bool(false),
                    "review": .object(["outcome": .string("allowed"), "reason": .string("Creates follow-up tracking issue"), "risk": .string("low"), "userAuthorization": .string("high")]),
                    "arguments": .object(["team": .string("IOS"), "title": .string("Inject TestClock into Store")]),
                    "result": .object(["output": .string("{\"id\":\"IOS-142\",\"state\":\"Todo\"}")]),
                ]),
                text("Fixed the race in `Sources/Cache/Store.swift`, verified all tests pass, and filed `IOS-142` for the `TestClock` follow-up.\n\n```swift\nguard pending.isEmpty else { return schedule() }\n```"),
            ]),
        ])
        conversations["reviewer-agent"] = [richToolsRun]
        conversations["t1-agent"] = [richToolsRun]
        conversations["local-t1-agent"] = [richToolsRun]

        // Task t2 has an interactive pending question!
        conversations["t2-agent"] = [
            run("t2-r1", started: ago(20), ended: ago(19), messages: [
                msg("t2-u1", role: "user", at: ago(20), content: [text("Update the GenUI chart palette for dark mode.")]),
                msg("t2-m1", role: "agent", at: ago(19), content: [text("I've prepared two palette options. Please pick your preference in the prompt below.")]),
            ]),
        ]
        pendingQuestions["t2-agent"] = .object([
            "id": .string("q-palette"),
            "agentId": .string("t2-agent"),
            "prompts": .array([
                .object([
                    "id": .string("theme"),
                    "header": .string("Chart Palette"),
                    "question": .string("Which accent palette should GenUI charts use in dark mode?"),
                    "multiSelect": .bool(false),
                    "options": .array([
                        .object(["label": .string("Emerald & Slate (Recommended)"), "description": .string("High-contrast teal with muted grid lines")]),
                        .object(["label": .string("Indigo & Amber"), "description": .string("Warm accent highlights for comparisons")]),
                    ]),
                ]),
            ]),
        ])

        conversations["t1-sub-agent"] = [
            run("sub-r1", started: ago(10), ended: ago(9), messages: [
                msg("sub-u1", role: "user", at: ago(10), content: [text("Verify offline transport rejects external URLSession calls.")]),
                msg("sub-m1", role: "agent", at: ago(9), content: [text("Verified: `DemoOfflineHTTPTransport` and `DemoOfflineWebSocketConnector` block all external network requests while `DemoAgentServer` serves all `/v0/` routes locally.")]),
            ]),
        ]
        conversations["t3-agent"] = [
            run("t3-r1", started: ago(50), ended: ago(49), messages: [
                msg("t3-u1", role: "user", at: ago(50), content: [text("Summarize what's in v2026.11.")]),
                msg("t3-m1", role: "agent", at: ago(49), content: [text("Here is the summary for **v2026.11**:\n- Offline demo mode with full interactive mock server\n- Swift 6 concurrency & Xcode latest build fixes\n- Full GenUI, Vaults, Documents, Todos, and Pipelines explorer")]),
            ]),
        ]
        conversations["local-helper-agent"] = conversations["research-agent"]
        conversations["local-t2-agent"] = conversations["t3-agent"]
        return (conversations, pendingQuestions)
    }

    func browserConnection() async throws -> any BrowserStream {
        DemoBrowserStream(server: self)
    }

    func reset() async {}
    func close() async {}

    func stream(path: String, credential: String, headers: [String: String]) async throws -> HTTP1Stream {
        let streamId = UUID()
        let (body, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        streams[streamId] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeStream(streamId) }
        }
        let hello = #"{"cursor":"c1","daemonId":"demo-daemon-1","resumed":false}"#
        continuation.yield(Data("event: hello\ndata: \(hello)\n\n".utf8))
        keepalives[streamId] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await self?.sendKeepalive(to: streamId)
            }
        }
        return HTTP1Stream(status: 200, body: body)
    }

    private func sendKeepalive(to id: UUID) {
        streams[id]?.yield(Data(": keepalive\n\n".utf8))
    }

    private func removeStream(_ id: UUID) {
        keepalives.removeValue(forKey: id)?.cancel()
        streams.removeValue(forKey: id)
    }

    private func emit(_ type: String, _ payload: [String: JSONValue]) {
        eventId += 1
        let envelope: JSONValue = .object(["type": .string(type), "payload": .object(payload)])
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        let frame = Data("id: e\(eventId)\ndata: ".utf8) + data + Data("\n\n".utf8)
        for continuation in streams.values {
            continuation.yield(frame)
        }
    }

    private func emitRaw(event type: String, payloadJSON: String) {
        eventId += 1
        let frame = #"{"cursor":"e\#(eventId)","type":"\#(type)","occurredAt":\#(Int64(Date().timeIntervalSince1970 * 1000)),"payload":\#(payloadJSON)}"#
        let data = Data("id: e\(eventId)\nevent: \(type)\ndata: \(frame)\n\n".utf8)
        for continuation in streams.values {
            continuation.yield(data)
        }
    }

    private func emitNamedFrame(event: String, data: String) {
        let chunk = Data("event: \(event)\ndata: \(data)\n\n".utf8)
        for continuation in streams.values {
            continuation.yield(chunk)
        }
    }

    func request(method: String, path: String, credential: String, body: Data?, headers: [String: String]) async throws -> HTTP1Response {
        let route = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        let sent = body.flatMap { try? JSONValue.decode($0) }

        if isCloud, let answer = pipelines.answer(method, path) {
            for ev in answer.events {
                emitRaw(event: ev.type, payloadJSON: ev.payload)
            }
            return HTTP1Response(status: answer.status, headers: ["content-type": "application/json"], body: Data(answer.body.utf8))
        }

        // Health, Config, Bootstrap, Profile, Permissions, Onboarding
        switch (method, route) {
        case ("GET", "/v0/health"):
            return jsonResponse(DemoData.healthJSON(isCloud: isCloud))
        case ("GET", "/v0/config"):
            return jsonResponse(DemoData.configJSON(name: displayName))
        case ("PATCH", "/v0/config"):
            return jsonResponse(DemoData.configJSON(name: sent?["node"]?["name"]?.stringValue ?? displayName))
        case ("PUT", "/v0/environment"):
            return jsonResponse(.object(["ok": .bool(true)]))
        case ("GET", "/v0/bootstrap/desktop"):
            return jsonResponse(bootstrapJSON())
        case ("GET", "/v0/profile"):
            return jsonResponse(profileJSON())
        case ("PATCH", "/v0/profile"):
            profileName = sent?["name"]?.stringValue ?? profileName
            emit("profile.updated", ["userId": .string("ridoy")])
            return jsonResponse(profileJSON())
        case ("PUT", "/v0/profile/photo"):
            return jsonResponse(profileJSON())
        case ("GET", "/v0/permissions"):
            let perms = ["content.write", "bots.manage", "mcp.manage", "config.manage", "providers.manage", "providers.own", "policy.edit", "compute.use", "pools.manage"]
            return jsonResponse(.object([
                "role": .string("owner"),
                "granted": .array(perms.map(JSONValue.string)),
                "permissions": .array(perms.map { .object(["id": .string($0), "description": .string("")]) }),
            ]))
        case ("GET", "/v0/onboarding"):
            return jsonResponse(.object(["finished": .bool(true), "completed": .bool(true), "blocking": .array([]), "gates": .array([])]))
        case ("POST", "/v0/onboarding/complete"):
            return jsonResponse(.object(["completed": .bool(true)]))
        case ("GET", "/v0/users"):
            return jsonResponse(DemoData.usersJSON)
        case ("GET", let r) where r.hasPrefix("/v0/users/") && r.hasSuffix("/profile"):
            return jsonResponse(.object([
                "user": .object(["id": .string("ridoy"), "name": .string(profileName), "role": .string("owner")]),
                "recentActivity": .array([]),
            ]))
        case ("GET", "/v0/roles"):
            return jsonResponse(.object(["roles": .array([.object(["id": .string("owner"), "name": .string("Owner")])])]))
        case ("GET", "/v0/node/avatar"), ("GET", "/v0/profile/photo"):
            return HTTP1Response(status: 200, headers: ["content-type": "image/png", "etag": "\"demo-avatar-1\""], body: DemoImages.badge(letter: "H", red: 0.12, green: 0.14, blue: 0.18))
        case ("GET", let r) where r.hasPrefix("/v0/bots/") && r.hasSuffix("/avatar"):
            let letter = r.contains("/cos/") ? "C" : (r.contains("/research/") ? "R" : "A")
            return HTTP1Response(status: 200, headers: ["content-type": "image/png"], body: DemoImages.badge(letter: letter, red: 0.16, green: 0.45, blue: 0.78))
        case ("GET", let r) where r.hasPrefix("/v0/users/") && r.hasSuffix("/photo"):
            return HTTP1Response(status: 200, headers: ["content-type": "image/png"], body: DemoImages.badge(letter: "R", red: 0.14, green: 0.56, blue: 0.48))
        case ("GET", let r) where r.hasPrefix("/v0/plugins/images/"):
            let digest = String(r.dropFirst("/v0/plugins/images/".count))
            if let png = DemoImages.pluginMark(digest) {
                return HTTP1Response(status: 200, headers: ["content-type": "image/png"], body: png)
            }
            return HTTP1Response(status: 404, body: Data())
        case ("GET", "/v0/skills"):
            return jsonResponse(DemoData.skillsJSON)
        case ("GET", "/v0/usage"):
            return jsonResponse(DemoData.usageJSON())
        case ("GET", "/v0/usage/daily"):
            let comps = URLComponents(string: path)?.queryItems
            let days = comps?.first(where: { $0.name == "days" })?.value.flatMap(Int.init) ?? 90
            let tz = comps?.first(where: { $0.name == "tz" })?.value ?? TimeZone.current.identifier
            return jsonResponse(DemoData.dailyUsageJSON(days: days, timeZone: tz))
        case ("POST", "/v0/usage/refresh"):
            return jsonResponse(.object(["ok": .bool(true)]))
        case ("GET", "/v0/config/instructions"):
            return jsonResponse(.object(["instructions": .string(instructionsText)]))
        case ("PUT", "/v0/config/instructions"):
            instructionsText = sent?["instructions"]?.stringValue ?? instructionsText
            return jsonResponse(.object(["instructions": .string(instructionsText)]))
        case ("GET", "/v0/config/security"):
            return jsonResponse(.object(["policy": .string(securityText)]))
        case ("PUT", "/v0/config/security"):
            securityText = sent?["policy"]?.stringValue ?? securityText
            return jsonResponse(.object(["policy": .string(securityText)]))
        case ("GET", "/v0/cloud/providers"):
            let payload: [String: Any] = [
                "providers": [
                    ["id": "claude", "name": "Claude Max", "scope": "team", "source": "operator", "vendors": ["anthropic"], "models": [], "credentialCount": 1],
                    ["id": "codex", "name": "OpenAI Codex", "scope": "team", "source": "operator", "vendors": ["openai"], "models": [], "credentialCount": 1],
                ] + customProviders,
                "capabilities": ["apiKeys": true, "claudeSetupToken": true, "codexSignIn": true, "claudeSignIn": true],
            ]
            return anyJSONResponse(payload)
        case ("GET", "/v0/provider-clis"):
            return jsonResponse(.object(["clis": .array([])]))
        case ("PUT", let r) where r.hasPrefix("/v0/providers/"):
            let pid = String(r.dropFirst("/v0/providers/".count))
            customProviders.removeAll { ($0["id"] as? String) == pid }
            customProviders.append(["id": pid, "name": pid, "scope": "team", "source": "tenant", "vendors": ["openai_compatible"], "models": [], "credentialCount": 1])
            return jsonResponse(.object(["providerId": .string(pid), "credentials": .string("available")]))
        case ("POST", let r) where r.hasPrefix("/v0/cloud/providers/") && r.hasSuffix("/credentials"):
            return jsonResponse(.object(["credential": .object(["id": .string("cred-demo-1")])]), status: 201)
        case ("GET", "/v0/computers"):
            return anyJSONResponse(["computers": computers])
        case ("GET", "/v0/computers/approvals"):
            return anyJSONResponse(["approvals": approvals])
        case ("POST", "/v0/computers/join-tokens"):
            return jsonResponse(.object(["token": .string("demo-join-token"), "command": .string("happy compute join --token demo-join-token")]))
        case ("POST", "/v0/invites"):
            return jsonResponse(.object(["invite": .object(["id": .string("inv-demo"), "link": .string("https://acme.happy.engineering/join#demo"), "expiresAt": .string("2026-12-31T00:00:00Z"), "role": .string("member"), "deliveryStatus": .string("sent")])]), status: 201)
        case ("GET", "/v0/search"):
            let q = URLComponents(string: path)?.queryItems?.first(where: { $0.name == "q" })?.value?.lowercased() ?? ""
            let results: [JSONValue] = (bots + tasks).compactMap { item in
                let name = item["name"]?.stringValue ?? ""
                guard q.isEmpty || name.lowercased().contains(q) else { return nil }
                return .object(["id": item["id"] ?? .string(""), "title": .string(name), "kind": .string(item["agent"] != nil ? "task" : "bot")])
            }
            return jsonResponse(.object(["results": .array(results)]))
        case ("PUT", let r) where r.hasPrefix("/v0/user-settings/"):
            let key = String(r.dropFirst("/v0/user-settings/".count))
            let val = sent?["value"] ?? .null
            emit("user_settings.updated", ["setting": .object(["key": .string(key), "value": val, "version": .string("1")])])
            return jsonResponse(.object(["setting": .object(["key": .string(key), "value": val, "version": .string("1")])]))
        case ("PUT", let r) where r.hasPrefix("/v0/viewers/streams/"):
            return jsonResponse(.object(["ok": .bool(true)]))
        default:
            break
        }

        // Plugins
        if route == "/v0/plugins" && method == "GET" {
            return HTTP1Response(status: 200, headers: ["content-type": "application/json"], body: Data(DemoData.pluginCatalogJSON.utf8))
        }
        if route == "/v0/plugins/installations" && method == "GET" {
            return anyJSONResponse(["installations": pluginInstallations, "canManage": true])
        }
        if route == "/v0/plugins/installations" && method == "POST" {
            let plugin = sent?["plugin"]?.stringValue ?? "github"
            let ordinal = (pluginInstallations.filter { ($0["plugin"] as? String) == plugin }.compactMap { $0["ordinal"] as? Int }.max() ?? 0) + 1
            let name = ["github": "GitHub", "linear": "Linear", "sentry": "Sentry"][plugin] ?? plugin
            let made: [String: Any] = [
                "id": "inst-\(nextInstallId)", "plugin": plugin, "pluginName": name, "ordinal": ordinal,
                "label": NSNull(), "status": plugin == "linear" ? "active" : "not_configured", "reason": NSNull(),
                "authMethod": NSNull(), "toolPrefix": "plugin_\(plugin)_",
                "image": ["digest": plugin, "mime": "image/png", "thumbhash": NSNull()], "available": true,
            ]
            nextInstallId += 1
            pluginInstallations.append(made)
            return anyJSONResponse(["installation": made], status: 201)
        }
        if route.hasPrefix("/v0/plugins/installations/") {
            let parts = route.dropFirst("/v0/plugins/installations/".count).split(separator: "/").map(String.init)
            if let id = parts.first, let idx = pluginInstallations.firstIndex(where: { ($0["id"] as? String) == id }) {
                switch (method, parts.dropFirst().first) {
                case ("DELETE", nil):
                    pluginInstallations.remove(at: idx)
                    return jsonResponse(.object(["deleted": .bool(true), "secretsDeleted": .number(1), "cleanedUpOutside": .bool(true)]))
                case ("POST", "configure"):
                    pluginInstallations[idx]["status"] = "active"
                    pluginInstallations[idx]["authMethod"] = sent?["method"]?.stringValue ?? "token"
                    return anyJSONResponse(["installation": pluginInstallations[idx]])
                case ("POST", "disconnect"):
                    pluginInstallations[idx]["status"] = "not_configured"
                    pluginInstallations[idx]["authMethod"] = NSNull()
                    return anyJSONResponse(["installation": pluginInstallations[idx], "removed": ["s1"]])
                default:
                    break
                }
            }
        }

        // Bots & Tasks
        if route == "/v0/bots" && method == "GET" { return jsonResponse(.object(["bots": .array(bots)])) }
        if route == "/v0/tasks" && method == "GET" { return jsonResponse(.object(["tasks": .array(tasks), "memberships": .array(memberships)])) }
        if route == "/v0/tasks" && method == "POST" {
            let id = sent?["id"]?.stringValue ?? ClientID.make()
            let agentId = sent?["agentId"]?.stringValue ?? ClientID.make()
            let workspaceId = sent?["workspaceId"]?.stringValue ?? "w-ios"
            let name = sent?["name"]?.stringValue ?? "New Task"
            if let existing = tasks.first(where: { $0["id"]?.stringValue == id }) {
                return jsonResponse(.object(["task": existing]))
            }
            let created: JSONValue = .object([
                "id": .string(id), "name": .string(name), "ownerUserId": .string("ridoy"), "status": .string("active"), "version": .string("v1"),
                "agent": .object(["id": .string(agentId), "workspaceId": .string(workspaceId), "status": .string("idle")]),
            ])
            tasks.insert(created, at: 0)
            memberships.append(.object(["taskId": .string(id)]))
            conversations[agentId] = []
            emit("task.created", ["taskId": .string(id)])
            return jsonResponse(.object(["task": created]), status: 201)
        }
        if route == "/v0/bots" && method == "POST" {
            let id = sent?["id"]?.stringValue ?? ClientID.make()
            let agentId = sent?["agentId"]?.stringValue ?? ClientID.make()
            let workspaceId = sent?["workspaceId"]?.stringValue ?? "w-ios"
            let name = sent?["name"]?.stringValue ?? "New Bot"
            let created: JSONValue = .object([
                "id": .string(id), "name": .string(name), "status": .string("active"), "version": .string("v1"),
                "agent": .object(["id": .string(agentId), "workspaceId": .string(workspaceId), "status": .string("idle")]),
            ])
            bots.append(created)
            conversations[agentId] = []
            emit("bot.created", ["botId": .string(id)])
            return jsonResponse(.object(["bot": created]), status: 201)
        }
        if route.hasPrefix("/v0/tasks/") {
            let parts = route.dropFirst("/v0/tasks/".count).split(separator: "/").map(String.init)
            if let tid = parts.first, let idx = tasks.firstIndex(where: { $0["id"]?.stringValue == tid }) {
                if method == "GET" && parts.count == 1 { return jsonResponse(.object(["task": tasks[idx]])) }
                if method == "PATCH", let name = sent?["name"]?.stringValue, case .object(var obj) = tasks[idx] {
                    obj["name"] = .string(name)
                    tasks[idx] = .object(obj)
                    emit("task.updated", ["taskId": .string(tid)])
                    return jsonResponse(.object(["task": tasks[idx]]))
                }
                if method == "POST" && parts.last == "archive" {
                    tasks.remove(at: idx)
                    emit("task.updated", ["taskId": .string(tid)])
                    return jsonResponse(.object(["ok": .bool(true)]))
                }
                if method == "POST" && parts.last == "leave" {
                    memberships.removeAll { $0["taskId"]?.stringValue == tid }
                    return jsonResponse(.object(["ok": .bool(true)]))
                }
                if method == "POST" && parts.last == "reorder" {
                    return jsonResponse(.object(["ok": .bool(true)]))
                }
            }
        }
        if route.hasPrefix("/v0/bots/") {
            let parts = route.dropFirst("/v0/bots/".count).split(separator: "/").map(String.init)
            if let bid = parts.first, let idx = bots.firstIndex(where: { $0["id"]?.stringValue == bid }) {
                if method == "GET" && parts.count == 1 { return jsonResponse(.object(["bot": bots[idx]])) }
                if method == "PATCH", let name = sent?["name"]?.stringValue, case .object(var obj) = bots[idx] {
                    obj["name"] = .string(name)
                    bots[idx] = .object(obj)
                    emit("bot.updated", ["botId": .string(bid)])
                    return jsonResponse(.object(["bot": bots[idx]]))
                }
                if method == "POST" && parts.last == "archive" {
                    bots.remove(at: idx)
                    emit("bot.updated", ["botId": .string(bid)])
                    return jsonResponse(.object(["ok": .bool(true)]))
                }
            }
        }
        if (route == "/v0/spaces/tidy" || route == "/v0/spaces/attention") && method == "POST" {
            return jsonResponse(.object(["ok": .bool(true)]))
        }

        // Agent conversations (/v0/agents/:agentId/...)
        if route.hasPrefix("/v0/agents/") {
            let parts = route.dropFirst("/v0/agents/".count).split(separator: "/").map(String.init)
            if let agentId = parts.first {
                let tail = parts.dropFirst().joined(separator: "/")
                if tail == "" && method == "GET" {
                    let agent = findAgent(agentId) ?? .object(["id": .string(agentId), "workspaceId": .string("w-ios"), "status": .string("idle")])
                    return jsonResponse(.object(["agent": agent]))
                }
                if tail == "bootstrap" && method == "GET" {
                    let agent = findAgent(agentId) ?? .object(["id": .string(agentId), "workspaceId": .string("w-ios"), "status": .string("idle")])
                    let mode = modes[agentId] ?? .object(["providerId": .string("claude"), "modelId": .string("anthropic/claude-sonnet-4-5"), "effort": .string("medium"), "permissionMode": .string("auto")])
                    var payload: [String: JSONValue] = [
                        "agent": agent,
                        "mode": mode,
                        "pending": .array([]),
                        "slashCommands": .array(DemoData.slashCommands),
                        "context": .object(["usedTokens": .number(42_800), "contextWindow": .number(200_000)]),
                    ]
                    if let draft = drafts[agentId] { payload["draft"] = draft }
                    return jsonResponse(.object(payload))
                }
                if tail == "messages" && method == "GET" {
                    let runs = conversations[agentId] ?? []
                    return jsonResponse(.object(["hasMore": .bool(false), "runs": .array(runs)]))
                }
                if tail == "mode" && method == "GET" {
                    let mode = modes[agentId] ?? .object(["providerId": .string("claude"), "modelId": .string("anthropic/claude-sonnet-4-5"), "effort": .string("medium"), "permissionMode": .string("auto")])
                    return jsonResponse(.object(["mode": mode]))
                }
                if tail == "draft" && method == "GET" {
                    return jsonResponse(.object(["draft": drafts[agentId] ?? .object(["value": .null, "updatedAt": .number(0)])]))
                }
                if tail == "draft" && method == "PUT" {
                    let saved: JSONValue = .object(["value": sent?["draft"] ?? .null, "updatedAt": sent?["updatedAt"] ?? .number(Date().timeIntervalSince1970 * 1000)])
                    drafts[agentId] = saved
                    return jsonResponse(.object(["draft": saved]))
                }
                if tail == "question" && method == "GET" {
                    return jsonResponse(.object(["question": pendingQuestions[agentId] ?? .null]))
                }
                if tail.hasPrefix("question/") && tail.hasSuffix("/answer") && method == "POST" {
                    let q = pendingQuestions.removeValue(forKey: agentId) ?? .object(["id": .string("q"), "prompts": .array([])])
                    Task { await self.replyToQuestion(agentId: agentId, answers: sent?["answers"]) }
                    return jsonResponse(.object(["question": q]))
                }
                if tail == "read" && method == "POST" {
                    clearUnread(agentId)
                    return jsonResponse(.object(["ok": .bool(true)]))
                }
                if tail == "abort" && method == "POST" {
                    return jsonResponse(.object(["ok": .bool(true)]))
                }
                if tail == "archive" && method == "POST" {
                    return jsonResponse(.object(["ok": .bool(true)]))
                }
                if tail == "send" && method == "POST" {
                    if let mode = sent?["mode"] { modes[agentId] = mode }
                    let msgId = sent?["id"]?.stringValue ?? ClientID.make()
                    let text = sent?["text"]?.stringValue ?? ""
                    Task { await self.streamReply(agentId: agentId, userMessageId: msgId, userText: text) }
                    return jsonResponse(.object(["ok": .bool(true)]))
                }
                if tail.hasPrefix("slash-commands/") && method == "POST" {
                    let cmd = parts.count >= 3 ? parts[2] : "command"
                    let args = sent?["arguments"]?.stringValue ?? ""
                    Task { await self.streamReply(agentId: agentId, userMessageId: ClientID.make(), userText: "/\(cmd) \(args)".trimmingCharacters(in: .whitespaces)) }
                    return jsonResponse(.object(["slashCommands": .array(DemoData.slashCommands)]))
                }
            }
        }

        // Surfaces catalog & System Monitor
        if route == "/v0/surfaces" && method == "GET" {
            return jsonResponse(.object(["surfaces": .array(surfaces)]))
        }
        if route == "/v0/surfaces" && method == "POST" {
            let id = sent?["id"]?.stringValue ?? ClientID.make()
            let type = sent?["type"]?.stringValue ?? "todo"
            let name = sent?["name"]?.stringValue ?? "New Surface"
            let created: JSONValue = .object(["id": .string(id), "name": .string(name), "type": .string(type), "members": .array([])])
            surfaces.append(created)
            if type == "todo" { todos[id] = [] }
            emit("surface.created", ["surfaceId": .string(id)])
            return jsonResponse(.object(["surface": created]), status: 201)
        }
        if route.hasPrefix("/v0/surfaces/system-monitor/") && method == "GET" {
            return jsonResponse(DemoData.systemMonitorJSON())
        }

        // Todo routes
        if route.hasPrefix("/v0/surfaces/todo/") {
            return handleTodoRoute(method: method, path: path, route: route, sent: sent)
        }

        // Document routes
        if route.hasPrefix("/v0/surfaces/document/") {
            return handleDocumentRoute(method: method, path: path, route: route, sent: sent)
        }

        // Vault routes
        if route.hasPrefix("/v0/surfaces/vault/") || route.hasPrefix("/v0/vault-uploads") {
            return handleVaultRoute(method: method, path: path, route: route, body: body, sent: sent, headers: headers)
        }

        // Feed routes
        if route.hasPrefix("/v0/feed") {
            return handleFeedRoute(method: method, path: path, route: route, sent: sent)
        }

        // Generic Surface rename / join / leave (/v0/surfaces/:id...)
        if route.hasPrefix("/v0/surfaces/") {
            let parts = route.dropFirst("/v0/surfaces/".count).split(separator: "/").map(String.init)
            if let sid = parts.first, let idx = surfaces.firstIndex(where: { $0["id"]?.stringValue == sid }) {
                if parts.count == 1 && method == "PATCH", let name = sent?["name"]?.stringValue, case .object(var obj) = surfaces[idx] {
                    obj["name"] = .string(name)
                    surfaces[idx] = .object(obj)
                    emit("surface.updated", ["surfaceId": .string(sid)])
                    return jsonResponse(.object(["surface": surfaces[idx]]))
                }
                if parts.count == 2 && (parts[1] == "join" || parts[1] == "leave") && method == "POST" {
                    return jsonResponse(.object(["surface": surfaces[idx], "ok": .bool(true)]))
                }
            }
        }

        // Artifacts & GenUI
        if route.hasPrefix("/v0/artifacts") {
            return handleArtifactRoute(method: method, path: path, route: route, headers: headers, sent: sent)
        }

        // Workspaces & Git changes
        if route.hasPrefix("/v0/workspaces/") {
            return handleWorkspaceRoute(method: method, path: path, route: route, body: body)
        }
        if route == "/v0/workspaces" && method == "GET" {
            return jsonResponse(.object(["workspaces": .array([.object(["id": .string("w-ios"), "name": .string("happy-ios")])])]))
        }

        return jsonResponse(.object(["error": .string("Not found in demo"), "code": .string("not_found")]), status: 404)
    }

    // MARK: - Helpers & Sub-routers

    private func bootstrapJSON() -> JSONValue {
        .object([
            "cursor": .string("c1"),
            "daemonId": .string("demo-daemon-1"),
            "health": DemoData.healthJSON(isCloud: isCloud),
            "config": DemoData.configJSON(name: displayName)["config"] ?? .object([:]),
            "profile": .object([
                "userId": .string("ridoy"),
                "name": .string(profileName),
                "photo": .object(["thumbhash": .string(DemoData.ridoyThumb)]),
            ]),
            "teammates": DemoData.usersJSON["users"] ?? .array([]),
            "userSettings": .array([]),
            "projects": .array([
                .object(["id": .string("p-ios"), "name": .string("happy-ios"), "status": .string("active"), "orderKey": .string("a"), "agents": .array([])]),
                .object(["id": .string("p-api"), "name": .string("backend-api"), "status": .string("active"), "orderKey": .string("b"), "agents": .array([])]),
            ]),
            "workspaces": .array([
                .object(["id": .string("w-ios"), "name": .string("happy-ios"), "projectId": .string("p-ios")]),
                .object(["id": .string("w-api"), "name": .string("backend-api"), "projectId": .string("p-api")]),
            ]),
            "bots": .array(bots),
            "tasks": .array(tasks),
            "taskMemberships": .array(memberships),
            "surfaces": .array(surfaces),
            "feedUnread": .number(Double(feedItems.filter { $0["seenAt"] == .null }.count)),
        ])
    }

    private func profileJSON() -> JSONValue {
        .object([
            "profile": .object([
                "email": .string("ridoy@demo.happy.local"),
                "name": .string(profileName),
                "photo": .object(["thumbhash": .string(DemoData.ridoyThumb)]),
                "userId": .string("ridoy"),
                "updatedAt": .number(1),
                "version": .string("v1"),
            ]),
        ])
    }

    private func findAgent(_ agentId: String) -> JSONValue? {
        for bot in bots {
            if bot["agent"]?["id"]?.stringValue == agentId { return bot["agent"] }
        }
        for task in tasks {
            if task["agent"]?["id"]?.stringValue == agentId { return task["agent"] }
            for sub in task["agent"]?["subtasks"]?.arrayValue ?? [] {
                if sub["id"]?.stringValue == agentId { return sub }
            }
        }
        return nil
    }

    private func clearUnread(_ agentId: String) {
        for idx in bots.indices {
            if case .object(var bot) = bots[idx], case .object(var agent) = bot["agent"], agent["id"]?.stringValue == agentId {
                agent["unread"] = nil
                bot["agent"] = .object(agent)
                bots[idx] = .object(bot)
            }
        }
        for idx in tasks.indices {
            if case .object(var task) = tasks[idx], case .object(var agent) = task["agent"], agent["id"]?.stringValue == agentId {
                agent["unread"] = nil
                task["agent"] = .object(agent)
                tasks[idx] = .object(task)
            }
        }
    }

    private func streamReply(agentId: String, userMessageId: String, userText: String) async {
        let runId = "demo-run-\(UUID().uuidString.prefix(8))"
        let started = Date().timeIntervalSince1970 * 1000
        let userMsg: JSONValue = .object([
            "id": .string(userMessageId),
            "role": .string("user"),
            "createdAt": .number(started),
            "metadata": .object([:]),
            "content": .array([.object(["type": .string("text"), "text": .string(userText)])]),
        ])
        emit("message.created", ["agentId": .string(agentId), "runId": .string(runId), "message": userMsg])
        emit("run.started", [
            "agentId": .string(agentId),
            "run": .object(["id": .string(runId), "status": .string("running"), "startedAt": .number(started), "messages": .array([])]),
            "acceptedMessageIds": .array([.string(userMessageId)]),
        ])

        try? await Task.sleep(for: .milliseconds(350))
        let replyId = "\(runId)-reply"
        emit("message.created", [
            "agentId": .string(agentId),
            "runId": .string(runId),
            "message": .object(["id": .string(replyId), "role": .string("agent"), "createdAt": .number(started + 1), "metadata": .object([:]), "content": .array([.object(["type": .string("text"), "text": .string("")])])]),
        ])

        let replyText = demoReplyText(for: userText)
        let chunks = stride(from: 0, to: replyText.count, by: 24).map { idx -> String in
            let start = replyText.index(replyText.startIndex, offsetBy: idx)
            let end = replyText.index(start, offsetBy: min(24, replyText.distance(from: start, to: replyText.endIndex)))
            return String(replyText[start..<end])
        }
        var offset = 0
        for piece in chunks {
            try? await Task.sleep(for: .milliseconds(120))
            emit("message.delta", [
                "agentId": .string(agentId),
                "runId": .string(runId),
                "messageId": .string(replyId),
                "blockIndex": .number(0),
                "offset": .number(Double(offset)),
                "append": .string(piece),
            ])
            offset += piece.utf16.count
        }

        let agentMsg: JSONValue = .object([
            "id": .string(replyId),
            "role": .string("agent"),
            "createdAt": .number(started + 1),
            "metadata": .object([:]),
            "content": .array([.object(["type": .string("text"), "text": .string(replyText)])]),
        ])
        emit("message.updated", ["agentId": .string(agentId), "runId": .string(runId), "message": agentMsg])
        let finished: JSONValue = .object([
            "id": .string(runId), "status": .string("completed"),
            "startedAt": .number(started), "endedAt": .number(Date().timeIntervalSince1970 * 1000),
            "reason": .string("completed"), "messages": .array([userMsg, agentMsg]),
        ])
        conversations[agentId, default: []].append(finished)
        emit("run.finished", ["agentId": .string(agentId), "run": finished])
    }

    private func replyToQuestion(agentId: String, answers: JSONValue?) async {
        let picked = answers?.objectValue?.values.first?.arrayValue?.first?.stringValue ?? "selected option"
        await streamReply(agentId: agentId, userMessageId: ClientID.make(), userText: "Selected: \(picked)")
    }

    private func demoReplyText(for prompt: String) -> String {
        let lower = prompt.lowercased()
        if lower.contains("chart") || lower.contains("ui") || lower.contains("demo") {
            return "Demo Mode is active with **all live network calls disabled**. You can explore **Bots**, **Tasks**, **GenUI Cards**, **Todos**, **Documents**, **Vaults**, **Pipelines**, **Plugins**, and **Settings › Usage** right from the sidebar."
        }
        return "Got it: *\"\(prompt)\"*\n\nThis reply was streamed locally by `DemoAgentServer` with zero network traffic. Try opening **Artifacts**, **Sprint Checklist**, **Architecture Spec**, or **Pipelines** to test the rest of the UI."
    }

    private func handleTodoRoute(method: String, path: String, route: String, sent: JSONValue?) -> HTTP1Response {
        let rest = String(route.dropFirst("/v0/surfaces/todo/".count))
        let parts = rest.split(separator: "/").map(String.init)
        guard let surfaceId = parts.first else { return jsonResponse(.object(["todos": .array([])])) }
        var list = todos[surfaceId] ?? []
        let now = Date().timeIntervalSince1970 * 1000

        if parts.count == 1 && method == "GET" {
            let scope = URLComponents(string: path)?.queryItems?.first(where: { $0.name == "scope" })?.value ?? "active"
            let filtered = list.filter { $0.status.rawValue == scope }
            return encodeKeyed("todos", filtered)
        }
        if parts.count == 1 && method == "POST" {
            todoCounter += 1
            let id = sent?["id"]?.stringValue ?? "td-\(todoCounter)"
            if let existing = list.first(where: { $0.id == id }) {
                return encodeKeyed("todo", existing)
            }
            let item = TodoItem(
                id: id, surfaceId: surfaceId, authorUserId: "ridoy",
                text: sent?["text"]?.stringValue ?? "", status: .active,
                orderKey: "0\(todoCounter)", createdAt: now, updatedAt: now, version: "v\(todoCounter)"
            )
            list.insert(item, at: 0)
            todos[surfaceId] = list
            emit("todo.created", ["surfaceId": .string(surfaceId), "todoId": .string(id)])
            return encodeKeyed("todo", item)
        }
        if parts.count >= 2 {
            let todoId = parts[1]
            if parts.count == 3 && parts[2] == "versions" && method == "GET" {
                return jsonResponse(.object(["versions": .array([]), "nextAfterVersion": .null]))
            }
            guard let idx = list.firstIndex(where: { $0.id == todoId }) else {
                return jsonResponse(.object(["error": .string("Not found")]), status: 404)
            }
            todoCounter += 1
            if parts.count == 3 && parts[2] == "reorder" && method == "POST" {
                let afterId = sent?["afterId"]?.stringValue
                var moved = list.remove(at: idx)
                if let afterId, let afterIdx = list.firstIndex(where: { $0.id == afterId }) {
                    list.insert(moved, at: afterIdx + 1)
                } else {
                    list.insert(moved, at: 0)
                }
                for i in list.indices where list[i].status == .active {
                    list[i].orderKey = String(format: "k%04d", i)
                }
                moved = list.first { $0.id == todoId } ?? moved
                moved.version = "v\(todoCounter)"
                todos[surfaceId] = list
                return encodeKeyed("todo", moved)
            }
            if method == "GET" { return encodeKeyed("todo", list[idx]) }
            if method == "PATCH" {
                if let text = sent?["text"]?.stringValue { list[idx].text = text }
                if let statusRaw = sent?["status"]?.stringValue, let status = TodoItem.Status(rawValue: statusRaw) {
                    list[idx].status = status
                    list[idx].completedAt = status == .completed ? now : nil
                }
                list[idx].updatedAt = now
                list[idx].version = "v\(todoCounter)"
                todos[surfaceId] = list
                return encodeKeyed("todo", list[idx])
            }
            if method == "DELETE" {
                list[idx].status = .deleted
                list[idx].deletedAt = now
                list[idx].version = "v\(todoCounter)"
                todos[surfaceId] = list
                return encodeKeyed("todo", list[idx])
            }
        }
        return jsonResponse(.object(["error": .string("Not found")]), status: 404)
    }

    private func handleDocumentRoute(method: String, path: String, route: String, sent: JSONValue?) -> HTTP1Response {
        let rest = String(route.dropFirst("/v0/surfaces/document/".count))
        let parts = rest.split(separator: "/").map(String.init)
        guard let surfaceId = parts.first else { return jsonResponse(.object([:]), status: 404) }
        let tail = parts.dropFirst().joined(separator: "/")

        if tail == "" && method == "GET" {
            let doc = YDoc()
            try? doc.applyUpdate(docData)
            let text = DocumentReader.blocks(doc).map(\.plainText).joined(separator: "\n\n")
            return jsonResponse(.object(["document": .object(["text": .string(text), "seq": .number(Double(docSeq))])]))
        }
        if tail == "state" && method == "GET" {
            let doc = YDoc()
            try? doc.applyUpdate(docData)
            let sv = Data(YDoc.encodeStateVector(doc.stateVector())).base64EncodedString()
            let updateB64 = Data(doc.encodeStateAsUpdate()).base64EncodedString()
            return jsonResponse(.object(["seq": .number(Double(docSeq)), "update": .string(updateB64), "stateVector": .string(sv)]))
        }
        if tail == "updates" && method == "GET" {
            return jsonResponse(.object(["updates": .array(docUpdates), "nextAfterSeq": .null]))
        }
        if tail == "updates" && method == "POST" {
            if let b64 = sent?["update"]?.stringValue, let bytes = Data(base64Encoded: b64) {
                let doc = YDoc()
                try? doc.applyUpdate(docData)
                try? doc.applyUpdate(Array(bytes))
                docData = doc.encodeStateAsUpdate()
                docSeq += 1
                docUpdates.append(.object([
                    "seq": .number(Double(docSeq)),
                    "actor": .object(["userId": .string("ridoy"), "agentId": .null]),
                    "source": .string("api"),
                    "createdAt": .number(Date().timeIntervalSince1970 * 1000),
                    "size": .number(Double(bytes.count)),
                ]))
                let framePayload = #"{"surfaceId":"\#(surfaceId)","seq":\#(docSeq),"update":"\#(b64)","mutationId":null,"actor":{"userId":"ridoy","agentId":null},"source":"api"}"#
                emitNamedFrame(event: "document.update", data: framePayload)
            }
            return jsonResponse(.object(["seq": .number(Double(docSeq))]))
        }
        if tail == "subscribe" && method == "POST" {
            return jsonResponse(.object(["seq": .number(Double(docSeq))]))
        }
        if (tail == "unsubscribe" || tail == "presence") && method == "POST" {
            return jsonResponse(.object(["ok": .bool(true)]))
        }
        return jsonResponse(.object(["error": .string("Not found")]), status: 404)
    }

    private func handleVaultRoute(method: String, path: String, route: String, body: Data?, sent: JSONValue?, headers: [String: String]) -> HTTP1Response {
        if route == "/v0/vault-uploads" && method == "POST" {
            let id = "up-\(UUID().uuidString.prefix(8))"
            let size = Int(sent?["size"]?.numberValue ?? 0)
            vaultUploads[id] = (size: size, data: Data())
            return encodeKeyed("upload", VaultUpload(id: id, size: size, received: 0, status: "receiving"))
        }
        if route.hasPrefix("/v0/vault-uploads/") {
            let id = String(route.dropFirst("/v0/vault-uploads/".count))
            if method == "GET", let up = vaultUploads[id] {
                return encodeKeyed("upload", VaultUpload(id: id, size: up.size, received: up.data.count, status: up.data.count >= up.size ? "complete" : "receiving"))
            }
            if method == "PUT", var up = vaultUploads[id] {
                if let body { up.data.append(body) }
                vaultUploads[id] = up
                return encodeKeyed("upload", VaultUpload(id: id, size: up.size, received: up.data.count, status: up.data.count >= up.size ? "complete" : "receiving"))
            }
            if method == "DELETE" {
                vaultUploads.removeValue(forKey: id)
                return jsonResponse(.object(["ok": .bool(true)]))
            }
        }

        let rest = String(route.dropFirst("/v0/surfaces/vault/".count))
        let parts = rest.split(separator: "/").map(String.init)
        guard let surfaceId = parts.first else { return jsonResponse(.object([:]), status: 404) }
        let sub = Array(parts.dropFirst())
        let now = Date().timeIntervalSince1970 * 1000

        if sub == ["items"] && method == "GET" {
            let parentId = URLComponents(string: path)?.queryItems?.first(where: { $0.name == "parentId" })?.value
            let items = vaultEntries.filter { $0.surfaceId == surfaceId && $0.deletedAt == nil && $0.parentId == parentId }
            return encodableResponse(VaultItemsResponse(items: items, nextPageCursor: nil))
        }
        if sub == ["trash"] && method == "GET" {
            let trashed = vaultEntries.filter { $0.surfaceId == surfaceId && $0.deletedAt != nil }.map { VaultTrashItem(entry: $0, path: "/\($0.name)") }
            return encodeKeyed("items", trashed)
        }
        if sub == ["settings"] && method == "GET" {
            return encodeKeyed("settings", vaultSettings)
        }
        if sub == ["settings"] && method == "PATCH" {
            if let rData = try? JSONEncoder().encode(sent?["retention"]), let ret = try? JSONDecoder().decode(VaultRetention.self, from: rData) {
                vaultSettings.retention = ret
                vaultSettings.updatedAt = now
                vaultSettings.version = "vs-\(Int.random(in: 2...9999))"
            }
            return encodeKeyed("settings", vaultSettings)
        }
        if (sub == ["folders"] || sub == ["files"]) && method == "POST" {
            let isFolder = sub == ["folders"]
            let id = sent?["id"]?.stringValue ?? "ve-\(UUID().uuidString.prefix(8))"
            let name = sent?["name"]?.stringValue ?? "Untitled"
            let parentId = sent?["parentId"]?.stringValue
            let bytes = sent?["uploadId"]?.stringValue.flatMap { vaultUploads[$0]?.data } ?? Data()
            let entry = VaultEntry(
                id: id, surfaceId: surfaceId, parentId: parentId, name: name,
                kind: isFolder ? .folder : VaultEntry.kind(named: name),
                latestVersion: isFolder ? nil : 1, size: isFolder ? nil : bytes.count,
                mediaType: isFolder ? nil : "application/octet-stream",
                createdAt: now, createdBy: VaultActor(userId: "ridoy"),
                updatedAt: now, updatedBy: VaultActor(userId: "ridoy"), version: "ver-\(Int.random(in: 10...9999))"
            )
            vaultEntries.append(entry)
            if !isFolder {
                vaultFilesData[id] = [1: bytes]
                vaultVersions[id] = [VaultVersion(entryId: id, surfaceId: surfaceId, number: 1, size: bytes.count, createdAt: now, actor: VaultActor(userId: "ridoy"))]
            }
            return encodeKeyed(isFolder ? "folder" : "file", entry, status: 201)
        }
        if sub.count >= 2 && (sub[0] == "folders" || sub[0] == "files") {
            let isFolder = sub[0] == "folders"
            let entryId = sub[1]
            let key = isFolder ? "folder" : "file"
            guard let idx = vaultEntries.firstIndex(where: { $0.id == entryId }) else {
                return jsonResponse(.object(["error": .string("Not found")]), status: 404)
            }
            if sub.count == 2 && method == "GET" {
                let entry = vaultEntries[idx]
                if isFolder {
                    return encodableResponse(VaultFolderLocationResponse(folder: entry, path: "/\(entry.name)", ancestors: [], inTrash: entry.deletedAt != nil))
                }
                return encodableResponse(VaultFileLocationResponse(file: entry, path: "/\(entry.name)", ancestors: [], inTrash: entry.deletedAt != nil))
            }
            if sub.count == 2 && method == "PATCH" {
                if let name = sent?["name"]?.stringValue { vaultEntries[idx].name = name }
                if let parentVal = sent?["parentId"] { vaultEntries[idx].parentId = parentVal.stringValue }
                vaultEntries[idx].updatedAt = now
                return encodeKeyed(key, vaultEntries[idx])
            }
            if sub.count == 3 && sub[2] == "delete" && method == "POST" {
                vaultEntries[idx].deletedAt = now
                return encodeKeyed(key, vaultEntries[idx])
            }
            if sub.count == 3 && sub[2] == "restore" && method == "POST" {
                vaultEntries[idx].deletedAt = nil
                return encodeKeyed(key, vaultEntries[idx])
            }
            if sub.count == 3 && sub[2] == "versions" && method == "GET" {
                return encodeKeyed("versions", vaultVersions[entryId] ?? [])
            }
            if sub.count == 3 && sub[2] == "activity" && method == "GET" {
                return encodeKeyed("activity", [VaultActivity]())
            }
            if sub.count >= 4 && sub[2] == "versions" {
                let verNum = sub[3] == "latest" ? (vaultEntries[idx].latestVersion ?? 1) : (Int(sub[3]) ?? 1)
                if sub.count == 4 && method == "GET", let v = (vaultVersions[entryId] ?? []).first(where: { $0.number == verNum }) {
                    return encodeKeyed("version", v)
                }
                if sub.count == 5 && sub[4] == "content" && method == "GET" {
                    let bytes = vaultFilesData[entryId]?[verNum] ?? Data("Demo file contents\n".utf8)
                    return HTTP1Response(status: 200, headers: ["content-type": vaultEntries[idx].mediaType ?? "text/plain", "content-length": "\(bytes.count)"], body: bytes)
                }
                if sub.count == 5 && (sub[4] == "pin" || sub[4] == "unpin") && method == "POST" {
                    var list = vaultVersions[entryId] ?? []
                    if let vi = list.firstIndex(where: { $0.number == verNum }) {
                        list[vi].pinned = (sub[4] == "pin")
                        vaultVersions[entryId] = list
                        return encodeKeyed("version", list[vi])
                    }
                }
            }
        }
        return jsonResponse(.object(["error": .string("Not found")]), status: 404)
    }

    private func handleFeedRoute(method: String, path: String, route: String, sent: JSONValue?) -> HTTP1Response {
        if route == "/v0/feed" && method == "GET" {
            let unread = feedItems.filter { $0["seenAt"] == .null }.count
            return jsonResponse(.object(["items": .array(feedItems), "unread": .number(Double(unread)), "hasMore": .bool(false)]))
        }
        if route == "/v0/feed/seen" && method == "POST" {
            let now = Date().timeIntervalSince1970 * 1000
            for idx in feedItems.indices {
                if case .object(var obj) = feedItems[idx] {
                    obj["seenAt"] = .number(now)
                    feedItems[idx] = .object(obj)
                }
            }
            return jsonResponse(.object(["items": .array(feedItems), "unread": .number(0)]))
        }
        if route == "/v0/feed/read-all" && method == "POST" {
            let now = Date().timeIntervalSince1970 * 1000
            for idx in feedItems.indices {
                if case .object(var obj) = feedItems[idx] {
                    obj["seenAt"] = .number(now)
                    feedItems[idx] = .object(obj)
                }
            }
            return jsonResponse(.object(["unread": .number(0)]))
        }
        if route == "/v0/feed/clusters" && method == "GET" {
            return jsonResponse(.object(["clusters": .array(feedClusters)]))
        }
        if route.hasPrefix("/v0/feed/subscriptions/") {
            let cid = String(route.dropFirst("/v0/feed/subscriptions/".count)).removingPercentEncoding ?? ""
            if let idx = feedClusters.firstIndex(where: { $0["cluster"]?.stringValue == cid }), case .object(var obj) = feedClusters[idx] {
                obj["state"] = .string(method == "PUT" ? "subscribed" : "muted")
                feedClusters[idx] = .object(obj)
                return jsonResponse(.object(["cluster": feedClusters[idx]]))
            }
        }
        if route.hasPrefix("/v0/feed/clusters/") {
            return jsonResponse(.object(["cluster": feedClusters.first ?? .null, "entries": .array(feedItems)]))
        }
        return jsonResponse(.object(["items": .array([])]))
    }

    private func handleArtifactRoute(method: String, path: String, route: String, headers: [String: String], sent: JSONValue?) -> HTTP1Response {
        let ago: (Double) -> Double = { (Date().timeIntervalSince1970 * 1000 - $0 * 60_000).rounded() }
        if route == "/v0/artifacts" && method == "GET" {
            var list: [JSONValue] = [
                .object([
                    "id": .string("revenue"), "type": .string("html"), "title": .string("Q3 Revenue & Growth Review"), "latestVersion": .number(2),
                    "createdAt": .number(ago(600)), "updatedAt": .number(ago(12)),
                    "entry": .object(["path": .string("index.html"), "mimeType": .string("text/html"), "size": .number(1024)]),
                    "cover": .object(["path": .string("cover.png"), "mimeType": .string("image/png"), "width": .number(960), "height": .number(540), "aspect": .string("wide"), "thumbhash": .string(DemoData.ridoyThumb)]),
                    "summary": .string("Revenue up 28% QoQ across enterprise and self-serve plans."),
                    "background": .string("#0d1f36"),
                ]),
                .object([
                    "id": .string("roadmap"), "type": .string("markdown"), "title": .string("Q4 Engineering Roadmap"), "latestVersion": .number(1),
                    "createdAt": .number(ago(400)), "updatedAt": .number(ago(40)),
                    "entry": .object(["path": .string("roadmap.md"), "mimeType": .string("text/markdown"), "size": .number(512)]),
                    "summary": .string("Milestones for GenUI, Collaborative Documents, Vaults, and Pipelines."),
                ]),
            ]
            for name in Self.genUINames {
                list.append(.object([
                    "id": .string("genui-\(name)"), "type": .string("gen_ui"), "title": .string("GenUI · \(name)"), "latestVersion": .number(1),
                    "createdAt": .number(ago(200)), "updatedAt": .number(ago(25)),
                    "entry": .object(["path": .string(GenUIRenderDocument.path), "mimeType": .string("application/json"), "size": .number(Double(DemoData.genUIDocument(named: name)?.count ?? 256))]),
                ]))
            }
            return jsonResponse(.object(["artifacts": .array(list), "nextPageCursor": .null]))
        }

        let parts = route.dropFirst("/v0/artifacts/".count).split(separator: "/").map(String.init)
        guard let id = parts.first else { return jsonResponse(.object([:]), status: 404) }

        if parts.count == 1 && method == "GET" {
            if id.hasPrefix("genui-") {
                let name = String(id.dropFirst("genui-".count))
                return jsonResponse(.object(["artifact": .object([
                    "id": .string(id), "type": .string("gen_ui"), "title": .string("GenUI · \(name)"), "latestVersion": .number(1), "status": .string("active"),
                    "entry": .object(["path": .string(GenUIRenderDocument.path), "mimeType": .string("application/json"), "size": .number(Double(DemoData.genUIDocument(named: name)?.count ?? 256))]),
                ])]))
            }
            let type = id == "roadmap" ? "markdown" : "html"
            let entryPath = id == "roadmap" ? "roadmap.md" : "index.html"
            let mime = id == "roadmap" ? "text/markdown" : "text/html"
            return jsonResponse(.object(["artifact": .object([
                "id": .string(id), "type": .string(type), "title": .string(id == "roadmap" ? "Q4 Engineering Roadmap" : "Q3 Revenue & Growth Review"),
                "latestVersion": .number(1), "status": .string("active"),
                "entry": .object(["path": .string(entryPath), "mimeType": .string(mime), "size": .number(512)]),
            ])]))
        }
        if parts.count == 3 && parts[1] == "versions" && method == "GET" {
            if id.hasPrefix("genui-") {
                let name = String(id.dropFirst("genui-".count))
                let docSize = Double(DemoData.genUIDocument(named: name)?.count ?? 0)
                return jsonResponse(.object(["version": .object([
                    "artifactId": .string(id), "number": .number(1), "title": .string("GenUI · \(name)"),
                    "entry": .object(["path": .string(GenUIRenderDocument.path), "mimeType": .string("application/json"), "size": .number(docSize)]),
                    "createdBy": .object(["kind": .string("agent"), "agentId": .string("research-agent"), "botId": .string("research")]),
                    "files": .array([.object(["path": .string(GenUIRenderDocument.path), "mimeType": .string("application/json"), "size": .number(docSize)])]),
                ])]))
            }
            let entryPath = id == "roadmap" ? "roadmap.md" : "index.html"
            let mime = id == "roadmap" ? "text/markdown" : "text/html"
            return jsonResponse(.object(["version": .object([
                "artifactId": .string(id), "number": .number(1), "title": .string(id),
                "entry": .object(["path": .string(entryPath), "mimeType": .string(mime), "size": .number(512)]),
                "createdBy": .object(["kind": .string("agent"), "agentId": .string("research-agent"), "botId": .string("research")]),
                "files": .array([.object(["path": .string(entryPath), "mimeType": .string(mime), "size": .number(512)])]),
            ])]))
        }
        if parts.count >= 5 && parts[1] == "versions" && parts[3] == "files" && method == "GET" {
            let wanted = parts[4...].joined(separator: "/").removingPercentEncoding ?? ""
            if wanted == "cover.png" {
                return serveBytes(DemoImages.chartCover(), mime: "image/png", range: headers["Range"])
            }
            if id.hasPrefix("genui-") {
                let name = String(id.dropFirst("genui-".count))
                if wanted == GenUIRenderDocument.path, let data = DemoData.genUIDocument(named: name) {
                    return serveBytes(data, mime: "application/json", range: headers["Range"])
                }
                if let asset = DemoData.genUIAsset(named: wanted) {
                    return serveBytes(asset, mime: "image/jpeg", range: headers["Range"])
                }
            }
            if id == "roadmap" {
                let md = Data("# Q4 Engineering Roadmap\n\n- **GenUI Interactive Blocks**: Live stats, charts, tables, and secrets forms\n- **Offline-First Sync**: Instant SQLite checkpoints\n- **Pipelines & Vaults**: Full version history and log streaming\n".utf8)
                return serveBytes(md, mime: "text/markdown", range: headers["Range"])
            }
            let html = Data("""
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>body{font-family:-apple-system,sans-serif;padding:24px;background:#0d1f36;color:#fff;}h1{margin-top:0;} .card{background:rgba(255,255,255,0.08);padding:16px;border-radius:14px;}</style>
            </head><body><h1>Q3 Revenue & Growth Review</h1><div class="card"><p><strong>+28% QoQ</strong> across Enterprise & Pro plans.</p><p>Interactive HTML artifact rendered offline in Demo Mode.</p></div></body></html>
            """.utf8)
            return serveBytes(html, mime: "text/html", range: headers["Range"])
        }
        if parts.count >= 4 && parts[3] == "actions" && method == "POST" {
            return jsonResponse(.object(["secret": .object(["id": .string("demo-secret"), "version": .string("v2"), "environmentVariables": .array([.string("DEMO_KEY")])]), "outcome": .string("created"), "granted": .bool(true)]))
        }
        return jsonResponse(.object(["error": .string("Not found")]), status: 404)
    }

    private func handleWorkspaceRoute(method: String, path: String, route: String, body: Data?) -> HTTP1Response {
        if route.hasSuffix("/git") && method == "GET" {
            return jsonResponse(.object([
                "git": .object([
                    "facts": .object(["branch": .string("feat/demo-ui"), "detached": .bool(false), "head": .string("4be1c0d"), "upstream": .string("origin/feat/demo-ui"), "ahead": .number(2), "behind": .number(0)]),
                    "comparison": .string("ready"), "base": .string("origin/main"), "changedFiles": .number(2), "insertions": .number(18), "deletions": .number(4),
                    "countsExact": .bool(true), "conflicted": .bool(false),
                    "files": .array([
                        .object(["path": .string("Sources/Cache/Store.swift"), "status": .string("modified"), "staged": .bool(false), "unstaged": .bool(true), "binary": .bool(false), "insertions": .number(12), "deletions": .number(4)]),
                        .object(["path": .string("README.md"), "status": .string("modified"), "staged": .bool(true), "unstaged": .bool(false), "binary": .bool(false), "insertions": .number(6), "deletions": .number(0)]),
                    ]),
                    "filesTruncated": .bool(false), "scannedAt": .number(1),
                ]),
            ]))
        }
        if route.hasSuffix("/file") && method == "PUT", let body {
            let hash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
            return jsonResponse(.object(["hash": .string(hash)]))
        }
        return jsonResponse(.object(["content": .string("// Demo workspace file\nimport Foundation\n")]))
    }

    private func serveBytes(_ data: Data, mime: String, range: String?) -> HTTP1Response {
        let total = data.count
        guard let range, range.hasPrefix("bytes=") else {
            return HTTP1Response(status: 200, headers: ["content-type": mime, "content-length": "\(total)"], body: data)
        }
        let bounds = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2, let start = Int(bounds[0]), start < total else {
            return HTTP1Response(status: 416, headers: ["content-range": "bytes */\(total)"], body: Data())
        }
        let end = min(total - 1, Int(bounds[1]) ?? total - 1)
        return HTTP1Response(status: 206, headers: ["content-type": mime, "content-range": "bytes \(start)-\(end)/\(total)", "content-length": "\(end - start + 1)"], body: data.subdata(in: start..<(end + 1)))
    }

    private func jsonResponse(_ value: JSONValue, status: Int = 200) -> HTTP1Response {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return HTTP1Response(status: status, headers: ["content-type": "application/json"], body: data)
    }

    private func anyJSONResponse(_ value: Any, status: Int = 200) -> HTTP1Response {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
        return HTTP1Response(status: status, headers: ["content-type": "application/json"], body: data)
    }

    private func encodeKeyed<T: Encodable>(_ key: String, _ value: T, status: Int = 200) -> HTTP1Response {
        encodableResponse([key: value], status: status)
    }

    private func encodableResponse<T: Encodable>(_ value: T, status: Int = 200) -> HTTP1Response {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return HTTP1Response(status: status, headers: ["content-type": "application/json"], body: data)
    }
}

private struct VaultItemsResponse: Encodable {
    let items: [VaultEntry]
    let nextPageCursor: String?
}

private struct VaultFolderLocationResponse: Encodable {
    let folder: VaultEntry
    let path: String
    let ancestors: [VaultLocation.Ancestor]
    let inTrash: Bool
}

private struct VaultFileLocationResponse: Encodable {
    let file: VaultEntry
    let path: String
    let ancestors: [VaultLocation.Ancestor]
    let inTrash: Bool
}
#endif
