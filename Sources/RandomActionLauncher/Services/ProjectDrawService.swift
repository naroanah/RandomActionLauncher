import Foundation

@MainActor
protocol ProjectClock: AnyObject {
    var now: Date { get }
}

@MainActor
final class SystemProjectClock: ProjectClock {
    var now: Date { .now }
}

@MainActor
protocol ProjectTicketSource: AnyObject {
    func nextTicket(in range: Range<Int>) -> Int
}

@MainActor
final class SystemProjectTicketSource: ProjectTicketSource {
    func nextTicket(in range: Range<Int>) -> Int {
        Int.random(in: range)
    }
}

/// 只做抽取前的实时可访问性检查，不更新路径或持久化 availability；这些行为属于 S6。
@MainActor
protocol ProjectResourceChecking: AnyObject {
    func isResourceAvailable(for project: Project) -> Bool
}

@MainActor
final class LiveProjectResourceChecker: ProjectResourceChecking {
    private let bookmarks: any BookmarkHandling

    init(bookmarks: any BookmarkHandling = SecurityBookmarkService()) {
        self.bookmarks = bookmarks
    }

    func isResourceAvailable(for project: Project) -> Bool {
        guard let resolved = bookmarks.resolveBookmark(project.bookmarkData) else {
            return false
        }

        let url = resolved.url
        let didBeginAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didBeginAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isReadableKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return false
        }
        guard values.isReadable == true else {
            return false
        }
        return values.isDirectory == true || values.isRegularFile == true
    }
}

enum ProjectDrawError: LocalizedError, Equatable {
    case loadFailed(reason: String)
    case saveFailed(reason: String)
    case invalidTicket(value: Int, totalWeight: Int)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let reason):
            return "读取抽取项目失败：\(reason)"
        case .saveFailed(let reason):
            return "保存抽取结果失败：\(reason)"
        case .invalidTicket(let value, let totalWeight):
            return "随机票号无效：\(value)，总权重为 \(totalWeight)。"
        }
    }
}

enum ProjectDrawResult: Equatable {
    case selected(Project)
    case noEligibleProjects
    case operationInProgress
}

/// S4 抽取领域服务：读取最新项目、过滤候选、按权重选择并提交冷却时间。
/// 该服务不展示 UI、不更新资源路径、不保存会话记录。
@MainActor
final class ProjectDrawService {
    static let cooldownDuration: TimeInterval = 86_400

    private let store: any ProjectManaging
    private let clock: any ProjectClock
    private let ticketSource: any ProjectTicketSource
    private let resourceChecker: any ProjectResourceChecking
    private var isOperationInProgress = false

    init(
        store: any ProjectManaging,
        clock: any ProjectClock = SystemProjectClock(),
        ticketSource: any ProjectTicketSource = SystemProjectTicketSource(),
        resourceChecker: any ProjectResourceChecking = LiveProjectResourceChecker()
    ) {
        self.store = store
        self.clock = clock
        self.ticketSource = ticketSource
        self.resourceChecker = resourceChecker
    }

    func draw() throws -> ProjectDrawResult {
        guard !isOperationInProgress else {
            return .operationInProgress
        }

        isOperationInProgress = true
        defer {
            isOperationInProgress = false
        }

        let now = clock.now
        let projects: [Project]
        do {
            projects = try store.fetchAll()
        } catch {
            throw ProjectDrawError.loadFailed(reason: error.localizedDescription)
        }

        let candidates = projects
            .filter { project in
                guard project.status == .active else { return false }
                guard project.cooldownUntil.map({ now >= $0 }) ?? true else {
                    return false
                }
                return resourceChecker.isResourceAvailable(for: project)
            }
            .sorted { lhs, rhs in
                lhs.id.uuidString < rhs.id.uuidString
            }

        guard !candidates.isEmpty else {
            return .noEligibleProjects
        }

        let totalWeight = candidates.reduce(0) { partialResult, project in
            partialResult + project.weight.numericValue
        }
        let ticketRange = 0..<totalWeight
        let ticket = ticketSource.nextTicket(in: ticketRange)
        guard ticketRange.contains(ticket) else {
            throw ProjectDrawError.invalidTicket(value: ticket, totalWeight: totalWeight)
        }

        guard let selected = selectCandidate(from: candidates, ticket: ticket) else {
            throw ProjectDrawError.invalidTicket(value: ticket, totalWeight: totalWeight)
        }

        do {
            let updated = try store.update(id: selected.id) { project in
                project.lastDrawnAt = now
                project.cooldownUntil = now.addingTimeInterval(Self.cooldownDuration)
            }
            return .selected(updated)
        } catch {
            throw ProjectDrawError.saveFailed(reason: error.localizedDescription)
        }
    }

    private func selectCandidate(from candidates: [Project], ticket: Int) -> Project? {
        var remaining = ticket
        for candidate in candidates {
            remaining -= candidate.weight.numericValue
            if remaining < 0 {
                return candidate
            }
        }
        return nil
    }
}
