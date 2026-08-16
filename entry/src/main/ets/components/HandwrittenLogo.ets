import { ThemeService } from '../service/theme/ThemeService';
import { accessibility } from '@kit.AccessibilityKit';
import { layoutHandwritten, HandwrittenLayout, HandwrittenStroke } from './HandwrittenLayout';

/**
 * IvyReverie 逐笔书写 Logo(阶段 v2.2,Canvas 版):
 * 网页端(SVG dashoffset)在 ArkUI Path 上存在坐标缩放与动画不可控问题(真机反馈),
 * 改 Canvas 2D 逐帧部分绘制——坐标显式 vp、动画由定时器驱动,行为确定;
 * 系统"减弱动效"时一次性画完。写完回调 onDone(副标题淡入)。
 */
@Component
export struct HandwrittenLogo {
  @State theme: ThemeService = ThemeService.getInstance();
  onDone: () => void = () => {
  };
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx2d: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private layout: HandwrittenLayout = layoutHandwritten('IvyReverie', 260, 3000);
  private animTimer: number = -1;
  private startedAt: number = 0;

  aboutToDisappear(): void {
    this.stop();
  }

  private reduceMotion(): boolean {
    try {
      return accessibility.isAnimationReduceEnabledSync();
    } catch (err) {
      return false;
    }
  }

  private stop(): void {
    if (this.animTimer >= 0) {
      clearTimeout(this.animTimer);
      this.animTimer = -1;
    }
  }

  /** Canvas 就绪后开始(动画必须等 onReady,否则首帧画不上) */
  private start(): void {
    this.startedAt = Date.now();
    if (this.reduceMotion()) {
      this.drawAt(this.layout.totalMs + 1);
      this.onDone();
      return;
    }
    this.tick();
  }

  private tick(): void {
    const elapsed = Date.now() - this.startedAt;
    this.drawAt(elapsed);
    if (elapsed >= this.layout.totalMs) {
      this.onDone();
      return;
    }
    this.animTimer = setTimeout(() => {
      this.tick();
    }, 16);
  }

  private drawAt(elapsedMs: number): void {
    const ctx = this.ctx2d;
    const w = this.layout.width;
    const h = this.layout.height;
    ctx.clearRect(0, 0, w, h);
    ctx.strokeStyle = this.theme.primaryText;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    for (let i = 0; i < this.layout.strokes.length; i++) {
      const s = this.layout.strokes[i];
      if (elapsedMs < s.delayMs) {
        continue;
      }
      const progress = Math.min(1, (elapsedMs - s.delayMs) / s.durMs);
      this.drawStroke(ctx, s, progress);
    }
  }

  private drawStroke(ctx: CanvasRenderingContext2D, s: HandwrittenStroke, progress: number): void {
    const pts = s.points;
    if (pts.length === 0 || progress <= 0) {
      return;
    }
    const targetLen = s.len * progress;
    ctx.lineWidth = Math.max(0.5, s.width);
    ctx.beginPath();
    ctx.moveTo(pts[0][0], pts[0][1]);
    if (targetLen <= 0) {
      ctx.stroke();
      return;
    }
    let acc = 0;
    for (let i = 1; i < pts.length; i++) {
      const dx = pts[i][0] - pts[i - 1][0];
      const dy = pts[i][1] - pts[i - 1][1];
      const seg = Math.sqrt(dx * dx + dy * dy);
      if (acc + seg >= targetLen) {
        const rem = targetLen - acc;
        const k = seg > 0 ? rem / seg : 1;
        ctx.lineTo(pts[i - 1][0] + dx * k, pts[i - 1][1] + dy * k);
        break;
      }
      ctx.lineTo(pts[i][0], pts[i][1]);
      acc += seg;
    }
    ctx.stroke();
  }

  build() {
    Canvas(this.ctx2d)
      .width(this.layout.width)
      .height(this.layout.height)
      .onReady(() => {
        this.start();
      })
  }
}
