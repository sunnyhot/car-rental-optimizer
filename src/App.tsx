import { useMemo, useRef, useState } from "react";
import { formDataToSearchValues, mergeSearchFormValues } from "./domain/searchRequest";
import { formatSearchCompletionStatus } from "./domain/searchSummary";
import type { PlatformId, Recommendation, ReturnMode, SearchRequest } from "./domain/types";
import { createMockMapService } from "./services/mockMapService";
import { createMockRentalAdapters } from "./services/mockRentalAdapters";
import { searchRentalOptions } from "./services/searchOrchestrator";

const DEFAULT_REQUEST: SearchRequest = {
  origin: { lat: 39.9169, lng: 116.6462 },
  originLabel: "北京通州",
  pickupAt: "2026-06-05T09:00",
  returnAt: "2026-06-07T18:00",
  returnMode: "same-store",
  radiusKm: 100,
  vehicleQuery: "瑞虎8",
  platforms: ["ehi", "car-inc"]
};

const PLATFORM_LABELS: Record<PlatformId, string> = {
  ehi: "一嗨",
  "car-inc": "神州"
};

export default function App() {
  const formRef = useRef<HTMLFormElement>(null);
  const [request, setRequest] = useState<SearchRequest>(DEFAULT_REQUEST);
  const [results, setResults] = useState<Recommendation[]>([]);
  const [selectedId, setSelectedId] = useState<string>("");
  const [isSearching, setIsSearching] = useState(false);
  const [status, setStatus] = useState("使用本地模拟适配器，真实平台登录自动化接口已预留。");

  const selected = useMemo(
    () => results.find((result) => result.listing.id === selectedId) ?? results[0],
    [results, selectedId]
  );

  async function runSearch() {
    const formValues = formRef.current ? formDataToSearchValues(new FormData(formRef.current)) : {};
    const searchRequest = mergeSearchFormValues(request, formValues);

    setRequest(searchRequest);
    setIsSearching(true);
    setResults([]);
    setSelectedId("");
    setStatus("正在查询一嗨、神州，并计算打车/公共交通成本...");

    try {
      const [nextResults] = await Promise.all([
        searchRentalOptions(searchRequest, {
          rentalAdapters: createMockRentalAdapters(),
          mapService: createMockMapService()
        }),
        waitForFeedback()
      ]);

      setResults(nextResults);
      setSelectedId(nextResults[0]?.listing.id ?? "");
      setStatus(formatSearchCompletionStatus(searchRequest, nextResults.length));
    } finally {
      setIsSearching(false);
    }
  }

  function updateRequest<T extends keyof SearchRequest>(key: T, value: SearchRequest[T]) {
    setRequest((current) => ({ ...current, [key]: value }));
    if (results.length > 0) {
      setStatus("搜索条件已变更，点击“开始比较”重新计算总成本。");
    }
  }

  function togglePlatform(platform: PlatformId) {
    setRequest((current) => {
      const exists = current.platforms.includes(platform);
      const platforms = exists
        ? current.platforms.filter((item) => item !== platform)
        : [...current.platforms, platform];

      return { ...current, platforms: platforms.length > 0 ? platforms : current.platforms };
    });
  }

  return (
    <main className="app-shell">
      <header className="titlebar">
        <div>
          <p className="eyebrow">Car rental optimizer</p>
          <h1>租车总成本比较</h1>
        </div>
        <div className="automation-status">
          <span className="status-dot" />
          本地登录态自动化架构
        </div>
      </header>

      <section className="workspace" aria-label="租车比价工作区">
        <aside className="search-panel" aria-label="搜索条件">
          <div className="panel-header">
            <h2>搜索条件</h2>
            <span>默认 100km</span>
          </div>

          <form
            className="search-form"
            ref={formRef}
            onSubmit={(event) => {
              event.preventDefault();
              void runSearch();
            }}
          >
          <label className="field">
            <span>当前位置</span>
            <input
              name="originLabel"
              value={request.originLabel}
              onChange={(event) => updateRequest("originLabel", event.target.value)}
            />
          </label>

          <div className="field-grid">
            <label className="field">
              <span>取车时间</span>
              <input
                name="pickupAt"
                type="datetime-local"
                value={request.pickupAt}
                onChange={(event) => updateRequest("pickupAt", event.target.value)}
              />
            </label>
            <label className="field">
              <span>还车时间</span>
              <input
                name="returnAt"
                type="datetime-local"
                value={request.returnAt}
                onChange={(event) => updateRequest("returnAt", event.target.value)}
              />
            </label>
          </div>

          <label className="field">
            <span>车型</span>
            <input
              name="vehicleQuery"
              value={request.vehicleQuery}
              onChange={(event) => updateRequest("vehicleQuery", event.target.value)}
              placeholder="瑞虎8"
            />
          </label>

          <label className="field">
            <span>搜索半径：{request.radiusKm} km</span>
            <input
              name="radiusKm"
              type="range"
              min="10"
              max="500"
              step="10"
              value={request.radiusKm}
              onChange={(event) => updateRequest("radiusKm", Number(event.target.value))}
            />
          </label>

          <label className="field">
            <span>还车方式</span>
            <select
              name="returnMode"
              value={request.returnMode}
              onChange={(event) => updateRequest("returnMode", event.target.value as ReturnMode)}
            >
              <option value="same-store">同店取还</option>
              <option value="different-store">异店/异地还车</option>
            </select>
          </label>

          <div className="toggle-group" aria-label="平台选择">
            {(["ehi", "car-inc"] as PlatformId[]).map((platform) => (
              <button
                className={request.platforms.includes(platform) ? "toggle active" : "toggle"}
                key={platform}
                onClick={() => togglePlatform(platform)}
                type="button"
              >
                {PLATFORM_LABELS[platform]}
              </button>
            ))}
          </div>

          <button className="primary-action" disabled={isSearching} type="submit">
            {isSearching ? "查询中..." : "开始比较"}
          </button>

          <div className="notice">
            <strong>自动化说明</strong>
            <p>真实版会在本地浏览器保存一嗨和神州登录态；遇到验证码或短信时暂停让你处理。</p>
          </div>
          </form>
        </aside>

        <section className="result-panel" aria-label="推荐结果">
          <div className="panel-header">
            <h2>候选方案</h2>
            <span>{status}</span>
          </div>

          {isSearching ? (
            <div className="loading-state" role="status">
              <div className="spinner" />
              <h3>正在重新比较</h3>
              <p>正在按当前日期、半径和平台重新计算租车价、打车成本和公共交通成本。</p>
            </div>
          ) : results.length === 0 ? (
            <div className="empty-state">
              <h3>先跑一次比较</h3>
              <p>保持默认 100km 会看到北京周边方案；把半径拉到 500km，会出现德州东站低价跨城方案。</p>
            </div>
          ) : (
            <div className="result-list">
              {results.map((result, index) => (
                <button
                  className={selected?.listing.id === result.listing.id ? "result-row selected" : "result-row"}
                  key={result.listing.id}
                  onClick={() => setSelectedId(result.listing.id)}
                  type="button"
                >
                  <div className="rank">{index + 1}</div>
                  <div className="result-main">
                    <div className="row-title">
                      <strong>{result.listing.store.name}</strong>
                      <span>{PLATFORM_LABELS[result.listing.platform]}</span>
                    </div>
                    <p>{result.listing.vehicleName} · {result.match.label}</p>
                    <div className="cost-strip">
                      <span>最佳 ¥{result.bestTotal}</span>
                      <span>打车 ¥{result.taxiTotal}</span>
                      <span>公交/高铁 ¥{result.transitTotal}</span>
                    </div>
                  </div>
                </button>
              ))}
            </div>
          )}
        </section>

        <aside className="detail-panel" aria-label="方案明细">
          {selected ? <RecommendationDetail recommendation={selected} /> : <NoSelection />}
        </aside>
      </section>
    </main>
  );
}

function RecommendationDetail({ recommendation }: { recommendation: Recommendation }) {
  const { listing } = recommendation;

  return (
    <>
      <div className="panel-header">
        <h2>推荐明细</h2>
        <span>{recommendation.match.label}</span>
      </div>

      <div className="hero-metric">
        <span>推荐总成本</span>
        <strong>¥{recommendation.bestTotal}</strong>
        <p>
          {recommendation.bestRouteMode === "taxi" ? "按打车到店计算" : "按公共交通到店计算"}
        </p>
      </div>

      <section className="detail-section">
        <h3>{listing.store.name}</h3>
        <p>{listing.store.city} · {listing.store.address}</p>
        <p>{listing.store.hours} · 距离约 {listing.store.distanceKm} km</p>
      </section>

      <section className="detail-section">
        <h3>费用拆分</h3>
        <CostLine label="租车基础价" value={listing.basePrice} />
        <CostLine label="平台服务费" value={listing.platformFees} />
        <CostLine label="保险/保障" value={listing.insuranceFees} />
        <CostLine label="异店还车费" value={listing.oneWayFee} />
        <CostLine label="租车小计" value={recommendation.rentalTotal} strong />
      </section>

      <section className="route-grid">
        <RouteBox title="打车" total={recommendation.taxiTotal} route={recommendation.taxiRoute.summary} />
        <RouteBox title="公共交通" total={recommendation.transitTotal} route={recommendation.transitRoute.summary} />
      </section>

      {recommendation.warnings.length > 0 && (
        <section className="warning-box">
          <h3>提醒</h3>
          <p>{renderWarnings(recommendation.warnings)}</p>
        </section>
      )}

      <a className="source-link" href={listing.sourceUrl} target="_blank" rel="noreferrer">
        打开原始平台
      </a>
    </>
  );
}

function CostLine({ label, value, strong = false }: { label: string; value: number; strong?: boolean }) {
  return (
    <div className={strong ? "cost-line strong" : "cost-line"}>
      <span>{label}</span>
      <strong>¥{value}</strong>
    </div>
  );
}

function RouteBox({ title, total, route }: { title: string; total: number; route: string }) {
  return (
    <div className="route-box">
      <span>{title}</span>
      <strong>¥{total}</strong>
      <p>{route}</p>
    </div>
  );
}

function NoSelection() {
  return (
    <div className="empty-state detail-empty">
      <h3>等待结果</h3>
      <p>点击“开始比较”后，这里会显示最优方案、费用拆分和路线明细。</p>
    </div>
  );
}

function renderWarnings(warnings: string[]) {
  if (warnings.includes("cross-city-pickup")) {
    return "这是跨城取车方案，租车价格低，但需要额外关注高铁班次、门店营业时间和行李不便。";
  }

  return "该方案存在数据完整度提醒，建议打开原始平台复核。";
}

function waitForFeedback() {
  return new Promise((resolve) => window.setTimeout(resolve, 450));
}
