import { describe, it, expect } from '@ohos/hypium';
import {
  HealthStateMachine, ConnectionStatus, validateProfileUrl
} from '../main/ets/service/network/HealthStateMachine';

export default function healthStateMachineTest() {
  describe('HealthStateMachine', () => {
    it('initial_offline', 0, () => {
      const m = new HealthStateMachine();
      expect(m.status).assertEqual(ConnectionStatus.OFFLINE);
    });

    it('beginProbe_checking', 0, () => {
      const m = new HealthStateMachine();
      const s = m.beginProbe();
      expect(s).assertEqual(ConnectionStatus.CHECKING);
      expect(m.status).assertEqual(ConnectionStatus.CHECKING);
    });

    it('ok_online', 0, () => {
      const m = new HealthStateMachine();
      m.beginProbe();
      const s = m.onProbeResult(true);
      expect(s).assertEqual(ConnectionStatus.ONLINE);
    });

    it('fail_offline', 0, () => {
      const m = new HealthStateMachine();
      m.beginProbe();
      const s = m.onProbeResult(false);
      expect(s).assertEqual(ConnectionStatus.OFFLINE);
    });

    it('onlineThenProbeAgain', 0, () => {
      const m = new HealthStateMachine();
      m.beginProbe();
      m.onProbeResult(true);
      expect(m.status).assertEqual(ConnectionStatus.ONLINE);
      expect(m.beginProbe()).assertEqual(ConnectionStatus.CHECKING);
      expect(m.onProbeResult(false)).assertEqual(ConnectionStatus.OFFLINE);
    });

    it('flapping_sequence', 0, () => {
      const m = new HealthStateMachine();
      m.beginProbe();
      m.onProbeResult(true);
      m.beginProbe();
      m.onProbeResult(true);
      m.beginProbe();
      m.onProbeResult(false);
      m.beginProbe();
      m.onProbeResult(false);
      expect(m.status).assertEqual(ConnectionStatus.OFFLINE);
    });
  });

  describe('ProfileValidator', () => {
    it('valid_httpsDomain', 0, () => {
      expect(validateProfileUrl('https://music.example.com')).assertTrue();
    });

    it('valid_httpLan', 0, () => {
      expect(validateProfileUrl('http://192.168.1.10:3000')).assertTrue();
    });

    it('valid_trailingSlash', 0, () => {
      expect(validateProfileUrl('https://a.com/')).assertTrue();
    });

    it('invalid_empty', 0, () => {
      expect(validateProfileUrl('')).assertFalse();
    });

    it('invalid_scheme', 0, () => {
      expect(validateProfileUrl('ftp://a.com')).assertFalse();
    });

    it('invalid_noHost', 0, () => {
      expect(validateProfileUrl('http://')).assertFalse();
    });
  });
}
