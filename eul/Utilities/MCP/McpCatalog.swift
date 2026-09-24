import Foundation

struct McpCatalog: Codable, Equatable {
    var version: Int
    var port: Int
    var servers: [McpServerEntry]

    static let empty = McpCatalog(version: 1, port: McpPaths.defaultPort, servers: [])

    var listenPort: Int {
        port > 0 ? port : McpPaths.defaultPort
    }

    mutating func setEnabled(id: String, enabled: Bool) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else {
            return
        }
        servers[index].enabled = enabled
    }

    mutating func moveServer(from offset: Int, to destination: Int) {
        guard servers.indices.contains(offset), servers.indices.contains(destination), offset != destination else {
            return
        }
        let entry = servers.remove(at: offset)
        servers.insert(entry, at: destination)
    }
}

struct McpServerEntry: Codable, Equatable, Identifiable {
    var id: String
    var enabled: Bool
    var command: String?
    var args: [String]
    var env: [String: String]
    var cwd: String?
    var url: String?
    var headers: [String: String]

    var isRemote: Bool {
        url?.isEmpty == false
    }

    enum CodingKeys: String, CodingKey {
        case id, enabled, command, args, env, cwd, url, headers
    }

    init(
        id: String,
        enabled: Bool = true,
        command: String? = nil,
        args: [String] = [],
        env: [String: String] = [:],
        cwd: String? = nil,
        url: String? = nil,
        headers: [String: String] = [:]
    ) {
        self.id = id
        self.enabled = enabled
        self.command = command
        self.args = args
        self.env = env
        self.cwd = cwd
        self.url = url
        self.headers = headers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        command = try container.decodeIfPresent(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(enabled, forKey: .enabled)
        try container.encodeIfPresent(command, forKey: .command)
        if !args.isEmpty {
            try container.encode(args, forKey: .args)
        }
        if !env.isEmpty {
            try container.encode(env, forKey: .env)
        }
        try container.encodeIfPresent(cwd, forKey: .cwd)
        try container.encodeIfPresent(url, forKey: .url)
        if !headers.isEmpty {
            try container.encode(headers, forKey: .headers)
        }
    }
}

enum McpCatalogStore {
    static func load() -> McpCatalog {
        let url = McpPaths.catalogURL
        guard let data = try? Data(contentsOf: url) else {
            return .empty
        }
        return (try? JSONDecoder().decode(McpCatalog.self, from: data)) ?? .empty
    }

    static func save(_ catalog: McpCatalog) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(catalog)
        try McpPaths.writeAtomic(data, to: McpPaths.catalogURL, posixPermissions: 0o600)
    }
}
