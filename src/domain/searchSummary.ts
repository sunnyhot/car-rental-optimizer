import type { SearchRequest } from "./types";

export function calculateRentalDays(request: Pick<SearchRequest, "pickupAt" | "returnAt">): number {
  const pickupTime = new Date(request.pickupAt).getTime();
  const returnTime = new Date(request.returnAt).getTime();
  const hours = Math.max(1, (returnTime - pickupTime) / (1000 * 60 * 60));

  return Math.max(1, Math.ceil(hours / 24));
}

export function formatSearchCompletionStatus(request: SearchRequest, resultCount: number): string {
  const timeRange = `${formatDateTime(request.pickupAt)} - ${formatDateTime(request.returnAt)}`;
  const billableDays = calculateRentalDays(request);

  if (resultCount === 0) {
    return `已按 ${timeRange} 查询，按 ${billableDays} 天计费，没有找到候选车辆。`;
  }

  return `已按 ${timeRange} 查询，按 ${billableDays} 天计费，找到 ${resultCount} 个候选方案。`;
}

function formatDateTime(value: string): string {
  const date = new Date(value);
  const year = date.getFullYear();
  const month = pad(date.getMonth() + 1);
  const day = pad(date.getDate());
  const hours = pad(date.getHours());
  const minutes = pad(date.getMinutes());

  return `${year}/${month}/${day} ${hours}:${minutes}`;
}

function pad(value: number): string {
  return String(value).padStart(2, "0");
}
