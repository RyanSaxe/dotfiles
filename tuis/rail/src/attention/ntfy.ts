export interface NtfyMessage {
  title: string;
  body: string;
  priority: "default" | "high";
  tags: string[];
}

export function ntfyEndpoint(
  env: NodeJS.ProcessEnv = process.env,
): string | null {
  return (
    env["AI_HARNESS_NTFY_URL"] ??
    (env["AGENT_NOTIFICATION_ID"]
      ? `https://ntfy.sh/ai-agent-notification-${env["AGENT_NOTIFICATION_ID"]}`
      : null)
  );
}

export async function sendNtfy(
  message: NtfyMessage,
  endpoint = ntfyEndpoint(),
): Promise<void> {
  if (endpoint === null) {
    throw new Error(
      "no ntfy channel configured; set AGENT_NOTIFICATION_ID or AI_HARNESS_NTFY_URL",
    );
  }
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      Title: message.title,
      Priority: message.priority,
      Tags: message.tags.join(","),
    },
    body: message.body,
  });
  if (!response.ok) {
    throw new Error(`ntfy returned HTTP ${response.status}`);
  }
}
