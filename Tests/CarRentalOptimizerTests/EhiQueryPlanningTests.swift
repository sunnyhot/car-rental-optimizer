import JavaScriptCore
import Testing
@testable import CarRentalOptimizer

@Suite("eHi query planning")
struct EhiQueryPlanningTests {
    @Test func unknownCitiesAreNotTreatedAsZeroKilometersAway() throws {
        let context = try #require(JSContext())
        context.evaluateScript("const cityId = c => c.id; const cityName = c => c.name;")
        context.evaluateScript(makeEhiCityPlanningScript())
        let value = context.evaluateScript("""
        planEhiCityEntries([
          {city:{id:1,name:'北京'},distanceKm:null},
          {city:{id:2,name:'附近城市'},distanceKm:50},
          {city:{id:3,name:'远处城市'},distanceKm:300},
          {city:{id:4,name:'没有坐标城市'},distanceKm:null}
        ], '1', 100).map(e => e.city.id).join(',')
        """)?.toString()
        #expect(value == "1,2")
    }

    @Test func currentCityIsRetainedAndKnownCitiesRespectTheRadius() throws {
        let context = try #require(JSContext())
        context.evaluateScript("const cityId = c => c.id; const cityName = c => c.name;")
        context.evaluateScript(makeEhiCityPlanningScript())
        let value = context.evaluateScript("""
        planEhiCityEntries([
          {city:{id:1,name:'当前城市'},distanceKm:null},
          {city:{id:2,name:'边界城市'},distanceKm:100},
          {city:{id:3,name:'范围外'},distanceKm:100.1}
        ], '1', 100).map(e => e.city.id).join(',')
        """)?.toString()
        #expect(value == "1,2")
    }
}
