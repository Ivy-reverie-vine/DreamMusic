import { common } from '@kit.AbilityKit';
import { OnlineSong } from '../model/Entities';
import { NetEaseApi, SearchSourcePage } from '../service/network/NetEaseApi';
import { ApiError } from '../service/network/ApiClient';
import { networkViewModel } from './NetworkViewModel';

export function searchSourceName(source: string): string {
  if (source === 'api-enhanced') { return '网易云'; }
  if (source === 'meting-tencent') { return 'QQ音乐'; }
  if (source === 'meting-kugou') { return '酷狗'; }
  return source;
}

/** 页面只渲染公开状态；分页、去重与迟到响应在这里维护。 */
@Observed
export class OnlineSearchViewModel {
  keyword: string = '';
  results: OnlineSong[] = [];
  sources: SearchSourcePage[] = [];
  loading: boolean = false;
  errorText: string = '';
  errorCode: string = '';
  private generation: number = 0;
  private searchTimer: number = -1;
  private pendingPages: Record<string, number> = {};

  get hasMore(): boolean {
    return this.sources.some((source: SearchSourcePage) => source.status !== 'failed' && source.hasMore);
  }

  get status(): string {
    if (this.sources.length === 0) { return ''; }
    const failures = this.sources.filter((source: SearchSourcePage) => source.status === 'failed').length;
    if (failures === this.sources.length) { return 'all_failed'; }
    if (failures > 0) { return 'partial_failure'; }
    return this.results.length > 0 ? 'success' : 'empty';
  }

  changeKeyword(context: common.Context, value: string): void {
    this.cancel();
    this.keyword = value;
    if (value.trim() === '') { return; }
    this.searchTimer = setTimeout(() => {
      this.searchTimer = -1;
      this.search(context);
    }, 300);
  }

  cancel(): void {
    this.generation++;
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); }
    this.searchTimer = -1;
    this.loading = false;
    this.results = [];
    this.sources = [];
    this.errorText = '';
    this.errorCode = '';
    this.pendingPages = {};
  }

  async search(context: common.Context): Promise<void> {
    if (this.searchTimer >= 0) { clearTimeout(this.searchTimer); this.searchTimer = -1; }
    if (this.loading || this.keyword.trim() === '') { return; }
    const pages: Record<string, number> = {};
    pages['api-enhanced'] = 0;
    pages['meting-tencent'] = 0;
    pages['meting-kugou'] = 0;
    await this.fetch(context, pages);
  }

  async loadMore(context: common.Context): Promise<void> {
    if (this.loading) { return; }
    const pages: Record<string, number> = {};
    for (const source of this.sources) {
      if (source.status !== 'failed' && source.hasMore) { pages[source.source] = source.nextOffset; }
    }
    if (Object.keys(pages).length > 0) { await this.fetch(context, pages); }
  }

  async retry(context: common.Context): Promise<void> {
    if (!this.loading && Object.keys(this.pendingPages).length > 0) {
      await this.fetch(context, this.pendingPages);
    }
  }

  async retrySource(context: common.Context, id: string): Promise<void> {
    if (this.loading) { return; }
    for (const source of this.sources) {
      if (source.source === id && source.status === 'failed') {
        const pages: Record<string, number> = {};
        pages[id] = source.offset;
        await this.fetch(context, pages);
        return;
      }
    }
  }

  private async fetch(context: common.Context, pages: Record<string, number>): Promise<void> {
    const version = this.generation;
    this.pendingPages = pages;
    this.loading = true;
    this.errorText = '';
    this.errorCode = '';
    try {
      const page = await NetEaseApi.aggregateSearch(context, this.keyword.trim(), pages);
      if (version !== this.generation) { return; }
      const results = this.results.slice();
      const seen = new Set<string>();
      for (const song of results) { seen.add(song.mediaRef !== undefined ? song.mediaRef : 'api-enhanced|' + song.id); }
      for (const song of page.songs) {
        const key = song.mediaRef !== undefined ? song.mediaRef : 'api-enhanced|' + song.id;
        if (!seen.has(key)) { seen.add(key); results.push(song); }
      }
      const sources = this.sources.slice();
      for (const incoming of page.sources) {
        const index = sources.findIndex((source: SearchSourcePage) => source.source === incoming.source);
        if (index >= 0) { sources[index] = incoming; } else { sources.push(incoming); }
      }
      this.results = results;
      this.sources = sources;
      networkViewModel.markOnline();
    } catch (err) {
      if (version !== this.generation) { return; }
      this.errorText = err instanceof Error ? err.message : '搜索失败，请重试';
      this.errorCode = err instanceof ApiError ? err.code : '';
      if (this.errorCode === 'NETWORK' || this.errorCode === 'UPSTREAM_DOWN' || this.errorCode === 'TIMEOUT') {
        networkViewModel.markOffline();
      } else { networkViewModel.markOnline(); }
    } finally {
      if (version === this.generation) { this.loading = false; }
    }
  }
}
