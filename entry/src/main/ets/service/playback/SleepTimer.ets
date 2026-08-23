/** 定时暂停的纯逻辑状态，不依赖 ArkUI、播放器或网络。 */
export interface SleepTimerSnapshot {
  active: boolean;
  deadlineMs: number;
}

export class SleepTimer {
  private deadlineMs: number = 0;

  startAfter(durationMs: number, nowMs: number = Date.now()): void {
    if (durationMs <= 0) {
      this.cancel();
      return;
    }
    this.deadlineMs = nowMs + durationMs;
  }

  cancel(): void {
    this.deadlineMs = 0;
  }

  restore(snapshot: SleepTimerSnapshot, nowMs: number = Date.now()): void {
    if (!snapshot.active || snapshot.deadlineMs <= nowMs) {
      this.cancel();
      return;
    }
    this.deadlineMs = snapshot.deadlineMs;
  }

  remainingMs(nowMs: number = Date.now()): number {
    if (this.deadlineMs <= 0) {
      return 0;
    }
    return Math.max(0, this.deadlineMs - nowMs);
  }

  consumeIfDue(nowMs: number = Date.now()): boolean {
    if (this.deadlineMs <= 0 || nowMs < this.deadlineMs) {
      return false;
    }
    this.cancel();
    return true;
  }

  get snapshot(): SleepTimerSnapshot {
    return {
      active: this.deadlineMs > 0,
      deadlineMs: this.deadlineMs
    };
  }
}
