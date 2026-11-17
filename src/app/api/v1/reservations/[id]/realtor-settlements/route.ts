import { handleRealtorSettlementPost } from "@/modules/finance/realtor-settlement-handlers.ts";
import { recordRealtorSettlement } from "@/modules/finance/supabase-realtor-settlement-api.ts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
type Context = { params: Promise<{ id: string }> };

export async function POST(request: Request, context: Context): Promise<Response> {
  const { id } = await context.params;
  return handleRealtorSettlementPost(request, id, recordRealtorSettlement);
}
