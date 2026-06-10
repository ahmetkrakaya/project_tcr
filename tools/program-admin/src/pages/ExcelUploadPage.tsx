import { FormEvent, useState } from "react";
import {
  downloadMonthlyProgramTemplate,
  importMonthlyProgram,
} from "../lib/api";

export function ExcelUploadPage() {
  const now = new Date();
  const [selectedMonth, setSelectedMonth] = useState(
    `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`,
  );
  const [file, setFile] = useState<File | null>(null);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<{
    type: "success" | "error" | "warning";
    text: string;
  } | null>(null);
  const [errors, setErrors] = useState<
    Array<{ row: number; message: string; sheet?: string }>
  >([]);
  const [acceptedRows, setAcceptedRows] = useState(0);

  async function handleDownloadTemplate() {
    setLoading(true);
    setMessage(null);
    try {
      const blob = await downloadMonthlyProgramTemplate();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = "monthly_program_template.xlsx";
      a.click();
      URL.revokeObjectURL(url);
      setMessage({ type: "success", text: "Şablon indirildi" });
    } catch (err) {
      setMessage({
        type: "error",
        text: err instanceof Error ? err.message : "Şablon indirilemedi",
      });
    } finally {
      setLoading(false);
    }
  }

  async function handleImport(e: FormEvent) {
    e.preventDefault();
    if (!file) {
      setMessage({ type: "warning", text: "Lütfen bir .xlsx dosyası seçin" });
      return;
    }

    setLoading(true);
    setMessage(null);
    setErrors([]);
    setAcceptedRows(0);

    try {
      const bytes = new Uint8Array(await file.arrayBuffer());
      const response = await importMonthlyProgram({
        monthKey: selectedMonth,
        fileName: file.name,
        fileBytes: bytes,
      });

      const importErrors = response.errors ?? [];
      const accepted = response.accepted_rows ?? 0;
      const months = response.imported_month_keys ?? [];

      setErrors(importErrors);
      setAcceptedRows(accepted);

      if (importErrors.length === 0) {
        setMessage({
          type: "success",
          text:
            months.length > 0
              ? `Import tamamlandı: ${accepted} satır (${months.join(", ")})`
              : `Import tamamlandı: ${accepted} satır`,
        });
      } else {
        setMessage({
          type: "error",
          text: `Import hatalı: ${importErrors.length} satır hatası (${accepted} satır kabul edildi)`,
        });
      }
    } catch (err) {
      setMessage({
        type: "error",
        text: err instanceof Error ? err.message : "Import başarısız",
      });
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="stack">
      <div className="card stack">
        <h2 style={{ margin: 0 }}>Excel ile aylık program yükle</h2>
        <p className="muted" style={{ margin: 0 }}>
          Mobil uygulamadaki gelişmiş import ile aynı şablon ve edge function
          kullanılır.
        </p>
        <button
          type="button"
          className="btn"
          onClick={handleDownloadTemplate}
          disabled={loading}
        >
          Şablon indir (.xlsx)
        </button>
      </div>

      <form className="card stack" onSubmit={handleImport}>
        <label>
          Ay (YYYY-MM)
          <input
            type="month"
            required
            value={selectedMonth}
            onChange={(e) => setSelectedMonth(e.target.value)}
          />
        </label>
        <label>
          Excel dosyası
          <input
            type="file"
            accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            onChange={(e) => setFile(e.target.files?.[0] ?? null)}
          />
        </label>
        <button type="submit" className="btn btn-primary" disabled={loading}>
          {loading ? "Yükleniyor…" : "Import et"}
        </button>
      </form>

      {message && (
        <div className={`alert alert-${message.type}`}>{message.text}</div>
      )}

      {acceptedRows > 0 && errors.length === 0 && (
        <div className="alert alert-success">{acceptedRows} satır içe aktarıldı</div>
      )}

      {errors.length > 0 && (
        <div className="card stack">
          <strong>Hata detayları</strong>
          <ul style={{ margin: 0, paddingLeft: 20 }}>
            {errors.slice(0, 30).map((err, i) => (
              <li key={i}>
                {err.sheet ? `${err.sheet} ` : ""}
                Satır {err.row}: {err.message}
              </li>
            ))}
          </ul>
          {errors.length > 30 && (
            <p className="muted">…ve {errors.length - 30} hata daha</p>
          )}
        </div>
      )}
    </div>
  );
}
