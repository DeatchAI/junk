import { BrowserAutomation, type BrowserActivitySink } from "../browser/BrowserAutomation";
import { BrowserBridge } from "../browser/BrowserBridge";
import { BROWSER_TOOLS, BROWSER_TOOL_COMMANDS } from "../browser/BrowserMCPServer";
import { DesktopBridge } from "../desktop/DesktopBridge";
import { MACOS_TOOLS, MACOS_TOOL_COMMANDS } from "../desktop/DesktopMCPServer";
import { SecretBridge } from "../secrets/SecretBridge";
import { SECRETS_TOOLS } from "../secrets/SecretsMCPServer";
import { CAPABILITY_BROKER_ID, type CapabilityId } from "./CapabilityConstants";

export { CAPABILITY_BROKER_ID } from "./CapabilityConstants";

export interface CapabilityDescriptor {
  id: CapabilityId;
  name: string;
  summary: string;
  whenToUse: string;
  connection: "ready" | "needs_connection";
  hint?: string;
  operationCount: number;
}

export interface CapabilityDescription extends CapabilityDescriptor {
  tools: CapabilityTool[];
}

export interface CapabilityTool {
  name: string;
  description?: string;
  inputSchema?: Record<string, unknown>;
}

interface CapabilityDefinition {
  id: CapabilityId;
  name: string;
  summary: string;
  whenToUse: string;
  tools: CapabilityTool[];
}

interface RegisteredRun {
  runId: string;
  allowedUploadPaths: string[];
  activitySink?: BrowserActivitySink;
  browserStartedByBroker: boolean;
  startingBrowserTask?: Promise<void>;
}

const DEFINITIONS: CapabilityDefinition[] = [
  {
    id: "browser",
    name: "Browser",
    summary: "Operate the user's focused signed-in Chrome page and verify web state.",
    whenToUse: "Web pages, tabs, DOM inspection, forms, downloads, screenshots, and signed-in sites.",
    tools: BROWSER_TOOLS,
  },
  {
    id: "macos",
    name: "macOS",
    summary: "Inspect and control native macOS applications through the connected Detach app.",
    whenToUse: "Native app windows, accessibility trees, keyboard input, clicks, scrolling, and desktop screenshots.",
    tools: MACOS_TOOLS,
  },
  {
    id: "secrets",
    name: "Secrets",
    summary: "Search safe credential metadata and fill verified browser fields through Touch ID.",
    whenToUse: "Login flows where the user has a saved credential and secure fill is explicitly needed.",
    tools: SECRETS_TOOLS,
  },
];

export class CapabilityBroker {
  private readonly runs = new Map<string, RegisteredRun>();

  constructor(
    private readonly browserAutomation: BrowserAutomation,
    private readonly browserBridge: BrowserBridge,
    private readonly desktopBridge: DesktopBridge,
    private readonly secretBridge: SecretBridge,
  ) {}

  async list(query?: string): Promise<CapabilityDescriptor[]> {
    const normalizedQuery = query?.trim().toLocaleLowerCase();
    const descriptors = await Promise.all(DEFINITIONS.map(async (definition) => this.toDescriptor(definition)));
    if (!normalizedQuery) return descriptors;
    return descriptors.filter((item) => [item.id, item.name, item.summary, item.whenToUse].some((value) => value.toLocaleLowerCase().includes(normalizedQuery)));
  }

  async describe(capabilityId: string): Promise<CapabilityDescription> {
    const definition = this.definition(capabilityId);
    return { ...await this.toDescriptor(definition), tools: definition.tools };
  }

  registerRun(runId: string, options: { allowedUploadPaths?: string[]; activitySink?: BrowserActivitySink } = {}) {
    this.runs.set(runId, {
      runId,
      allowedUploadPaths: options.allowedUploadPaths ?? [],
      activitySink: options.activitySink,
      browserStartedByBroker: false,
    });
  }

  async endRun(runId: string) {
    const registered = this.runs.get(runId);
    if (!registered) return undefined;
    if (registered.startingBrowserTask) await registered.startingBrowserTask.catch(() => undefined);

    let artifacts;
    if (registered.browserStartedByBroker && this.browserAutomation.isTaskActive(runId)) {
      await this.browserAutomation.endTask(runId).catch(() => undefined);
      artifacts = this.browserAutomation.getArtifacts(runId);
    }
    this.runs.delete(runId);
    return artifacts;
  }

  async invoke(invocation: {
    capabilityId: string;
    toolName: string;
    arguments?: Record<string, unknown>;
    runId?: string;
  }) {
    const definition = this.definition(invocation.capabilityId);
    const tool = definition.tools.find((item) => item.name === invocation.toolName);
    if (!tool) throw new Error(`Unknown ${definition.name} operation: ${invocation.toolName}`);
    const payload = invocation.arguments ?? {};

    if (definition.id === "browser") {
      const runId = invocation.runId?.trim();
      if (!runId) throw new Error("Browser capability calls require an active Detach run.");
      await this.ensureBrowserTask(runId);
      return this.browserAutomation.execute({
        command: BROWSER_TOOL_COMMANDS[invocation.toolName] ?? "browser.execute_code",
        payload,
      }, runId);
    }

    if (definition.id === "macos") {
      const command = MACOS_TOOL_COMMANDS[invocation.toolName];
      if (!command) throw new Error(`No runtime command is mapped for ${invocation.toolName}`);
      return this.desktopBridge.execute({
        command,
        payload,
      });
    }

    return this.executeSecretCommand(invocation.toolName, payload);
  }

  async executeSecretCommand(command: "search" | "use" | string, payload: Record<string, unknown>) {
    if (command === "search" || command === "detach_secrets_search_credential") {
      const resultJson = await this.secretBridge.execute({ command: "secrets.search", payload });
      return JSON.parse(resultJson);
    }
    if (command !== "use" && command !== "detach_secrets_use_credential") {
      throw new Error("Unknown secure credential command");
    }

    const prepared = await this.browserBridge.execute({ command: "browser.prepare_secret_fill", payload });
    const resultJson = await this.secretBridge.execute({ command: "secrets.use_browser", payload: { ...payload, prepared } });
    const authorized = JSON.parse(resultJson) as { approved?: boolean; username?: string; password?: string };
    const username = authorized.username;
    const password = authorized.password;
    authorized.username = undefined;
    authorized.password = undefined;
    if (authorized.approved !== true || typeof username !== "string" || typeof password !== "string") {
      throw new Error("Touch ID completed without a valid credential payload.");
    }

    const filled = await this.browserBridge.execute({
      command: "browser.secure_fill",
      payload: { ...payload, username, password },
    }) as {
      filled?: boolean;
      submitted?: boolean;
      inspection?: string;
      navigation?: { changed?: boolean; documentReloaded?: boolean; beforeUrl?: string; afterUrl?: string; title?: string; status?: string };
      next?: string;
    };
    if (!filled.filled) throw new Error("Chrome did not confirm the secure credential fill.");
    return {
      filled: true,
      submitted: filled.submitted === true,
      inspection: filled.inspection || "locked_until_navigation",
      navigation: filled.navigation,
      next: filled.next || (filled.submitted ? "wait_for_navigation" : "submit_required"),
    };
  }

  private async ensureBrowserTask(runId: string) {
    let registered = this.runs.get(runId);
    if (!registered) {
      registered = { runId, allowedUploadPaths: [], browserStartedByBroker: false };
      this.runs.set(runId, registered);
    }
    if (this.browserAutomation.isTaskActive(runId)) return;
    if (registered.startingBrowserTask) return registered.startingBrowserTask;

    const starting = this.browserAutomation.beginTask(runId, registered.allowedUploadPaths, registered.activitySink).then(() => {
      registered!.browserStartedByBroker = true;
    });
    registered.startingBrowserTask = starting;
    try {
      await starting;
    } finally {
      registered.startingBrowserTask = undefined;
    }
  }

  private definition(capabilityId: string) {
    const definition = DEFINITIONS.find((item) => item.id === capabilityId);
    if (!definition) throw new Error(`Unknown Detach capability: ${capabilityId}`);
    return definition;
  }

  private async toDescriptor(definition: CapabilityDefinition): Promise<CapabilityDescriptor> {
    const connection = await this.connection(definition.id);
    return {
      id: definition.id,
      name: definition.name,
      summary: definition.summary,
      whenToUse: definition.whenToUse,
      connection: connection.ready ? "ready" : "needs_connection",
      ...(connection.hint ? { hint: connection.hint } : {}),
      operationCount: definition.tools.length,
    };
  }

  private async connection(capabilityId: CapabilityId) {
    if (capabilityId === "browser") {
      const status = await this.browserAutomation.getStatus();
      return status.extensionConnected && status.runtimeConnected
        ? { ready: true as const }
        : { ready: false as const, hint: "Open the Detach Browser Agent extension popup in signed-in Chrome; it must connect to this runtime." };
    }
    if (capabilityId === "macos") {
      return this.desktopBridge.getStatus().appConnected
        ? { ready: true as const }
        : { ready: false as const, hint: "The Detach macOS app socket is not connected." };
    }
    return this.secretBridge.isAppConnected()
      ? { ready: true as const }
      : { ready: false as const, hint: "The Detach macOS app socket is not connected for Touch ID." };
  }
}
