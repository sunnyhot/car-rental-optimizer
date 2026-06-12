import CarRentalDomain
import Testing
@testable import CarRentalOptimizer

@Suite("Monitor presentation")
struct MonitorPresentationTests {
    @Test("Monitoring frequency labels are concise")
    func monitoringFrequencyLabelsAreConcise() {
        #expect(MonitoringFrequency.smart.label == "智能频率")
        #expect(MonitoringFrequency.fixed30Minutes.label == "每 30 分钟")
        #expect(MonitoringFrequency.fixed1Hour.label == "每 1 小时")
        #expect(MonitoringFrequency.fixed3Hours.label == "每 3 小时")
        #expect(MonitoringFrequency.fixed1Day.label == "每天")
    }

    @Test("Monitor status labels use workbench copy")
    func monitorStatusLabelsUseWorkbenchCopy() {
        #expect(PriceMonitorStatus.active.label == "监控中")
        #expect(PriceMonitorStatus.paused.label == "已暂停")
        #expect(PriceMonitorStatus.checking.label == "巡查中")
        #expect(PriceMonitorStatus.needsAttention.label == "需处理")
        #expect(PriceMonitorStatus.expired.label == "已过期")
    }

    @Test("Signed money formatter shows plus minus and empty values")
    func signedMoneyFormatterShowsPlusMinusAndEmptyValues() {
        #expect(formatSignedMoney(12) == "+¥12")
        #expect(formatSignedMoney(-8) == "¥-8")
        #expect(formatSignedMoney(nil) == "--")
    }
}
