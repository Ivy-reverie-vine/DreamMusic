import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo } from '@kit.FormKit';
import { PLAYLIST_ID_KEY } from '../model/PlaybackLaunch';
import { PlaylistCardSnapshot } from '../model/PlaylistCard';
import { PlaylistFormStore } from '../service/form/PlaylistFormStore';

export default class PlaylistFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const id = String(want.parameters?.[formInfo.FormParam.IDENTITY_KEY] ?? '');
    const target = Number(want.parameters?.[PLAYLIST_ID_KEY] ?? 0);
    const initial = new PlaylistCardSnapshot();
    try {
      PlaylistFormStore.bind(this.context, id, target);
      initial.playlistId = PlaylistFormStore.readId(this.context, id);
      if (initial.playlistId > 0) { initial.title = '本地歌单'; }
      this.onUpdateForm(id);
    } catch (err) {}
    return PlaylistFormStore.binding(initial);
  }

  onUpdateForm(formId: string): void { PlaylistFormStore.update(this.context, formId); }
  onCastToNormalForm(formId: string): void { this.onUpdateForm(formId); }
  onChangeFormVisibility(status: Record<string, number>): void {
    Object.keys(status).forEach((id: string) => {
      if (status[id] === formInfo.VisibilityType.FORM_VISIBLE) { this.onUpdateForm(id); }
    });
  }
  onRemoveForm(formId: string): void {
    try { PlaylistFormStore.remove(this.context, formId); } catch (err) {}
  }
}
