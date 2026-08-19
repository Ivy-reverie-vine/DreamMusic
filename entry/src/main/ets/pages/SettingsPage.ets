import { ThemeService, BG_PRESETS, BgPreset, ThemeMode } from '../service/theme/ThemeService';
import { BackgroundAdapter } from '../service/theme/BackgroundAdapter';
import { LibraryScanService } from '../service/library/LibraryScanService';
import { networkViewModel, NetworkViewModel } from '../viewmodel/NetworkViewModel';
import { DreamMusicAuth, Announcement } from '../service/network/DreamMusicAuth';
import { OnlineMusicService } from '../service/network/OnlineMusicService';
import { ServerProfile } from '../model/Entities';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { OutlineButton } from '../components/OutlineButton';
import { QrBindView } from '../components/QrBindView';
import { RADIUS_CARD, RADIUS_CAPSULE, FONT_LABEL, FONT_TITLE } from '../common/DesignTokens';

interface ThemeModeOption {
  label: string;
  mode: ThemeMode;
}

const THEME_MODES: ThemeModeOption[] = [
  { label: '深色', mode: ThemeMode.DARK },
  { label: '浅色', mode: ThemeMode.LIGHT },
  { label: '跟随系统', mode: ThemeMode.SYSTEM }
];

/**
 * 设置页(issue-14 定稿 + 阶段 v2):
 * 主题模式三态(兑现 DESIGN.md,8/16 恢复入口)/ 背景图(内置预设 + 自定义 + 恢复默认)/
 * 账户(DreamMusic 中间层:登录/注册 + QR 绑定)/ 重新扫描 / 中间层连接(请求驱动,ADR-0003)/ 服务器配置(删除需确认)。
 */
@Component
export struct SettingsPage {
  @State theme: ThemeService = ThemeService.getInstance();
  @State scanStatus: string = '';
  @State bgStatus: string = '';
  @State net: NetworkViewModel = networkViewModel;
  @State newAlias: string = '';
  @State newUrl: string = '';
  /** 账户区状态与弹层:0=关 1=登录/注册 2=QR 绑定 */
  @State accountStatus: string = '';
  @State sheetMode: number = 0;
  /** 弹层显隐独立状态:拖拽关闭时 onDisappear 复位,避免"大框常驻"(v2.2 修复) */
  @State showSheet: boolean = false;
  @State username: string = '';
  @State password: string = '';
  @State inviteCode: string = 'dreammusic';
  @State busy: boolean = false;
  @State redeemCode: string = '';
  @State msgTitle: string = '';
  @State msgContent: string = '';
  @State announcements: Announcement[] = [];
  @State accountActionBusy: string = '';

  aboutToAppear(): void {
    this.net.load();
    this.refreshAccountStatus();
    this.loadAnnouncements();
  }

  private async loadAnnouncements(): Promise<void> {
    try {
      this.announcements = await DreamMusicAuth.announcements(this.ctx());
    } catch (err) {
      this.announcements = [];
    }
  }

  private async doCheckin(): Promise<void> {
    if (this.accountActionBusy !== '') {
      return;
    }
    this.accountActionBusy = 'checkin';
    this.accountStatus = '签到处理中…';
    try {
      const r = await DreamMusicAuth.checkin(this.ctx());
      this.accountStatus = r.alreadyChecked ? '今日已签到过' : '签到成功 +10 梦点';
    } catch (err) {
      this.accountStatus = '签到失败:' + (err as Error).message;
    } finally {
      this.accountActionBusy = '';
    }
  }

  private async doRedeem(): Promise<void> {
    if (this.redeemCode.trim() === '' || this.accountActionBusy !== '') {
      return;
    }
    this.accountActionBusy = 'redeem';
    this.accountStatus = '兑换处理中…';
    try {
      const r = await DreamMusicAuth.redeem(this.ctx(), this.redeemCode);
      this.accountStatus = '兑换成功 +' + r.redeemed + ' 梦点';
      this.redeemCode = '';
    } catch (err) {
      this.accountStatus = '兑换失败:' + (err as Error).message;
    } finally {
      this.accountActionBusy = '';
    }
  }

  private confirmSendMessage(): void {
    if (this.msgTitle.trim() === '' || this.msgContent.trim() === '') {
      this.accountStatus = '标题和内容不能为空';
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '发送消息',
      message: '将消耗 1 梦点发送到 Mewo(失败也扣,每日最多 3 次)。确定发送?',
      primaryButton: {
        value: '发送',
        action: () => {
          this.doSendMessage();
        }
      },
      secondaryButton: {
        value: '取消',
        action: () => {
        }
      }
    });
  }

  private async doSendMessage(): Promise<void> {
    if (this.accountActionBusy !== '') {
      return;
    }
    this.accountActionBusy = 'message';
    this.accountStatus = '发送处理中…';
    try {
      const r = await DreamMusicAuth.sendMessage(this.ctx(), this.msgTitle, this.msgContent);
      if (r.result === 'sent') {
        this.accountStatus = '消息已发送(今日剩余 ' + r.remaining + ' 次)';
      } else {
        const reason = r.detail !== '' ? r.detail : r.result;
        this.accountStatus = '已扣 1 梦点,发送未送达(' + reason + '),剩余 ' + r.remaining + ' 次';
      }
      this.msgTitle = '';
      this.msgContent = '';
    } catch (err) {
      this.accountStatus = '发送失败:' + (err as Error).message;
    } finally {
      this.accountActionBusy = '';
    }
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async setThemeMode(mode: ThemeMode): Promise<void> {
    let systemDark = false;
    if (mode === ThemeMode.SYSTEM) {
      try {
        const cfg = await this.ctx().resourceManager.getConfiguration();
        systemDark = (cfg.colorMode as number) === (ConfigurationConstant.ColorMode.COLOR_MODE_DARK as number);
      } catch (err) {
        systemDark = false;
      }
    }
    this.theme.applyMode(mode, systemDark);
    ThemeService.saveMode(this.ctx(), mode);
  }

  private async refreshAccountStatus(): Promise<void> {
    const ctx = this.ctx();
    if (!DreamMusicAuth.isLoggedIn(ctx)) {
      this.accountStatus = '未登录';
      return;
    }
    try {
      const user = await DreamMusicAuth.me(ctx);
      if (user === null) {
        this.accountStatus = '未登录';
        return;
      }
      if (user.status === 'banned') {
        this.accountStatus = '账号被封禁';
      } else if (user.bindInvalid) {
        this.accountStatus = `已登录:${user.username}(绑定失效,请重新扫码)`;
      } else if (user.bound) {
        this.accountStatus = `已登录:${user.username}(已绑定网易云)`;
      } else {
        this.accountStatus = `已登录:${user.username}(未绑定网易云)`;
      }
    } catch (err) {
      this.accountStatus = '会话失效,请重新登录';
    }
  }

  private async doLogin(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.accountStatus = '登录中…';
    try {
      await DreamMusicAuth.login(this.ctx(), this.username.trim(), this.password);
      OnlineMusicService.clearCache(this.ctx());
      OnlineMusicService.prefetch(this.ctx()).catch(() => {
      });
      this.sheetMode = 0;
      this.showSheet = false;
      await this.refreshAccountStatus();
      this.net.probe(this.ctx()).catch(() => {
      });
    } catch (err) {
      this.accountStatus = '登录失败:' + (err as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private async doRegister(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.accountStatus = '注册中…';
    try {
      await DreamMusicAuth.register(this.ctx(), this.username.trim(), this.password,
        this.inviteCode.trim());
      OnlineMusicService.clearCache(this.ctx());
      OnlineMusicService.prefetch(this.ctx()).catch(() => {
      });
      this.sheetMode = 0;
      this.showSheet = false;
      await this.refreshAccountStatus();
      this.net.probe(this.ctx()).catch(() => {
      });
    } catch (err) {
      this.accountStatus = '注册失败:' + (err as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private async doLogout(): Promise<void> {
    if (this.busy || this.accountActionBusy !== '') {
      return;
    }
    this.busy = true;
    this.accountStatus = '退出登录中…';
    try {
      await DreamMusicAuth.logout(this.ctx());
      OnlineMusicService.clearCache(this.ctx());
      await this.refreshAccountStatus();
      this.net.probe(this.ctx()).catch(() => {
      });
    } finally {
      this.busy = false;
    }
  }

  applyBg(index: number): void {
    // 切预设 = 放弃自定义背景(持久化同步)
    this.theme.applyPresetBg(index);
    ThemeService.saveBgIndex(this.ctx(), index);
    ThemeService.saveCustomBg(this.ctx(), '');
    this.bgStatus = `已应用背景 ${index + 1} · 取色中…`;
    BackgroundAdapter.extractPresetColors(this.ctx(), BG_PRESETS[index].res)
      .then((colors) => {
        this.theme.applyExtracted(colors.primary, colors.secondary);
        this.bgStatus = `已应用背景 ${index + 1}`;
      })
      .catch(() => {
        this.bgStatus = `已应用背景 ${index + 1}(取色失败,保持当前颜色)`;
      });
  }

  async pickCustomBg(): Promise<void> {
    this.bgStatus = '应用背景图中…';
    const err = await BackgroundAdapter.pickAndApply(this.ctx(), this.theme);
    this.bgStatus = err === '' ? '已应用自定义背景,界面随图而变' : err;
  }

  /** 恢复默认背景:清除自定义 → 回退上次内置预设(无则品牌种子色) */
  restoreDefaultBg(): void {
    BackgroundAdapter.removeBackgroundFiles(this.ctx());
    ThemeService.saveCustomBg(this.ctx(), '');
    const idx = this.theme.bgPresetIndex;
    if (idx >= 0 && idx < BG_PRESETS.length) {
      this.applyBg(idx);
    } else {
      this.theme.clearBackground();
      this.bgStatus = '已恢复默认主题色';
    }
  }

  async rescan(): Promise<void> {
    this.scanStatus = '扫描中…';
    const report = await LibraryScanService.scan(this.ctx());
    this.scanStatus = `新增 ${report.added},缺失 ${report.missing}`;
  }

  confirmRemoveProfile(p: ServerProfile): void {
    this.getUIContext().showAlertDialog({
      title: '删除服务器',
      message: `确定删除「${p.alias}」吗?此操作不可恢复。`,
      primaryButton: {
        value: '删除',
        action: () => {
          this.net.removeProfile(p.id, this.ctx());
        }
      },
      secondaryButton: {
        value: '取消',
        action: () => {
        }
      }
    });
  }

  @Builder
  SettingRow(icon: Resource, title: string, subtitle: string) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([this.theme.muted])
      Column({ space: 3 }) {
        Text(title)
          .fontSize(15)
          .fontColor(this.theme.ink)
        if (subtitle !== '') {
          Text(subtitle)
            .fontSize(11)
            .fontColor(this.theme.muted)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .borderRadius(RADIUS_CARD)
    .backgroundColor(this.theme.card)
  }

  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(FONT_LABEL)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.theme.muted)
      .width('100%')
      .padding({ left: 4, top: 10, bottom: 2 })
  }

  @Builder
  ThemeModeRow() {
    Row({ space: 8 }) {
      ForEach(THEME_MODES, (m: ThemeModeOption) => {
        Text(m.label)
          .fontSize(13)
          .fontColor(this.theme.mode === m.mode ? this.theme.primaryText : this.theme.muted)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .borderRadius(RADIUS_CAPSULE)
          .backgroundColor(this.theme.mode === m.mode
            ? ThemeService.alpha(this.theme.primary, 0.14)
            : this.theme.card)
          .stateStyles({
            pressed: { .opacity(0.6) }
          })
          .onClick(() => {
            this.setThemeMode(m.mode);
          })
      })
    }
    .width('100%')
    .padding({ left: 12, right: 12, bottom: 10 })
  }

  @Builder
  BgGrid() {
    // 横向可滚动:5 预设 + 自定义图块,窄屏不再溢出(8/16 修复)
    Scroll() {
      Row({ space: 10 }) {
        ForEach(BG_PRESETS, (p: BgPreset, index: number) => {
          Stack() {
            Image(p.res)
              .width(76)
              .height(132)
              .borderRadius(14)
              .objectFit(ImageFit.Cover)
            if (this.theme.bgCustomPath === '' && this.theme.bgPresetIndex === index) {
              Column()
                // 固定尺寸高亮层:避免横向 Scroll 内 100% 被解析成整行宽,出现巨大留白(8/16 真机修复)
                .width(76)
                .height(132)
                .borderRadius(14)
                .border({ width: 2, color: this.theme.primary })
                .backgroundColor(ThemeService.alpha(this.theme.primary, 0.18))
            }
          }
          .width(76)
          .height(132)
          .stateStyles({
            pressed: { .opacity(0.7) }
          })
          .onClick(() => {
            this.applyBg(index);
          })
        })

        // 自定义背景图块(阶段 v2 恢复)
        Stack() {
          Column({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(22)
              .fontColor([this.theme.muted])
            Text('自定义')
              .fontSize(11)
              .fontColor(this.theme.muted)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          if (this.theme.bgCustomPath !== '') {
            Column()
              .width('100%')
              .height('100%')
              .borderRadius(14)
              .border({ width: 2, color: this.theme.primary })
              .backgroundColor(ThemeService.alpha(this.theme.primary, 0.18))
          }
        }
        .width(76)
        .height(132)
        .borderRadius(14)
        .border({ width: 1, color: ThemeService.alpha(this.theme.primary, 0.45) })
        .stateStyles({
          pressed: { .opacity(0.7) }
        })
        .onClick(() => {
          this.pickCustomBg();
        })
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Auto)
    .width('100%')
    .padding({ left: 12, right: 12, bottom: 10 })
  }

  @Builder
  AuthSheet() {
    Column({ space: 10 }) {
      Text('登录 / 注册')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.ink)
        .width('100%')
      TextInput({ placeholder: '用户名(3-32 位字母/数字/_-)', text: this.username })
        .fontSize(14)
        .fontColor(this.theme.ink)
        .placeholderColor(this.theme.muted)
        .backgroundColor(ThemeService.alpha(this.theme.bg, 0.35))
        .borderRadius(12)
        .height(40)
        .width('100%')
        .onChange((v: string) => {
          this.username = v;
        })
      TextInput({ placeholder: '密码(至少 6 位)', text: this.password })
        .type(InputType.Password)
        .fontSize(14)
        .fontColor(this.theme.ink)
        .placeholderColor(this.theme.muted)
        .backgroundColor(ThemeService.alpha(this.theme.bg, 0.35))
        .borderRadius(12)
        .height(40)
        .width('100%')
        .onChange((v: string) => {
          this.password = v;
        })
      TextInput({ placeholder: '邀请码', text: this.inviteCode })
        .fontSize(14)
        .fontColor(this.theme.ink)
        .placeholderColor(this.theme.muted)
        .backgroundColor(ThemeService.alpha(this.theme.bg, 0.35))
        .borderRadius(12)
        .height(40)
        .width('100%')
        .onChange((v: string) => {
          this.inviteCode = v;
        })
      Row({ space: 12 }) {
        Text('登录')
          .fontSize(14)
          .fontColor(this.theme.primaryText)
          .padding({ left: 28, right: 28, top: 10, bottom: 10 })
          .borderRadius(RADIUS_CAPSULE)
          .backgroundColor(ThemeService.alpha(this.theme.primary, 0.14))
          .onClick(() => {
            this.doLogin();
          })
        Text('注册并登录')
          .fontSize(14)
          .fontColor(this.theme.primaryText)
          .padding({ left: 28, right: 28, top: 10, bottom: 10 })
          .borderRadius(RADIUS_CAPSULE)
          .border({ width: 1, color: ThemeService.alpha(this.theme.primary, 0.4) })
          .onClick(() => {
            this.doRegister();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 6 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.theme.bg)
  }

  @Builder
  QrSheet() {
    Column({ space: 12 }) {
      Text('绑定网易云账号')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.ink)
        .width('100%')
      QrBindView({
        onBound: () => {
          this.showSheet = false;
          this.sheetMode = 0;
          this.refreshAccountStatus();
        }
      })
    }
    .width('100%')
    .padding(20)
    .backgroundColor(this.theme.bg)
  }

  @Builder
  sheetContent() {
    if (this.sheetMode === 1) {
      this.AuthSheet()
    } else if (this.sheetMode === 2) {
      this.QrSheet()
    }
  }

  @Builder
  AccountSection() {
    this.SettingRow($r('sys.symbol.person_crop_circle_fill'), '账户', this.accountStatus)
    if (!DreamMusicAuth.isLoggedIn(this.ctx())) {
      Row() {
        OutlineButton({
          text: '登录 / 注册',
          onTap: (): void => {
            this.sheetMode = 1;
            this.showSheet = true;
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ right: 12, bottom: 10 })
    } else {
      Row({ space: 8 }) {
        if (DreamMusicAuth.isBound(this.ctx()) && !DreamMusicAuth.isBindInvalid(this.ctx())) {
          Text('已绑定网易云')
            .fontSize(12)
            .fontColor(this.theme.muted)
        } else {
          OutlineButton({
            text: '绑定网易云账号',
            onTap: (): void => {
              this.sheetMode = 2;
              this.showSheet = true;
            }
          })
        }
        Text('退出登录')
          .fontSize(12)
          .fontColor(this.theme.primaryText)
          .padding(8)
          .onClick(() => {
            this.doLogout();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ right: 12, bottom: 10 })

      // 梦点 + 每日签到(与 D:\Blog 中间层对齐)
      Row({ space: 12 }) {
        Text('梦点 ' + DreamMusicAuth.dreamPoints(this.ctx()))
          .fontSize(13)
          .fontColor(this.theme.ink)
        Text(this.accountActionBusy === 'checkin'
          ? '签到中…'
          : (DreamMusicAuth.checkedInToday(this.ctx()) ? '今日已签' : '每日签到 +10'))
          .fontSize(12)
          .fontColor(this.theme.primaryText)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(RADIUS_CAPSULE)
          .backgroundColor(ThemeService.alpha(this.theme.primary, 0.14))
          .onClick(() => {
            if (!DreamMusicAuth.checkedInToday(this.ctx())) {
              this.doCheckin();
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ right: 12, bottom: 6 })

      // 兑换码
      Row({ space: 8 }) {
        TextInput({ placeholder: '兑换码', text: this.redeemCode })
          .fontSize(13)
          .fontColor(this.theme.ink)
          .placeholderColor(this.theme.muted)
          .backgroundColor(ThemeService.alpha(this.theme.bg, 0.35))
          .borderRadius(12)
          .height(36)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.redeemCode = v;
          })
        Text(this.accountActionBusy === 'redeem' ? '兑换中…' : '兑换')
          .fontSize(13)
          .fontColor(this.theme.primaryText)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(RADIUS_CAPSULE)
          .border({ width: 1, color: ThemeService.alpha(this.theme.primary, 0.4) })
          .onClick(() => {
            this.doRedeem();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 10 })

      // 发消息(Bark 式 webhook,扣 1 梦点,每日 3 次,失败也扣)
      Text('发消息 · 今日 ' + DreamMusicAuth.messageToday(this.ctx()) + '/3')
        .fontSize(FONT_LABEL)
        .fontColor(this.theme.muted)
        .width('100%')
        .padding({ left: 12, right: 12 })
      TextInput({ placeholder: '标题(≤40 字)', text: this.msgTitle })
        .fontSize(13)
        .fontColor(this.theme.ink)
        .placeholderColor(this.theme.muted)
        .backgroundColor(ThemeService.alpha(this.theme.bg, 0.35))
        .borderRadius(12)
        .height(34)
        .width('100%')
        .onChange((v: string) => {
          this.msgTitle = v;
        })
      TextInput({ placeholder: '内容(≤200 字)', text: this.msgContent })
        .fontSize(13)
        .fontColor(this.theme.ink)
        .placeholderColor(this.theme.muted)
        .backgroundColor(ThemeService.alpha(this.theme.bg, 0.35))
        .borderRadius(12)
        .height(34)
        .width('100%')
        .onChange((v: string) => {
          this.msgContent = v;
        })
      Row({ space: 8 }) {
        Text(this.accountActionBusy === 'message' ? '发送中…' : '发送(1 梦点)')
          .fontSize(13)
          .fontColor(this.theme.primaryText)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(RADIUS_CAPSULE)
          .backgroundColor(ThemeService.alpha(this.theme.primary, 0.14))
          .onClick(() => {
            this.confirmSendMessage();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ left: 12, right: 12, bottom: 10 })

    }
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Text('设置')
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.ink)
          .width('100%')

        this.SectionTitle('外观')
        // 主题模式(三态,阶段 v2 恢复入口)
        this.SettingRow($r('sys.symbol.sun_max'), '主题模式', '深色 / 浅色 / 跟随系统')
        this.ThemeModeRow()

        // 背景图(内置预设 + 自定义 + 恢复默认)
        this.SettingRow($r('sys.symbol.paintpalette'), '背景图',
          this.bgStatus !== '' ? this.bgStatus : '内置氛围图或选择自定义图片,界面随图取色')
        this.BgGrid()
        if (this.theme.bgCustomPath !== '') {
          Row() {
            Text('恢复默认背景')
              .fontSize(FONT_LABEL)
              .fontColor(this.theme.primaryText)
              .onClick(() => {
                this.restoreDefaultBg();
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
          .padding({ right: 12, bottom: 10 })
        }

        this.SectionTitle('账户')
        // 账户(DreamMusic 中间层:登录/注册 + QR 绑定 + 退出)
        this.AccountSection()

        // 平台公告(公开接口,无需登录)
        if (this.announcements.length > 0) {
          this.SettingRow($r('sys.symbol.doc_text'), '平台公告',
            this.announcements.length + ' 条公告')
          ForEach(this.announcements, (a: Announcement) => {
            Column({ space: 4 }) {
              Text(a.title)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.theme.ink)
                .width('100%')
              if (a.content !== '') {
                Text(a.content)
                  .fontSize(11)
                  .fontColor(this.theme.muted)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(RADIUS_CARD)
            .backgroundColor(this.theme.card)
          })
        }

        this.SectionTitle('本地音乐库')
        // 重新扫描
        this.SettingRow($r('sys.symbol.arrow_clockwise'), '重新扫描',
          this.scanStatus !== '' ? this.scanStatus : '比对沙箱目录与数据库')
        Row() {
          OutlineButton({
            text: '扫描',
            onTap: (): void => {
              this.rescan();
            }
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 12, bottom: 10 })

        this.SectionTitle('网络')
        // DreamMusic 中间层连接(请求驱动,ADR-0003)
        this.SettingRow($r('sys.symbol.wifi'), 'DreamMusic 中间层', this.net.statusText)
        Row() {
          OutlineButton({
            text: '刷新',
            onTap: (): void => {
              this.net.probe(this.ctx());
            }
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 12, bottom: 10 })

        Row({ space: 8 }) {
          TextInput({ placeholder: '别名(可选)', text: this.newAlias })
            .fontSize(13)
            .fontColor(this.theme.ink)
            .placeholderColor(this.theme.muted)
            .backgroundColor(this.theme.card)
            .borderRadius(12)
            .height(38)
            .width(110)
            .onChange((v: string) => {
              this.newAlias = v;
            })
          TextInput({ placeholder: 'http://IP:3001 或 https://域名', text: this.newUrl })
            .fontSize(13)
            .fontColor(this.theme.ink)
            .placeholderColor(this.theme.muted)
            .backgroundColor(this.theme.card)
            .borderRadius(12)
            .height(38)
            .layoutWeight(1)
            .onChange((v: string) => {
              this.newUrl = v;
            })
          OutlineButton({
            text: '添加',
            onTap: (): void => {
              this.net.addProfile(this.newAlias, this.newUrl, this.ctx()).then(() => {
                this.newAlias = '';
                this.newUrl = '';
              });
            }
          })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 6 })

        ForEach(this.net.profiles, (p: ServerProfile) => {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(p.alias)
                .fontSize(14)
                .fontColor(this.theme.ink)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(p.url)
                .fontSize(11)
                .fontColor(this.theme.muted)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            if (!p.isCurrent) {
              Text('设为当前')
                .fontSize(12)
                .fontColor(this.theme.primaryText)
                .onClick(() => {
                  this.net.setCurrent(p.id, this.ctx());
                })
            } else {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(13)
                  .fontColor([this.theme.primaryText])
                Text('当前')
                  .fontSize(12)
                  .fontColor(this.theme.primaryText)
              }
            }
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(15)
              .fontColor([this.theme.muted])
              .padding(4)
              .onClick(() => {
                this.confirmRemoveProfile(p);
              })
          }
          .width('100%')
          .padding(10)
          .borderRadius(12)
          .backgroundColor(this.theme.card)
        })
      }
      .padding(20)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .bindSheet(this.showSheet, this.sheetContent(), {
      height: this.sheetMode === 1 ? 320 : 380,
      backgroundColor: this.theme.bg,
      onDisappear: () => {
        this.showSheet = false;
        this.sheetMode = 0;
      }
    })
  }
}
