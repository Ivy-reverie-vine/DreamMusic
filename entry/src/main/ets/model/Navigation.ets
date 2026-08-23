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
    sourceRoot: sourceRoot
  };
}
