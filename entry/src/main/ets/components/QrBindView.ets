import { ThemeService } from '../service/theme/ThemeService';
import { common } from '@kit.AbilityKit';
import { DreamMusicAuth } from '../service/network/DreamMusicAuth';
import { FONT_LABEL, RADIUS_CAPSULE } from '../common/DesignTokens';

/**
 * 网易云 QR 扫码绑定视图(阶段 v2.1/v2.2):
 * 登录页与设置页共用;进入即生成二维码,1.5s 轮询 801/802/800/803;
 * 绑定成功后回调 onBound。
 */
@Component
export struct QrBindView {
  @State theme: ThemeService = ThemeService.getInstance();
  onBound: () => void = () => {
  };
  @State qrImagePath: string = '';
  @State qrStatus: string = '';
  @State busy: boolean = false;
  private timer: number = -1;
  private unikey: string = '';

  aboutToAppear(): void {
    this.start();
  }

  aboutToDisappear(): void {
    this.stop();
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async start(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.qrStatus = '生成二维码中…';
    this.qrImagePath = '';
    try {
      const qr = await DreamMusicAuth.qrStart(this.ctx());
      this.unikey = qr.unikey;
      this.qrImagePath = 'file://' + qr.qrimgPath;
      this.qrStatus = '等待扫码…';
      this.poll();
    } catch (err) {
      this.qrStatus = '二维码生成失败:' + (err as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private poll(): void {
    this.stop();
    this.timer = setTimeout(() => {
      this.pollTick();
    }, 1500);
  }

  private async pollTick(): Promise<void> {
    try {
      const code = await DreamMusicAuth.qrCheck(this.ctx(), this.unikey);
      if (code === 803) {
        this.qrStatus = '绑定成功!';
        this.onBound();
        return;
      }
      if (code === 802) {
        this.qrStatus = '已扫码,请在手机上确认';
      } else if (code === 800) {
        this.qrStatus = '二维码已过期,请重新生成';
        return;
      } else {
        this.qrStatus = '等待扫码…';
      }
      this.poll();
    } catch (err) {
      this.qrStatus = '轮询失败:' + (err as Error).message;
      this.poll();
    }
  }

  private stop(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  build() {
    Column({ space: 12 }) {
      if (this.qrImagePath !== '') {
        Image(this.qrImagePath)
          .width(220)
          .height(220)
          .borderRadius(12)
          .objectFit(ImageFit.Contain)
          .backgroundColor('#FFFFFF')
      }
      Text(this.qrStatus)
        .fontSize(FONT_LABEL)
        .fontColor(this.theme.primaryText)
      Text('用网易云音乐 App 扫码,在手机上确认后自动绑定')
        .fontSize(11)
        .fontColor(this.theme.muted)
        .textAlign(TextAlign.Center)
      if (this.qrStatus.indexOf('过期') >= 0) {
        Text('重新生成')
          .fontSize(13)
          .fontColor(this.theme.primaryText)
          .padding({ left: 18, right: 18, top: 8, bottom: 8 })
          .borderRadius(RADIUS_CAPSULE)
          .border({ width: 1, color: ThemeService.alpha(this.theme.primary, 0.4) })
          .onClick(() => {
            this.start();
          })
      }
    }
    .width('100%')
  }
}
