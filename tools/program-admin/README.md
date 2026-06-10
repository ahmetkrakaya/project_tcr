# TCR Antrenman Programı

`app.rivlus.com` için hafif antrenman programı yönetim paneli. Mobil uygulamadaki haftalık editör ile aynı Supabase tablolarını ve `weekly-program-upsert` edge function'ını kullanır.

## Yerel geliştirme

```bash
cd tools/program-admin
cp .env.example .env
# .env içine VITE_SUPABASE_URL ve VITE_SUPABASE_ANON_KEY yazın
npm install
npm run dev
```

## Vercel deploy

1. Vercel'de yeni proje oluşturun (veya eski web projesini yeniden kullanın).
2. **Root Directory:** `tools/program-admin`
3. **Framework:** Vite
4. **Build Command:** `npm run build`
5. **Output Directory:** `dist`
6. Environment variables:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
7. Domain: `app.rivlus.com`

### Cloudflare DNS

| Type  | Name | Target               | Proxy   |
|-------|------|----------------------|---------|
| CNAME | app  | cname.vercel-dns.com | DNS only |

### Supabase Auth

Authentication → URL Configuration:

- Site URL: `https://app.rivlus.com`
- Redirect URLs: `https://app.rivlus.com/**`

## Yetki

Yalnızca `user_roles` tablosunda `super_admin` rolü olan hesaplar giriş yapabilir.
