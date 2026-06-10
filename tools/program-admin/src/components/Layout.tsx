import { Outlet } from "react-router-dom";
import { signOut } from "../lib/auth";

export function Layout() {
  return (
    <div className="app-shell">
      <header className="app-header">
        <h1>TCR Antrenman Programı</h1>
        <button type="button" className="btn btn-ghost" onClick={() => signOut()}>
          Çıkış
        </button>
      </header>
      <main className="app-main">
        <Outlet />
      </main>
    </div>
  );
}
