import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';

export interface SecureReadResult {
  value: string;
  available: boolean;
}

/**
 * HarmonyOS AssetStoreKit 封装:
 * - SECRET 保存敏感凭证正文;
 * - ALIAS 作为稳定查询键;
 * - DEVICE_FIRST_UNLOCKED 避免设备首次解锁前读取;
 * - 不设置 IS_PERSISTENT,卸载应用时不保留账户凭证。
 */
export class SecureCredentialStore {
  private static readonly encoder = util.TextEncoder.create('utf-8');
  private static readonly decoder = util.TextDecoder.create('utf-8');

  static async read(alias: string): Promise<SecureReadResult> {
    const query = SecureCredentialStore.aliasQuery(alias, true);
    try {
      const rows = await asset.query(query);
      if (rows.length === 0) {
        return { value: '', available: true };
      }
      const secret = rows[0].get(asset.Tag.SECRET);
      if (!(secret instanceof Uint8Array)) {
        return { value: '', available: true };
      }
      return {
        value: SecureCredentialStore.decoder.decodeToString(secret),
        available: true
      };
    } catch (err) {
      const code = SecureCredentialStore.errorCode(err);
      // 资产不存在属于正常首次读取，不代表 AssetStoreKit 不可用。
      if (code === 24000002) {
        return { value: '', available: true };
      }
      return { value: '', available: false };
    }
  }

  static async write(alias: string, value: string): Promise<void> {
    if (value === '') {
      await SecureCredentialStore.remove(alias);
      return;
    }
    const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, SecureCredentialStore.encoder.encodeInto(alias));
    attributes.set(asset.Tag.SECRET, SecureCredentialStore.encoder.encodeInto(value));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attributes.set(asset.Tag.AUTH_TYPE, asset.AuthType.NONE);
    attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    await asset.add(attributes);
  }

  static async remove(alias: string): Promise<void> {
    try {
      await asset.remove(SecureCredentialStore.aliasQuery(alias, false));
    } catch (err) {
      // 删除不存在的资产是幂等操作;其它错误交给调用方决定是否提示。
      if (SecureCredentialStore.errorCode(err) !== 24000002) {
        if (err instanceof Error) {
        if (err instanceof Error) {
          throw err;
        }
        throw new Error('安全凭证删除失败');
        }
        throw new Error('安全凭证删除失败');
      }
    }
  }

  private static aliasQuery(alias: string, includeSecret: boolean): asset.AssetMap {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, SecureCredentialStore.encoder.encodeInto(alias));
    if (includeSecret) {
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      query.set(asset.Tag.RETURN_LIMIT, 1);
    }
    return query;
  }

  private static errorCode(err: Object): number {
    const value = (err as Record<string, Object>)['code'];
    return typeof value === 'number' ? value : 0;
  }
}
