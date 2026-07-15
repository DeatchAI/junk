# AGENTS.md — Detach

Detach is an inline AI assistant for macOS. Floating AI chat is triggered by text/file selection anywhere.

## Architecture
- **lazzy/** — Native macOS SwiftUI app (Xcode project: `lazzy.xcodeproj`)
- **server/** — Bun WebSocket server with Vercel AI SDK, multi-provider (OpenAI, Anthropic, Google, etc.)
- **web/** — Next.js 16 marketing/dashboard site with Supabase auth
- **ilazzy/** — iOS companion app (WIP)

## Commands
```bash
# Server (requires Bun)
cd server && bun run build        # Compile to lazzy-server binary
bun run index.ts                  # Dev mode

# Web
cd web && bun dev                 # Next.js dev server
cd web && bun run lint            # ESLint

# macOS app: Build via Xcode (⌘B) or xcodebuild
```

## Code Style
- **Swift**: SwiftUI declarative, async/await, Core/ for shared logic, UI/ for views
- **TypeScript**: Strict mode, Zod for validation, ES modules, functional patterns
- **Naming**: camelCase (TS), PascalCase types/components, snake_case DB columns
- **Imports**: Group by external → internal → relative; avoid default exports in TS

# Adding a New AI Model to Lazzy

This guide documents the process of adding a new AI model to both the server-side registry and the iOS client UI.

---

## 🚀 Overview

Adding a model involves four main steps:
1.  **Registering** the model on the server.
2.  **Updating** the client-side provider lists.
3.  **Configuring** feature gating (Free vs. Premium).
4.  **Handling** BYOK (Bring Your Own Key) support.

---

## 🛠️ Step 1: Server-Side Registration

All models are defined in the backend registry.

### 1.1 Update `server/src/ai/registry.ts`
Add your model to the `MODELS` constant.

```typescript
// server/src/ai/registry.ts

export const MODELS: Record<string, AIModel> = {
    // ... existing models
    "my-new-model": {
        displayName: "My New Model",
        provider: "openai", // Must be one of the supported Provider types
        modelId: "gpt-new-special", // Actual ID used by the provider SDK/Gateway
        tier: "premium", // "free" or "premium"
        pricing: { 
            inputPricePer1M: 0.50, 
            outputPricePer1M: 1.50 
        }
    },
};
```

> [!IMPORTANT]
> The **key** used in the `MODELS` object (e.g., `"my-new-model"`) must be the lowercase, trimmed version of the name sent by the iOS client.

### 1.2 Update `server/src/ai/models.ts` (If needed)
If you added a **new provider**, you must update the `createModel` function to handle its initialization when BYOK is active.

```typescript
// server/src/ai/models.ts

function createModel(mapping: ModelMapping): LanguageModel {
    if (isBYOKActive) {
        switch (mapping.provider) {
            case "new-provider":
                const sdk = createNewProviderSDK({ apiKey: process.env.NEW_PROVIDER_API_KEY });
                return sdk(mapping.modelId);
            // ...
        }
    }
    // ...
}
```

---

## 📱 Step 2: Client-Side Configuration

The iOS app needs to know about the new model to display it in the settings menu.

### 2.1 Update `lazzy/Models/BYOKSettings.swift`
Add the model's display name to the `models` computed property of the `AIProvider` enum.

```swift
// lazzy/Models/BYOKSettings.swift

enum AIProvider: String, ... {
    // ...
    var models: [String] {
        switch self {
        case .openai:
            return [
                "GPT-4o",
                "My New Model", // Add here
                // ...
            ]
        // ...
    }
}
```

### 2.2 Update `lazzy/Models/FeatureGating.swift`
Define whether the model is available to free users or requires a premium subscription.

```swift
// lazzy/Models/FeatureGating.swift

struct FeatureGating {
    static let freeTierModels: Set<String> = [
        "Gemini 2.5 Flash",
        // ...
    ]

    static let premiumModels: Set<String> = [
        "My New Model", // Add here if premium
        "GPT-4o",
        // ...
    ]
}
```

---

## 🧪 Step 3: Verification

1.  **Restart the Server**: Ensure the backend picks up the new registry entry.
2.  **Run the iOS App**:
    *   Navigate to **Settings > General**.
    *   Check the **Default Model** dropdown.
    *   Verify if the model is correctly enabled/disabled based on your current account tier.
3.  **Test BYOK**: If you have an API key for the new model, enable BYOK mode and verify that requests are routed correctly via the provider SDK instead of the AI Gateway.

---

## 📝 Naming Conventions

| Component | Example | Notes |
| :--- | :--- | :--- |
| **Display Name** | `Claude 3.5 Sonnet` | Used in the UI and `registry.ts`'s `displayName`. |
| **Registry Key** | `claude 3.5 sonnet` | Must be lowercase and match the normalized UI name. |
| **Model ID** | `claude-3-5-sonnet-latest` | The actual technical ID used for API calls. |
| **Provider** | `anthropic` | Must match one of the string literals in `Provider` type. |
