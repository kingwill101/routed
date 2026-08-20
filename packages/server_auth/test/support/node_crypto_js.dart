import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Makes Node 24's receiver-sensitive global crypto getter safe for dart2js.
void stabilizeNodeCryptoBinding() {
  final evaluate = globalContext.getProperty('eval'.toJS) as JSFunction;
  evaluate.callAsFunction(
    null,
    '''Object.defineProperty(globalThis, 'crypto', {
      value: globalThis.crypto,
      configurable: true,
      writable: true
    })'''
        .toJS,
  );
}
