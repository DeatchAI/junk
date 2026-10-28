import { readFileSync } from "node:fs";

const args = process.argv.slice(2);
if (args.includes("--fixture-hang")) {
  setInterval(() => {}, 1_000);
} else {
  const input = args.includes("--prompt-file")
    ? readFileSync(args[args.indexOf("--prompt-file") + 1]!, "utf8")
    : args[0] === "run" ? args.at(-1)! : await Bun.stdin.text();
  if (!input.includes("JSON string") || !process.cwd().includes("detach-title-")) process.exit(2);
  if (args.includes("--settings-file")) {
    const settings = JSON.parse(readFileSync(args[args.indexOf("--settings-file") + 1]!, "utf8"));
    if (settings["amp.tools.disable"]?.[0] !== "*") process.exit(3);
  }
  const title = "Add Notch Keyboard Navigation";
  if (args[0] === "exec") console.log(JSON.stringify({
    type: "item.completed", item: { type: "agent_message", text: title },
  }));
  else if (args[0] === "run") console.log(JSON.stringify({ type: "text", part: { text: title } }));
  else if (args.includes("--stream-json") || args.includes("--output-format") && args.includes("json")) {
    console.log(JSON.stringify({ type: "result", result: title }));
  } else console.log(title);
}
