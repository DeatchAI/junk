const MAX_API_KEY_LENGTH = 4096;

class CursorProviderCredentials {
  private savedApiKey?: string;

  get apiKey() {
    return this.savedApiKey;
  }

  setApiKey(value: unknown) {
    if (value === null || value === undefined || value === "") {
      this.savedApiKey = undefined;
      return;
    }
    if (typeof value !== "string") throw new Error("Cursor API key must be text.");
    const apiKey = value.trim();
    if (!apiKey || apiKey.length > MAX_API_KEY_LENGTH || /\s/.test(apiKey)) {
      throw new Error("Enter a valid Cursor API key.");
    }
    this.savedApiKey = apiKey;
  }

  environment() {
    return this.savedApiKey ? { CURSOR_API_KEY: this.savedApiKey } : {};
  }
}

export const cursorProviderCredentials = new CursorProviderCredentials();
