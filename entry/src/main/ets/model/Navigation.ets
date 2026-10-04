/** 应用主壳的根入口与“我的”子页面状态。 */
export enum RootTab {
  LIBRARY = 0,
  NOW_PLAYING = 1,
  QUEUE = 2,
  MY = 3
}

export enum MySubpage {
  HOME = 'home',
  PLAYLISTS = 'playlists',
  HISTORY = 'history',
  STATS = 'stats',
  ACCOUNT = 'account',
  ANNOUNCEMENTS = 'announcements',
  SETTINGS = 'settings'
}

export interface NavigationState {
  root: RootTab;
  myPage: MySubpage;
  sourceRoot: RootTab;
}

export enum BackAction {
  CLOSE_OVERLAY = 'close-overlay',
  MY_HOME = 'my-home',
  SOURCE_ROOT = 'source-root',
  DELEGATE_SYSTEM = 'delegate-system'
}

interface ChildBackHandler {
  priority: number;
  handle: () => boolean;
}

/** 只有 @Entry 接收系统返回；可见子组件显式注册，卸载时注销。 */
export class BackDispatcher {
  private handlers: Map<string, ChildBackHandler> = new Map<string, ChildBackHandler>();

  register(owner: string, priority: number, handle: () => boolean): void {
    this.handlers.set(owner, { priority: priority, handle: handle });
  }

  unregister(owner: string): void {
    this.handlers.delete(owner);
  }

  handle(): boolean {
    const ordered: ChildBackHandler[] = Array.from(this.handlers.values());
    ordered.sort((a: ChildBackHandler, b: ChildBackHandler) => b.priority - a.priority);
    for (const entry of ordered) {
      if (entry.handle()) { return true; }
    }
    return false;
  }
}

/** 纯逻辑返回策略，供入口事件和单元测试共同使用。 */
export function resolveBack(state: NavigationState, overlayOpen: boolean): BackAction {
  if (overlayOpen) {
    return BackAction.CLOSE_OVERLAY;
  }
  if (state.root === RootTab.MY && state.myPage !== MySubpage.HOME) {
    return state.sourceRoot === RootTab.MY ? BackAction.MY_HOME : BackAction.SOURCE_ROOT;
  }
  return BackAction.DELEGATE_SYSTEM;
}

export function selectRoot(current: NavigationState, next: RootTab): NavigationState {
  return {
    root: next,
    myPage: MySubpage.HOME,
    sourceRoot: next
  };
}

export function openMyPage(current: NavigationState, page: MySubpage,
  sourceRoot: RootTab = RootTab.MY): NavigationState {
  return {
    root: RootTab.MY,
    myPage: page,
    sourceRoot: current.root === RootTab.MY && current.myPage !== MySubpage.HOME
      ? current.sourceRoot : sourceRoot
  };
}
