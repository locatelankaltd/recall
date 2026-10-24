import { createClient } from 'jsr:@supabase/supabase-js@2';
import { createAccountDeletionHandler } from './core.ts';

const admin = () => {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) throw new Error('Server configuration unavailable');
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
};
Deno.serve(createAccountDeletionHandler({
  env: (key: string) => Deno.env.get(key),
  verifyUser: async (token: string) => {
    const { data: { user }, error } = await admin().auth.getUser(token);
    return error ? null : user;
  },
  deleteUser: async (userId: string) => {
    const { error } = await admin().auth.admin.deleteUser(userId);
    return !error;
  },
}));
