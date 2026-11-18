import Foundation
import JavaScriptCore
import Testing
@testable import CarRentalOptimizer

@Suite("eHi bounded query execution") @MainActor
struct EhiQueryBudgetTests {
    @Test func theCompleteBridgeScriptRemainsValidJavaScript() throws {
        let context = try #require(JSContext())
        context.evaluateScript("(async function() {" + makeEhiSearchScript(json: "{}") + "})")
        #expect(context.exception == nil)
    }

    @Test func aSlowRequestDoesNotDiscardCompletedQuotes() async throws {
        let runner = try QueryJavaScriptRunner()
        let value = await runner.run("""
        const request = { queryBudgetMilliseconds: 40 };
        const apiTimeoutMs = 6000;
        \(makeEhiQueryBudgetScript())
        const retained = [];
        await withEhiQueryBudget(async () => {
          const queue = createEhiQueryQueue(2);
          queue.add(async () => { retained.push(await withAPITimeout(() => Promise.resolve('ready'), 'fast')); });
          queue.add(async () => { await withAPITimeout(() => new Promise(() => {}), 'slow'); });
          await queue.run();
        });
        return { retained, expired: queryBudgetExpired };
        """)
        #expect(value.contains("ready"))
        #expect(value.contains("\"expired\":true"))
    }

    @Test func completedCityImmediatelyQueuesNearestQuotesBeforeOtherCities() async throws {
        let runner = try QueryJavaScriptRunner()
        let value = await runner.run("""
        const request = { queryBudgetMilliseconds: 500 };
        const apiTimeoutMs = 6000;
        \(makeEhiQueryBudgetScript())
        const order = [];
        const queue = createEhiQueryQueue(1);
        queue.add(async () => {
          order.push('current-city');
          queue.addAll([async () => order.push('nearest'), async () => order.push('next-store')], true);
        });
        queue.add(async () => order.push('other-city'));
        await withEhiQueryBudget(() => queue.run());
        return order;
        """)
        #expect(value == #"["current-city","nearest","next-store","other-city"]"#)
    }

    @Test func fullBridgeDoesNotRequestCitiesWithoutCoordinates() async throws {
        let runner = try QueryJavaScriptRunner()
        let payload = #"{"origin":{"lat":39.78,"lng":116.56},"originLabel":"北京","originCityCandidates":["北京"],"pickupTime":"2027-01-15 10:00","returnTime":"2027-02-14 10:00","rentalDays":30,"vehicleQuery":"零跑C16","radiusKm":100,"queryBudgetMilliseconds":500}"#
        let value = await runner.run("""
        const cityRequests = [];
        const http = {
          getEncrypt: async (path, parameters) => {
            if (path === '/Address/City/List') return {data:[{id:1,name:'北京'},{id:2,name:'远处无坐标城市'}]};
            cityRequests.push(parameters.cityId);
            return {data:[{id:101,name:'本地门店',latitude:39.78,longitude:116.56,address:'北京'}]};
          },
          postEncrypt: async (path) => path === '/Verify/Step1'
            ? {data:{isSuccess:true}}
            : {data:{bookingAvailableCarTypes:[{carType:{id:8,name:'零跑C16',maxPassenger:6},baseAvgAmount:100}]}}
        };
        const window = {webpackChunkbooking:{push: value => value[2](id => ({A: id === 4211 ? http : {getGD:()=>1}}))}};
        const response = JSON.parse(await (async function(){
          \(makeEhiSearchScript(json: payload))
        })());
        return {cityRequests, count:response.listings.length, status:response.statusKind};
        """)
        #expect(value.contains("\"cityRequests\":[1]"))
        #expect(value.contains("\"count\":1"))
        #expect(value.contains("\"status\":\"ready\""))
    }

    @Test func exhaustedBudgetDoesNotStartAnotherAPIRequest() async throws {
        let runner = try QueryJavaScriptRunner()
        let value = await runner.run("""
        const request = { queryBudgetMilliseconds: 1 };
        const apiTimeoutMs = 6000;
        \(makeEhiQueryBudgetScript())
        await new Promise(resolve => setTimeout(resolve, 10));
        let started = false;
        try { await withAPITimeout(() => { started = true; return Promise.resolve(); }, 'late'); } catch (_) {}
        return { started, expired: queryBudgetExpired };
        """)
        #expect(value.contains("\"started\":false"))
        #expect(value.contains("\"expired\":true"))
    }
}

@MainActor private final class QueryJavaScriptRunner {
    private let context: JSContext
    private var timers: [Int: Task<Void, Never>] = [:]
    private var nextID = 0

    init() throws {
        context = try #require(JSContext())
        let set: @convention(block) (JSValue, Double) -> Int = { [weak self] callback, milliseconds in
            guard let self else { return 0 }
            self.nextID += 1
            let id = self.nextID
            self.timers[id] = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(max(0, milliseconds) * 1_000_000)) } catch { return }
                guard !Task.isCancelled else { return }
                callback.call(withArguments: [])
                self?.timers[id] = nil
            }
            return id
        }
        let clear: @convention(block) (Int) -> Void = { [weak self] id in self?.timers.removeValue(forKey: id)?.cancel() }
        context.setObject(set, forKeyedSubscript: "setTimeout" as NSString)
        context.setObject(clear, forKeyedSubscript: "clearTimeout" as NSString)
    }

    func run(_ script: String) async -> String {
        let result: String = await withCheckedContinuation { continuation in
            var done = false
            let finish: @convention(block) (String) -> Void = { value in
                guard !done else { return }; done = true; continuation.resume(returning: value)
            }
            context.setObject(finish, forKeyedSubscript: "finishTest" as NSString)
            timers[0] = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                finish("ERROR: JavaScript test did not finish")
            }
            context.evaluateScript("(async function(){" + script + "})().then(value => finishTest(JSON.stringify(value)), error => finishTest('ERROR: ' + error));")
            if let error = context.exception { finish("ERROR: " + error.toString()) }
        }
        for timer in timers.values { timer.cancel() }
        timers.removeAll()
        context.setObject(nil, forKeyedSubscript: "finishTest" as NSString)
        return result
    }
}
