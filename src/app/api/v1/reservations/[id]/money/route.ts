import { handleRentEntryGet, handleRentEntryPost } from "@/modules/finance/rent-entry-handlers.ts";
import { createRentEntry, listRentEntries } from "@/modules/finance/supabase-rent-entry-api.ts";

type Context = { params: Promise<{ id: string }> };

export async function GET(request: Request, context: Context): Promise<Response> {
  const { id } = await context.params;
  return handleRentEntryGet(request, id, listRentEntries);
}

export async function POST(request: Request, context: Context): Promise<Response> {
  const { id } = await context.params;
  return handleRentEntryPost(request, id, createRentEntry);
}
