import { describe, expect, it, vi } from "vitest";
import platformWindowModule from "./platformWindows.cjs";

const { createPlatformWindowController } = platformWindowModule;

describe("createPlatformWindowController", () => {
  it("opens a platform window when a snapshot read has no active window yet", async () => {
    const createdWindows = [];
    const BrowserWindow = vi.fn(function FakeBrowserWindow(options) {
      this.options = options;
      this.closedHandler = undefined;
      this.webContents = {
        setWindowOpenHandler: vi.fn()
      };
      this.isDestroyed = vi.fn(() => false);
      this.show = vi.fn();
      this.focus = vi.fn();
      this.on = vi.fn((event, handler) => {
        if (event === "closed") {
          this.closedHandler = handler;
        }
      });
      this.loadURL = vi.fn(async () => undefined);
      createdWindows.push(this);
    });
    const platformWindows = new Map();
    const controller = createPlatformWindowController({
      BrowserWindow,
      platformWindows,
      getPlatformConfig: () => ({
        label: "一嗨",
        partition: "persist:rental-ehi",
        url: "https://www.1hai.cn/"
      })
    });

    const result = await controller.ensurePlatformWindow("ehi");

    expect(result.opened).toBe(true);
    expect(platformWindows.get("ehi")).toBe(createdWindows[0]);
    expect(createdWindows[0].loadURL).toHaveBeenCalledWith("https://www.1hai.cn/");
  });
});
