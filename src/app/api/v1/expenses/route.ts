import { handleExpenseProposalPost } from "@/modules/finance/expense-proposal-handler.ts";
import { createExpenseProposal } from "@/modules/finance/supabase-expense-proposal-api.ts";

export async function POST(request: Request): Promise<Response> {
  return handleExpenseProposalPost(request, createExpenseProposal);
}
