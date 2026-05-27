const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("rentalAutomation", {
  getAuthStates: () => ipcRenderer.invoke("rental:get-auth-states"),
  openPlatform: (platform) => ipcRenderer.invoke("rental:open-platform", platform),
  readSnapshot: (platform) => ipcRenderer.invoke("rental:read-snapshot", platform),
  clearPlatform: (platform) => ipcRenderer.invoke("rental:clear-platform", platform)
});
