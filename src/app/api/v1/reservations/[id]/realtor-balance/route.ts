import { handleRealtorBalanceGet } from "@/modules/finance/realtor-settlement-handlers.ts";
import { getRealtorBalance } from "@/modules/finance/supabase-realtor-settlement-api.ts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
type Context = { params: Promise<{ id: string }> };

export async function GET(request: Request, context: Context): Promise<Response> {
  const { id } = await context.params;
  return handleRealtorBalanceGet(request, id, getRealtorBalance);
}
