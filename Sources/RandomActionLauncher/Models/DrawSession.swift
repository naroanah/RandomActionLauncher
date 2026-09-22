import Foundation

struct DrawSession: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let startedAt: Date
    var rerollCount: Int
    var didClickOpen: Bool
    var openedProjectId: UUID?
    var openedAt: Date?
    var timeToOpenMs: Int?
    var endedAt: Date?

    init(
        startedAt: Date,
        id: UUID = UUID()
    ) {
        self.id = id
        self.startedAt = startedAt
        self.rerollCount = 0
        self.didClickOpen = false
        self.openedProjectId = nil
        self.openedAt = nil
        self.timeToOpenMs = nil
        self.endedAt = nil
    }
}
