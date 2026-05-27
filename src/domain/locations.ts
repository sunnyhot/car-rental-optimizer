import type { GeoPoint } from "./types";

const KNOWN_ORIGINS: Array<{ keywords: string[]; point: GeoPoint }> = [
  { keywords: ["北京通州", "通州"], point: { lat: 39.9169, lng: 116.6462 } },
  { keywords: ["北京南站"], point: { lat: 39.865, lng: 116.379 } },
  { keywords: ["德州东站", "德州"], point: { lat: 37.443, lng: 116.374 } },
  { keywords: ["天津南站", "天津"], point: { lat: 39.0622, lng: 117.0669 } },
  { keywords: ["济南西站", "济南"], point: { lat: 36.6683, lng: 116.892 } },
  { keywords: ["上海虹桥", "虹桥"], point: { lat: 31.194, lng: 121.318 } }
];

export function resolveKnownOrigin(label: string): GeoPoint | undefined {
  const normalized = label.trim().toLowerCase();

  return KNOWN_ORIGINS.find((origin) =>
    origin.keywords.some((keyword) => normalized.includes(keyword.toLowerCase()))
  )?.point;
}
