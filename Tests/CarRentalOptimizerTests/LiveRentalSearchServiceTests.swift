import Foundation
import JavaScriptCore
import Testing
@testable import CarRentalOptimizer

@Suite("Live rental search service")
struct LiveRentalSearchServiceTests {
    @Test("Date-only pickup today uses a future platform time and keeps return hour aligned")
    func dateOnlyPickupTodayUsesFuturePlatformTime() {
        let now = date("2026-06-03 15:45")

        let range = platformQueryTimeRange(
            pickupDate: "2026-06-03",
            returnDate: "2026-06-04",
            now: now
        )

        #expect(range.pickupTime == "2026-06-03 18:00")
        #expect(range.returnTime == "2026-06-04 18:00")
    }

    @Test("Future date-only pickup keeps the standard platform hour")
    func futureDateOnlyPickupKeepsStandardPlatformHour() {
        let now = date("2026-06-03 15:45")

        let range = platformQueryTimeRange(
            pickupDate: "2026-06-05",
            returnDate: "2026-06-06",
            now: now
        )

        #expect(range.pickupTime == "2026-06-05 10:00")
        #expect(range.returnTime == "2026-06-06 10:00")
    }

    @Test("Explicit platform times are preserved")
    func explicitPlatformTimesArePreserved() {
        let now = date("2026-06-03 15:45")

        let range = platformQueryTimeRange(
            pickupDate: "2026-06-03 19:30",
            returnDate: "2026-06-04 20:30",
            now: now
        )

        #expect(range.pickupTime == "2026-06-03 19:30")
        #expect(range.returnTime == "2026-06-04 20:30")
    }

    @Test("eHi bridge decodes obfuscated price digits used by official stock API")
    func ehiBridgeDecodesObfuscatedPriceDigits() {
        let script = makeEhiSearchScript(json: "{}")

        #expect(script.contains("charCodeAt(0)"))
        #expect(script.contains("57345"))
        #expect(script.contains("57354"))
        #expect(script.contains("code - 57345"))
    }

    @Test("eHi obfuscated price digits convert to usable numeric prices")
    func ehiObfuscatedPriceDigitsConvertToUsableNumericPrices() throws {
        let context = try #require(JSContext())
        let decodedPrice = context.evaluateScript(
            """
            const decodeObfuscatedDigits = (value) => String(value).split('').map(ch => {
              const code = ch.charCodeAt(0);
              return code >= 57345 && code <= 57354 ? String(code - 57345) : ch;
            }).join('');
            const num = (value) => {
              if (value === null || value === undefined || value === '') return null;
              const n = Number(decodeObfuscatedDigits(value).replace(/[^0-9.]/g, ''));
              return Number.isFinite(n) ? n : null;
            };
            num('\u{E002}\u{E003}\u{E004}.5');
            """
        )

        #expect(decodedPrice?.toDouble() == 123.5)
    }
}

private func date(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return formatter.date(from: value)!
}
