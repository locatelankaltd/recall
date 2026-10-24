import { createClient } from 'jsr:@supabase/supabase-js@2';
import { createAnalysisHandler } from './core.ts';

Deno.serve(createAnalysisHandler({
  env: (key: string) => Deno.env.get(key),
  reserveAnalysis: async (userId: string, limit: number) => {
    const url = Deno.env.get('SUPABASE_URL');
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !key) return false;
    const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data, error } = await admin.rpc('recall_reserve_analysis', { p_user_id: userId, p_daily_limit: limit });
    return !error && data === true;
  },
  verifyUser: async (token: string) => {
    const url = Deno.env.get('SUPABASE_URL');
    const key = Deno.env.get('SUPABASE_ANON_KEY');
    if (!url || !key) return null;
    const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: { user }, error } = await client.auth.getUser(token);
    return error ? null : user;
  },
}));
