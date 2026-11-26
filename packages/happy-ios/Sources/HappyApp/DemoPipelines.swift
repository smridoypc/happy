#if canImport(UIKit)
import Foundation

/// Self-contained pipeline definitions, runs, and logs for offline demo exploration.
struct DemoPipelines {
    struct Run {
        var id: String
        var pipeline: String
        var version: Int
        var state: String
        var trigger: String
        var parent: String?
        var created: Double
        var started: Double?
        var ended: Double?
    }

    static let names: [String: String] = [
        "deploy": "Deploy preview",
        "build": "Build and sign",
        "sweep": "Nightly test sweep",
        "notes": "Release notes",
        "triage": "Triage inbox",
        "importer": "Old importer",
    ]

    static let descriptions: [String: String] = [
        "deploy": "Builds the branch, runs migrations on preview, and publishes once review says ship.",
        "build": "Builds and signs the app on a Mac and uploads the artifact.",
        "notes": "Drafts release notes from commits since the last tag.",
        "sweep": "Runs sharded test suites and triages regressions.",
        "triage": "Sorts incoming messages by urgency.",
    ]

    static let live = ["build", "deploy", "notes", "sweep", "triage"]

    let now: Double
    private(set) var runs: [Run]
    private var ticks = 0
    private let pageSize = 8

    init(now: Date = Date()) {
        let nowMs = (now.timeIntervalSince1970 * 1000).rounded()
        self.now = nowMs
        func ago(_ seconds: Double) -> Double { nowMs - seconds * 1000 }
        let agent = { (id: String) in #"{"kind":"agent","agentId":"\#(id)"}"# }
        let node = { (run: String, node: String) in #"{"kind":"pipeline","runId":"\#(run)","nodeId":"\#(node)"}"# }
        runs = [
            Run(id: "r1", pipeline: "deploy", version: 8, state: "running", trigger: agent("t1-agent"), created: ago(72), started: ago(72)),
            Run(id: "r2", pipeline: "build", version: 4, state: "running", trigger: node("r1", "build"), parent: "r1", created: ago(50), started: ago(50)),
            Run(id: "r3", pipeline: "sweep", version: 12, state: "queued", trigger: agent("cos-agent"), created: ago(40)),
            Run(id: "r4", pipeline: "sweep", version: 12, state: "failed", trigger: agent("cos-agent"), created: ago(3 * 3600), started: ago(3 * 3600), ended: ago(3 * 3600 - 843)),
            Run(id: "r5", pipeline: "build", version: 4, state: "succeeded", trigger: node("r6", "build"), parent: "r6", created: ago(24 * 60), started: ago(24 * 60), ended: ago(20 * 60)),
            Run(id: "r6", pipeline: "deploy", version: 8, state: "superseded", trigger: agent("t1-agent"), created: ago(25 * 60), started: ago(25 * 60), ended: ago(19 * 60)),
            Run(id: "r7", pipeline: "importer", version: 2, state: "succeeded", trigger: #"{"kind":"agent","agentId":null}"#, created: ago(26 * 3600), started: ago(26 * 3600), ended: ago(26 * 3600 - 95)),
            Run(id: "r8", pipeline: "notes", version: 3, state: "aborted", trigger: agent("cos-agent"), created: ago(2 * 86400), started: ago(2 * 86400), ended: ago(2 * 86400 - 30)),
            Run(id: "r9", pipeline: "notes", version: 2, state: "succeeded", trigger: agent("cos-agent"), created: ago(4 * 86400), started: ago(4 * 86400), ended: ago(4 * 86400 - 212)),
            Run(id: "r10", pipeline: "sweep", version: 11, state: "succeeded", trigger: agent("cos-agent"), created: ago(9 * 86400), started: ago(9 * 86400), ended: ago(9 * 86400 - 3910)),
        ]
    }

    struct Answer {
        var status = 200
        var body: String
        var events: [(type: String, payload: String)] = []
    }

    mutating func tick() -> [(type: String, payload: String)] {
        ticks += 1
        return [("pipeline.node.log", #"{"runId":"r1","nodeId":"migrate"}"#)]
    }

    mutating func answer(_ method: String, _ path: String) -> Answer? {
        let route = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        let parts = route.split(separator: "/").map(String.init)
        if method == "POST", parts.count == 4, parts[1] == "pipeline-runs", parts[3] == "abort" {
            return abort(parts[2])
        }
        guard method == "GET" else { return nil }
        if route == "/v0/pipelines" { return Answer(body: pipelinesJSON) }
        if route == "/v0/pipeline-runs" {
            let cursor = URLComponents(string: path)?.queryItems?.first { $0.name == "cursor" }?.value
            let start = cursor.flatMap { id in runs.firstIndex { $0.id == id }.map { $0 + 1 } } ?? 0
            let page = Array(runs.dropFirst(start).prefix(pageSize))
            let next = start + page.count < runs.count ? page.last.map { "\"\($0.id)\"" } ?? "null" : "null"
            return Answer(body: #"{"runs":[\#(page.map(runJSON).joined(separator: ","))],"nextCursor":\#(next)}"#)
        }
        if parts.count == 3, parts[1] == "pipelines" { return pipelineDetail(parts[2]) }
        if parts.count == 5, parts[1] == "pipelines", parts[3] == "versions", let number = Int(parts[4]) {
            return pipelineVersion(parts[2], number: number)
        }
        if parts.count == 3, parts[1] == "pipeline-runs" { return runDetail(parts[2]) }
        if parts.count == 6, parts[1] == "pipeline-runs", parts[3] == "nodes", parts[5] == "logs" {
            return nodeLogs(parts[2], node: parts[4])
        }
        return nil
    }

    private mutating func abort(_ id: String) -> Answer {
        guard let index = runs.firstIndex(where: { $0.id == id }) else {
            return Answer(status: 404, body: #"{"code":"not_found","error":"Run not found."}"#)
        }
        let nowMs = (Date().timeIntervalSince1970 * 1000).rounded()
        runs[index].state = "aborted"
        runs[index].ended = nowMs
        let pipeline = runs[index].pipeline
        return Answer(
            body: #"{"run":\#(runJSON(runs[index]))}"#,
            events: [("pipeline.run.updated", #"{"pipelineId":"\#(pipeline)","runId":"\#(id)"}"#)]
        )
    }

    private func runJSON(_ run: Run) -> String {
        func num(_ value: Double?) -> String { value.map { String(Int64($0)) } ?? "null" }
        let parent = run.parent.map { "\"\($0)\"" } ?? "null"
        let name = Self.names[run.pipeline] ?? run.pipeline
        return #"{"id":"\#(run.id)","version":\#(run.version),"state":"\#(run.state)","trigger":\#(run.trigger),"parentRunId":\#(parent),"createdAt":\#(num(run.created)),"startedAt":\#(num(run.started)),"endedAt":\#(num(run.ended)),"pipelineId":"\#(run.pipeline)","pipelineName":"\#(name)","pipelineArchived":\#(run.pipeline == "importer")}"#
    }

    private var pipelinesJSON: String {
        encode(["pipelines": Self.live.compactMap { pipelineObject($0, whole: false) }])
    }

    private func pipelineObject(_ id: String, whole: Bool) -> [String: Any]? {
        guard Self.live.contains(id), let head = versions(id).first else { return nil }
        let last = runs.first { $0.pipeline == id }
        let lastRun: Any = last.map { run -> [String: Any] in
            ["id": run.id, "state": run.state, "createdAt": run.created, "endedAt": jsonDouble(run.ended)]
        } ?? NSNull()
        let created = versions(id).last?.at ?? now
        return [
            "id": id,
            "name": Self.names[id] ?? id,
            "description": jsonString(Self.descriptions[id]),
            "enabled": id != "notes",
            "head": versionObject(id, head, whole: whole),
            "lastRun": lastRun,
            "createdBy": id == "build" ? "ada" : "ridoy",
            "createdAt": created,
            "updatedAt": head.at,
        ]
    }

    private func versions(_ pipeline: String) -> [(number: Int, message: String, author: [String: Any], at: Double)] {
        let count: Int
        switch pipeline {
        case "deploy": count = 8
        case "build": count = 4
        case "notes": count = 3
        case "sweep": count = 12
        default: count = 1
        }
        return (1...count).reversed().map { num in
            (num, num == count ? "Latest pipeline revision" : "Step update v\(num)", ["kind": "user", "userId": "ridoy"], now - Double((count - num) * 86_400) * 1000)
        }
    }

    private func versionObject(_ pipeline: String, _ entry: (number: Int, message: String, author: [String: Any], at: Double), whole: Bool) -> [String: Any] {
        var result: [String: Any] = [
            "number": entry.number,
            "digest": "sha256:" + String(String(repeating: "\(entry.number)c4e9\(pipeline.count)f0b", count: 8).prefix(64)),
            "parent": entry.number > 1 ? entry.number - 1 : NSNull() as Any,
            "message": entry.message,
            "author": entry.author,
            "createdAt": entry.at,
        ]
        if whole {
            result["definition"] = definition(pipeline, entry.number) ?? NSNull()
        }
        return result
    }

    private func pipelineDetail(_ id: String) -> Answer {
        guard let pipeline = pipelineObject(id, whole: true) else {
            return Answer(status: 404, body: #"{"code":"not_found","error":"Pipeline not found."}"#)
        }
        let versionList = versions(id).map { versionObject(id, $0, whole: false) }
        let matchingRuns: [[String: Any]] = runs.filter { $0.pipeline == id }.map { r in
            ["id": r.id, "version": r.version, "state": r.state, "createdAt": r.created, "startedAt": jsonDouble(r.started), "endedAt": jsonDouble(r.ended)]
        }
        return Answer(body: encode(["pipeline": pipeline, "versions": versionList, "runs": matchingRuns]))
    }

    private func pipelineVersion(_ id: String, number: Int) -> Answer {
        guard let entry = versions(id).first(where: { $0.number == number }) else {
            return Answer(status: 404, body: #"{"code":"not_found","error":"Version not found."}"#)
        }
        return Answer(body: encode(["version": versionObject(id, entry, whole: true)]))
    }

    private func runDetail(_ id: String) -> Answer {
        guard let run = runs.first(where: { $0.id == id }) else {
            return Answer(status: 404, body: #"{"code":"not_found","error":"Run not found."}"#)
        }
        let nodes = runNodes(run)
        let def = definition(run.pipeline, run.version) ?? [:]
        return Answer(body: encode([
            "run": [
                "id": run.id,
                "pipelineId": run.pipeline,
                "pipelineName": Self.names[run.pipeline] ?? run.pipeline,
                "version": run.version,
                "state": run.state,
                "createdAt": run.created,
                "startedAt": jsonDouble(run.started),
                "endedAt": jsonDouble(run.ended),
                "nodes": nodes,
            ] as [String: Any],
            "definition": def,
        ]))
    }

    private func runNodes(_ run: Run) -> [[String: Any]] {
        let base = run.started ?? run.created
        switch run.pipeline {
        case "deploy":
            return [
                ["nodeId": "checkout", "state": "succeeded", "startedAt": base, "endedAt": base + 5_000, "output": ["commit": "4be1c0d", "branch": "feat/demo-ui"]],
                ["nodeId": "build", "state": run.state == "running" ? "running" : run.state, "startedAt": base + 6_000, "childRunId": "r2"],
                ["nodeId": "migrate", "state": run.state == "running" ? "running" : "succeeded", "startedAt": base + 6_000],
                ["nodeId": "review", "state": run.state == "running" ? "waiting" : "succeeded"],
                ["nodeId": "release", "state": run.state == "running" ? "pending" : "succeeded"],
                ["nodeId": "smoke", "state": run.state == "running" ? "pending" : "succeeded"],
            ]
        case "build":
            return [
                ["nodeId": "fetch", "state": "succeeded", "startedAt": base, "endedAt": base + 4_000],
                ["nodeId": "compile", "state": run.state == "running" ? "running" : "succeeded", "startedAt": base + 5_000],
                ["nodeId": "sign", "state": run.state == "running" ? "pending" : "succeeded"],
                ["nodeId": "upload", "state": run.state == "running" ? "pending" : "succeeded"],
            ]
        case "sweep":
            let failed = run.state == "failed"
            return [
                ["nodeId": "plan", "state": "succeeded", "startedAt": base, "endedAt": base + 3_000],
                ["nodeId": "tests", "state": failed ? "failed" : run.state, "startedAt": base + 4_000, "endedAt": failed ? base + 12_000 : NSNull()],
                ["nodeId": "triage", "state": failed ? "skipped" : "pending"],
            ]
        default:
            return [
                ["nodeId": "collect", "state": run.state, "startedAt": base, "endedAt": jsonDouble(run.ended)],
            ]
        }
    }

    private func nodeLogs(_ runId: String, node: String) -> Answer {
        var lines = [
            "[\(node)] Preparing environment...",
            "[\(node)] Checking out revision 4be1c0d",
            "[\(node)] Running demo step 1 of 3",
            "[\(node)] Connected to in-memory runner pool",
        ]
        if ticks > 0 {
            lines += (1...min(ticks + 2, 10)).map { "[\(node)] Applied batch \($0) (\($0 * 250) items)" }
        }
        return Answer(body: encode(["lines": lines, "nextCursor": NSNull()]))
    }

    private func definition(_ pipeline: String, _ number: Int) -> [String: Any]? {
        func str(_ desc: String? = nil) -> [String: Any] {
            var out: [String: Any] = ["type": "string"]
            if let desc { out["description"] = desc }
            return out
        }
        func obj(_ props: [String: [String: Any]], required: [String]) -> [String: Any] {
            ["type": "object", "properties": props, "required": required]
        }
        func code(_ source: String) -> [String: Any] {
            ["kind": "code", "input": obj([:], required: []), "output": obj([:], required: []), "source": source]
        }
        func doc(root: String, nodes: [String: [String: Any]], edges: [String]) -> [String: Any] {
            let parsedEdges: [[String: Any]] = edges.map { edge in
                let fail = edge.contains("!")
                let ends = edge.split(whereSeparator: { $0 == ">" || $0 == "!" }).map(String.init)
                return ["from": ends[0], "to": ends[1], "on": fail ? "failure" : "success"]
            }
            return ["input": obj(["branch": str("Branch")], required: ["branch"]), "concurrency": ["mode": "supersede"], "triggers": ["agents": ["cos-agent"]], "permissions": [:], "root": root, "nodes": nodes, "edges": parsedEdges]
        }
        switch pipeline {
        case "deploy":
            return doc(
                root: "checkout",
                nodes: [
                    "checkout": code("def main(input):\n    return {'branch': input['branch']}\n"),
                    "build": ["kind": "pipeline", "pipeline": "build", "input": obj([:], required: []), "output": obj([:], required: [])],
                    "migrate": code("def main(input):\n    status('Running migrations')\n    return {'applied': 3}\n"),
                    "review": ["kind": "agent", "model": "anthropic/claude-opus-4-5", "effort": "high", "instructions": "Review migration safety before release.", "input": obj([:], required: []), "output": obj([:], required: [])],
                    "release": code("def main(input):\n    return {'url': 'https://preview.demo.invalid'}\n"),
                    "smoke": code("def main(input):\n    return {'passed': True}\n"),
                ],
                edges: ["checkout>build", "checkout>migrate", "checkout>review", "build>release", "migrate>release", "review>release", "release>smoke"]
            )
        case "build":
            return doc(
                root: "fetch",
                nodes: [
                    "fetch": code("def main(input):\n    return {'path': '/workspace/happy'}\n"),
                    "compile": code("def main(input):\n    return {'warnings': 0}\n"),
                    "sign": code("def main(input):\n    return {'signed': True}\n"),
                    "upload": code("def main(input):\n    return {'url': 'https://builds.demo.invalid/app.ipa'}\n"),
                ],
                edges: ["fetch>compile", "compile>sign", "sign>upload"]
            )
        case "sweep":
            return doc(
                root: "plan",
                nodes: [
                    "plan": ["kind": "agent", "model": "openai/gpt-5-codex", "instructions": "Split tests into shards.", "input": obj([:], required: []), "output": obj([:], required: [])],
                    "tests": code("def main(input):\n    sh('swift test')\n"),
                    "triage": ["kind": "agent", "model": "openai/gpt-5-codex", "instructions": "File issues for failures.", "input": obj([:], required: []), "output": obj([:], required: [])],
                ],
                edges: ["plan>tests", "tests>triage"]
            )
        default:
            return doc(
                root: "collect",
                nodes: ["collect": code("def main(input):\n    return {'ok': True}\n")],
                edges: []
            )
        }
    }

    private func jsonDouble(_ value: Double?) -> Any {
        if let value { return value }
        return NSNull()
    }

    private func jsonString(_ value: String?) -> Any {
        if let value { return value }
        return NSNull()
    }

    private func encode(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
