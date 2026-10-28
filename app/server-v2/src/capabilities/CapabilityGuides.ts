import browserSkill from "../browser/skill/SKILL.md" with { type: "text" };
import type { CapabilityId } from "./CapabilityConstants";

export const MACOS_GUIDE = [
  "Check detach_macos_status. Accessibility enables inspection/input; Screen Recording enables window images. No extra model is required.",
  "List windows and choose the exact rebuilt app/window. observe returns tree, screenshot, observationId and screenshotId together; snapshot is tree-only. Never infer screen coordinates from an unbound image.",
  "Use fresh refs from your task's latest observation. Pixel actions require observationId and screenshotId; resizing, moving, other tasks and ended runs never authorize stale coordinates.",
  "Actions return fresh state plus inputDelivered, uiChanged and effectVerified. UI change is not proof of task success; inspect the actual outcome. Do not blindly repeat an unverified click.",
  "Prefer accessibility editing and actions, then targeted background input. allowForeground is an explicit user-authorized fallback, never an automatic retry. Pause on user_active or app_busy; Stop revokes the run.",
  "type inserts at the caret/selection; set_value replaces the whole value. Secure fields are refused. Optional ocr uses local text recognition; use the selected agent's vision for other visual judgment.",
  "Use wait for text readiness, select_text, drag and exposed secondary accessibility actions as needed. Report connection/permission failures accurately; preserve the agent's own tools and approvals.",
].join("\n");

const SECRETS_GUIDE = [
  "Search credential metadata, then describe username/password/submit controls before requesting Touch ID.",
  "Pass all retained refs to detach_secrets_use_credential for atomic fill and submit. Credential values are never returned.",
  "After filling, follow the returned inspection/navigation state; do not inspect the protected document until navigation unlocks it.",
].join("\n");

export function capabilityGuide(id: CapabilityId) {
  if (id === "browser") return browserSkill.trim();
  return id === "macos" ? MACOS_GUIDE : SECRETS_GUIDE;
}
