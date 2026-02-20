import XCTest
@testable import PiSession

final class SessionRepositoryTests: XCTestCase {
    var db: SessionDatabase!
    var repo: SessionRepository!

    override func setUpWithError() throws {
        db = try SessionDatabase(path: nil) // in-memory
        repo = SessionRepository(database: db)
    }

    override func tearDown() {
        repo = nil
        db = nil
    }

    // MARK: - Helpers

    private func makeSession(
        id: String = UUID().uuidString,
        title: String = "Test Session",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> Session {
        Session(
            id: id,
            title: title,
            modelProvider: "openai",
            modelId: "gpt-4",
            systemPrompt: "",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func makeEntry(
        id: String = UUID().uuidString,
        sessionId: String,
        parentId: String? = nil,
        role: String = "user",
        content: String = "Hello",
        createdAt: Date = Date()
    ) -> Entry {
        Entry(
            id: id,
            sessionId: sessionId,
            parentId: parentId,
            role: role,
            content: content,
            createdAt: createdAt
        )
    }

    // MARK: - Session CRUD

    func testCreateAndGetSession() throws {
        let session = makeSession(id: "s1", title: "My Session")
        try repo.createSession(session)

        let fetched = try repo.getSession(id: "s1")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "My Session")
        XCTAssertEqual(fetched?.modelProvider, "openai")
    }

    func testGetNonexistentSessionReturnsNil() throws {
        let fetched = try repo.getSession(id: "nonexistent")
        XCTAssertNil(fetched)
    }

    func testListSessionsOrderedByUpdatedAt() throws {
        let earlier = Date(timeIntervalSince1970: 1000)
        let later = Date(timeIntervalSince1970: 2000)

        let s1 = makeSession(id: "s1", title: "Old", updatedAt: earlier)
        let s2 = makeSession(id: "s2", title: "New", updatedAt: later)

        try repo.createSession(s1)
        try repo.createSession(s2)

        let sessions = try repo.listSessions()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first?.title, "New")
        XCTAssertEqual(sessions.last?.title, "Old")
    }

    func testDeleteSession() throws {
        let session = makeSession(id: "s1")
        try repo.createSession(session)
        try repo.deleteSession(id: "s1")

        let fetched = try repo.getSession(id: "s1")
        XCTAssertNil(fetched)
    }

    // MARK: - Entry CRUD

    func testAddAndGetEntry() throws {
        let session = makeSession(id: "s1")
        try repo.createSession(session)

        let entry = makeEntry(id: "e1", sessionId: "s1", content: "Hello world")
        try repo.addEntry(entry)

        let fetched = try repo.getEntry(id: "e1")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.content, "Hello world")
        XCTAssertEqual(fetched?.sessionId, "s1")
    }

    func testAddEntryUpdatesSessionTimestamp() throws {
        let session = makeSession(id: "s1", updatedAt: Date(timeIntervalSince1970: 1000))
        try repo.createSession(session)

        let entry = makeEntry(sessionId: "s1", createdAt: Date(timeIntervalSince1970: 5000))
        try repo.addEntry(entry)

        let updated = try repo.getSession(id: "s1")
        XCTAssertNotNil(updated)
        // The session's updatedAt should have been updated to the entry's createdAt
        XCTAssertEqual(updated?.updatedAt.timeIntervalSince1970, 5000, accuracy: 1)
    }

    // MARK: - DAG / Branch Operations

    func testGetBranchTraversesDAG() throws {
        let session = makeSession(id: "s1")
        try repo.createSession(session)

        let now = Date()
        let e1 = makeEntry(id: "e1", sessionId: "s1", parentId: nil, content: "Root", createdAt: now)
        let e2 = makeEntry(id: "e2", sessionId: "s1", parentId: "e1", content: "Middle", createdAt: now.addingTimeInterval(1))
        let e3 = makeEntry(id: "e3", sessionId: "s1", parentId: "e2", content: "Leaf", createdAt: now.addingTimeInterval(2))

        try repo.addEntry(e1)
        try repo.addEntry(e2)
        try repo.addEntry(e3)

        let branch = try repo.getBranch(leafId: "e3")
        XCTAssertEqual(branch.count, 3)
        // Should be ordered root -> e2 -> e3 (by created_at ASC)
        XCTAssertEqual(branch[0].id, "e1")
        XCTAssertEqual(branch[1].id, "e2")
        XCTAssertEqual(branch[2].id, "e3")
    }

    func testGetBranchSingleEntry() throws {
        let session = makeSession(id: "s1")
        try repo.createSession(session)

        let e1 = makeEntry(id: "e1", sessionId: "s1", content: "Solo")
        try repo.addEntry(e1)

        let branch = try repo.getBranch(leafId: "e1")
        XCTAssertEqual(branch.count, 1)
        XCTAssertEqual(branch[0].id, "e1")
    }

    func testListBranchesFindsLeafNodes() throws {
        let session = makeSession(id: "s1")
        try repo.createSession(session)

        let now = Date()
        // Tree: root -> (e2, e3)  — two branches
        let root = makeEntry(id: "root", sessionId: "s1", parentId: nil, content: "Root", createdAt: now)
        let e2 = makeEntry(id: "e2", sessionId: "s1", parentId: "root", content: "Branch A", createdAt: now.addingTimeInterval(1))
        let e3 = makeEntry(id: "e3", sessionId: "s1", parentId: "root", content: "Branch B", createdAt: now.addingTimeInterval(2))

        try repo.addEntry(root)
        try repo.addEntry(e2)
        try repo.addEntry(e3)

        let branches = try repo.listBranches(sessionId: "s1")
        XCTAssertEqual(branches.count, 2)

        let leafIds = Set(branches.map(\.leafId))
        XCTAssertTrue(leafIds.contains("e2"))
        XCTAssertTrue(leafIds.contains("e3"))
    }

    func testLatestLeafReturnsMostRecent() throws {
        let session = makeSession(id: "s1")
        try repo.createSession(session)

        let now = Date()
        let e1 = makeEntry(id: "e1", sessionId: "s1", parentId: nil, content: "Root", createdAt: now)
        let e2 = makeEntry(id: "e2", sessionId: "s1", parentId: "e1", content: "Older leaf", createdAt: now.addingTimeInterval(1))
        let e3 = makeEntry(id: "e3", sessionId: "s1", parentId: "e1", content: "Newer leaf", createdAt: now.addingTimeInterval(2))

        try repo.addEntry(e1)
        try repo.addEntry(e2)
        try repo.addEntry(e3)

        let latest = try repo.latestLeaf(sessionId: "s1")
        XCTAssertNotNil(latest)
        XCTAssertEqual(latest?.id, "e3")
    }

    func testLatestLeafEmptySessionReturnsNil() throws {
        let session = makeSession(id: "s1")
        try repo.createSession(session)

        let latest = try repo.latestLeaf(sessionId: "s1")
        XCTAssertNil(latest)
    }

    func testAllEntriesOrdered() throws {
        let session = makeSession(id: "s1")
        try repo.createSession(session)

        let now = Date()
        let e1 = makeEntry(id: "e1", sessionId: "s1", createdAt: now)
        let e2 = makeEntry(id: "e2", sessionId: "s1", createdAt: now.addingTimeInterval(1))
        let e3 = makeEntry(id: "e3", sessionId: "s1", createdAt: now.addingTimeInterval(2))

        try repo.addEntry(e1)
        try repo.addEntry(e2)
        try repo.addEntry(e3)

        let all = try repo.allEntries(sessionId: "s1")
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[0].id, "e1")
        XCTAssertEqual(all[1].id, "e2")
        XCTAssertEqual(all[2].id, "e3")
    }

    func testDeleteSessionCascadesEntries() throws {
        let session = makeSession(id: "s1")
        try repo.createSession(session)

        let entry = makeEntry(id: "e1", sessionId: "s1")
        try repo.addEntry(entry)

        try repo.deleteSession(id: "s1")

        let fetched = try repo.getEntry(id: "e1")
        XCTAssertNil(fetched)
    }
}
