const DISPLAY_PREFIXES = [
  "artifacts.composio.io/proxy/composio-rodent/008971668139.dkr.ecr.us-east-1.amazonaws.com/composio-self-host/",
  "008971668139.dkr.ecr.us-east-1.amazonaws.com/composio-self-host/",
  "proxy.replicated.com/library/",
];

export function displayImageName(image) {
  const value = String(image || "unknown");
  for (const prefix of DISPLAY_PREFIXES) {
    if (value.startsWith(prefix)) {
      return value.slice(prefix.length);
    }
  }
  return value;
}
