const DAY_LABELS = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"] as const;

export function mondayOf(date: Date): Date {
  const d = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const weekday = d.getDay();
  const daysToMonday = weekday === 0 ? 6 : weekday - 1;
  d.setDate(d.getDate() - daysToMonday);
  return d;
}

export function ymd(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

export function dayDate(weekStartMonday: Date, index: number): Date {
  const d = new Date(weekStartMonday);
  d.setDate(d.getDate() + index);
  return d;
}

export function weekTitle(weekStartMonday: Date): string {
  const end = new Date(weekStartMonday);
  end.setDate(end.getDate() + 6);
  const fmt = new Intl.DateTimeFormat("tr-TR", {
    day: "numeric",
    month: "short",
  });
  return `${fmt.format(weekStartMonday)} – ${fmt.format(end)} ${end.getFullYear()}`;
}

export function monthKey(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

export { DAY_LABELS };
