import { useEffect, useMemo, useRef, useState } from "react";
import { formDataToSearchValues, mergeSearchFormValues } from "./domain/searchRequest";
import { formatSearchCompletionStatus } from "./domain/searchSummary";
import type { PlatformId, Recommendation, ReturnMode, SearchRequest } from "./domain/types";
import { createMockMapService } from "./services/mockMapService";
import {
  analyzeLivePlatformSnapshot,
  parseLivePlatformSnapshot,
  type LiveSnapshotDiagnostics
} from "./services/livePageParser";
import {
  getPlatformAutomation,
  type PlatformAuthState,
  type PlatformSnapshotResult
} from "./services/platformAutomation";
import { rankRentalListings } from "./services/searchOrchestrator";

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

type SnapshotReadDiagnostic = LiveSnapshotDiagnostics & {
  autoOpened?: boolean;
  message?: string;
};

export default function App() {
  const formRef = useRef<HTMLFormElement>(null);
  const automation = useMemo(() => getPlatformAutomation(), []);
  const [request, setRequest] = useState<SearchRequest>(DEFAULT_REQUEST);
  const [results, setResults] = useState<Recommendation[]>([]);
  const [selectedId, setSelectedId] = useState<string>("");
  const [isSearching, setIsSearching] = useState(false);
  const [authStates, setAuthStates] = useState<PlatformAuthState[]>([]);
  const [snapshotDiagnostics, setSnapshotDiagnostics] = useState<SnapshotReadDiagnostic[]>([]);
  const [status, setStatus] = useState(
    automation
      ? "真实数据模式：点击开始比较会读取已登录平台窗口的当前页面。"
      : "真实数据模式需要在 Electron 桌面 app 中运行；普通浏览器不能读取平台登录态。"
  );

  const selected = useMemo(
    () => results.find((result) => result.listing.id === selectedId) ?? results[0],
    [results, selectedId]
  );

  useEffect(() => {
    void refreshAuthStates();
  }, []);

  async function runSearch() {
    const formValues = formRef.current ? formDataToSearchValues(new FormData(formRef.current)) : {};
    const searchRequest = mergeSearchFormValues(request, formValues);

    setRequest(searchRequest);
    setIsSearching(true);
    setResults([]);
    setSelectedId("");
    setSnapshotDiagnostics([]);
    setStatus("正在打开/读取平台官网当前页面，并计算打车/公共交通成本...");

    try {
      if (!automation) {
        setStatus("请用 `npm run dev` 打开 Electron 桌面窗口；浏览器预览不会读取真实平台登录态。");
        return;
      }

      const [snapshots] = await Promise.all([
        Promise.all(searchRequest.platforms.map((platform) => readPlatformSnapshot(platform))),
        waitForFeedback()
      ]);
      const availableSnapshots = snapshots.flatMap((result) => (result.ok && result.snapshot ? [result.snapshot] : []));
      const messages = snapshots.flatMap((result) => (result.message ? [result.message] : []));
      const diagnostics = snapshots.flatMap((result) =>
        result.ok && result.snapshot
          ? [{ ...analyzeLivePlatformSnapshot(result.snapshot), autoOpened: result.autoOpened, message: result.message }]
          : []
      );
      const liveListings = availableSnapshots.flatMap((snapshot) =>
        parseLivePlatformSnapshot(snapshot, searchRequest)
      );

      setSnapshotDiagnostics(diagnostics);

      if (liveListings.length === 0) {
        setStatus(formatNoLiveListingsStatus(messages, diagnostics));
        return;
      }

      const nextResults = await rankRentalListings(searchRequest, liveListings, createMockMapService());

      setResults(nextResults);
      setSelectedId(nextResults[0]?.listing.id ?? "");
      setStatus(formatSearchCompletionStatus(searchRequest, nextResults.length));
      await refreshAuthStates();
    } finally {
      setIsSearching(false);
    }
  }

  async function readPlatformSnapshot(platform: PlatformId): Promise<PlatformSnapshotResult> {
    if (!automation) {
      return { ok: false, message: "Electron 桌面桥接不可用。" };
    }

    try {
      return await automation.readSnapshot(platform);
    } catch (error) {
      return {
        ok: false,
        message: `${PLATFORM_LABELS[platform]}读取失败：${formatError(error)}`
      };
    }
  }

  async function refreshAuthStates() {
    if (!automation) {
      return;
    }

    setAuthStates(await automation.getAuthStates());
  }

  async function openPlatform(platform: PlatformId) {
    if (!automation) {
      setStatus("请用 Electron 桌面窗口打开平台登录页，普通浏览器预览不可用。");
      return;
    }

    const state = await automation.openPlatform(platform);
    await refreshAuthStates();
    setStatus(`已打开${state.label}官方页面。请登录，并在该窗口里按城市/日期/车型完成搜索。`);
  }

  async function clearPlatform(platform: PlatformId) {
    if (!automation) {
      return;
    }

    await automation.clearPlatform(platform);
    await refreshAuthStates();
    setStatus(`${PLATFORM_LABELS[platform]}登录态已清除。`);
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

          <div className="login-manager">
            <strong>平台登录态</strong>
            {(["ehi", "car-inc"] as PlatformId[]).map((platform) => {
              const authState = authStates.find((state) => state.platform === platform);
              return (
                <div className="login-row" key={platform}>
                  <span>
                    {PLATFORM_LABELS[platform]}
                    <small>{authState?.hasCookies ? `已保存 ${authState.cookieCount} 个 Cookie` : "未检测到 Cookie"}</small>
                  </span>
                  <div>
                    <button type="button" onClick={() => void openPlatform(platform)}>
                      打开/登录
                    </button>
                    <button type="button" onClick={() => void clearPlatform(platform)} disabled={!automation}>
                      清除
                    </button>
                  </div>
                </div>
              );
            })}
          </div>

          <button className="primary-action" disabled={isSearching} type="submit">
            {isSearching ? "查询中..." : "开始比较"}
          </button>

          <div className="notice">
            <strong>真实数据说明</strong>
            <p>这里不再使用 mock 车源。开始比较会自动打开/读取平台官方窗口；若页面还没有价格，会显示读取诊断。</p>
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
              <p>正在读取平台官网当前页面，解析车辆价格，并重新计算交通成本。</p>
            </div>
          ) : results.length === 0 ? (
            <div className="empty-state">
              <h3>等待真实页面数据</h3>
              <p>打开一嗨/神州官方窗口，登录后在平台页面完成搜索，再回到这里点击“开始比较”。</p>
              {snapshotDiagnostics.length > 0 && <SnapshotDiagnostics diagnostics={snapshotDiagnostics} />}
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

function SnapshotDiagnostics({ diagnostics }: { diagnostics: SnapshotReadDiagnostic[] }) {
  return (
    <div className="diagnostic-list" aria-label="页面读取诊断">
      {diagnostics.map((diagnostic) => (
        <div className="diagnostic-card" key={`${diagnostic.platform}-${diagnostic.url}`}>
          <div>
            <strong>{PLATFORM_LABELS[diagnostic.platform]}</strong>
            <span>{diagnostic.autoOpened ? "已自动打开窗口" : "已读取当前窗口"}</span>
          </div>
          <p>{diagnostic.title || "未读取到页面标题"}</p>
          <dl>
            <div>
              <dt>页面文本</dt>
              <dd>{diagnostic.textLength} 字</dd>
            </div>
            <div>
              <dt>价格候选</dt>
              <dd>{diagnostic.priceCandidateCount}</dd>
            </div>
            <div>
              <dt>车型候选</dt>
              <dd>{diagnostic.vehicleCandidateCount}</dd>
            </div>
            <div>
              <dt>门店候选</dt>
              <dd>{diagnostic.storeCandidateCount}</dd>
            </div>
          </dl>
          <small>{shortenUrl(diagnostic.url)}</small>
        </div>
      ))}
    </div>
  );
}

function formatNoLiveListingsStatus(messages: string[], diagnostics: SnapshotReadDiagnostic[]): string {
  if (diagnostics.some((diagnostic) => diagnostic.autoOpened)) {
    return "已自动打开平台官网窗口，但当前页面还没有可解析车价；请在官方窗口完成搜索后再点开始比较。";
  }

  if (diagnostics.length > 0) {
    const summary = diagnostics
      .map(
        (diagnostic) =>
          `${PLATFORM_LABELS[diagnostic.platform]}：价格候选 ${diagnostic.priceCandidateCount}，车型候选 ${diagnostic.vehicleCandidateCount}`
      )
      .join("；");
    return `已读取平台官网，但没有识别到可比价车源。${summary}`;
  }

  return messages.length > 0
    ? messages.join("；")
    : "没有从平台官网当前页面识别到车辆价格。请在平台窗口完成城市、日期、门店/车型搜索后再点开始比较。";
}

function shortenUrl(url: string): string {
  try {
    const parsedUrl = new URL(url);
    return `${parsedUrl.host}${parsedUrl.pathname}`;
  } catch {
    return url;
  }
}

function formatError(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
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
