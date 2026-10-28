// Local echo-only MCP fixture for the optional real-Pi bridge check.
let buffer = "";
for await (const chunk of Bun.stdin.stream()) {
  buffer += new TextDecoder().decode(chunk);
  let end: number;
  while ((end = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
    if (!line.trim()) continue;
    const request = JSON.parse(line);
    if (request.id === undefined) continue;
    let result: unknown = {};
    if (request.method === "initialize") result = {
      protocolVersion: request.params.protocolVersion,
      capabilities: { tools: {} }, serverInfo: { name: "detach-probe", version: "1" },
    };
    else if (request.method === "tools/list") result = { tools: [{
      name: "probe_echo", description: "Local integration fixture; returns bridge-ok.",
      inputSchema: { type: "object", properties: {}, additionalProperties: false },
    }] };
    else if (request.method === "tools/call") result = { content: [{ type: "text", text: "bridge-ok" }] };
    process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id: request.id, result }) + "\n");
  }
}
