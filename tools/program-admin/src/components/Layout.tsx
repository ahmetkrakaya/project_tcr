import { NavLink, Outlet } from "react-router-dom";
import { signOut } from "../lib/auth";

export function Layout() {
  return (
    <div className="app-shell">
      <header className="app-header">
        <h1>TCR Program Admin</h1>
        <nav className="app-nav">
          <NavLink
            to="/"
            end
            className={({ isActive }) => (isActive ? "active" : undefined)}
          >
            Haftalık program
          </NavLink>
          <NavLink
            to="/excel"
            className={({ isActive }) => (isActive ? "active" : undefined)}
          >
            Excel yükle
          </NavLink>
        </nav>
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
