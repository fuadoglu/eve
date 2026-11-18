import { handleRevokeTaskLink } from "@/modules/operations/task-link-http.ts";
import { revokeTaskShareLink } from "@/modules/operations/supabase-task-link-api.ts";

export const runtime = "nodejs";
export async function DELETE(request: Request, context: { params: Promise<{ id: string }> }): Promise<Response> {
  const { id } = await context.params;
  return handleRevokeTaskLink(request, id, revokeTaskShareLink);
}
