# Detach demo mode

Debug builds can run eight scripted demo tasks without launching Codex, Claude, Grok, or any hosted AI model. Paste one of the prompts below exactly into the floating composer:

```text
Triage the failed CI run for this PR and draft a review note with evidence.
Check onboarding readiness for our new hire starting Monday.
Review our top five SaaS renewals and flag anything that needs attention.
Verify the claims in this market brief against the current sources.
Prepare a source-backed brief for my Acme discovery call.
Build a dashboard to make our research findings interactive.
Get my paystubs for this month.
Reply to all comments my X post has received.
```

Each scenario uses the normal chat, history, structured activity, multi-window, and notch lifecycle. The data and results are fictional and intended only for product demos. The paystub flow does not access a real portal, credential, or document; the X flow only stages replies and never posts them.

Runs are intentionally paced like a real agent: a substantial planning pause, an early conversational response, workspace-memory and connected-tool checks, interleaved progress updates, evidence-gathering activity, and then the final result. A typical scenario takes roughly 35 seconds.

Release builds do not enable this path. If a prompt does not match one of the strings above, the request follows the normal agent path.
