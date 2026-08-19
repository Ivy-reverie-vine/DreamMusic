/**
 * 东八区自然日 YYYY-MM-DD(与 DreamMusic 中间层 shanghaiDate 对齐,纯逻辑可单测)。
 */
export function shanghaiDateString(now: number = Date.now()): string {
  const shifted = new Date(now + 8 * 3600 * 1000);
  const y = shifted.getUTCFullYear();
  const m = shifted.getUTCMonth() + 1;
  const d = shifted.getUTCDate();
  const mm = m < 10 ? '0' + m : String(m);
  const dd = d < 10 ? '0' + d : String(d);
  return y + '-' + mm + '-' + dd;
}
