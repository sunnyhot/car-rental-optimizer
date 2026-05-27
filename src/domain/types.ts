export type PlatformId = "ehi" | "car-inc";

export type ReturnMode = "same-store" | "different-store";

export type MatchKind = "exact" | "similar-class" | "low-confidence";

export type RouteMode = "taxi" | "transit";

export type ResultWarning =
  | "cross-city-pickup"
  | "partial-price"
  | "login-required"
  | "captcha-required"
  | "map-cost-missing";

export interface GeoPoint {
  lat: number;
  lng: number;
}

export interface SearchRequest {
  origin: GeoPoint;
  originLabel: string;
  pickupAt: string;
  returnAt: string;
  returnMode: ReturnMode;
  radiusKm: number;
  vehicleQuery: string;
  platforms: PlatformId[];
}

export interface Store {
  id: string;
  platform: PlatformId;
  name: string;
  city: string;
  address: string;
  location: GeoPoint;
  distanceKm: number;
  hours: string;
}

export interface RentalListing {
  id: string;
  platform: PlatformId;
  store: Store;
  vehicleName: string;
  vehicleClass: string;
  basePrice: number;
  platformFees: number;
  insuranceFees: number;
  oneWayFee: number;
  currency: "CNY";
  sourceUrl: string;
  dataCompleteness: number;
  warnings: ResultWarning[];
}

export interface VehicleMatch {
  kind: MatchKind;
  score: number;
  label: string;
}

export interface RouteEstimate {
  mode: RouteMode;
  cost: number;
  durationMinutes: number;
  distanceKm: number;
  summary: string;
}

export interface Recommendation {
  listing: RentalListing;
  match: VehicleMatch;
  taxiRoute: RouteEstimate;
  transitRoute: RouteEstimate;
  rentalTotal: number;
  taxiTotal: number;
  transitTotal: number;
  bestTotal: number;
  bestRouteMode: RouteMode;
  warnings: ResultWarning[];
}
