function createPlatformWindowController({ BrowserWindow, platformWindows, getPlatformConfig }) {
  async function ensurePlatformWindow(platform, options = {}) {
    const config = getPlatformConfig(platform);
    const show = options.show !== false;
    const existing = platformWindows.get(platform);

    if (existing && !existing.isDestroyed()) {
      if (show) {
        existing.show();
        existing.focus();
      }

      return { config, opened: false, window: existing };
    }

    const platformWindow = new BrowserWindow({
      width: 1180,
      height: 820,
      title: `${config.label} 登录/查询`,
      webPreferences: {
        partition: config.partition,
        contextIsolation: true,
        nodeIntegration: false
      }
    });

    platformWindows.set(platform, platformWindow);
    platformWindow.on("closed", () => {
      platformWindows.delete(platform);
    });
    platformWindow.webContents.setWindowOpenHandler(({ url }) => {
      void platformWindow.loadURL(url);
      return { action: "deny" };
    });

    await platformWindow.loadURL(config.url);

    if (show) {
      platformWindow.show();
      platformWindow.focus();
    }

    return { config, opened: true, window: platformWindow };
  }

  return { ensurePlatformWindow };
}

module.exports = { createPlatformWindowController };
