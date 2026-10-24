// @ts-nocheck
export function createAccountDeletionHandler({ env, verifyUser, deleteUser }) {
  return async request => {
    const origin = env('APP_ORIGIN');
    const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': origin ?? '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Vary': 'Origin' };
    const send = (status, data) => new Response(JSON.stringify(data), { status, headers });
    if (origin && request.headers.get('Origin') && request.headers.get('Origin') !== origin) return send(403, { error: 'Origin unavailable.' });
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
    if (request.method !== 'POST') return send(405, { error: 'Use POST.' });
    const authorization = request.headers.get('Authorization') ?? '';
    if (!authorization.startsWith('Bearer ')) return send(401, { error: 'Sign in again before deleting your account.' });
    try {
      const user = await verifyUser(authorization.slice(7));
      if (!user) return send(401, { error: 'Sign in again before deleting your account.' });
      // No request-body user ID is accepted. Only Auth's verified ID can be deleted.
      if (!(await deleteUser(user.id))) return send(500, { error: 'Your account could not be deleted. Please retry.' });
      return send(200, { deleted: true });
    } catch {
      return send(503, { error: 'Account deletion is temporarily unavailable. Please retry.' });
    }
  };
}
