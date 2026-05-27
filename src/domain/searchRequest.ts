import type { ReturnMode, SearchRequest } from "./types";

type SearchFormValues = Partial<Record<"originLabel" | "pickupAt" | "returnAt" | "radiusKm" | "returnMode" | "vehicleQuery", FormDataEntryValue | string>>;

export function mergeSearchFormValues(
  current: SearchRequest,
  values: SearchFormValues
): SearchRequest {
  return {
    ...current,
    originLabel: readString(values.originLabel, current.originLabel),
    pickupAt: readString(values.pickupAt, current.pickupAt),
    returnAt: readString(values.returnAt, current.returnAt),
    radiusKm: readPositiveNumber(values.radiusKm, current.radiusKm),
    returnMode: readReturnMode(values.returnMode, current.returnMode),
    vehicleQuery: readString(values.vehicleQuery, current.vehicleQuery)
  };
}

export function formDataToSearchValues(formData: FormData): SearchFormValues {
  return {
    originLabel: formData.get("originLabel") ?? undefined,
    pickupAt: formData.get("pickupAt") ?? undefined,
    returnAt: formData.get("returnAt") ?? undefined,
    radiusKm: formData.get("radiusKm") ?? undefined,
    returnMode: formData.get("returnMode") ?? undefined,
    vehicleQuery: formData.get("vehicleQuery") ?? undefined
  };
}

function readString(value: FormDataEntryValue | string | undefined, fallback: string): string {
  return typeof value === "string" && value.trim() ? value : fallback;
}

function readPositiveNumber(value: FormDataEntryValue | string | undefined, fallback: number): number {
  if (typeof value !== "string") {
    return fallback;
  }

  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function readReturnMode(value: FormDataEntryValue | string | undefined, fallback: ReturnMode): ReturnMode {
  return value === "same-store" || value === "different-store" ? value : fallback;
}
