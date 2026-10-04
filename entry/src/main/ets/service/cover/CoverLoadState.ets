import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { CoverArtService, CoverLease } from './CoverArtService';

/** 每个显示节点持有独立请求序号；迟到结果只归还，不提交。 */
export class CoverLoadState {
  private revision: number = 0;
  private lease: CoverLease | null = null;

  async load(context: common.Context, uri: string, size: number,
    apply: (pixels: image.PixelMap | null) => void, keepCurrent: boolean = false): Promise<void> {
    if (keepCurrent) {
      this.revision++;
    } else {
      this.clear();
      apply(null);
    }
    const revision = this.revision;
    const lease = await CoverArtService.getInstance().acquire(context, uri, size);
    if (revision !== this.revision) {
      lease.release();
      return;
    }
    const previous = this.lease;
    this.lease = lease;
    apply(lease.pixelMap);
    if (previous !== null) {
      previous.release();
    }
  }

  clear(): void {
    this.revision++;
    if (this.lease !== null) {
      this.lease.release();
      this.lease = null;
    }
  }
}
