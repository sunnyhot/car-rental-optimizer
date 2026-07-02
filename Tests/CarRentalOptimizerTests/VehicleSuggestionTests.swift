import Foundation
import Testing
@testable import CarRentalOptimizer

@Suite("Vehicle suggestions")
struct VehicleSuggestionTests {
    @Test("Suggestions match Chinese text and aliases")
    func suggestionsMatchChineseTextAndAliases() {
        let store = VehicleSuggestionStore(
            learned: [
                VehicleSuggestion(name: "尚界 H5", source: .learned, aliases: ["shangjie", "h5"], lastUsedAt: nil, learnedAt: date("2026-07-02 10:00"), count: 2),
                VehicleSuggestion(name: "奇瑞瑞虎8", source: .learned, aliases: ["ruihu8", "tiggo8"], lastUsedAt: nil, learnedAt: date("2026-07-02 10:01"), count: 1)
            ],
            recent: [],
            builtIns: VehicleSuggestionStore.defaultBuiltIns,
            fileURL: temporaryURL()
        )

        #expect(store.suggestions(matching: "h5").map(\.name).contains("尚界 H5"))
        #expect(store.suggestions(matching: "瑞虎").map(\.name).contains("奇瑞瑞虎8"))
        #expect(store.suggestions(matching: "ruihu").map(\.name).contains("奇瑞瑞虎8"))
        #expect(store.suggestions(matching: "suv").contains { $0.name == "SUV" })
    }

    @Test("Recent learned and built in suggestions dedupe by source priority")
    func recentLearnedAndBuiltInSuggestionsDedupeBySourcePriority() {
        let store = VehicleSuggestionStore(
            learned: [
                VehicleSuggestion(name: "尚界 H5", source: .learned, aliases: ["h5"], lastUsedAt: nil, learnedAt: date("2026-07-02 09:00"), count: 5),
                VehicleSuggestion(name: "大众朗逸", source: .learned, aliases: ["lavida"], lastUsedAt: nil, learnedAt: date("2026-07-02 09:10"), count: 2)
            ],
            recent: [
                VehicleSuggestion(name: "尚界 H5", source: .recent, aliases: ["h5"], lastUsedAt: date("2026-07-02 11:00"), learnedAt: nil, count: 1)
            ],
            builtIns: [
                VehicleSuggestion(name: "尚界 H5", source: .builtIn, aliases: ["h5"], lastUsedAt: nil, learnedAt: nil, count: 0),
                VehicleSuggestion(name: "SUV", source: .builtIn, aliases: ["suv"], lastUsedAt: nil, learnedAt: nil, count: 0)
            ],
            fileURL: temporaryURL()
        )

        let suggestions = store.suggestions(matching: "", limit: 6)

        #expect(suggestions.map(\.name) == ["尚界 H5", "大众朗逸", "SUV"])
        #expect(suggestions.first?.source == .recent)
        #expect(suggestions.first?.sourceLabel == "最近使用")
    }

    @Test("Recording search results ignores placeholders and caps learned history")
    func recordingSearchResultsIgnoresPlaceholdersAndCapsLearnedHistory() {
        let store = VehicleSuggestionStore(
            learned: [],
            recent: [],
            builtIns: [],
            fileURL: temporaryURL()
        )
        let names = (0..<120).map { "测试车型\($0)" } + ["未指定车型", "   "]

        store.recordSearchResults(names, now: date("2026-07-02 12:00"))

        #expect(store.learnedSuggestions.count == 100)
        #expect(!store.learnedSuggestions.contains { $0.name == "未指定车型" })
        #expect(!store.learnedSuggestions.contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    @Test("Recording search result variants collapses platform qualifiers into one model")
    func recordingSearchResultVariantsCollapsesPlatformQualifiersIntoOneModel() {
        let store = VehicleSuggestionStore(
            learned: [],
            recent: [],
            builtIns: [],
            fileURL: temporaryURL()
        )

        store.recordSearchResults(["比亚迪宋 Pro 新能源", "比亚迪宋 Pro 京牌"], now: date("2026-07-02 12:00"))

        let suggestions = store.suggestions(matching: "比亚迪宋 pro")

        #expect(store.learnedSuggestions.count == 1)
        #expect(store.learnedSuggestions.first?.name == "比亚迪宋 Pro")
        #expect(store.learnedSuggestions.first?.count == 2)
        #expect(suggestions.map(\.name) == ["比亚迪宋 Pro"])
    }

    @Test("Recording selection promotes item to recent and caps recent history")
    func recordingSelectionPromotesItemToRecentAndCapsRecentHistory() {
        let store = VehicleSuggestionStore(
            learned: [],
            recent: [],
            builtIns: [],
            fileURL: temporaryURL()
        )

        for index in 0..<25 {
            let suggestion = VehicleSuggestion(name: "最近车型\(index)", source: .learned, aliases: [], lastUsedAt: nil, learnedAt: nil, count: 0)
            store.recordSelection(suggestion, now: date("2026-07-02 12:\(String(format: "%02d", index))"))
        }

        #expect(store.recentSuggestions.count == 20)
        #expect(store.recentSuggestions.first?.name == "最近车型24")
        #expect(store.recentSuggestions.last?.name == "最近车型5")
    }
}

private func date(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.date(from: value)!
}

private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("vehicle-suggestions-\(UUID().uuidString).json")
}
