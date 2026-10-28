export function executableSearchDirs(): string[] {
  const home = Bun.env.HOME;
  const applicationRoots = [
    ...(home ? [`${home}/Applications`] : []),
    "/Applications",
  ];
  const bundledCLIDirs = applicationRoots.flatMap((root) =>
    ["ChatGPT.app", "Codex.app"].flatMap((app) => {
      const resources = `${root}/${app}/Contents/Resources`;
      return [
        resources,
        `${resources}/codex-cli/CodexCLI.app/Contents/MacOS`,
      ];
    }),
  );

  return [
    ...(home ? [`${home}/.grok/bin`, `${home}/.local/bin`, `${home}/.bun/bin`, `${home}/.amp/bin`, `${home}/.npm-global/bin`] : []),
    ...bundledCLIDirs,
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin",
  ];
}
