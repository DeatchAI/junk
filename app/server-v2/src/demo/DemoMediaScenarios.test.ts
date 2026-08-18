import { describe, expect, test } from "bun:test";

import {
  DEMO_IMAGE_TRIGGER_PROMPTS,
  DEMO_VIDEO_TRIGGER_PROMPTS,
  demoImagePath,
  demoImageURL,
  demoVideoPath,
  demoVideoURL,
  matchDemoImageScenario,
  matchDemoVideoScenario,
} from "./DemoMediaScenarios";

describe("demo image scenarios", () => {
  test("only matches exact image prompts when Debug mode is enabled", () => {
    expect(matchDemoImageScenario(DEMO_IMAGE_TRIGGER_PROMPTS.image1, false)).toBeUndefined();
    expect(matchDemoImageScenario(DEMO_IMAGE_TRIGGER_PROMPTS.image1, true)?.id).toBe("image1");
    expect(matchDemoImageScenario(`**${DEMO_IMAGE_TRIGGER_PROMPTS.image2}**`, true)).toBeUndefined();
    expect(matchDemoImageScenario(`${DEMO_IMAGE_TRIGGER_PROMPTS.image3}!`, true)).toBeUndefined();
  });

  test("maps each scenario to the numbered Downloads asset", () => {
    expect(demoImagePath(1)).toEndWith("Downloads/demo-mode/images/1.png");
    expect(demoImageURL(3)).toMatch(/^file:\/\/\/.*Downloads\/demo-mode\/images\/3\.png$/);
    expect(demoVideoPath(2)).toEndWith("Downloads/demo-mode/videos/2.mp4");
    expect(demoVideoURL(3)).toMatch(/^file:\/\/\/.*Downloads\/demo-mode\/videos\/3\.mp4$/);
  });

  test("matches video prompts only for video generations", () => {
    expect(matchDemoVideoScenario(DEMO_VIDEO_TRIGGER_PROMPTS.video1, false)).toBeUndefined();
    expect(matchDemoVideoScenario(DEMO_VIDEO_TRIGGER_PROMPTS.video1, true)?.id).toBe("video1");
    expect(matchDemoImageScenario(DEMO_VIDEO_TRIGGER_PROMPTS.video2, true)).toBeUndefined();
    expect(matchDemoVideoScenario(`**${DEMO_VIDEO_TRIGGER_PROMPTS.video3}**`, true)).toBeUndefined();
  });
});
