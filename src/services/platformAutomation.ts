import type { PlatformId } from "../domain/types";
import type { LivePlatformSnapshot } from "./livePageParser";

export interface PlatformAuthState {
  platform: PlatformId;
  label: string;
  cookieCount: number;
  hasCookies: boolean;
  url: string;
}

export interface PlatformOpenResult extends PlatformAuthState {
  opened: boolean;
}

export interface PlatformSnapshotResult {
  ok: boolean;
  autoOpened?: boolean;
  snapshot?: LivePlatformSnapshot;
  message?: string;
}

export interface PlatformAutomationBridge {
  getAuthStates(): Promise<PlatformAuthState[]>;
  openPlatform(platform: PlatformId): Promise<PlatformOpenResult>;
  readSnapshot(platform: PlatformId): Promise<PlatformSnapshotResult>;
  clearPlatform(platform: PlatformId): Promise<PlatformAuthState>;
}

export function getPlatformAutomation(): PlatformAutomationBridge | undefined {
  const bridge = typeof window === "undefined" ? undefined : window.rentalAutomation;

  if (
    bridge &&
    typeof bridge.getAuthStates === "function" &&
    typeof bridge.openPlatform === "function" &&
    typeof bridge.readSnapshot === "function" &&
    typeof bridge.clearPlatform === "function"
  ) {
    return bridge;
  }

  return undefined;
}
