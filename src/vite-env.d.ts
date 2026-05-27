/// <reference types="vite/client" />

import type { PlatformAutomationBridge } from "./services/platformAutomation";

declare global {
  interface Window {
    rentalAutomation?: PlatformAutomationBridge;
  }
}
