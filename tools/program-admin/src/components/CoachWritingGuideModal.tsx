import type { ReactNode } from "react";

type Props = {
  open: boolean;
  onClose: () => void;
};

function GuideCard({
  icon,
  title,
  children,
  className = "",
}: {
  icon: string;
  title: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={`guide-card ${className}`.trim()}>
      <div className="guide-card-head">
        <span className="guide-card-icon" aria-hidden="true">
          {icon}
        </span>
        <h3>{title}</h3>
      </div>
      <div className="guide-card-body">{children}</div>
    </section>
  );
}

function ExampleTable({ rows }: { rows: [string, string][] }) {
  return (
    <table className="guide-table">
      <thead>
        <tr>
          <th>Yazım</th>
          <th>Anlam</th>
        </tr>
      </thead>
      <tbody>
        {rows.map(([code, meaning]) => (
          <tr key={code}>
            <td>
              <code>{code}</code>
            </td>
            <td>{meaning}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

export function CoachWritingGuideModal({ open, onClose }: Props) {
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
        <div className="guide-header">
          <div className="guide-header-text">
            <p className="guide-eyebrow">Koç metni parser</p>
            <h2 id="guide-title">Antrenman yazım kılavuzu</h2>
            <p className="guide-lead">
              Her satır bir adım. Boşluklu veya bitişik yazım aynı sonucu verir —{" "}
              <code>15dk</code> ile <code>15 dk</code> eşdeğerdir. Yazdıktan sonra{" "}
              <strong>Önizleme</strong> ile kontrol edin.
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
        </div>

        <div className="guide-pills" aria-label="Hızlı özet">
          <span className="guide-pill">Isınma → Ana → Soğuma</span>
          <span className="guide-pill">Boşluk fark etmez</span>
          <span className="guide-pill">R = toparlanma</span>
          <span className="guide-pill">+ ile zincirle</span>
        </div>

        <div className="modal-body guide-body">
          <div className="guide-grid">
            <GuideCard icon="📋" title="Genel yapı">
              <p>
                Antrenmanı satır satır yazın. Tipik sıra:{" "}
                <strong>ısınma</strong> → <strong>ana antrenman</strong> →{" "}
                <strong>soğuma</strong>. Birden fazla bloğu <code>+</code> ile aynı
                satırda birleştirebilirsiniz.
              </p>
              <pre className="guide-example">{`15dk ısınma
4x8dk vdot R 1dk
10dk soğuma`}</pre>
              <p className="guide-note">
                Etiketler başta veya sonda olabilir: <code>ısınma 15dk</code>,{" "}
                <code>ana 6x5dk 3:00 R 1dk</code>, <code>soğuma 2km</code>
              </p>
            </GuideCard>

            <GuideCard icon="🏷️" title="Etiketler">
              <ExampleTable
                rows={[
                  ["ısınma, isinma, warmup", "Isınma adımı"],
                  ["ana, main", "Ana antrenman"],
                  ["soğuma, soguma, cooldown", "Soğuma adımı"],
                  ["toparlanma, recovery, rec, float", "R ile aynı (toparlanma)"],
                  ["REST, dinlenme", "Dinlenme günü — adım yok"],
                ]}
              />
            </GuideCard>

            <GuideCard icon="🔥" title="Isınma ve soğuma">
              <p>Süre, mesafe veya tempo belirtebilirsiniz.</p>
              <ExampleTable
                rows={[
                  ["15dk ısınma", "15 dk kolay ısınma"],
                  ["15dakika ısınma", "Boşluksuz dakika da geçerli"],
                  ["15dk 7:00 pace ısınma", "15 dk @ 7:00/km"],
                  ["500m ısınma", "500 m koşu"],
                  ["500metre ısınma", "Uzun birim adı da geçerli"],
                  ["2km soğuma", "2 km soğuma"],
                  ["45min soğuma", "min / minute / minutes"],
                ]}
              />
            </GuideCard>

            <GuideCard icon="⚡" title="Ana antrenman">
              <p>Süre koşusu, mesafe koşusu veya tekrarlı interval.</p>
              <ExampleTable
                rows={[
                  ["45dk 6:00", "45 dk @ 6:00/km"],
                  ["60dk 6:00/5:50", "60 dk tempo aralığı"],
                  ["10km vdot", "10 km @ VDOT temposu"],
                  ["4x8dk vdot R 1dk", "4×8 dk @ VDOT, 1 dk R"],
                  ["6x5 dakika 3:00p R 1 dakika 3:00 p", "Süre interval + p kısaltması"],
                  ["5x400 (1:51) R200m", "5×400 m hedef 1:51, 200 m R"],
                  ["400m vdot R 1dk", "Tek tekrar, parantezsiz"],
                  ["5x1200(5:10/5:00) R400m 2:20", "Split hedef + mesafe R"],
                ]}
              />
            </GuideCard>

            <GuideCard icon="⏱️" title="Tempo, pace ve VDOT">
              <ExampleTable
                rows={[
                  ["7:00", "Tek tempo (dk:sn / km)"],
                  ["7:00 pace", "pace kelimesi opsiyonel"],
                  ["7:00p", "p kısaltması = pace"],
                  ["7:00pace", "Bitişik yazım"],
                  ["9:00-10:00", "Tempo aralığı (tire)"],
                  ["6:00/5:50", "Tempo aralığı (slash)"],
                  ["5pace, 5p", "Kısaltma → 5:00/km"],
                  ["3 pace, 3p", "Tek haneli kısaltma → 3:00/km"],
                  ["vdot", "Sporcu VDOT değerinden tempo"],
                  ["(5:10/5:00)", "Parantez içi split veya tempo"],
                ]}
              />
            </GuideCard>

            <GuideCard icon="💤" title="Toparlanma (R)">
              <p>
                <code>R</code> sonrasındaki tüm ifade toparlanmadır — mesafe, süre
                ve/veya tempo birlikte kullanılabilir.
              </p>
              <ExampleTable
                rows={[
                  ["R 1dk", "1 dk toparlanma"],
                  ["R1dk", "Bitişik yazım"],
                  ["R200m", "200 m toparlanma"],
                  ["R 200", "200 m (m birimi opsiyonel)"],
                  ["R 200 3pace", "200 m @ 3:00/km"],
                  ["R 200 3p", "p kısaltması ile tempo"],
                  ["R 1dk 3:00 pace", "Süre + tempo birlikte"],
                  ["R400m 2:20", "400 m, en fazla 2:20/km"],
                ]}
              />
            </GuideCard>

            <GuideCard icon="📏" title="Birimler ve eşdeğerler" className="guide-card-wide">
              <p className="guide-note">
                Tüm birimler <strong>boşluklu</strong> veya <strong>bitişik</strong>{" "}
                yazılabilir. Aşağıdaki sütunlar birbirinin yerine geçer.
              </p>
              <div className="guide-unit-grid">
                <div className="guide-unit-block">
                  <h4>Süre</h4>
                  <div className="guide-chips">
                    <code>dk</code>
                    <code>dakika</code>
                    <code>dak</code>
                    <code>min</code>
                    <code>minute</code>
                    <code>saat</code>
                    <code>h</code>
                    <code>1h30dk</code>
                    <code>1:30:00</code>
                  </div>
                  <p className="guide-mini">
                    Örn: <code>15dk</code> = <code>15 dk</code> = <code>15dakika</code>
                  </p>
                </div>
                <div className="guide-unit-block">
                  <h4>Mesafe</h4>
                  <div className="guide-chips">
                    <code>m</code>
                    <code>metre</code>
                    <code>km</code>
                    <code>k</code>
                    <code>kilometre</code>
                  </div>
                  <p className="guide-mini">
                    Örn: <code>400m</code> = <code>400 m</code> = <code>400metre</code>
                  </p>
                </div>
                <div className="guide-unit-block">
                  <h4>Tekrar</h4>
                  <div className="guide-chips">
                    <code>x</code>
                    <code>*</code>
                    <code>×</code>
                    <code>tekrar</code>
                    <code>rep</code>
                  </div>
                  <p className="guide-mini">
                    Örn: <code>4x400</code> = <code>4 x 400</code> = <code>4 tekrar 400m</code>
                  </p>
                </div>
                <div className="guide-unit-block">
                  <h4>Tempo</h4>
                  <div className="guide-chips">
                    <code>pace</code>
                    <code>p</code>
                    <code>/km</code>
                    <code>@</code>
                    <code>tempo</code>
                  </div>
                  <p className="guide-mini">
                    Örn: <code>3:00pace</code> = <code>3:00 p</code> = <code>3:00/km</code>
                  </p>
                </div>
              </div>
            </GuideCard>

            <GuideCard icon="🔗" title="Zincirleme ve uzun koşu">
              <p>
                <code>+</code> ile adımları birleştirin. Uzun koşuda segmentleri{" "}
                <code>/</code> veya <code>:</code> ile ayırabilirsiniz.
              </p>
              <pre className="guide-example">{`3k 6:10/6:00 + 5x1200(5:10/5:00) R400m + 1k 6:00/6:10

18k: 3k 5:40 / 12k 5:30 / 3k 5:20

15dk 6:00 + 30dk 5:20/5:25 + 15dk 5:14`}</pre>
            </GuideCard>

            <GuideCard icon="📝" title="Tam antrenman örnekleri" className="guide-card-wide">
              <div className="guide-examples-row">
                <div className="guide-example-block">
                  <span className="guide-example-label">Interval günü</span>
                  <pre className="guide-example">{`15dk ısınma
6x5dk 3:00 R 1dk 3:00
10dk soğuma`}</pre>
                </div>
                <div className="guide-example-block">
                  <span className="guide-example-label">Mesafe tekrarları</span>
                  <pre className="guide-example">{`15dk 7:00 pace ısınma
5x400 (1:51) R200m
2km soğuma`}</pre>
                </div>
                <div className="guide-example-block">
                  <span className="guide-example-label">VDOT tempo</span>
                  <pre className="guide-example">{`10dk ısınma
4x8dk vdot R 1dk
400m vdot R 200 3p
10dk soğuma`}</pre>
                </div>
              </div>
            </GuideCard>
          </div>

          <div className="guide-footer">
            <div className="guide-footer-item guide-footer-success">
              <strong>İpucu</strong>
              <span>
                Metni yazdıktan sonra <strong>Önizleme</strong> ile adımların doğru
                ayrıştığını kontrol edin.
              </span>
            </div>
            <div className="guide-footer-item guide-footer-warn">
              <strong>Dikkat</strong>
              <span>
                Tekrarlı koşularda toparlanma (<code>R …</code>) zorunludur. Interval
                bloğu R olmadan parse edilmez.
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
