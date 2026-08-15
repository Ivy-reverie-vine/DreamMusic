import { ThemeService } from '../service/theme/ThemeService';
import { RADIUS_CAPSULE } from '../common/DesignTokens';

/** 描边胶囊按钮(issue-13 设置页/歌单页统一控件;无实色块) */
@Component
export struct OutlineButton {
  @Prop theme: ThemeService;
  @Prop text: string;
  onTap: () => void = () => {
  };

  build() {
    Text(this.text)
      .fontSize(13)
      .fontColor(this.theme.primary)
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .borderRadius(RADIUS_CAPSULE)
      .border({ width: 1, color: ThemeService.alpha(this.theme.primary, 0.4) })
      .stateStyles({
        pressed: { .opacity(0.6) }
      })
      .onClick(() => {
        this.onTap();
      })
  }
}
