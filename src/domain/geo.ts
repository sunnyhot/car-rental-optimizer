import type { GeoPoint } from "./types";

const EARTH_RADIUS_KM = 6371;

export function distanceKmBetween(from: GeoPoint, to: GeoPoint): number {
  const latDelta = toRadians(to.lat - from.lat);
  const lngDelta = toRadians(to.lng - from.lng);
  const fromLat = toRadians(from.lat);
  const toLat = toRadians(to.lat);

  const haversine =
    Math.sin(latDelta / 2) ** 2 +
    Math.cos(fromLat) * Math.cos(toLat) * Math.sin(lngDelta / 2) ** 2;

  return Math.round(2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(haversine)) * 10) / 10;
}

function toRadians(value: number): number {
  return (value * Math.PI) / 180;
}
