import type { DesktopBridge } from "../desktop/DesktopBridge";

export async function macOSReadiness(bridge: DesktopBridge) {
  if (!bridge.getStatus().appConnected) {
    return { ready: false, hint: "The Detach macOS app socket is not connected." };
  }
  try {
    const result = await bridge.execute({ command: "desktop.status", payload: {} }, 3_000);
    const status = result && typeof result === "object" ? result as Record<string, unknown> : {};
    const accessibility = status.accessibilityGranted;
    const screenRecording = status.screenRecordingGranted;
    const help = status.permissionHelp as Record<string, string> | undefined;
    const permissions = {
      accessibility: accessibility === true,
      screenRecording: screenRecording === true,
    };
    if (typeof accessibility !== "boolean" || typeof screenRecording !== "boolean") {
      return { ready: false, needsPermission: true, permissions,
        hint: "Detach connected, but native permission status was not returned. Check detach_macos_status." };
    }
    if (!accessibility) return { ready: false, needsPermission: true, permissions,
      hint: help?.accessibility || "Enable Detach in System Settings > Privacy & Security > Accessibility." };
    return { ready: true, permissions, ...(!screenRecording ? {
      hint: `Inspection and input are ready. Screenshots require Screen Recording: ${help?.screenRecording || "Enable Detach in System Settings > Privacy & Security > Screen & System Audio Recording."}`,
    } : {}) };
  } catch (error) {
    return { ready: false, hint: `Native status check failed: ${error instanceof Error ? error.message : String(error)}` };
  }
}
