import { resolveKnownOrigin } from "../domain/locations";
import type { PlatformId, RentalListing, SearchRequest, Store } from "../domain/types";
import { distanceKmBetween } from "../domain/geo";

export interface LivePlatformSnapshot {
  platform: PlatformId;
  title: string;
  url: string;
  text: string;
}

const VEHICLE_HINTS = ["瑞虎", "哈弗", "大众", "丰田", "本田", "日产", "别克", "宝马", "奔驰", "奥迪", "SUV", "自动"];
const STORE_HINTS = ["店", "站", "机场", "门店", "取车点"];
const NON_VEHICLE_PRICE_HINTS = ["保险", "保障", "押金", "服务费", "手续费", "违章", "优惠", "券"];

export function parseLivePlatformSnapshot(
  snapshot: LivePlatformSnapshot,
  request: SearchRequest
): RentalListing[] {
  const lines = snapshot.text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  const listings: RentalListing[] = [];

  lines.forEach((line, index) => {
    if (NON_VEHICLE_PRICE_HINTS.some((hint) => line.includes(hint))) {
      return;
    }

    const price = extractPrice(line);
    if (!price) {
      return;
    }

    const vehicleName = findVehicleName(lines, index);
    if (!vehicleName) {
      return;
    }

    const store = buildStore(snapshot.platform, findStoreName(lines, index), request);

    listings.push({
      id: `${snapshot.platform}-live-${index}-${vehicleName}`,
      platform: snapshot.platform,
      store,
      vehicleName,
      vehicleClass: inferVehicleClass(vehicleName),
      basePrice: price,
      platformFees: 0,
      insuranceFees: 0,
      oneWayFee: 0,
      currency: "CNY",
      sourceUrl: snapshot.url,
      dataCompleteness: 0.72,
      warnings: ["partial-price"]
    });
  });

  return dedupeListings(listings);
}

function extractPrice(line: string): number | undefined {
  const match = line.match(/[¥￥]\s*(\d{2,6})|(\d{2,6})\s*元/);
  const raw = match?.[1] ?? match?.[2];

  return raw ? Number(raw) : undefined;
}

function findVehicleName(lines: string[], priceLineIndex: number): string | undefined {
  const candidates = lines.slice(Math.max(0, priceLineIndex - 4), priceLineIndex + 1).reverse();

  return candidates.find((line) => VEHICLE_HINTS.some((hint) => line.toLowerCase().includes(hint.toLowerCase())));
}

function findStoreName(lines: string[], priceLineIndex: number): string {
  const candidates = lines.slice(Math.max(0, priceLineIndex - 8), priceLineIndex + 1).reverse();
  const storeLine = candidates.find((line) => STORE_HINTS.some((hint) => line.includes(hint)));

  return storeLine ?? "平台当前门店";
}

function buildStore(platform: PlatformId, name: string, request: SearchRequest): Store {
  const location = resolveKnownOrigin(name) ?? request.origin;
  const distanceKm = distanceKmBetween(request.origin, location);

  return {
    id: `${platform}-${name}`,
    platform,
    name,
    city: inferCity(name),
    address: name,
    location,
    distanceKm,
    hours: "以平台页面为准"
  };
}

function inferVehicleClass(vehicleName: string): string {
  return vehicleName.toLowerCase().includes("suv") || vehicleName.includes("瑞虎") || vehicleName.includes("哈弗")
    ? "SUV"
    : "未知车型";
}

function inferCity(storeName: string): string {
  if (storeName.includes("德州")) return "德州";
  if (storeName.includes("北京")) return "北京";
  if (storeName.includes("天津")) return "天津";
  if (storeName.includes("济南")) return "济南";

  return "未知城市";
}

function dedupeListings(listings: RentalListing[]): RentalListing[] {
  const seen = new Set<string>();

  return listings.filter((listing) => {
    const key = `${listing.platform}-${listing.store.name}-${listing.vehicleName}-${listing.basePrice}`;
    if (seen.has(key)) {
      return false;
    }
    seen.add(key);
    return true;
  });
}
