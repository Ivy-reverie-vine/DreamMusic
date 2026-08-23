import { describe, it, expect } from '@ohos/hypium';
import {
  BackAction, MySubpage, RootTab, NavigationState, openMyPage, resolveBack, selectRoot
} from '../main/ets/model/Navigation';

export default function navigationTest() {
  describe('NavigationPolicy', () => {
    const home: NavigationState = {
      root: RootTab.MY,
      myPage: MySubpage.HOME,
      sourceRoot: RootTab.MY
    };

    it('closes_overlay_before_page', 0, () => {
      expect(resolveBack(openMyPage(home, MySubpage.SETTINGS), true))
        .assertEqual(BackAction.CLOSE_OVERLAY);
    });

    it('returns_my_child_to_home', 0, () => {
      expect(resolveBack(openMyPage(home, MySubpage.HISTORY), false))
        .assertEqual(BackAction.MY_HOME);
    });

    it('returns_deep_link_to_source_root', 0, () => {
      expect(resolveBack(openMyPage({
        root: RootTab.LIBRARY,
        myPage: MySubpage.HOME,
        sourceRoot: RootTab.LIBRARY
      }, MySubpage.ACCOUNT, RootTab.LIBRARY), false))
        .assertEqual(BackAction.SOURCE_ROOT);
    });

    it('delegates_at_root', 0, () => {
      expect(resolveBack(home, false)).assertEqual(BackAction.DELEGATE_SYSTEM);
    });

    it('root_selection_resets_my_child', 0, () => {
      const next = selectRoot(openMyPage(home, MySubpage.STATS), RootTab.QUEUE);
      expect(next.root).assertEqual(RootTab.QUEUE);
      expect(next.myPage).assertEqual(MySubpage.HOME);
    });
  });
}
