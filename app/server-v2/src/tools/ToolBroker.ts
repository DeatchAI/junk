import { MACOS_TOOL_NAMES } from "../desktop/DesktopTools";

export interface ToolBrokerSummary {
  mode: "compact";
  tools: string[];
}

export class ToolBroker {
  summary(): ToolBrokerSummary {
    return {
      mode: "compact",
      tools: [
        "detach_get_context",
        "detach_code_task",
        "detach_browser_execute",
        ...MACOS_TOOL_NAMES,
        "detach_request_approval",
      ],
    };
  }
}
