import { describe, it, expect } from '@ohos/hypium';
import {
  PlaybackDiagnostics,
  classifyPlaybackError,
  DIAGNOSTIC_CATEGORY_AVPLAYER_INITIALIZATION_FAILURE,
  DIAGNOSTIC_CATEGORY_EMPTY_PLAYBACK_URL,
  DIAGNOSTIC_CATEGORY_SOURCE_TIMEOUT,
  DIAGNOSTIC_CATEGORY_URL_EXPIRED_OR_UNREACHABLE
} from '../main/ets/service/playback/PlaybackDiagnostics';

export default function playbackDiagnosticsTest() {
  describe('PlaybackDiagnostics', () => {
    it('keeps bounded redacted events', 0, () => {
      const diagnostics = new PlaybackDiagnostics(2);
      diagnostics.record({
        source: 'api-enhanced',
        capability: 'media-resolution',
        stage: 'url_response',
        durationMs: 12,
        ok: false,
        errorCategory: DIAGNOSTIC_CATEGORY_EMPTY_PLAYBACK_URL
      });
      diagnostics.record({
        source: 'api-enhanced',
        capability: 'media-resolution',
        stage: 'source_resolution',
        durationMs: 2,
        ok: true
      });
      diagnostics.record({
        source: 'api-enhanced',
        capability: 'media-resolution',
        stage: 'source_resolution',
        durationMs: 3,
        ok: true
      });

      const events = diagnostics.recent();
      expect(events.length).assertEqual(2);
      expect(events[0].durationMs).assertEqual(2);
      expect(JSON.stringify(events).indexOf('token')).assertEqual(-1);
    });

    it('classifies source and player failures without exposing raw errors', 0, () => {
      expect(classifyPlaybackError('source_resolution', 'request timeout')).assertEqual(
        DIAGNOSTIC_CATEGORY_SOURCE_TIMEOUT);
      expect(classifyPlaybackError('url_response', 'empty url')).assertEqual(
        DIAGNOSTIC_CATEGORY_EMPTY_PLAYBACK_URL);
      expect(classifyPlaybackError('url_response', 'http 403')).assertEqual(
        DIAGNOSTIC_CATEGORY_URL_EXPIRED_OR_UNREACHABLE);
      expect(classifyPlaybackError('avplayer_initialization', 'initialized timeout')).assertEqual(
        DIAGNOSTIC_CATEGORY_AVPLAYER_INITIALIZATION_FAILURE);
    });
  });
}
