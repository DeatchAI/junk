import type { GitReviewService } from "../git/GitReviewService";

/** Called only after RuntimeServer validates the per-launch app bearer token. */
export async function gitResponse(request: Request, service: GitReviewService) {
  const reply = (value: unknown, status = 200) => Response.json(value, { status, headers: { "Cache-Control": "no-store" } });
  if (request.headers.has("origin")) return reply({ error: "Browser access to local project changes is not allowed." }, 403);
  const url = new URL(request.url), route = url.pathname.replace("/api/git/", "");
  try {
    if (request.method === "GET") {
      if (route === "settings") return reply(service.settings());
      const workspace = url.searchParams.get("workspace");
      if (!workspace) return reply({ error: "Choose a project folder." }, 400);
      if (route === "working-status") return reply(await service.workingStatus(workspace));
      if (route === "session-status") {
        const conversation = url.searchParams.get("conversation");
        if (!conversation) throw new Error("Choose a conversation.");
        return reply(await service.sessionStatus(workspace, conversation));
      }
      if (route === "tasks") return reply({ tasks: await service.tasks(workspace, url.searchParams.get("conversation") ?? undefined) });
      if (route === "review" && url.searchParams.get("scope") === "session") {
        const conversation = url.searchParams.get("conversation");
        if (!conversation) return reply({ error: "Choose a conversation to review." }, 400);
        return reply(await service.sessionReview(workspace, conversation));
      }
      if (route === "review") return reply(await service.review(workspace, url.searchParams.get("run") ?? undefined, url.searchParams.get("scope") === "project"));
    }
    if (request.method !== "POST") return reply({ error: "Unsupported Git review request." }, 405);
    if (Number(request.headers.get("content-length") ?? 0) > 64_000) return reply({ error: "Request is too large." }, 413);
    const text = await request.text(); if (text.length > 64_000) return reply({ error: "Request is too large." }, 413);
    const body = JSON.parse(text) as Record<string, unknown>;
    if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error("Invalid Git review request.");
    const keys = (allowed: string[]) => { if (Object.keys(body).some(key => !allowed.includes(key))) throw new Error("Unexpected Git review fields."); };
    if (route === "settings") {
      keys(["enabled", "clear"]);
      if ((body.enabled !== undefined && typeof body.enabled !== "boolean") || (body.clear !== undefined && body.clear !== true)
        || (body.enabled === undefined && body.clear !== true)) throw new Error("Invalid snapshot settings.");
      return reply(service.settings(body.enabled as boolean | undefined, body.clear === true));
    }
    if (route === "preview") {
      keys(["workspace", "run", "conversation", "paths", "undo"]);
      if (typeof body.workspace === "string" && typeof body.conversation === "string" && body.run === undefined && body.paths === undefined && (body.undo === undefined || typeof body.undo === "boolean"))
        return reply(await service.previewSession(body.workspace, body.conversation, body.undo === true));
      if (typeof body.workspace !== "string" || typeof body.run !== "string"
        || (body.undo !== undefined && typeof body.undo !== "boolean")
        || (body.paths !== undefined && (!Array.isArray(body.paths) || !body.paths.every(path => typeof path === "string")))) throw new Error("Invalid restore selection.");
      return reply(await service.preview(body.workspace, body.run, body.paths as string[] | undefined, body.undo === true));
    }
    if (route === "commit-preview") {
      keys(["workspace", "scope", "id", "paths", "branch"]);
      if (typeof body.workspace !== "string" || !["project", "task", "session"].includes(String(body.scope)) ||
        (body.id !== undefined && typeof body.id !== "string") || typeof body.branch !== "string" ||
        !Array.isArray(body.paths) || !body.paths.every(path => typeof path === "string")) throw new Error("Invalid commit selection.");
      if (body.scope !== "project" && typeof body.id !== "string") throw new Error("Choose a task or conversation.");
      return reply(await service.previewCommit(body.workspace, String(body.scope), body.id as string | undefined, body.paths as string[], body.branch));
    }
    if (route === "commit") {
      keys(["plan", "message"]);
      if (typeof body.plan !== "string" || typeof body.message !== "string") throw new Error("Review the selected files and enter a commit message.");
      return reply(await service.commit(body.plan, body.message));
    }
    if (route === "push") {
      keys(["workspace", "head", "branch", "remote", "remoteBranch"]);
      if (["workspace", "head", "branch", "remote", "remoteBranch"].some(key => typeof body[key] !== "string")) throw new Error("Choose the branch and remote to push.");
      return reply(await service.push(body.workspace as string, { head: body.head as string, branch: body.branch as string, remote: body.remote as string, remoteBranch: body.remoteBranch as string }));
    }
    if (route === "apply") {
      keys(["plan"]);
      if (typeof body.plan !== "string") throw new Error("Review a restore preview first.");
      return reply(await service.apply(body.plan));
    }
    return reply({ error: "Unknown Git review endpoint." }, 404);
  } catch (error) { return reply({ error: error instanceof Error ? error.message : "Git review is unavailable." }, 400); }
}
