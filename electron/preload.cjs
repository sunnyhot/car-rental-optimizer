const { contextBridge } = require("electron");

contextBridge.exposeInMainWorld("rentalAutomation", {
  platform: "local-browser-automation"
});
