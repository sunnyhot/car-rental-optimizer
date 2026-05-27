import { describe, expect, it, vi } from "vitest";
import { getPlatformAutomation } from "./platformAutomation";

describe("getPlatformAutomation", () => {
  it("returns undefined when the app is running outside Electron", () => {
    vi.stubGlobal("window", {});

    expect(getPlatformAutomation()).toBeUndefined();

    vi.unstubAllGlobals();
  });

  it("returns the Electron bridge when all required methods exist", () => {
    const bridge = {
      getAuthStates: vi.fn(),
      openPlatform: vi.fn(),
      readSnapshot: vi.fn(),
      clearPlatform: vi.fn()
    };
    vi.stubGlobal("window", { rentalAutomation: bridge });

    expect(getPlatformAutomation()).toBe(bridge);

    vi.unstubAllGlobals();
  });
});
