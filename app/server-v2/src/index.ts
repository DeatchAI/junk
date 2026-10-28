import { runNativeBrowserHost } from "./browser/NativeBrowserHost";
import { runBrowserMCPServer } from "./browser/BrowserMCPServer";
import { runDesktopMCPServer } from "./desktop/DesktopMCPServer";
import { runSecretsMCPServer } from "./secrets/SecretsMCPServer";
import { runCapabilityMCPServer } from "./capabilities/CapabilityMCPServer";

if (process.argv.includes("--native-browser-host")) {
  await runNativeBrowserHost();
  process.exit(0);
}

if (process.argv.includes("--mcp-browser-tools")) {
  await runBrowserMCPServer();
  process.exit(0);
}

if (process.argv.includes("--mcp-macos-tools")) {
  await runDesktopMCPServer();
  process.exit(0);
}

if (process.argv.includes("--mcp-secrets-tools")) {
  await runSecretsMCPServer();
  process.exit(0);
}

if (process.argv.includes("--mcp-capability-tools")) {
  await runCapabilityMCPServer();
  process.exit(0);
}

await import("./server/RuntimeServer");
