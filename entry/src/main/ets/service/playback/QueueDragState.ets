export interface QueueRowBounds {
  id: number;
  top: number;
  height: number;
}

/** 按真实行中心寻找落位目标；不同字体/行高不依赖固定步长。 */
export function nearestQueueRow(y: number, rows: QueueRowBounds[]): number | null {
  let nearest: number | null = null;
  let distance = Number.MAX_VALUE;
  rows.forEach((row: QueueRowBounds) => {
    const delta = Math.abs(y - row.top - row.height / 2);
    if (delta < distance) {
      distance = delta;
      nearest = row.id;
    }
  });
  return nearest;
}

/** 排序草稿只记录源与目标；取消/队列发生外部变化时不写回。 */
export class QueueDragState {
  private original: number[] = [];
  private source: number = -1;
  private target: number = -1;

  begin(ids: number[], id: number): boolean {
    this.cancel();
    this.source = ids.indexOf(id);
    if (this.source < 0) {
      return false;
    }
    this.original = ids.slice();
    this.target = this.source;
    return true;
  }

  setTarget(index: number): void {
    this.target = index >= 0 && index < this.original.length ? index : -1;
  }

  finish(current: number[]): number[] | null {
    const unchanged = current.length === this.original.length &&
      current.every((id: number, index: number) => id === this.original[index]);
    let result: number[] | null = null;
    if (unchanged && this.source >= 0 && this.target >= 0 && this.source !== this.target) {
      result = this.original.slice();
      const moved = result.splice(this.source, 1)[0];
      result.splice(this.target, 0, moved);
    }
    this.cancel();
    return result;
  }

  cancel(): void {
    this.original = [];
    this.source = -1;
    this.target = -1;
  }
}
