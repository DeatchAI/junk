# Detach demo mode

Debug builds can run eight scripted demo tasks without launching Codex, Claude, Grok, or any Detach Cloud model. Each task names the context it needs, and the Debug shortcut attaches a small deterministic set of fixture files or folders before typing the prompt.

```text
Review the attached checkout pull request, test changes, and CI notes for bugs, regressions, and missing tests.
Fix the failing tests in the attached project files, run the relevant checks, and show me the diff.
Open the staging checkout URL from the attached runbook, reproduce the payment bug, and tell me what broke.
Use the attached pricing brief to compare the current plans for these tools and cite the live sources.
Review the attached Downloads folder and propose a cleaner project-based organization without deleting anything.
Build a small dashboard from the attached usage CSV and run it locally.
Log in to the admin dashboard and export this month's usage report using the attached report specification.
Summarize the attached meeting transcript and turn the action items into a checklist.
```

While filming, choose **Agent**, focus the floating composer, and press `Fn+1` through `Fn+8`. In Debug builds the composer walks through the real menus before typing: it opens the attachment picker, attaches the scenario’s fixture folders/files, selects only the required capabilities, opens the command picker, selects the relevant command, and then types the matching prompt one character at a time. The prompt is not submitted automatically. The selected attachments, MCP capabilities, and command remain attached if you press Send afterward.

The capability selection is intentionally different per task:

| shortcut | visible context | capabilities |
| --- | --- | --- |
| Fn+1 | checkout pull request, tests, and CI notes | none |
| Fn+2 | test-fix project and regression test | none |
| Fn+3 | staging checkout runbook | Browser |
| Fn+4 | pricing brief | Browser |
| Fn+5 | Downloads folder and example files | macOS |
| Fn+6 | usage dashboard folder and CSV | none |
| Fn+7 | report specification | Browser, Secrets |
| Fn+8 | meeting transcript | none |

The first scenario therefore shows concrete pull-request attachments instead of unrelated tool tags. The fixture set is deterministic so repeated takes produce the same composer state. Secrets is only selected for the admin-dashboard login flow; Browser does not automatically add it.

Each scenario uses the normal chat, history, structured activity, multi-window, and notch lifecycle. The data and results are fictional and intended only for product demos. The paystub flow does not access a real portal, credential, or document; the X flow only stages replies and never posts them.

Runs are intentionally paced like a real agent: a substantial planning pause, an early conversational response, workspace-memory and connected-tool checks, interleaved progress updates, evidence-gathering activity, and then the final result. A typical scenario takes roughly 35 seconds.

The menu walkthrough adds the real file/folder and capability tokens plus a built-in slash command to the typed field. Debug matching removes those known demo tokens before selecting the scripted scenario, while the real attachments and MCP selections still travel with the request.

## Image demo tasks

Debug builds also support three scripted image generations. Switch the composer to **Image** and paste one of these prompts exactly:

While filming, the prompts can be inserted with the temporary Debug-only simulator: choose **Image** or **Video**, focus the floating composer, and press `Fn+1`, `Fn+2`, or `Fn+3`. The matching prompt for the selected media mode is typed into the field one character at a time and is not submitted automatically.

```text
Ultra realistic editorial photography, decisive moment in a premium restaurant kitchen. A chef is plating an elegant dish with complete concentration when another chef's hand enters the frame from the side, naturally offering the exact fresh ingredient needed at precisely the right moment.

A cinematic alternative rock band performing in a vast abstract black space, no stage, no audience, no architecture, deep black background with subtle depth. wearing a black turtleneck and long black coat, looking directly into the camera with calm psychological presence

A foreign tourist with a warm grateful smile, Western facial features, looking touched and appreciative after receiving help, soft warm lighting, genuine emotional expression, vertical composition, photorealistic cinematic style
```

The image response uses the matching numbered file from `~/Downloads/demo-mode/images/`:

```text
1.png → prompt 1
2.png → prompt 2
3.png → prompt 3
```

The local runtime simulates the media-job lifecycle and serves the local file to the composer. It does not call a hosted image model or consume credits. Release builds do not enable this path.

If a prompt does not match one of the supported demo strings, the request follows the normal agent or hosted-media path.

## Video demo tasks

Debug builds also support three scripted video generations. Switch the composer to **Video**, then use the same `Fn+1`, `Fn+2`, or `Fn+3` simulator shortcuts:

```text
SEQUENCE SHOT. NO CUT.
Single unbroken handheld take throughout, 30 seconds total.

Young Caucasian woman,  wearing a yellow and green Brazil national football jersey and white denim shorts, sitting pensively on a sofa inside a large bright suburban Parisian house, summer daytime, sunlight through the windows, young adults dancing and laughing around her holding drinks, loud music implied by energetic crowd movement

An average shift at Waffle House - make sure it's retarded and gets 50 likes.

Sum up the AI discourse in a meme - make sure it’s retarded and gets 50 likes.
```

The video response uses the matching numbered MP4 from `~/Downloads/demo-mode/videos/`:

```text
1.mp4 → prompt 1
2.mp4 → prompt 2
3.mp4 → prompt 3
```

The local runtime simulates the video-job lifecycle and serves the local file to the composer. It does not call a hosted video model or consume credits. Release builds do not enable this path.
