import { fileIo } from '@kit.CoreFileKit';

/**
 * 文件复制工具(issue-12 修复):
 * 系统选择器返回的 URI(file://docs/... / file://media/...)对部分 fs 接口兼容性不一致,
 * 统一策略:先 copyFileSync,失败则回退 openSync 流式复制;仍失败向上抛出原因。
 */
export function copyFileRobust(source: string, dest: string): void {
  try {
    fileIo.copyFileSync(source, dest);
    return;
  } catch (e1) {
    // 回退:openSync 流式复制(对选择器 URI 兼容性更好)
  }
  const src = fileIo.openSync(source, fileIo.OpenMode.READ_ONLY);
  try {
    const dst = fileIo.openSync(dest,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      const buf = new ArrayBuffer(1024 * 1024);
      let read = fileIo.readSync(src.fd, buf);
      while (read > 0) {
        fileIo.writeSync(dst.fd, buf);
        read = fileIo.readSync(src.fd, buf);
      }
    } finally {
      fileIo.closeSync(dst.fd);
    }
  } finally {
    fileIo.closeSync(src.fd);
  }
}
