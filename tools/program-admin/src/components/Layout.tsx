import { useState } from "react";
import { Outlet } from "react-router-dom";
import { signOut } from "../lib/auth";
import { CoachWritingGuideModal } from "./CoachWritingGuideModal";

export function Layout() {
  const [guideOpen, setGuideOpen] = useState(false);

  return (
    <div className="app-shell">
      <header className="app-header">
        <h1>TCR Antrenman Programı</h1>
        <div className="app-header-actions">
          <button
            type="button"
            className="btn btn-ghost"
            onClick={() => setGuideOpen(true)}
            aria-label="Program kılavuzu"
          >
            ⓘ Kılavuz
          </button>
          <button type="button" className="btn btn-ghost" onClick={() => signOut()}>
            Çıkış
          </button>
        </div>
      </header>
      <main className="app-main">
        <Outlet />
      </main>
      <CoachWritingGuideModal open={guideOpen} onClose={() => setGuideOpen(false)} />
    </div>
  );
}
