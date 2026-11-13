import { renderConfirmationLanding } from "./confirmation-page.ts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const tokenHash = url.searchParams.get("token_hash");
  const type = url.searchParams.get("type");
  if (type !== null && type !== "email") return renderConfirmationLanding(null);
  return renderConfirmationLanding(tokenHash);
}
