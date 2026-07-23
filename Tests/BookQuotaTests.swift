import GRDB
import ReadiumShared
import XCTest
@testable import PagePilot

final class BookQuotaTests: XCTestCase {
    private var db: PagePilot.Database!
    private var repo: BookRepository!
    private var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PagePilotTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        db = try Database(file: tmpDir.appendingPathComponent("test.db"))
        repo = BookRepository(db: db)
    }

    override func tearDown() async throws {
        db = nil
        repo = nil
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func makeBook(title: String = "Book") -> Book {
        Book(
            identifier: UUID().uuidString,
            title: title,
            type: "application/epub+zip",
            url: AnyURL(string: "/\(title).epub")!
        )
    }

    func testAddIfWithinLimitRejectsOverLimit() async throws {
        let limit = 3
        for _ in 0..<limit {
            _ = try await repo.addIfWithinLimit(makeBook(), limit: limit, hasProAccess: false)
        }
        let count = try await repo.count()
        XCTAssertEqual(count, limit)

        do {
            _ = try await repo.addIfWithinLimit(makeBook(), limit: limit, hasProAccess: false)
            XCTFail("Should have thrown bookLimitReached")
        } catch LibraryError.bookLimitReached {
            // expected
        }
        let afterCount = try await repo.count()
        XCTAssertEqual(afterCount, limit)
    }

    func testAddIfWithinLimitBypassesForPro() async throws {
        let limit = 1
        _ = try await repo.addIfWithinLimit(makeBook(title: "First"), limit: limit, hasProAccess: false)
        _ = try await repo.addIfWithinLimit(makeBook(title: "Second"), limit: limit, hasProAccess: true)
        let count = try await repo.count()
        XCTAssertEqual(count, 2)
    }

    /// Simulates the TOCTOU race: two concurrent addIfWithinLimit calls when
    /// only one slot remains. The DatabaseQueue serializes writes, so the
    /// second call sees the first insert and must be rejected.
    func testConcurrentAddsDoNotExceedLimit() async throws {
        let limit = 10
        // Pre-fill to limit - 1.
        for i in 0..<9 {
            _ = try await repo.addIfWithinLimit(makeBook(title: "Book\(i)"), limit: limit, hasProAccess: false)
        }
        let countBefore = try await repo.count()
        XCTAssertEqual(countBefore, 9)

        // Two concurrent inserts competing for the last slot.
        async let first = try? repo.addIfWithinLimit(makeBook(title: "A"), limit: limit, hasProAccess: false)
        async let second = try? repo.addIfWithinLimit(makeBook(title: "B"), limit: limit, hasProAccess: false)
        let (r1, r2) = try await (first, second)

        let countAfter = try await repo.count()
        XCTAssertEqual(countAfter, limit, "Concurrent inserts must not breach the limit")
        XCTAssertFalse(r1 == nil && r2 == nil, "At least one insert should succeed")
        XCTAssertFalse(r1 != nil && r2 != nil, "Only one insert should succeed")
    }

    /// 10 concurrent inserts starting from empty, limit 10: result must be
    /// exactly 10, not more.
    func testTenConcurrentFromEmptyExactlyReachesLimit() async throws {
        let limit = 10
        var tasks: [Task<Void, Never>] = []
        for i in 0..<limit {
            let task = Task { [repo] in
                _ = try? await repo?.addIfWithinLimit(self.makeBook(title: "B\(i)"), limit: limit, hasProAccess: false)
            }
            tasks.append(task)
        }
        for task in tasks { await task.value }
        let count = try await repo.count()
        XCTAssertEqual(count, limit, "Exactly \(limit) books should be inserted, no more")
    }
}
