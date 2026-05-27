import { describe, expect, it } from "vitest";
import { calculateRentalDays, formatSearchCompletionStatus } from "./searchSummary";
import type { SearchRequest } from "./types";

const request: SearchRequest = {
  origin: { lat: 39.9169, lng: 116.6462 },
  originLabel: "北京通州",
  pickupAt: "2026-09-11T09:00",
  returnAt: "2026-10-11T18:00",
  returnMode: "same-store",
  radiusKm: 100,
  vehicleQuery: "瑞虎8",
  platforms: ["ehi", "car-inc"]
};

describe("calculateRentalDays", () => {
  it("rounds rental duration up to full 24-hour days", () => {
    expect(calculateRentalDays(request)).toBe(31);
  });
});

describe("formatSearchCompletionStatus", () => {
  it("shows the searched time range, billable days, and result count", () => {
    expect(formatSearchCompletionStatus(request, 2)).toBe(
      "已按 2026/09/11 09:00 - 2026/10/11 18:00 查询，按 31 天计费，找到 2 个候选方案。"
    );
  });

  it("keeps the searched time range visible when no cars are found", () => {
    expect(formatSearchCompletionStatus(request, 0)).toContain("没有找到候选车辆");
    expect(formatSearchCompletionStatus(request, 0)).toContain("2026/09/11 09:00");
  });
});
