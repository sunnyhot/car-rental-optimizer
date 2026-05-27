import { describe, expect, it } from "vitest";
import { matchVehicle } from "./vehicleMatcher";

describe("matchVehicle", () => {
  it("marks 瑞虎8 listings as exact matches for a 瑞虎8 query", () => {
    const match = matchVehicle("瑞虎8", {
      vehicleName: "奇瑞 瑞虎8 1.6T 自动",
      vehicleClass: "中型SUV"
    });

    expect(match.kind).toBe("exact");
    expect(match.score).toBe(1);
    expect(match.label).toContain("精确");
  });

  it("marks same-class SUV listings as similar when exact model is unavailable", () => {
    const match = matchVehicle("瑞虎8", {
      vehicleName: "哈弗 H6 自动",
      vehicleClass: "紧凑型SUV"
    });

    expect(match.kind).toBe("similar-class");
    expect(match.score).toBeGreaterThan(0.5);
    expect(match.score).toBeLessThan(1);
    expect(match.label).toContain("同级");
  });

  it("uses low confidence when class metadata is missing", () => {
    const match = matchVehicle("瑞虎8", {
      vehicleName: "经济型自动挡",
      vehicleClass: ""
    });

    expect(match.kind).toBe("low-confidence");
    expect(match.score).toBeLessThan(0.5);
    expect(match.label).toContain("低置信");
  });

  it("does not treat an empty vehicle query as an exact match", () => {
    const match = matchVehicle("", {
      vehicleName: "奇瑞 瑞虎8 1.6T 自动",
      vehicleClass: "中型SUV"
    });

    expect(match.kind).toBe("not-specified");
    expect(match.score).toBe(0);
    expect(match.label).toContain("未指定");
  });
});
