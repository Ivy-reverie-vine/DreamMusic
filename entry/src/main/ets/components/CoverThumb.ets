import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { ThemeService } from '../service/theme/ThemeService';
import { CoverLoadState } from '../service/cover/CoverLoadState';

/** 三个应用入口和系统播控共用封面缓存及同一品牌渐变音乐占位图。 */
@Component
export struct CoverThumb {
  @State theme: ThemeService = ThemeService.getInstance();
  @Prop @Watch('reload') uri: string = '';
  @Prop @Watch('reload') identity: string = '';
  @Prop thumbSize: number = 44;
  @Prop decodeSize: number = 96;
  @Prop circular: boolean = false;
  @Prop withShadow: boolean = true;
  @State pixels: image.PixelMap | null = null;
  private loader: CoverLoadState = new CoverLoadState();
  private visible: boolean = false;
  private displayedIdentity: string = '';

  aboutToAppear(): void {
    this.visible = true;
    this.reload();
  }

  aboutToDisappear(): void {
    this.visible = false;
    this.pixels = null;
    this.loader.clear();
  }

  private reload(): void {
    if (!this.visible) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.Context;
    const keepCurrent = this.identity !== '' && this.identity === this.displayedIdentity;
    this.displayedIdentity = this.identity;
    this.loader.load(context, this.uri, this.decodeSize, (pixels: image.PixelMap | null) => {
      this.pixels = pixels;
    }, keepCurrent);
  }

  build() {
    Image(this.pixels !== null ? this.pixels : $r('app.media.cover_placeholder'))
      .width(this.thumbSize)
      .height(this.thumbSize)
      .objectFit(ImageFit.Cover)
      .borderRadius(this.circular ? this.thumbSize / 2 : this.thumbSize * 0.25)
      .shadow({ radius: this.withShadow ? 10 : 0,
        color: this.theme.isDark ? ThemeService.alpha('#000000', 0.28) : this.theme.shadowColor,
        offsetX: 0, offsetY: this.withShadow ? 4 : 0 })
  }
}
