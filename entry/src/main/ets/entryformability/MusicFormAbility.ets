import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo } from '@kit.FormKit';
import { MusicFormStore } from '../service/form/MusicFormStore';

export default class MusicFormAbility extends FormExtensionAbility {
  private removed: Set<string> = new Set<string>();

  onAddForm(want: Want): formBindingData.FormBindingData {
    const id = String(want.parameters?.[formInfo.FormParam.IDENTITY_KEY] ?? '');
    this.removed.delete(id);
    // 同步返回文案，随后通过 updateForm 的完成边界管理封面 fd 生命周期。
    this.refresh(id);
    return MusicFormStore.binding(MusicFormStore.read(this.context));
  }

  onUpdateForm(formId: string): void { this.refresh(formId); }
  onCastToNormalForm(formId: string): void { this.refresh(formId); }
  onChangeFormVisibility(newStatus: Record<string, number>): void {
    Object.keys(newStatus).forEach((id: string) => {
      if (newStatus[id] === formInfo.VisibilityType.FORM_VISIBLE) { this.refresh(id); }
    });
  }

  private refresh(id: string): void {
    Promise.resolve().then(async () => {
      if (id === '' || this.removed.has(id)) { return; }
      await MusicFormStore.update(this.context, id, MusicFormStore.read(this.context));
    }).catch(() => {});
  }

  onRemoveForm(formId: string): void {
    this.removed.add(formId);
    // 无 timer、持久化实例表或播放会话；平台实例列表自动移除本卡片。
  }
}
