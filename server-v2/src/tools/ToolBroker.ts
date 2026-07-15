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
        "detach_browser_status",
        "detach_browser_list_tabs",
        "detach_browser_active_tab",
        "detach_browser_open_tab",
        "detach_browser_snapshot",
        "detach_browser_extract_text",
        "detach_browser_click",
        "detach_browser_type",
        "detach_browser_select",
        "detach_browser_scroll",
        "detach_browser_screenshot",
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
