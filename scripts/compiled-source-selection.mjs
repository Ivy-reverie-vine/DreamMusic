// Executes Hvigor's actual compiled component with a controlled ArkUI rendering boundary.
// Control labels/actions are production code; this does not emulate native layout or touch.
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

export function sourceSelectionHarness(player, PlayerState, searchSourceName) {
  const compiled = new URL('../entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/components/SourceSelection.ts', import.meta.url);
  const source = readFileSync(compiled, 'utf8').replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, '');
  let controls = [], current;
  class Property {
    constructor(value) { this.value = value; }
    get() { return this.value; } set(value) { this.value = value; }
  }
  class ViewPU {
    finalizeConstruction() {}
    observeComponentCreation2(callback) { callback(0, true); }
    ifElseBranchUpdateFunction(_branch, callback) { callback(); }
    forEachUpdateFunction(_id, items, callback) { items.forEach(callback); }
  }
  const node = kind => new Proxy({}, { get(_target, key) {
    if (key === 'create' || key === 'createWithLabel') return label => {
      current = { kind, text: typeof label === 'string' ? label : '', enabled: true };
      if (kind === 'Button' || kind === 'Text') controls.push(current);
    };
    if (key === 'pop') return () => {};
    return value => { current[key] = value; };
  } });
  const { SourceSelection } = runInNewContext(`${stripTypeScriptTypes(source, { mode: 'transform' })}\n({SourceSelection})`, {
    ViewPU, Reflect, ObservedPropertyObjectPU: Property, ObservedPropertySimplePU: Property,
    ThemeService: { getInstance: () => ({ primaryText: '#68c4bb', muted: '#a8b0b3', transparent: '#00000000', errorColor: '#ef9898' }) },
    playerViewModel: player, PlayerState, searchSourceName, CONTROL_HIT_SIZE: 48, FONT_BODY: 15, FONT_LABEL: 12, SPACE_SM: 8,
    HorizontalAlign: { Start: 0 }, If: node('If'), Column: node('Column'), Button: node('Button'), Text: node('Text'), ForEach: node('ForEach'),
  });
  const component = new SourceSelection(null, {});
  const render = () => { controls = []; component.initialRender(); return controls; };
  return { component, render,
    click(text) { const control = render().find(control => control.kind === 'Button' && control.text === text);
      if (!control || !control.enabled) throw new Error('Missing or disabled control: ' + text);
      control.onClick(); },
    snapshot() { return render().map(({ onClick, ...control }) => control); },
  };
}
