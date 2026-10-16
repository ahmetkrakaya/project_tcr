/** Yalnızca service role ile çağrılması gereken fonksiyonlar (cron, operasyonel işler) için. */
export function isServiceRoleRequest(req: Request, serviceKey: string): boolean {
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!token) return false;
  if (token === serviceKey) return true;
  try {
    const b64 = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    const payload = JSON.parse(atob(b64.padEnd(Math.ceil(b64.length / 4) * 4, '=')));
    return payload?.role === 'service_role';
  } catch {
    return false;
  }
}
