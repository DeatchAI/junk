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
        "detach_macos_status",
        "detach_macos_list_apps",
        "detach_macos_list_windows",
        "detach_macos_activate_app",
        "detach_macos_open_app",
        "detach_macos_snapshot",
        "detach_macos_screenshot",
        "detach_macos_click",
        "detach_macos_type",
        "detach_macos_key",
        "detach_macos_scroll",
        "detach_request_approval",
      ],
    };
  }
}
