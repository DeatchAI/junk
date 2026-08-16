export function isAuthorizedRuntimeRequest(req: Request, url: URL, token: string) {
  if (!token) return false;
  return req.headers.get("authorization") === `Bearer ${token}`
    || url.searchParams.get("token") === token;
}

export function isAllowedRuntimeSocketOrigin(
  path: string,
  origin: string | null,
  browserExtensionOrigin: string
) {
  if (path === "/api/browser/native") {
    return origin === null || origin === browserExtensionOrigin;
  }
  return origin === null;
}
