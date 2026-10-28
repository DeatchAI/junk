import { chmod } from "node:fs/promises";
import { arch, platform } from "node:os";
import { resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
const packageName = platformPackage();
const source = resolve(root, "node_modules", packageName, "bin", "opencode");
const destination = resolve(root, "..", "lazzy", "opencode");

if (!await Bun.file(source).exists()) {
  console.log(`Restoring missing ${packageName} executable from the lockfile…`);
  const install = Bun.spawnSync([
    process.execPath, "install", "--frozen-lockfile", "--force", "--ignore-scripts",
  ], {
    cwd: root,
    stdin: "ignore",
    stdout: "inherit",
    stderr: "inherit",
  });

  if (install.exitCode !== 0 || !await Bun.file(source).exists()) {
    throw new Error(
      `Could not restore ${packageName}. Run bun install --frozen-lockfile --force in ${root}, then rebuild.`,
    );
  }
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
