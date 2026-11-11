import XCTest
@testable import Training

/// The Swift sanitizers must give exactly what app.js's cleanBackup gives.
/// Fixtures/messy-backup.cleaned-by-app-js.json was made by running app.js's own clean* functions (node) on messy-backup.json.
final class SanitizeTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: SanitizeTests.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testMessyBackupMatchesWebApp() throws {
        let mine = try XCTUnwrap(Clean.backup(try fixture("messy-backup")))
        let web = try JSONDecoder().decode(AppData.self, from: try fixture("messy-backup.cleaned-by-app-js"))
        XCTAssertEqual(mine.exercises, web.exercises)
        XCTAssertEqual(mine.sets, web.sets)
        XCTAssertEqual(mine.days, web.days)
        XCTAssertEqual(mine.workouts, web.workouts)
        XCTAssertEqual(mine.plans, web.plans)
        XCTAssertEqual(mine.activePlan, web.activePlan)
        XCTAssertEqual(mine.settings, web.settings)
    }

    func testNotABackup() {
        XCTAssertNil(Clean.backup(Data("hello".utf8)))
        XCTAssertNil(Clean.backup(Data(#"{"exercises":[]}"#.utf8)))
        XCTAssertNotNil(Clean.backup(Data(#"{"exercises":[],"sets":[]}"#.utf8)))
    }

    func testYouTubeLinks() {
        XCTAssertEqual(ytId("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), "dQw4w9WgXcQ")
        XCTAssertEqual(ytId("https://youtube.com/shorts/dQw4w9WgXcQ?x=1"), "dQw4w9WgXcQ")
        XCTAssertNil(ytId("https://example.com/video"))
    }

    func testExportedBackupLoadsAgain() throws {
        // What this app exports goes through the same import path (and the web app's) unchanged
        let s = Store(data: SampleData.make(today: "2026-11-11"), persist: false)
        let url = try XCTUnwrap(s.exportBackupFile())
        let back = try XCTUnwrap(Clean.backup(try Data(contentsOf: url)))
        XCTAssertEqual(back.sets, s.data.sets)
        XCTAssertEqual(back.exercises, s.data.exercises)
        XCTAssertEqual(back.days, s.data.days)
        XCTAssertEqual(back.workouts, s.data.workouts)
    }
}
