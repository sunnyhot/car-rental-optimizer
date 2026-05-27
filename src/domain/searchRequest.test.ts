import { describe, expect, it } from "vitest";
import { mergeSearchFormValues } from "./searchRequest";
import type { SearchRequest } from "./types";

const current: SearchRequest = {
  origin: { lat: 39.9169, lng: 116.6462 },
  originLabel: "北京通州",
  pickupAt: "2026-06-05T09:00",
  returnAt: "2026-06-07T18:00",
  returnMode: "same-store",
  radiusKm: 100,
  vehicleQuery: "瑞虎8",
  platforms: ["ehi", "car-inc"]
};

describe("mergeSearchFormValues", () => {
  it("uses current visible form values over stale React state", () => {
    const merged = mergeSearchFormValues(current, {
      originLabel: "北京通州",
      pickupAt: "2026-09-11T09:00",
      returnAt: "2026-10-11T18:00",
      radiusKm: "500",
      returnMode: "different-store",
      vehicleQuery: "瑞虎8"
    });

    expect(merged.pickupAt).toBe("2026-09-11T09:00");
    expect(merged.returnAt).toBe("2026-10-11T18:00");
    expect(merged.radiusKm).toBe(500);
    expect(merged.returnMode).toBe("different-store");
    expect(merged.platforms).toEqual(["ehi", "car-inc"]);
  });
});
