import { useState, type ReactNode } from "react";

type Props = {
  open: boolean;
  onClose: () => void;
};

type TabId = "start" | "settings" | "writing" | "examples";

const TABS: { id: TabId; label: string }[] = [
  { id: "start", label: "Başlarken" },
  { id: "settings", label: "Grup & ayarlar" },
  { id: "writing", label: "Metin yazımı" },
  { id: "examples", label: "Örnekler" },
];

function GuideBlock({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="guide-block">
      <h3>{title}</h3>
      {children}
    </section>
  );
}

function GuideSteps({ steps }: { steps: string[] }) {
  return (
    <ol className="guide-steps">
      {steps.map((step) => (
        <li key={step}>{step}</li>
      ))}
    </ol>
  );
}

function GuideTable({ rows }: { rows: [string, string][] }) {
  return (
    <table className="guide-table">
      <tbody>
        {rows.map(([a, b]) => (
          <tr key={a}>
            <td>{a}</td>
            <td>{b}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function GuideCallout({
  type,
  title,
  children,
}: {
  type: "tip" | "warn" | "info";
  title: string;
  children: ReactNode;
}) {
  return (
    <div className={`guide-callout guide-callout-${type}`}>
      <strong>{title}</strong>
      <div>{children}</div>
    </div>
  );
}

function GuideCode({ children }: { children: string }) {
  return <pre className="guide-code">{children}</pre>;
}

function StartTab() {
  return (
    <>
      <GuideBlock title="Bu panel ne işe yarar?">
        <p>
          Haftalık antrenman programını <strong>Pazartesi–Pazar</strong> için
          hazırlarsınız. Her gün bir kart; metin yazıp kaydettiğinizde sporcular
          mobil uygulamada programı görür.
        </p>
      </GuideBlock>

      <GuideBlock title="Önerilen iş akışı">
        <GuideSteps
          steps={[
            "Üstten antrenman grubunu seçin (performansta sporcu da seçin).",
            "Her gün için antrenman metnini yazın; gerekirse tür ve pist ayarlayın.",
            "Kart altındaki önizlemeyi veya üstteki Önizleme butonunu kontrol edin.",
            "Kaydet — en az bir gün kaydedildiğinde sporculara bildirim gider.",
          ]}
        />
      </GuideBlock>

      <GuideBlock title="Önizleme">
        <p>
          Metin yazdıkça her gün kartının altında <strong>satır içi önizleme</strong>{" "}
          açılır: ısınma / ana / toparlanma / soğuma adımları, tempo veya{" "}
          <em>VDOT pace</em> etiketi görünür.
        </p>
        <p>
          Üst araç çubuğundaki <strong>Önizleme</strong> butonu tüm haftayı tek
          pencerede gösterir. Parse hatası varsa kırmızı uyarı çıkar — kaydetmeden
          önce düzeltin.
        </p>
      </GuideBlock>

      <GuideBlock title="Koç notu">
        <p>
          Sporcuya gösterilen serbest metindir; antrenmanın üstünde görünür.
        </p>
        <GuideCallout type="warn" title="Önemli">
          Antrenman metni boşken sadece koç notu kaydedilmez. Notun kalıcı olması
          için o gün geçerli bir antrenman metni yazmalısınız.
        </GuideCallout>
      </GuideBlock>

      <GuideBlock title="Dinlenme günü">
        <p>
          Alanı boş bırakmak, <code>REST</code> veya <code>dinlenme</code> yazmak
          dinlenme günü demektir. Kayıtta o gün veritabanından silinir; önizlemede
          &ldquo;Dinlenme günü&rdquo; yazar.
        </p>
      </GuideBlock>

      <GuideBlock title="Diğer araçlar">
        <GuideTable
          rows={[
            ["Geçen haftadan kopyala", "Aynı grup/sporcu için önceki haftayı getirir."],
            ["Gruptan kopyala", "Başka normal gruptan bu haftayı kopyalar (kaydetmek gerekir)."],
            ["Tümünü kaydet", "Birden fazla grubun kaydedilmemiş taslağı varsa hepsini kaydeder."],
          ]}
        />
      </GuideBlock>
    </>
  );
}

function SettingsTab() {
  return (
    <>
      <GuideBlock title="Antrenman grubu">
        <p>
          Program hangi gruba (veya performansta hangi sporcuya) yazılacağını
          belirler. Grup seçilmeden gün kartları kilitlidir.
        </p>
        <GuideTable
          rows={[
            [
              "Normal grup",
              "Program gruba atanır; gruptaki tüm üyeler aynı programı görür.",
            ],
            [
              "Performans grubu",
              "Program sporcu bazında kaydedilir. Önce en az bir sporcu seçmelisiniz.",
            ],
          ]}
        />
        <GuideCallout type="info" title="Performans — çoklu sporcu">
          Birden fazla sporcu seçerseniz aynı program hepsine yazılır; mevcut hafta
          yüklenmez. Tek sporcu seçiliyken o sporcunun haftası otomatik gelir.
        </GuideCallout>
      </GuideBlock>

      <GuideBlock title="Antrenman türü">
        <p>
          Her gün kartında <strong>Antrenman türü</strong> alanı vardır. Varsayılan{" "}
          <strong>Otomatik (metinden)</strong> — sistem metne bakarak türü tahmin eder.
        </p>
        <p>Otomatik tahmin kuralları (özet):</p>
        <GuideTable
          rows={[
            ["Tekrar + mesafe ≤ 600 m", "Repetition (tekrar)"],
            ["Tekrar + mesafe > 600 m", "Interval"],
            ["Uzun mesafe formatı veya ≥ 15 km", "Long Run"],
            ["Metinde threshold / eşik", "Threshold"],
            ["Diğer", "Easy Run"],
          ]}
        />
        <GuideCallout type="tip" title="Ne zaman manuel seçmeli?">
          Önizlemede tür yanlış görünüyorsa listeden doğru türü seçin. Tür; mobil
          uygulamada renk/ikon, VDOT tempo offset&apos;i ve antrenman kategorisini
          etkiler.
        </GuideCallout>
      </GuideBlock>

      <GuideBlock title="VDOT — metinde ne anlama gelir?">
        <p>
          Metne <code>vdot</code> yazdığınızda o adım için <strong>sabit tempo
          yazmazsınız</strong>; sporcu profilindeki VDOT değerinden tempo hesaplanır.
        </p>
        <GuideTable
          rows={[
            ["10km vdot", "10 km, kişisel VDOT temposunda"],
            ["4x8dk vdot R 1dk", "4×8 dk @ VDOT, 1 dk toparlanma"],
            ["400m vdot R 1dk", "400 m tekrarı @ VDOT"],
          ]}
        />
        <GuideCallout type="info" title="Panel vs mobil uygulama">
          <p style={{ margin: "0 0 8px" }}>
            <strong>Burada (önizleme):</strong> &ldquo;VDOT pace&rdquo; yazar — sayısal
            tempo hesaplanmaz; sporcu profili panelde yoktur.
          </p>
          <p style={{ margin: 0 }}>
            <strong>Mobil uygulamada:</strong> Sporcunun profil VDOT&apos;undan gerçek
            tempo (ör. 4:30/km) gösterilir. VDOT girilmemişse uyarı çıkar. Metne
            sayısal VDOT yazmayın — profildeki değer kullanılır.
          </p>
        </GuideCallout>
        <p className="guide-muted">
          Isınma, soğuma ve toparlanmada VDOT kullanıldığında tempo, ana segmentten
          daha kolay offset ile hesaplanır.
        </p>
      </GuideBlock>

      <GuideBlock title="Pist (kulvar) seçimi">
        <p>
          Pist antrenmanları için gün kartındaki <strong>Pist</strong> alanından
          referans kulvarı (1–8) seçin. Yol koşusu veya koşu bandı için{" "}
          <strong>Pistte değil</strong> bırakın.
        </p>
        <GuideTable
          rows={[
            ["Pistte değil", "Mesafe/süre yazdığınız gibi kullanılır."],
            ["Kulvar 1–8", "Referans kulvar kaydedilir; önizlemede Kulvar N chip'i görünür."],
          ]}
        />
        <GuideCallout type="info" title="Mobilde ne olur?">
          Dış kulvarlar daha uzun tur mesafesine sahiptir (IAAF formülü). Sporcu
          mobil uygulamada kendi kulvarını seçebilir; mesafe ve tur süreleri referans
          kulvara göre dönüştürülür. Panel önizlemesinde bu dönüşüm tam simüle
          edilmez — detay mobilde görülür.
        </GuideCallout>
      </GuideBlock>
    </>
  );
}

function WritingTab() {
  return (
    <>
      <GuideBlock title="Temel kural">
        <p>
          Her satır bir adım. Tipik sıra: <strong>ısınma</strong> →{" "}
          <strong>ana antrenman</strong> → <strong>soğuma</strong>. Birden fazla bloğu{" "}
          <code>+</code> ile aynı satırda birleştirebilirsiniz.
        </p>
        <p className="guide-muted">
          Boşluklu ve bitişik yazım aynı sonucu verir: <code>15dk</code> ={" "}
          <code>15 dk</code> = <code>15dakika</code>
        </p>
      </GuideBlock>

      <GuideBlock title="Etiketler">
        <GuideTable
          rows={[
            ["ısınma, warmup", "Isınma adımı (başta veya sonda)"],
            ["ana, main", "Ana antrenman"],
            ["soğuma, cooldown", "Soğuma"],
            ["R, toparlanma, recovery", "Toparlanma — tekrarlarda zorunlu"],
          ]}
        />
      </GuideBlock>

      <GuideBlock title="Tempo yazımı">
        <GuideTable
          rows={[
            ["7:00", "Tek tempo (dk:sn / km)"],
            ["7:00 pace veya 7:00p", "pace / p kelimesi opsiyonel"],
            ["9:00-10:00 veya 6:00/5:50", "Tempo aralığı"],
            ["5pace, 5p", "Kısaltma → 5:00/km"],
            ["vdot", "Sporcu VDOT temposu (sabit dk/km yazılmaz)"],
          ]}
        />
      </GuideBlock>

      <GuideBlock title="Tekrarlı koşular">
        <p>
          Format: <code>tekrar × mesafe veya süre + hedef + R + toparlanma</code>
        </p>
        <GuideCode>{`4x8dk vdot R 1dk
5x400 (1:51) R200m
6x5 dakika 3:00p R 1 dakika 3:00 p
400m vdot R 1dk`}</GuideCode>
        <GuideCallout type="warn" title="Toparlanma zorunlu">
          Tekrarlı intervalde <code>R …</code> olmadan parse edilmez. R sonrası süre,
          mesafe ve/veya tempo yazılabilir: <code>R 1dk 3:00</code>,{" "}
          <code>R 200 3p</code>
        </GuideCallout>
      </GuideBlock>

      <GuideBlock title="Birim eşdeğerleri">
        <div className="guide-unit-list">
          <div>
            <strong>Süre:</strong> dk, dakika, dak, min, saat, h, 1h30dk
          </div>
          <div>
            <strong>Mesafe:</strong> m, metre, km, k, kilometre
          </div>
          <div>
            <strong>Tekrar:</strong> x, *, ×, tekrar, rep
          </div>
          <div>
            <strong>Tempo:</strong> pace, p, /km, @, tempo
          </div>
        </div>
      </GuideBlock>

      <GuideBlock title="Zincirleme ve uzun koşu">
        <GuideCode>{`3k 6:10/6:00 + 5x1200(5:10/5:00) R400m + 1k 6:00

18k: 3k 5:40 / 12k 5:30 / 3k 5:20`}</GuideCode>
      </GuideBlock>
    </>
  );
}

function ExamplesTab() {
  return (
    <>
      <GuideBlock title="Interval günü">
        <GuideCode>{`15dk ısınma
6x5dk 3:00 R 1dk 3:00
10dk soğuma`}</GuideCode>
      </GuideBlock>

      <GuideBlock title="Pist tekrarları (kulvar seçili)">
        <GuideCode>{`15dk ısınma
5x400 (1:51) R200m
2km soğuma`}</GuideCode>
        <p className="guide-muted">Pist alanından referans kulvarını seçmeyi unutmayın.</p>
      </GuideBlock>

      <GuideBlock title="VDOT tempo günü">
        <GuideCode>{`10dk ısınma
4x8dk vdot R 1dk
400m vdot R 200 3p
10dk soğuma`}</GuideCode>
        <p className="guide-muted">
          Tür: Otomatik → Interval. VDOT temposu sporcunun profilindeki değerden gelir.
        </p>
      </GuideBlock>

      <GuideBlock title="Tempo koşusu">
        <GuideCode>{`15dk 7:00 pace ısınma
45dk 6:00/5:50
10dk soğuma`}</GuideCode>
      </GuideBlock>

      <GuideBlock title="Dinlenme">
        <GuideCode>{`REST`}</GuideCode>
        <p className="guide-muted">veya gün kartını boş bırakın.</p>
      </GuideBlock>
    </>
  );
}

export function CoachWritingGuideModal({ open, onClose }: Props) {
  const [tab, setTab] = useState<TabId>("start");

  if (!open) return null;

  return (
    <div className="modal-backdrop guide-backdrop" onClick={onClose} role="presentation">
      <div
        className="modal-panel guide-panel"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby="guide-title"
      >
        <header className="guide-header">
          <div>
            <h2 id="guide-title">Program kılavuzu</h2>
            <p className="guide-subtitle">
              Haftalık program girişi, grup ayarları, VDOT, pist ve metin yazımı
            </p>
          </div>
          <button
            type="button"
            className="btn btn-ghost guide-close"
            onClick={onClose}
            aria-label="Kapat"
          >
            ✕
          </button>
        </header>

        <nav className="guide-tabs" aria-label="Kılavuz bölümleri">
          {TABS.map((t) => (
            <button
              key={t.id}
              type="button"
              className={`guide-tab${tab === t.id ? " guide-tab-active" : ""}`}
              onClick={() => setTab(t.id)}
            >
              {t.label}
            </button>
          ))}
        </nav>

        <div className="modal-body guide-body">
          {tab === "start" && <StartTab />}
          {tab === "settings" && <SettingsTab />}
          {tab === "writing" && <WritingTab />}
          {tab === "examples" && <ExamplesTab />}
        </div>
      </div>
    </div>
  );
}
