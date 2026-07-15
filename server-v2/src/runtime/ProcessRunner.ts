export interface ProcessRunOptions {
  command: string;
  args: string[];
  cwd?: string;
  env?: Record<string, string | undefined>;
  input?: string;
  onStdout?(chunk: string): void;
  onStderr?(chunk: string): void;
}

export interface RunningProcess {
  cancel(): void;
  finished: Promise<{ stdout: string; stderr: string; exitCode: number | null }>;
}

const decoder = new TextDecoder();
const encoder = new TextEncoder();

export function runProcess(options: ProcessRunOptions): RunningProcess {
  const process = Bun.spawn(options.args.length > 0 ? [options.command, ...options.args] : [options.command], {
    cwd: options.cwd,
    env: {
      ...processEnv(),
      ...withoutUndefined(options.env ?? {}),
    },
    stdin: options.input ? "pipe" : "ignore",
    stdout: "pipe",
    stderr: "pipe",
  });

  if (options.input && process.stdin) {
    process.stdin.write(encoder.encode(options.input));
    process.stdin.end();
  }

  const stdoutPromise = readStream(process.stdout, options.onStdout);
  const stderrPromise = readStream(process.stderr, options.onStderr);

  return {
    cancel() {
      process.kill();
    },
    finished: Promise.all([process.exited, stdoutPromise, stderrPromise]).then(
      ([exitCode, stdout, stderr]) => ({ stdout, stderr, exitCode })
    ),
  };
}

async function readStream(stream: ReadableStream<Uint8Array>, onChunk?: (chunk: string) => void) {
  let full = "";
  const reader = stream.getReader();

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    const chunk = decoder.decode(value, { stream: true });
    full += chunk;
    onChunk?.(chunk);
  }

  const tail = decoder.decode();
  if (tail) {
    full += tail;
    onChunk?.(tail);
  }

  return full;
}

function processEnv() {
  const env = { ...Bun.env };
  const extraPath = [
    ...(Bun.env.HOME
      ? [
          `${Bun.env.HOME}/.grok/bin`,
          `${Bun.env.HOME}/.local/bin`,
          `${Bun.env.HOME}/.bun/bin`,
          `${Bun.env.HOME}/Applications/ChatGPT.app/Contents/Resources`,
          `${Bun.env.HOME}/Applications/Codex.app/Contents/Resources`,
        ]
      : []),
    "/Applications/ChatGPT.app/Contents/Resources",
    "/Applications/Codex.app/Contents/Resources",
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin",
  ].join(":");

  env.PATH = env.PATH ? `${env.PATH}:${extraPath}` : extraPath;
  return env;
}

function withoutUndefined(input: Record<string, string | undefined>) {
  return Object.fromEntries(Object.entries(input).filter(([, value]) => value !== undefined)) as Record<string, string>;
}
