-- TCR Migration 009: Fix User Insert Policies
-- Kullanıcı kaydı sırasında profil ve rol oluşturma izinleri

-- ==========================================
-- USERS INSERT POLICY
-- ==========================================
-- Kullanıcılar kayıt sırasında sadece kendi profillerini oluşturabilir
-- Bu policy, handle_new_user() trigger'ının çalışması için gerekli

CREATE POLICY "Users can insert own profile"
    ON public.users FOR INSERT
    WITH CHECK (auth.uid() = id);

-- ==========================================
-- USER ROLES INSERT POLICY
-- ==========================================
-- Trigger tarafından varsayılan "member" rolü atanabilir
-- Kullanıcı sadece kendi ID'si için ve sadece "member" rolü alabilir

CREATE POLICY "Users can receive default member role"
    ON public.user_roles FOR INSERT
    WITH CHECK (auth.uid() = user_id AND role = 'member');

-- ==========================================
-- ALTERNATIVE: Service Role Bypass
-- ==========================================
-- Eğer yukarıdaki policy'ler çalışmazsa, aşağıdaki fonksiyonu kullanın
-- Bu fonksiyon RLS'yi tamamen bypass eder

 DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
-- 
 CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS TRIGGER 
 SECURITY DEFINER
 SET search_path = public
 AS $$
 BEGIN
     INSERT INTO public.users (id, email, referral_code)
     VALUES (
         NEW.id,
         NEW.email,
         generate_referral_code()
     );
     
     INSERT INTO public.user_roles (user_id, role)
     VALUES (NEW.id, 'member');
     
     RETURN NEW;
 END;
 $$ LANGUAGE plpgsql;
-- 
 CREATE TRIGGER on_auth_user_created
     AFTER INSERT ON auth.users
     FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
