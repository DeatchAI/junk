import { describe, expect, test } from "bun:test";

import { fxEnvironment } from "./FxAdapter";

describe("fx adapter", () => {
  test("uses the user's fx account without unattended upgrades or sound", () => {
    const environment = fxEnvironment();

    expect(environment).toEqual({
      FX_AUTO_UPGRADE: "0",
      FX_PERMISSION_MODE: "ask",
      FX_SOUND: "off",
      NO_COLOR: "1",
    });
    expect(environment).not.toHaveProperty("AI_GATEWAY_API_KEY");
  });
});
