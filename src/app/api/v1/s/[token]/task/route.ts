import { handleReadScopedTask } from "@/modules/operations/task-link-http.ts";
import { readScopedTask } from "@/modules/operations/supabase-task-link-api.ts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export async function GET(request: Request, context: { params: Promise<{ token: string }> }): Promise<Response> {
  const { token } = await context.params;
  return handleReadScopedTask(request, token, readScopedTask);
}
