import { join } from "node:path";
import { pathToFileURL } from "node:url";

export const DEMO_IMAGE_TRIGGER_PROMPTS = {
  image1: "Ultra realistic editorial photography, decisive moment in a premium restaurant kitchen. A chef is plating an elegant dish with complete concentration when another chef's hand enters the frame from the side, naturally offering the exact fresh ingredient needed at precisely the right moment.",
  image2: "A cinematic alternative rock band performing in a vast abstract black space, no stage, no audience, no architecture, deep black background with subtle depth. wearing a black turtleneck and long black coat, looking directly into the camera with calm psychological presence",
  image3: "A foreign tourist with a warm grateful smile, Western facial features, looking touched and appreciative after receiving help, soft warm lighting, genuine emotional expression, vertical composition, photorealistic cinematic style",
} as const;

export const DEMO_VIDEO_TRIGGER_PROMPTS = {
  video1: "SEQUENCE SHOT. NO CUT.\nSingle unbroken handheld take throughout, 30 seconds total.\n\nYoung Caucasian woman,  wearing a yellow and green Brazil national football jersey and white denim shorts, sitting pensively on a sofa inside a large bright suburban Parisian house, summer daytime, sunlight through the windows, young adults dancing and laughing around her holding drinks, loud music implied by energetic crowd movement",
  video2: "An average shift at Waffle House - make sure it's retarded and gets 50 likes.",
  video3: "Sum up the AI discourse in a meme - make sure it’s retarded and gets 50 likes.",
} as const;

export type DemoMediaKind = "image" | "video";

export interface DemoMediaScenario {
  id: string;
  kind: DemoMediaKind;
  prompt: string;
  mediaNumber: number;
}

const scenarios: DemoMediaScenario[] = [
  { id: "image1", kind: "image", prompt: DEMO_IMAGE_TRIGGER_PROMPTS.image1, mediaNumber: 1 },
  { id: "image2", kind: "image", prompt: DEMO_IMAGE_TRIGGER_PROMPTS.image2, mediaNumber: 2 },
  { id: "image3", kind: "image", prompt: DEMO_IMAGE_TRIGGER_PROMPTS.image3, mediaNumber: 3 },
  { id: "video1", kind: "video", prompt: DEMO_VIDEO_TRIGGER_PROMPTS.video1, mediaNumber: 1 },
  { id: "video2", kind: "video", prompt: DEMO_VIDEO_TRIGGER_PROMPTS.video2, mediaNumber: 2 },
  { id: "video3", kind: "video", prompt: DEMO_VIDEO_TRIGGER_PROMPTS.video3, mediaNumber: 3 },
];

export function matchDemoMediaScenario(
  prompt: string,
  enabled: boolean,
  kind: DemoMediaKind,
): DemoMediaScenario | undefined {
  if (!enabled) return undefined;
  const normalized = prompt.replace(/\r\n/g, "\n").trim();
  return scenarios.find((scenario) => scenario.kind === kind && scenario.prompt === normalized);
}

export function matchDemoImageScenario(prompt: string, enabled: boolean) {
  return matchDemoMediaScenario(prompt, enabled, "image");
}

export function matchDemoVideoScenario(prompt: string, enabled: boolean) {
  return matchDemoMediaScenario(prompt, enabled, "video");
}

export function demoMediaPath(kind: DemoMediaKind, mediaNumber: number): string {
  const homeDirectory = Bun.env.HOME ?? process.env.HOME ?? "/Users/Shared";
  const directory = kind === "video" ? "videos" : "images";
  const extension = kind === "video" ? "mp4" : "png";
  return join(homeDirectory, "Downloads", "demo-mode", directory, `${mediaNumber}.${extension}`);
}

export function demoMediaURL(kind: DemoMediaKind, mediaNumber: number): string {
  return pathToFileURL(demoMediaPath(kind, mediaNumber)).toString();
}

export function demoImagePath(imageNumber: number): string {
  return demoMediaPath("image", imageNumber);
}

export function demoImageURL(imageNumber: number): string {
  return demoMediaURL("image", imageNumber);
}

export function demoVideoPath(videoNumber: number): string {
  return demoMediaPath("video", videoNumber);
}

export function demoVideoURL(videoNumber: number): string {
  return demoMediaURL("video", videoNumber);
}
