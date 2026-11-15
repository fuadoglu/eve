import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";
import { chromium } from "playwright";
import { createHmac, randomUUID } from "node:crypto";

const baseUrl = "http://localhost:4178";
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
const serviceKey = process.env.EVE_LOCAL_SERVICE_ROLE_KEY || localServiceRoleJwt();
if (!supabaseUrl || !publishableKey || !serviceKey) throw new Error("local_reservation_test_configuration_missing");

const suffix = randomUUID().replaceAll("-", "");
const email = `eve-reservation-${suffix}@example.test`;
const password = `${randomUUID()}aA1!`;
const ownerAccountId = randomUUID();
const propertyId = randomUUID();
let nextServer;
let browser;
let serverDiagnostics = "";

try {
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: createdUser, error: createError } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (createError || !createdUser.user) throw new Error("local_auth_fixture_creation_failed");

  const userClient = createClient(supabaseUrl, publishableKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: signedIn, error: signInError } = await userClient.auth.signInWithPassword({ email, password });
  if (signInError || !signedIn.session) throw new Error("local_auth_fixture_sign_in_failed");
  const { data: activeSession, error: activeSessionError } = await userClient.schema("api").rpc("is_my_session_active");
  const { data: propertyContexts, error: propertyContextError } = await userClient.schema("api").rpc("list_reservable_property_contexts");
  if (activeSessionError || activeSession !== true || propertyContextError || !Array.isArray(propertyContexts) || propertyContexts.length !== 0) {
    throw new Error(`local_authenticated_context_preflight_failed:${activeSessionError?.code ?? propertyContextError?.code ?? String(activeSession)}:${Array.isArray(propertyContexts) ? propertyContexts.length : "invalid"}`);
  }

  const fixtureSql = `
    insert into app_private.owner_accounts(id,owner_user_id) values ('${ownerAccountId}','${createdUser.user.id}');
    insert into app_private.properties(id,owner_account_id,name,area,max_guests,default_check_in,default_check_out)
      values ('${propertyId}','${ownerAccountId}','E2E test home','Bakı',4,'15:00','11:00');
    insert into app_private.subscriptions(owner_account_id,property_id,state,current_end)
      values ('${ownerAccountId}','${propertyId}','trialing',now()+interval '7 days');
  `;
  const fixture = spawnSync("docker", ["exec", "-i", "supabase_db_eve", "psql", "-U", "supabase_admin", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-q"], {
    input: fixtureSql,
    encoding: "utf8",
    stdio: ["pipe", "ignore", "pipe"],
  });
  if (fixture.status !== 0) throw new Error("local_reservation_fixture_database_insert_failed");
  const { data: populatedContexts, error: populatedContextError } = await userClient.schema("api").rpc("list_reservable_property_contexts");
  if (populatedContextError || !Array.isArray(populatedContexts) || !populatedContexts.some((property) => property.id === propertyId)) {
    throw new Error(`local_property_context_preflight_failed:${populatedContextError?.code ?? "property_context_missing"}`);
  }

  const childEnv = { ...process.env };
  delete childEnv.EVE_LOCAL_SERVICE_ROLE_KEY;
  delete childEnv.SERVICE_ROLE_KEY;
  delete childEnv.SECRET_KEY;
  delete childEnv.SUPABASE_SECRET_KEY;
  delete childEnv.JWT_SECRET;
  delete childEnv.PGRST_JWT_SECRET;
  childEnv.APP_BASE_URL = baseUrl;
  nextServer = spawn("node", ["node_modules/next/dist/bin/next", "start", "--port", "4178"], {
    env: childEnv,
    stdio: ["ignore", "ignore", "pipe"],
  });
  nextServer.stderr.setEncoding("utf8").on("data", (chunk) => {
    serverDiagnostics = `${serverDiagnostics}${chunk}`.slice(-8000);
  });
  await waitForServer(baseUrl);

  browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const cookieName = `sb-${new URL(supabaseUrl).hostname.split(".")[0]}-auth-token`;
  let serializedCookies = [];
  const serverAuthClient = createServerClient(supabaseUrl, publishableKey, {
    cookies: {
      getAll: () => serializedCookies,
      setAll: (cookies) => { serializedCookies = cookies; },
    },
  });
  const { error: cookieSessionError } = await serverAuthClient.auth.setSession(signedIn.session);
  if (cookieSessionError || !serializedCookies.some((cookie) => cookie.name === cookieName)) {
    throw new Error("local_ssr_cookie_serialization_failed");
  }
  const cookieProbe = createServerClient(supabaseUrl, publishableKey, {
    cookies: { getAll: () => serializedCookies, setAll: (cookies) => { serializedCookies = cookies; } },
  });
  const { data: cookieProbeUser, error: cookieProbeError } = await cookieProbe.auth.getUser();
  const { data: cookieProbeActive, error: cookieProbeActiveError } = await cookieProbe.schema("api").rpc("is_my_session_active");
  if (cookieProbeError || !cookieProbeUser.user || cookieProbeActiveError || cookieProbeActive !== true) {
    throw new Error(`local_ssr_cookie_preflight_failed:${cookieProbeError?.status ?? cookieProbeActiveError?.code ?? String(cookieProbeActive)}`);
  }
  await context.addCookies(serializedCookies.map(({ name, value }) => ({
    name, value, url: baseUrl, httpOnly: true, sameSite: "Lax",
  })));
  const installedCookieNames = (await context.cookies(baseUrl)).map((cookie) => cookie.name);
  if (!installedCookieNames.includes(cookieName)) throw new Error("local_browser_auth_cookie_install_failed");
  const page = await context.newPage();
  const browserDiagnostics = [];
  page.on("pageerror", (error) => browserDiagnostics.push(`pageerror:${error.name}:${error.message.slice(0, 180)}`));
  page.on("console", (message) => {
    if (message.type() === "error") browserDiagnostics.push(`console:${message.text().slice(0, 180)}`);
  });
  await page.addInitScript(() => {
    Object.defineProperty(window.navigator, "onLine", {
      configurable: true,
      get: () => window.__eveTestOnline !== false,
    });
  });
  let navigationCookieHeader = "";
  page.on("request", (request) => {
    if (request.url() === `${baseUrl}/calendar`) {
      void request.allHeaders().then((headers) => { navigationCookieHeader = headers.cookie ?? ""; });
    }
  });
  await page.goto(`${baseUrl}/calendar`, { waitUntil: "networkidle" });
  const propertyHeading = page.locator(".reservation-create-property").getByRole("heading", { name: "E2E test home" }).first();
  try {
    await propertyHeading.waitFor({ timeout: 10000 });
  } catch {
    const visibleText = (await page.locator("body").innerText()).replace(/\s+/g, " ").trim();
    const safeDiagnostics = serverDiagnostics.split("\n").filter((line) => line.includes("reservation_property_context_load_failed")).join(" | ");
    throw new Error(`authenticated property context was not rendered (auth_cookie_sent=${navigationCookieHeader.includes(cookieName)}; server=${safeDiagnostics || "no-safe-diagnostic"}): ${visibleText}`);
  }
  await page.getByRole("button", { name: "Təsdiqlə" }).click();
  try { await page.locator(".reservation-field-error").first().waitFor({ timeout: 20000 }); }
  catch {
    const diagnostics = browserDiagnostics.join(" | ") || "no-browser-errors";
    throw new Error(`reservation client validation did not hydrate: ${diagnostics}`);
  }
  await page.getByLabel("Giriş tarixi").fill("2027-08-01");
  await page.getByLabel("Çıxış tarixi").fill("2027-08-04");
  await page.getByLabel("Qonağın adı").fill("Synthetic guest");
  await page.getByLabel("Ümumi qiymət (AZN)").fill("300,00");
  await page.locator(".reservation-more summary").click();
  await page.getByLabel("Alınan pul (AZN, istəyə bağlı)").fill("100,00");
  await page.evaluate(() => { window.__eveTestOnline = false; });
  await page.getByRole("button", { name: "Təsdiqlə" }).click();
  const offlineError = page.locator(".reservation-request-error");
  try { await offlineError.waitFor({ timeout: 5000 }); }
  catch {
    const visibleText = (await page.locator("body").innerText()).replace(/\s+/g, " ").trim();
    throw new Error(`offline submission feedback missing: ${visibleText}`);
  }
  assert.equal(await offlineError.innerText(), "Bağlantı yoxdur. Son dəyişiklik hələ saxlanılmayıb.");
  assert.equal(await page.getByRole("heading", { name: "Pul xülasəsi" }).count(), 0);
  await page.evaluate(() => { window.__eveTestOnline = true; });
  await page.getByLabel("Qonağın adı").fill("Synthetic guest");
  const createRequest = page.waitForRequest((request) => request.url().endsWith("/api/v1/reservations") && request.method() === "POST");
  const createResponse = page.waitForResponse((response) => response.url().endsWith("/api/v1/reservations") && response.request().method() === "POST");
  await page.getByRole("button", { name: "Təsdiqlə" }).click();
  const capturedRequest = await createRequest;
  const firstResponse = await createResponse;
  const firstResponseText = await firstResponse.text();
  let firstEnvelope = null;
  try { firstEnvelope = JSON.parse(firstResponseText); } catch { /* report a bounded response category below */ }
  if (firstResponse.status() !== 201) {
    const capturedHeaders = await capturedRequest.allHeaders();
    const errorCode = typeof firstEnvelope?.error?.code === "string" ? firstEnvelope.error.code : "unknown_error";
    const publicError = firstEnvelope?.error?.message;
    const routeFailure = publicError === "Sorğu bu mənbədən qəbul edilmir." ? "origin_rejected"
      : publicError === "Bu evdə rezervasiya yaratmaq icazəsi yoxdur." ? "database_forbidden" : "other_route_error";
    const requestOrigin = capturedHeaders.origin ?? "missing";
    const requestReferer = capturedHeaders.referer ? new URL(capturedHeaders.referer).origin : "missing";
    const fetchSite = capturedHeaders["sec-fetch-site"] ?? "missing";
    const sameOriginMarker = capturedHeaders["x-eve-same-origin"] ?? "missing";
    const requestHost = new URL(capturedRequest.url()).origin;
    const originDiagnostics = serverDiagnostics.split("\n").filter((line) => line.includes("reservation_origin_rejected")).join(" | ") || "no-server-origin-diagnostic";
    const directCreate = await userClient.schema("api").rpc("create_reservation", {
      p_input: capturedRequest.postDataJSON(),
      p_idempotency_key: capturedRequest.headers()["idempotency-key"],
    });
    const directFailure = directCreate.error ? sanitizeDatabaseFailure(directCreate.error.message) : "success";
    const directRead = directCreate.data && typeof directCreate.data.reservation_id === "string"
      ? await userClient.schema("api").rpc("get_reservation", { p_reservation_id: directCreate.data.reservation_id })
      : null;
    const readFailure = directRead?.error ? sanitizeDatabaseFailure(directRead.error.message) : directRead ? "success" : "not_attempted";
    const bodyKind = firstResponseText.length === 0 ? "empty" : firstResponseText.startsWith("<!DOCTYPE") ? "html" : firstEnvelope ? "json" : "other";
    throw new Error(`reservation_create_http_failed:${firstResponse.status()}:${firstResponse.headers().get("content-type") ?? "no_content_type"}:${bodyKind}:${errorCode}:${routeFailure}:origin=${requestOrigin}:referer=${requestReferer}:fetch_site=${fetchSite}:same_origin_marker=${sameOriginMarker}:request=${requestHost}:server=${originDiagnostics}:direct_create=${directFailure}:direct_read=${readFailure}`);
  }
  if (!firstEnvelope || typeof firstEnvelope !== "object") throw new Error(`reservation_create_http_invalid_json:${firstResponse.status()}`);
  await page.getByRole("heading", { name: "Pul xülasəsi" }).waitFor();
  const createdText = await page.locator(".reservation-card").innerText();
  assert.match(createdText, /Balans serverdən alınıb/);
  assert.match(createdText, /200,00/);
  const body = capturedRequest.postDataJSON();
  const key = capturedRequest.headers()["idempotency-key"];
  assert.equal(typeof key, "string");
  const retryResponse = await page.request.post(`${baseUrl}/api/v1/reservations`, {
    headers: { Origin: baseUrl, "Idempotency-Key": key, "Content-Type": "application/json" },
    data: body,
  });
  assert.equal(retryResponse.status(), 201);
  const firstDto = await retryResponse.json();
  assert.equal(firstDto.data.guest_name, "Synthetic guest");
  assert.equal(firstDto.data.id, firstEnvelope.data.id);
  assert.equal(firstDto.data.balance.rent_received_minor, 10000);
  assert.equal(firstDto.data.balance.remaining_minor, 20000);

  const countResult = spawnSync("docker", ["exec", "-i", "supabase_db_eve", "psql", "-U", "supabase_admin", "-d", "postgres", "-Atqc",
    `select (select count(*) from app_private.reservations where id='${firstEnvelope.data.id}')::text || ':' || (select count(*) from app_private.rent_entries where reservation_id='${firstEnvelope.data.id}')::text;`], {
    encoding: "utf8", stdio: ["ignore", "pipe", "pipe"],
  });
  if (countResult.status !== 0) throw new Error("reservation_retry_database_count_failed");
  assert.equal(countResult.stdout.trim(), "1:1");

  const conflictResponse = await page.request.post(`${baseUrl}/api/v1/reservations`, {
    headers: { Origin: baseUrl, "Idempotency-Key": `reservation-conflict-${suffix}`, "Content-Type": "application/json" },
    data: { ...body, guest_name: "Other synthetic guest" },
  });
  assert.equal(conflictResponse.status(), 409);
  console.log("PASS reservation browser E2E: authenticated property context, mobile offline guard, server acknowledgement/balance, DB-backed idempotent retry and occupancy conflict");
  await context.close();
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`FAIL reservation browser E2E: ${message}`);
  process.exitCode = 1;
} finally {
  await browser?.close();
  if (nextServer && !nextServer.killed) nextServer.kill("SIGTERM");
}

async function waitForServer(url) {
  for (let attempt = 0; attempt < 45; attempt++) {
    try {
      const response = await fetch(url, { redirect: "manual" });
      if (response.status < 500) return;
    } catch { /* the local Next server has not bound its port yet */ }
    await delay(1000);
  }
  throw new Error("next_server_start_failed");
}

function localServiceRoleJwt() {
  const inspected = spawnSync("docker", ["inspect", "supabase_rest_eve"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  if (inspected.status !== 0) throw new Error("local_jwt_fixture_configuration_missing");
  const environment = JSON.parse(inspected.stdout)[0]?.Config?.Env ?? [];
  const config = environment.find((item) => item.startsWith("PGRST_JWT_SECRET="))?.split("=", 2)[1];
  const jwk = config ? JSON.parse(config).keys?.find((item) => item.kty === "oct") : null;
  if (!jwk?.k) throw new Error("local_jwt_fixture_configuration_missing");
  const key = Buffer.from(jwk.k, "base64url");
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const signingInput = `${encode({ alg: "HS256", typ: "JWT" })}.${encode({
    role: "service_role", sub: "00000000-0000-4000-8000-000000000000", aud: "authenticated",
    iat: now, exp: now + 300,
  })}`;
  const signature = createHmac("sha256", key).update(signingInput).digest("base64url");
  return `${signingInput}.${signature}`;
}

function sanitizeDatabaseFailure(message) {
  if (message.includes("active_entitlement_required")) return "active_entitlement_required";
  if (message.includes("active_session_required")) return "active_session_required";
  if (message.includes("receipt_owner_must_be_actor")) return "receipt_owner_must_be_actor";
  if (message.includes("receipt_manager_must_be_actor")) return "receipt_manager_must_be_actor";
  if (message.startsWith("permission denied for function")) return "permission_denied_for_function";
  if (message.startsWith("permission denied for schema")) return "permission_denied_for_schema";
  return "other_database_error";
}
