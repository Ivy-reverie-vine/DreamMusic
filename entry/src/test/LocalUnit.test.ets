import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import colorExtractTest from './ColorExtract.test';
import importPlannerTest from './ImportPlanner.test';
import scanDiffTest from './ScanDiff.test';
import queueEngineTest from './QueueEngine.test';
import lrcParserTest from './LrcParser.test';

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    });
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    });
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    });
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    });
    it('assertContain', 0, () => {
      // Defines a test case. This API supports three parameters: test case name, filter parameter, and test case function.
      let a = 'abc';
      let b = 'b';
      // Defines a variety of assertion methods, which are used to declare expected boolean conditions.
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });
    // 新增测试套件入口:hvigor CLI 不会自动发现 src/test 下的新文件,
    // 统一在此 import 并调用其默认导出(IDE 环境同样兼容)。见 docs/research/build-environment.md
    colorExtractTest();
    importPlannerTest();
    scanDiffTest();
    queueEngineTest();
    lrcParserTest();
  });
}