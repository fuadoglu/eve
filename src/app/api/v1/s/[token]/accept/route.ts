import { handleTransitionScopedTask } from "@/modules/operations/task-link-http.ts";
import { transitionScopedTask } from "@/modules/operations/supabase-task-link-api.ts";

export const runtime = "nodejs";
export async function POST(request: Request, context: { params: Promise<{ token: string }> }): Promise<Response> {
  const { token } = await context.params;
  return handleTransitionScopedTask(request, token, "accept", transitionScopedTask);
}
