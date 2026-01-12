import { headers } from "next/headers";
import { supabaseFromAuthHeader } from "@/lib/supabase/serverFromAuthHeader";
import { getCapabilities } from "./capabilities.server";
import { mapCapabilities } from "./capabilities";
import type { CapabilityKey } from "./capabilities";

export async function getServerCapabilitiesFromHeaders(): Promise<Record<string, boolean>> {
  const h = headers();
  // Construct a Request so supabaseFromAuthHeader can read headers.get('authorization')
  const req = new Request("http://localhost", { headers: h as unknown as HeadersInit });
  const supabase = supabaseFromAuthHeader(req);
  const capsRes = await getCapabilities(supabase);
  return capsRes.capabilities ?? mapCapabilities();
}

export async function requireServerCapability(key: CapabilityKey) {
  const caps = await getServerCapabilitiesFromHeaders();
  if (!caps[key]) {
    // throw so caller (server component) can catch and redirect/render Forbidden
    throw new Error("forbidden");
  }
  return caps;
}
