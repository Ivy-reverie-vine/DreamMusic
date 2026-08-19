import { ThemeService } from '../service/theme/ThemeService';
import { common } from '@kit.AbilityKit';
import { DreamMusicAuth } from '../service/network/DreamMusicAuth';
import { OnlineMusicService } from '../service/network/OnlineMusicService';
import { QrBindView } from './QrBindView';
import { BackgroundLayer } from './BackgroundLayer';
import { HandwrittenLogo } from './HandwrittenLogo';
import { FONT_LABEL, RADIUS_CAPSULE, RADIUS_CARD } from '../common/DesignTokens';

/**
 * 登录门禁(阶段 v2.2,用户拍板:不登录无法进入):
 * 登录/注册(邀请码)→ 成功后若未绑定网易云,自动进入 QR 绑定步骤(可跳过);
 * 全部通过后回调 onLoggedIn 进入主界面。
 */
@Component
export struct LoginView {
  onLoggedIn: () => void = () => {
  };
  /** 跳过登录(本地歌可先听;在线功能再用时提示登录) */
  onSkip: () => void = () => {
  };
  @State theme: ThemeService = ThemeService.getInstance();
  @State mode: string = 'login';
  @State username: string = '';
  @State password: string = '';
  @State inviteCode: string = 'dreammusic';
  @State statusText: string = '';
  @State busy: boolean = false;
  /** 登录成功但未绑定网易云 → 展示 QR 绑定步骤 */
  @State needBind: boolean = false;
  /** 手写 Logo 写完 → 副标题淡入 */
  @State logoDone: boolean = false;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async submit(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
      this.statusText = this.mode === 'login' ? '登录中…' : '注册中…';
    try {
      OnlineMusicService.clearCache(this.ctx());
      if (this.mode === 'login') {
        await DreamMusicAuth.login(this.ctx(), this.username.trim(), this.password);
      } else {
        await DreamMusicAuth.register(this.ctx(), this.username.trim(), this.password,
          this.inviteCode.trim());
      }
      if (DreamMusicAuth.isBound(this.ctx()) && !DreamMusicAuth.isBindInvalid(this.ctx())) {
        OnlineMusicService.prefetch(this.ctx()).catch(() => {
        });
        this.onLoggedIn();
      } else {
        this.needBind = true;
      }
    } catch (err) {
      this.statusText = (err as Error).message;
    } finally {
      this.busy = false;
    }
  }

  @Builder
  Field(placeholder: string, value: string, secret: boolean, onChange: (v: string) => void) {
    TextInput({ placeholder: placeholder, text: value })
      .type(secret ? InputType.Password : InputType.Normal)
      .fontSize(14)
      .fontColor(this.theme.ink)
      .placeholderColor(this.theme.muted)
      .backgroundColor(this.theme.card)
      .borderRadius(12)
      .height(42)
      .width('100%')
      .onChange((v: string) => {
        onChange(v);
      })
  }

  build() {
    Stack() {
      // 背景与主界面一致:近黑底 + 背景图 + 蒙层(v2.2)
      BackgroundLayer()

      Scroll() {
        Column({ space: 18 }) {
          if (this.needBind) {
            Column({ space: 18 }) {
              Text('绑定网易云账号')
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.theme.ink)
              QrBindView({
                onBound: () => {
                  this.onLoggedIn();
                }
              })
              Text('暂不绑定,先进入')
                .fontSize(13)
                .fontColor(this.theme.muted)
                .padding(10)
                .onClick(() => {
                  this.onLoggedIn();
                })
            }
            .width('100%')
          } else {
            // 品牌区:逐笔手写 Logo + 副标题(写完淡入)
            Column({ space: 12 }) {
              HandwrittenLogo({
                onDone: () => {
                  this.logoDone = true;
                }
              })
              Text('梦有回响,点滴成光')
                .fontSize(15)
                .fontColor(this.theme.muted)
                .opacity(this.logoDone ? 1 : 0)
                .animation({ duration: 500, curve: Curve.EaseOut })
            }
            .width('100%')

            // 表单卡片(静谧克制:半透明卡片 + 胶囊主按钮)
            Column({ space: 12 }) {
              Text(this.mode === 'login' ? '登录 DreamMusic 账户' : '注册 DreamMusic 账户')
                .fontSize(FONT_LABEL)
                .fontColor(this.theme.muted)
                .width('100%')
              this.Field('用户名', this.username, false, (v: string) => {
                this.username = v;
              })
              this.Field('密码(至少 6 位)', this.password, true, (v: string) => {
                this.password = v;
              })
              if (this.mode === 'register') {
                this.Field('邀请码', this.inviteCode, false, (v: string) => {
                  this.inviteCode = v;
                })
              }

          Text(this.statusText !== '' ? this.statusText : ' ')
            .fontSize(FONT_LABEL)
            .fontColor(this.theme.errorColor)
                .width('100%')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(this.mode === 'login' ? '登录' : '注册并登录')
                .fontSize(15)
                .fontColor(this.theme.primaryText)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 12, bottom: 12 })
                .borderRadius(RADIUS_CAPSULE)
                .backgroundColor(ThemeService.alpha(this.theme.primary, 0.14))
                .onClick(() => {
                  this.submit();
                })

              Text(this.mode === 'login' ? '没有账户?去注册' : '已有账户?去登录')
                .fontSize(13)
                .fontColor(this.theme.primaryText)
                .padding(8)
                .onClick(() => {
                  this.mode = this.mode === 'login' ? 'register' : 'login';
                  this.statusText = '';
                })
              if (this.mode === 'login') {
                Text('跳过,先听本地歌')
                  .fontSize(13)
                  .fontColor(this.theme.muted)
                  .padding(10)
                  .onClick(() => {
                    this.onSkip();
                  })
              }
            }
            .width('100%')
            .padding(18)
            .borderRadius(RADIUS_CARD)
            .backgroundColor(this.theme.card)
          }
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 88, bottom: 48 })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }
}
