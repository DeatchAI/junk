import { chmod } from "node:fs/promises";
import { arch, platform } from "node:os";
import { dirname, resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
const packageName = platformPackage();
const source = resolve(root, "node_modules", packageName, "bin", "opencode");
const destination = resolve(root, "..", "lazzy", "opencode");

if (!await Bun.file(source).exists()) {
  throw new Error(`OpenCode platform package is missing: ${packageName}. Run bun install first.`);
}

await Bun.write(destination, Bun.file(source));
await chmod(destination, 0o755);
console.log(`Bundled ${packageName} at ${destination}`);

function platformPackage() {
  if (platform() !== "darwin") {
    throw new Error("Detach currently packages OpenCode only for macOS.");
  }

  if (arch() === "arm64") return "opencode-darwin-arm64";
  if (arch() === "x64") return "opencode-darwin-x64";
  throw new Error(`Unsupported macOS architecture: ${arch()}`);
}
