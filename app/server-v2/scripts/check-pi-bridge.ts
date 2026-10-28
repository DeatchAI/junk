import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { piRunExtension, piMCPServerName } from "../src/agents/pi/PiExtension";
import { PiRPCProcess } from "../src/agents/pi/PiRPCProcess";
import { asStringRecord, createTempTextFile, withTimeout } from "../src/agents/CliAdapterUtils";

// Optional real-CLI probe: only local extension commands, never a model prompt.
const executable = process.argv[2];
if (!executable) throw new Error("Pass the absolute path to an installed Pi CLI.");
const stateDirectory = mkdtempSync(join(tmpdir(), "detach-pi-probe-state-"));
const marker = "detach-probe-ready";
const toolName = "mcp__" + piMCPServerName(marker, 0) + "__probe_echo";
const extension = createTempTextFile("detach-pi-probe-", "probe.mjs",
  piRunExtension({ type: "chat", text: "", agent: "pi", mcpServers: [{
    id: "probe", name: "Probe", transport: "stdio", command: process.execPath,
    args: [join(import.meta.dir, "fixtures/PiProbeMCP.ts")], enabled: true,
    approvalPolicy: "auto-approve", created_at: 0, updated_at: 0,
  }] }, marker).replace(/}\s*$/, `
    pi.registerCommand("detach-probe-dialogs", { description: "Local bridge check", handler: async (_args, ctx) => {
      const permitted = await ctx.ui.confirm("Fixture permission", "No command will run.");
      const answer = await ctx.ui.select("Fixture question", ["Mac app", "Website"]);
      if (!permitted || answer !== "Mac app") throw new Error("Dialog reply mismatch");
      const deadline = Date.now() + 5000;
      while (!pi.getAllTools().some(tool => tool.name === ${JSON.stringify(toolName)}) && Date.now() < deadline) {
        await new Promise(resolve => setTimeout(resolve, 25));
      }
      if (!pi.getAllTools().some(tool => tool.name === ${JSON.stringify(toolName)})) {
        throw new Error("Pi did not connect the run-local MCP server");
      }
    } });
  }`));
let permissions = 0, questions = 0;
const child = new PiRPCProcess({
  command: executable,
  args: ["--mode", "rpc", "--no-session", "--offline", "--no-context-files",
    "--no-skills", "--no-prompt-templates", "--no-themes", "--extension", extension.path],
  cwd: stateDirectory, env: { PI_CODING_AGENT_DIR: stateDirectory },
  callbacks: { onActivity() {}, onChunk() {},
    onPermission: async () => { permissions += 1; return true; },
    onQuestion: async () => { questions += 1; return { answer: { answers: ["Mac app"] } }; },
  },
});
try {
  await withTimeout((async () => {
    const data = asStringRecord(await child.request("get_commands"));
    if (!Array.isArray(data?.commands) || !data.commands.some((item) => asStringRecord(item)?.name === marker)) {
      throw new Error("Pi did not register the Detach bridge");
    }
    await child.request("prompt", { message: "/detach-probe-dialogs" });
    if (permissions !== 1 || questions !== 1) throw new Error("Pi dialog protocol did not complete");
    console.log(JSON.stringify({ bridgeLoaded: true, nativePermissions: permissions, nativeQuestions: questions,
      mcpToolAvailable: true, modelCalls: 0 }));
  })(), 15_000, () => child.cancel());
} finally {
  child.dispose(); extension.cleanup(); rmSync(stateDirectory, { recursive: true, force: true });
}
