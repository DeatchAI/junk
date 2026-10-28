export interface DriverResult { content?: unknown[]; structuredContent?: unknown; isError?: boolean }
export type DriverCall = (tool: string, args: Record<string, unknown>) => Promise<DriverResult>;

/** Calls an explicitly installed driver/daemon, never a shell or package installer. */
export const runCuaDriver: DriverCall = async (tool, args) => {
  const path = Bun.env.DETACH_CUA_DRIVER_PATH;
  if (!path?.startsWith("/")) throw new Error("Set DETACH_CUA_DRIVER_PATH to an installed Cua Driver executable for the opt-in comparison");
  const child = Bun.spawn([path, "call", tool, JSON.stringify(args)], {
    stdin: "ignore", stdout: "pipe", stderr: "pipe",
    // Do not hand runtime tokens or provider credentials to the comparison driver.
    env: { PATH: "/usr/bin:/bin:/usr/sbin:/sbin", HOME: Bun.env.HOME ?? "", TMPDIR: Bun.env.TMPDIR ?? "/tmp" },
  });
  const read = async (stream: ReadableStream<Uint8Array>) => {
    const reader = stream.getReader(); const chunks: Uint8Array[] = []; let size = 0;
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > 16 * 1024 * 1024) { child.kill(); throw new Error("Cua Driver output exceeded its comparison limit"); }
      chunks.push(value);
    }
    return Buffer.concat(chunks).toString("utf8");
  };
  const timer = setTimeout(() => child.kill(), 12_000);
  try {
    const [exit, stdout] = await Promise.all([child.exited, read(child.stdout), read(child.stderr)]);
    if (exit !== 0) throw new Error("Cua Driver comparison failed or timed out; check its installation, daemon and OS permissions");
    const result = JSON.parse(stdout) as DriverResult;
    if (!result || typeof result !== "object") throw new Error("Invalid Cua Driver result");
    return result;
  } finally { clearTimeout(timer); }
};
