import type { VehicleMatch } from "./types";

interface VehicleCandidate {
  vehicleName: string;
  vehicleClass: string;
}

const MODEL_ALIASES: Record<string, string[]> = {
  "瑞虎8": ["瑞虎8", "奇瑞瑞虎8", "tiggo8", "tiggo 8"],
  "哈弗h6": ["哈弗h6", "h6", "haval h6"]
};

const CLASS_KEYWORDS: Record<string, string[]> = {
  suv: ["suv", "越野", "运动型"],
  sedan: ["轿车", "三厢", "两厢", "sedan"],
  mpv: ["mpv", "商务", "多用途"]
};

export function matchVehicle(query: string, candidate: VehicleCandidate): VehicleMatch {
  const normalizedQuery = normalize(query);
  const normalizedName = normalize(candidate.vehicleName);
  const normalizedClass = normalize(candidate.vehicleClass);

  if (!normalizedQuery) {
    return {
      kind: "not-specified",
      score: 0,
      label: "未指定车型"
    };
  }

  const aliases = MODEL_ALIASES[normalizedQuery] ?? [normalizedQuery];
  if (aliases.some((alias) => normalizedName.includes(normalize(alias)))) {
    return {
      kind: "exact",
      score: 1,
      label: "精确车型"
    };
  }

  if (sameVehicleFamily(normalizedQuery, normalizedClass, normalizedName)) {
    return {
      kind: "similar-class",
      score: 0.72,
      label: "同级 SUV 替代"
    };
  }

  return {
    kind: "low-confidence",
    score: 0.35,
    label: "低置信替代"
  };
}

function sameVehicleFamily(query: string, vehicleClass: string, vehicleName: string): boolean {
  const queryFamily = inferFamily(query);
  const candidateFamily = inferFamily(`${vehicleClass} ${vehicleName}`);

  return Boolean(queryFamily && candidateFamily && queryFamily === candidateFamily);
}

function inferFamily(value: string): string | undefined {
  if (value.includes("瑞虎") || value.includes("哈弗") || value.includes("suv")) {
    return "suv";
  }

  return Object.entries(CLASS_KEYWORDS).find(([, keywords]) =>
    keywords.some((keyword) => value.includes(keyword))
  )?.[0];
}

function normalize(value: string): string {
  return value.toLowerCase().replace(/\s+/g, "").replace(/[·-]/g, "");
}
