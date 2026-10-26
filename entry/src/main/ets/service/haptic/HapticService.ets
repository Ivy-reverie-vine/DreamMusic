import { vibrator } from '@kit.SensorServiceKit';
import { accessibility } from '@kit.AccessibilityKit';

export class HapticService {
  private static isAnimationReduceEnabled(): boolean {
    try {
      return accessibility.isAnimationReduceEnabledSync();
    } catch (_e) {
      return false;
    }
  }

  private static vibrate(presetEffectId: string, fallbackMs: number): void {
    try {
      if (HapticService.isAnimationReduceEnabled()) {
        return;
      }
      const attribute: vibrator.VibrateAttribute = {
        usage: 'touch'
      };
      const preset: vibrator.VibratePreset = {
        type: 'preset',
        effectId: presetEffectId,
        count: 1
      };
      vibrator.startVibration(preset, attribute).catch((_err: Error) => {
        try {
          const fallback: vibrator.VibrateTime = {
            type: 'time',
            duration: fallbackMs
          };
          vibrator.startVibration(fallback, attribute).catch((_err2: Error) => {
            // Silently ignore on unsupported devices or simulator
          });
        } catch (_innerErr) {
          // Silently ignore
        }
      });
    } catch (_e) {
      // Silently ignore
    }
  }

  /** 队列拖拽排序吸附时的轻短触感 */
  static triggerDragSnap(): void {
    HapticService.vibrate(vibrator.EffectId.EFFECT_CLOCK_TIMER, 15);
  }

  /** 点击收藏点赞时的轻快清脆触感 */
  static triggerFavorite(): void {
    HapticService.vibrate('haptic.effect.sharp', 25);
  }

  /** 切换模式或关键轻击时的反馈 */
  static triggerSelection(): void {
    HapticService.vibrate('haptic.effect.soft', 15);
  }
}
