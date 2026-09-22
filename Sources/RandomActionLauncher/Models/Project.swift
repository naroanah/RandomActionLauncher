import Foundation

enum ProjectValidationError: LocalizedError, Equatable, Sendable {
    case emptyDisplayName

    var errorDescription: String? {
        switch self {
        case .emptyDisplayName:
            return "项目名称不能为空。"
        }
    }
}

enum ProjectResourceType: String, Codable, CaseIterable, Sendable, Hashable {
    case folder
    case video
    case document
}

enum ProjectStatus: String, Codable, CaseIterable, Sendable, Hashable {
    case active
    case paused
    case completed

    static let managementOrder: [ProjectStatus] = [.active, .paused, .completed]

    var localizedName: String {
        switch self {
        case .active: "进行中"
        case .paused: "暂停"
        case .completed: "已完成"
        }
    }
}

enum ProjectWeight: Int, Codable, CaseIterable, Sendable, Hashable {
    case low = 1
    case medium = 2
    case high = 3

    var numericValue: Int { rawValue }

    var localizedName: String {
        switch self {
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }
}

enum ProjectAvailability: String, Codable, CaseIterable, Sendable, Hashable {
    case available
    case unavailable

    var localizedName: String {
        switch self {
        case .available: "可用"
        case .unavailable: "不可用"
        }
    }
}

struct Project: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    var displayName: String
    var note: String
    var resourceType: ProjectResourceType
    var originalPath: String
    var bookmarkData: Data
    var status: ProjectStatus
    var weight: ProjectWeight
    var createdAt: Date
    var updatedAt: Date
    var lastDrawnAt: Date?
    var cooldownUntil: Date?
    var availability: ProjectAvailability

    init(
        displayName: String,
        note: String = "",
        resourceType: ProjectResourceType,
        originalPath: String,
        bookmarkData: Data = Data(),
        status: ProjectStatus = .active,
        weight: ProjectWeight = .medium,
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        lastDrawnAt: Date? = nil,
        cooldownUntil: Date? = nil,
        availability: ProjectAvailability = .available,
        id: UUID = UUID()
    ) throws {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw ProjectValidationError.emptyDisplayName
        }

        self.id = id
        self.displayName = normalizedName
        self.note = note
        self.resourceType = resourceType
        self.originalPath = originalPath
        self.bookmarkData = bookmarkData
        self.status = status
        self.weight = weight
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.lastDrawnAt = lastDrawnAt
        self.cooldownUntil = cooldownUntil
        self.availability = availability
    }

    func validate() throws {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectValidationError.emptyDisplayName
        }
    }

    mutating func normalizeDisplayName() throws {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw ProjectValidationError.emptyDisplayName
        }
        displayName = normalizedName
    }
}
