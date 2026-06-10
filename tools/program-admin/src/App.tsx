import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { Layout } from "./components/Layout";
import { ProtectedRoute } from "./components/ProtectedRoute";
import { ExcelUploadPage } from "./pages/ExcelUploadPage";
import { LoginPage } from "./pages/LoginPage";
import { WeeklyEditorPage } from "./pages/WeeklyEditorPage";

export function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route
          element={
            <ProtectedRoute>
              <Layout />
            </ProtectedRoute>
          }
        >
          <Route index element={<WeeklyEditorPage />} />
          <Route path="excel" element={<ExcelUploadPage />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  );
}
