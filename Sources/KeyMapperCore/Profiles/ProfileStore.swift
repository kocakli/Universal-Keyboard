import Foundation

/// Persists profiles as JSON files and remembers which profile is assigned to which keyboard.
public final class ProfileStore: @unchecked Sendable {
    public static let shared = ProfileStore()

    private let directory: URL
    private let assignmentsURL: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public init(directory: URL = AppPaths.profiles) {
        self.directory = directory
        self.assignmentsURL = directory.appendingPathComponent("assignments.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func all() -> [LayoutProfile] {
        lock.lock(); defer { lock.unlock() }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "assignments.json" }
            .compactMap { try? decoder.decode(LayoutProfile.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func profiles(for deviceKey: String) -> [LayoutProfile] {
        all().filter { $0.deviceKey == deviceKey }
    }

    public func save(_ profile: LayoutProfile) throws {
        lock.lock(); defer { lock.unlock() }
        var copy = profile
        copy.updatedAt = Date()
        try encoder.encode(copy).write(to: url(for: profile.id), options: .atomic)
    }

    public func delete(_ profile: LayoutProfile) {
        lock.lock()
        try? FileManager.default.removeItem(at: url(for: profile.id))
        lock.unlock()
        var assignments = self.assignments()
        assignments = assignments.filter { $0.value != profile.id }
        writeAssignments(assignments)
    }

    // MARK: Assignments (deviceKey -> profile)

    public func assignments() -> [String: UUID] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: assignmentsURL) else { return [:] }
        return (try? decoder.decode([String: UUID].self, from: data)) ?? [:]
    }

    public func assignedProfile(for deviceKey: String) -> LayoutProfile? {
        guard let id = assignments()[deviceKey] else { return nil }
        return all().first { $0.id == id }
    }

    public func assign(_ profile: LayoutProfile?, to deviceKey: String) {
        var assignments = self.assignments()
        assignments[deviceKey] = profile?.id
        writeAssignments(assignments)
    }

    private func writeAssignments(_ assignments: [String: UUID]) {
        lock.lock(); defer { lock.unlock() }
        if let data = try? encoder.encode(assignments) { try? data.write(to: assignmentsURL, options: .atomic) }
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
