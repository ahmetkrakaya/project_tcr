type Props = {
  open: boolean;
  onClose: () => void;
};

export function CoachWritingGuideModal({ open, onClose }: Props) {
  if (!open) return null;

  return (
    <div className="modal-backdrop" onClick={onClose} role="presentation">
      <div
        className="modal-panel guide-panel"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby="guide-title"
      >
        <div className="modal-header">
          <div>
            <h2 id="guide-title">Antrenman yazım kılavuzu</h2>
            <p className="muted">Her satır bir adım. Önizleme ile kontrol edin.</p>
          </div>
          <button type="button" className="btn btn-ghost" onClick={onClose}>
            Kapat
          </button>
        </div>
        <div className="modal-body stack guide-body">
          <section className="guide-section">
            <h3>Genel yapı</h3>
            <p>
              Antrenmanı satır satır yazın. Tipik sıra: <strong>ısınma</strong> →{" "}
              <strong>ana antrenman</strong> → <strong>soğuma</strong>. Birden fazla
              adımı <code>+</code> ile de birleştirebilirsiniz.
            </p>
            <pre className="guide-example">{`15dk ısınma
4x8dk vdot R 1dk
10dk soğuma`}</pre>
          </section>

          <section className="guide-section">
            <h3>Isınma ve soğuma</h3>
            <p>
              Etiket başta veya sonda olabilir. Süre, mesafe veya tempo
              belirtebilirsiniz.
            </p>
            <table className="guide-table">
              <thead>
                <tr>
                  <th>Örnek</th>
                  <th>Anlam</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>
                    <code>15dk ısınma</code>
                  </td>
                  <td>15 dk kolay ısınma</td>
                </tr>
                <tr>
                  <td>
                    <code>15dk 7:00 pace ısınma</code>
                  </td>
                  <td>15 dk, 7:00/km tempo</td>
                </tr>
                <tr>
                  <td>
                    <code>500m ısınma</code>
                  </td>
                  <td>500 m koşu</td>
                </tr>
                <tr>
                  <td>
                    <code>2km soğuma</code>
                  </td>
                  <td>2 km soğuma</td>
                </tr>
              </tbody>
            </table>
            <p className="guide-tags muted">
              Birimler bitişik veya boşluklu yazılabilir: <code>15dk</code> ={" "}
              <code>15 dk</code>, <code>500m</code> = <code>500 m</code>,{" "}
              <code>3:00pace</code> = <code>3:00 pace</code>, <code>R1dk</code> ={" "}
              <code>R 1 dk</code>
            </p>
          </section>

          <section className="guide-section">
            <h3>Ana antrenman</h3>
            <p>Süre koşusu, mesafe koşusu veya tekrarlı interval yazabilirsiniz.</p>
            <table className="guide-table">
              <thead>
                <tr>
                  <th>Örnek</th>
                  <th>Anlam</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>
                    <code>45dk 6:00</code>
                  </td>
                  <td>45 dk @ 6:00/km</td>
                </tr>
                <tr>
                  <td>
                    <code>10km vdot</code>
                  </td>
                  <td>10 km, VDOT temposu</td>
                </tr>
                <tr>
                  <td>
                    <code>4x8dk vdot R 1dk</code>
                  </td>
                  <td>4×8 dk @ VDOT, 1 dk toparlanma</td>
                </tr>
                <tr>
                  <td>
                    <code>5x400 (1:51) R200m</code>
                  </td>
                  <td>5×400 m hedef 1:51, 200 m R</td>
                </tr>
                <tr>
                  <td>
                    <code>400m vdot R 1dk</code>
                  </td>
                  <td>Tek tekrar 400 m @ VDOT</td>
                </tr>
              </tbody>
            </table>
          </section>

          <section className="guide-section">
            <h3>Tempo ve VDOT</h3>
            <ul className="guide-list">
              <li>
                <code>7:00</code>, <code>7:00 pace</code>, <code>7:00p</code> — tek
                tempo
              </li>
              <li>
                <code>9:00-10:00</code> veya <code>6:00/5:50</code> — tempo aralığı
              </li>
              <li>
                <code>vdot</code> — sporcu VDOT değerinden tempo
              </li>
              <li>
                <code>5pace</code> — kısaltma: <code>5:00</code>/km
              </li>
            </ul>
          </section>

          <section className="guide-section">
            <h3>Toparlanma (R)</h3>
            <p>
              <code>R</code> veya <code>Toparlanma</code> ile yazın.{" "}
              <strong>R</strong> sonrasındaki tüm ifade toparlanma içindir — mesafe,
              süre ve/veya tempo.
            </p>
            <table className="guide-table">
              <thead>
                <tr>
                  <th>Örnek</th>
                  <th>Anlam</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>
                    <code>R 1dk</code>
                  </td>
                  <td>1 dk toparlanma</td>
                </tr>
                <tr>
                  <td>
                    <code>R200m</code> veya <code>R 200</code>
                  </td>
                  <td>200 m toparlanma</td>
                </tr>
                <tr>
                  <td>
                    <code>R 1dk 3:00 pace</code>
                  </td>
                  <td>1 dk @ 3:00/km tempo</td>
                </tr>
                <tr>
                  <td>
                    <code>6x5dk 3:00pace</code>
                  </td>
                  <td>Boşluksuz pace de geçerli</td>
                </tr>
                <tr>
                  <td>
                    <code>R400m 2:20</code>
                  </td>
                  <td>400 m, en fazla 2:20</td>
                </tr>
              </tbody>
            </table>
          </section>

          <section className="guide-section">
            <h3>Birimler</h3>
            <table className="guide-table">
              <thead>
                <tr>
                  <th>Tür</th>
                  <th>Kabul edilen</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>Süre</td>
                  <td>dk, dakika, min, saat, h, 1h30dk</td>
                </tr>
                <tr>
                  <td>Mesafe</td>
                  <td>m, metre, km, k, kilometre</td>
                </tr>
                <tr>
                  <td>Tekrar</td>
                  <td>x, *, ×, tekrar — örn. 4x400</td>
                </tr>
                <tr>
                  <td>Dinlenme günü</td>
                  <td>REST veya dinlenme</td>
                </tr>
              </tbody>
            </table>
          </section>

          <section className="guide-section guide-tip">
            <h3>İpucu</h3>
            <p>
              Metni yazdıktan sonra <strong>Önizleme</strong> butonuna basarak
              adımların doğru ayrıştığını kontrol edin. Kırmızı hata kartı görürseniz
              yazımı kılavuza göre düzeltin.
            </p>
          </section>
        </div>
      </div>
    </div>
  );
}
