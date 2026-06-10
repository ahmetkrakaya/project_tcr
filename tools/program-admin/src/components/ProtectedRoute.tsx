import { useEffect, useState, type ReactNode } from "react";
import { Navigate } from "react-router-dom";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "../lib/supabase";
import { isSuperAdmin } from "../lib/auth";

type Props = {
  children: ReactNode;
};

export function ProtectedRoute({ children }: Props) {
  const [session, setSession] = useState<Session | null | undefined>(undefined);
  const [allowed, setAllowed] = useState<boolean | undefined>(undefined);

  useEffect(() => {
    let mounted = true;

    async function check(sess: Session | null) {
      if (!sess?.user) {
        if (mounted) {
          setSession(null);
          setAllowed(false);
        }
        return;
      }
      try {
        const admin = await isSuperAdmin(sess.user.id);
        if (mounted) {
          setSession(sess);
          setAllowed(admin);
        }
      } catch {
        if (mounted) {
          setSession(sess);
          setAllowed(false);
        }
      }
    }

    supabase.auth.getSession().then(({ data }) => check(data.session));

    const { data: sub } = supabase.auth.onAuthStateChange((_event, sess) => {
      check(sess);
    });

    return () => {
      mounted = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  if (session === undefined || allowed === undefined) {
    return (
      <div className="login-page">
        <p className="muted">Yükleniyor…</p>
      </div>
    );
  }

  if (!session) {
    return <Navigate to="/login" replace />;
  }

  if (!allowed) {
    return (
      <div className="login-page">
        <div className="card login-card">
          <h1>Erişim reddedildi</h1>
          <p>Bu panel yalnızca super_admin hesapları içindir.</p>
          <button
            type="button"
            className="btn btn-primary"
            onClick={() => supabase.auth.signOut()}
          >
            Çıkış yap
          </button>
        </div>
      </div>
    );
  }

  return <>{children}</>;
}
