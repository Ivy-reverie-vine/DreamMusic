import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'PlaybackDiagnostics';
const DEFAULT_MAX_EVENTS = 100;

export const DIAGNOSTIC_CATEGORY_SOURCE_TIMEOUT: string = 'source_timeout';
export const DIAGNOSTIC_CATEGORY_EMPTY_PLAYBACK_URL: string = 'empty_playback_url';
export const DIAGNOSTIC_CATEGORY_URL_EXPIRED_OR_UNREACHABLE: string = 'url_expired_or_unreachable';
export const DIAGNOSTIC_CATEGORY_AVPLAYER_INITIALIZATION_FAILURE: string = 'avplayer_initialization_failure';
export const DIAGNOSTIC_CATEGORY_PLAYBACK_FAILURE: string = 'playback_failure';
export const DIAGNOSTIC_CATEGORY_SOURCE_FAILURE: string = 'source_failure';

export interface PlaybackDiagnosticInput {
  source: string;
  capability: string;
  stage: string;
  durationMs: number;
  ok: boolean;
  errorCategory?: string;
}

export interface PlaybackDiagnosticEvent {
  timestampMs: number;
  source: string;
  capability: string;
  stage: string;
  durationMs: number;
  ok: boolean;
  errorCategory?: string;
}

function safeField(value: string, fallback: string): string {
  const candidate = value.replace(/[^a-zA-Z0-9_.-]/g, '_');
  return candidate.length > 0 && candidate.length <= 64 ? candidate : fallback;
}

/** 将系统/网络错误归一化为可检索类别，不保存原始错误文本或媒体 URL。 */
export function classifyPlaybackError(stage: string, message: string): string {
  const text = message.toLowerCase();
  if (text.indexOf('timeout') >= 0 || text.indexOf('timed out') >= 0 || text.indexOf('超时') >= 0) {
    return DIAGNOSTIC_CATEGORY_SOURCE_TIMEOUT;
  }
  if (stage === 'source_resolution') {
    return DIAGNOSTIC_CATEGORY_SOURCE_FAILURE;
  }
  if (stage === 'url_response') {
    if (text.indexOf('empty') >= 0 || text.indexOf('为空') >= 0 || text.indexOf('无版权') >= 0) {
      return DIAGNOSTIC_CATEGORY_EMPTY_PLAYBACK_URL;
    }
    return DIAGNOSTIC_CATEGORY_URL_EXPIRED_OR_UNREACHABLE;
  }
  if (stage === 'avplayer_initialization') {
    return DIAGNOSTIC_CATEGORY_AVPLAYER_INITIALIZATION_FAILURE;
  }
  return DIAGNOSTIC_CATEGORY_PLAYBACK_FAILURE;
}

/**
 * 播放诊断环形缓冲。只记录来源/能力/阶段/耗时/类别，避免 Cookie、Token、完整 URL 进入日志。
 */
export class PlaybackDiagnostics {
  private maxEvents: number;
  private events: PlaybackDiagnosticEvent[] = [];

  constructor(maxEvents: number = DEFAULT_MAX_EVENTS) {
    this.maxEvents = Math.max(1, Math.min(1000, Math.floor(maxEvents)));
  }

  record(input: PlaybackDiagnosticInput): void {
    const event: PlaybackDiagnosticEvent = {
      timestampMs: Date.now(),
      source: safeField(input.source, 'unknown'),
      capability: safeField(input.capability, 'unknown'),
      stage: safeField(input.stage, 'unknown'),
      durationMs: Math.max(0, Math.round(input.durationMs)),
      ok: input.ok
    };
    if (!input.ok && input.errorCategory !== undefined) {
      event.errorCategory = safeField(input.errorCategory, 'unknown_failure');
    }
    this.events.push(event);
    while (this.events.length > this.maxEvents) {
      this.events.shift();
    }
    hilog.info(DOMAIN, TAG,
      'source=%{public}s capability=%{public}s stage=%{public}s durationMs=%{public}s ok=%{public}s category=%{public}s',
      event.source, event.capability, event.stage, String(event.durationMs), String(event.ok), event.errorCategory || '');
  }

  recent(): PlaybackDiagnosticEvent[] {
    return this.events.slice();
  }

  clear(): void {
    this.events = [];
  }
}

export const playbackDiagnostics: PlaybackDiagnostics = new PlaybackDiagnostics();
