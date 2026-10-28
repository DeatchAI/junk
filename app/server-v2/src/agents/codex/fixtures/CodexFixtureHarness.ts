import { chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { CodexAdapter } from "../../CodexAdapter";

export async function withFixture(mode: string, body: (fixture: {
  adapter: CodexAdapter; workspace: string; marker: string; log: string;
}) => Promise<void>) {
  const dir = await mkdtemp(join(tmpdir(), "detach-codex-approvals-"));
  try {
    const executable = join(dir, "codex"), workspace = join(dir, "workspace");
    const marker = join(dir, "approved-effect.txt"), log = join(dir, "rpc.jsonl");
    await mkdir(workspace);
    await writeFile(executable, `#!${process.execPath}\nimport {runCodexFixture} from ${JSON.stringify(join(import.meta.dir, "CodexServerFixture.ts"))};\nawait runCodexFixture(${JSON.stringify({ mode, marker, log })});\n`);
    await chmod(executable, 0o755);
    await body({ adapter: new CodexAdapter(async () => executable), workspace, marker, log });
  } finally { await rm(dir, { recursive: true, force: true }); }
}
