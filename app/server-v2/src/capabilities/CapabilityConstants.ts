export const CAPABILITY_BROKER_ID = "detach-capability-tools";

export const CAPABILITY_IDS = ["browser", "macos", "secrets"] as const;

export type CapabilityId = (typeof CAPABILITY_IDS)[number];
