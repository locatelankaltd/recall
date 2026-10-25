import { createClient } from 'jsr:@supabase/supabase-js@2';
import { createBillingHandlers } from './billing.ts';
const client = (service = false, token?: string) => {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get(service ? 'SUPABASE_SERVICE_ROLE_KEY' : 'SUPABASE_ANON_KEY');
  if (!url || !key) throw new Error('Billing server configuration unavailable');
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false }, global: token ? { headers: { Authorization: `Bearer ${token}` } } : undefined });
};
export const billingHandlers = createBillingHandlers({
  env: (key: string) => Deno.env.get(key),
  verifyUser: async (token: string) => { const { data: { user }, error } = await client().auth.getUser(token); return error ? null : user; },
  eventSeen: async (id: string) => { const { data, error } = await client(true).rpc('recall_billing_event_seen', { p_event_id: id }); if (error) throw error; return data === true; },
  applyState: async (updates: unknown, eventId: string | null) => { const { data, error } = await client(true).rpc('recall_apply_billing_state', { p_updates: updates, p_event_id: eventId }); if (error) throw error; return data; },
  readEntitlement: async (token: string) => { const { data, error } = await client(false, token).rpc('recall_entitlement'); if (error) throw error; return data; },
});
