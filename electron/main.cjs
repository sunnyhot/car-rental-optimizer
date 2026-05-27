const { app, BrowserWindow, ipcMain, session, shell } = require("electron");
const path = require("node:path");

const isDev = Boolean(process.env.VITE_DEV_SERVER_URL);
const platformWindows = new Map();

const PLATFORMS = {
  ehi: {
    label: "一嗨",
    url: "https://www.1hai.cn/",
    partition: "persist:rental-ehi"
  },
  "car-inc": {
    label: "神州",
    url: "https://www.zuche.com/",
    partition: "persist:rental-car-inc"
  }
};

function createWindow() {
  const mainWindow = new BrowserWindow({
    width: 1320,
    height: 860,
    minWidth: 1120,
    minHeight: 720,
    title: "租车总成本比较",
    backgroundColor: "#f5f6f8",
    titleBarStyle: "hiddenInset",
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: "deny" };
  });

  if (isDev) {
    mainWindow.loadURL(process.env.VITE_DEV_SERVER_URL);
  } else {
    mainWindow.loadFile(path.join(__dirname, "../dist/index.html"));
  }
}

app.whenReady().then(() => {
  registerRentalAutomationHandlers();
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

function registerRentalAutomationHandlers() {
  ipcMain.handle("rental:get-auth-states", async () => Promise.all(platformIds().map(getPlatformState)));

  ipcMain.handle("rental:open-platform", async (_event, platform) => {
    const config = getPlatformConfig(platform);
    const existing = platformWindows.get(platform);

    if (existing && !existing.isDestroyed()) {
      existing.show();
      existing.focus();
      return { ...(await getPlatformState(platform)), opened: true };
    }

    const loginWindow = new BrowserWindow({
      width: 1180,
      height: 820,
      title: `${config.label} 登录/查询`,
      webPreferences: {
        partition: config.partition,
        contextIsolation: true,
        nodeIntegration: false
      }
    });

    platformWindows.set(platform, loginWindow);
    loginWindow.on("closed", () => {
      platformWindows.delete(platform);
    });
    loginWindow.webContents.setWindowOpenHandler(({ url }) => {
      loginWindow.loadURL(url);
      return { action: "deny" };
    });
    await loginWindow.loadURL(config.url);

    return { ...(await getPlatformState(platform)), opened: true };
  });

  ipcMain.handle("rental:read-snapshot", async (_event, platform) => {
    const config = getPlatformConfig(platform);
    const targetWindow = platformWindows.get(platform);

    if (!targetWindow || targetWindow.isDestroyed()) {
      return {
        ok: false,
        message: `请先打开${config.label}窗口，登录并在平台页面完成查询。`
      };
    }

    const snapshot = await targetWindow.webContents.executeJavaScript(
      `({
        title: document.title || "",
        url: location.href,
        text: document.body ? document.body.innerText : ""
      })`,
      true
    );

    return {
      ok: true,
      snapshot: {
        platform,
        title: snapshot.title,
        url: snapshot.url,
        text: snapshot.text
      }
    };
  });

  ipcMain.handle("rental:clear-platform", async (_event, platform) => {
    const config = getPlatformConfig(platform);
    const platformSession = session.fromPartition(config.partition);
    await platformSession.clearStorageData();
    const targetWindow = platformWindows.get(platform);
    if (targetWindow && !targetWindow.isDestroyed()) {
      await targetWindow.loadURL(config.url);
    }

    return getPlatformState(platform);
  });
}

async function getPlatformState(platform) {
  const config = getPlatformConfig(platform);
  const platformSession = session.fromPartition(config.partition);
  const cookies = await platformSession.cookies.get({ url: config.url });

  return {
    platform,
    label: config.label,
    cookieCount: cookies.length,
    hasCookies: cookies.length > 0,
    url: config.url
  };
}

function platformIds() {
  return Object.keys(PLATFORMS);
}

function getPlatformConfig(platform) {
  const config = PLATFORMS[platform];
  if (!config) {
    throw new Error(`Unsupported platform: ${platform}`);
  }
  return config;
}
