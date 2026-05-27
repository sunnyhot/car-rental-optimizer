import { describe, expect, it } from "vitest";
import { analyzeLivePlatformSnapshot, parseLivePlatformSnapshot } from "./livePageParser";
import type { SearchRequest } from "../domain/types";

const request: SearchRequest = {
  origin: { lat: 39.9169, lng: 116.6462 },
  originLabel: "北京通州",
  pickupAt: "2026-09-11T09:00",
  returnAt: "2026-09-13T18:00",
  returnMode: "same-store",
  radiusKm: 500,
  vehicleQuery: "瑞虎8",
  platforms: ["ehi", "car-inc"]
};

describe("parseLivePlatformSnapshot", () => {
  it("extracts real vehicle price rows from a platform page text snapshot", () => {
    const listings = parseLivePlatformSnapshot(
      {
        platform: "ehi",
        title: "一嗨租车",
        url: "https://booking.1hai.cn/",
        text: [
          "德州东站店",
          "奇瑞 瑞虎8 1.6T 自动",
          "租金 ¥268 / 日",
          "保险 ¥50",
          "北京南站店",
          "哈弗 H6 自动",
          "总价 ￥398"
        ].join("\n")
      },
      request
    );

    expect(listings).toHaveLength(2);
    expect(listings[0]).toMatchObject({
      platform: "ehi",
      store: { name: "德州东站店", city: "德州" },
      vehicleName: "奇瑞 瑞虎8 1.6T 自动",
      basePrice: 268,
      sourceUrl: "https://booking.1hai.cn/"
    });
    expect(listings[1].vehicleName).toBe("哈弗 H6 自动");
  });

  it("returns no listings when the page does not expose prices", () => {
    const listings = parseLivePlatformSnapshot(
      {
        platform: "car-inc",
        title: "神州租车",
        url: "https://www.zuche.com/",
        text: "请登录后查看车辆"
      },
      request
    );

    expect(listings).toEqual([]);
  });

  it("summarizes page diagnostics when no rental listings can be parsed", () => {
    const diagnostics = analyzeLivePlatformSnapshot({
      platform: "ehi",
      title: "一嗨租车",
      url: "https://www.1hai.cn/",
      text: ["北京通州", "瑞虎8", "请选择取车门店", "暂无价格"].join("\n")
    });

    expect(diagnostics).toEqual({
      platform: "ehi",
      title: "一嗨租车",
      url: "https://www.1hai.cn/",
      textLength: 21,
      lineCount: 4,
      priceCandidateCount: 0,
      vehicleCandidateCount: 1,
      storeCandidateCount: 1
    });
  });
});
