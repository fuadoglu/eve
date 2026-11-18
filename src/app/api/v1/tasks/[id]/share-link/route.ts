import { handleCreateTaskLink } from "@/modules/operations/task-link-http.ts";
import { createTaskShareLink } from "@/modules/operations/supabase-task-link-api.ts";

export const runtime = "nodejs";
export async function POST(request: Request, context: { params: Promise<{ id: string }> }): Promise<Response> {
  const { id } = await context.params;
  return handleCreateTaskLink(request, id, createTaskShareLink);
}
