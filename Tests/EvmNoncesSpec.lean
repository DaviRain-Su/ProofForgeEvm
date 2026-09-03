import ProofForge

/-!
W3 nonce SDK focused suite: pure decision helpers over one explicit `AddressMap256` namespace.

Host note: checked-runtime stubs keep map reads at zero; negative nonce checks and `useNext`
arithmetic are validated by later consumer/Anvil gates.
-/

namespace Tests.EvmNoncesSpec

open ProofForge.Evm.Sdk

def map0 : Storage.Allocated Storage.AddressMap256 :=
  Storage.Layout.root.addressMap256

def account : Address := ⟨1, 2, 3⟩

#guard Nonces.current map0.handle account == UInt256.zero
#guard Nonces.nonceMatches map0.handle account UInt256.zero == true
#guard Nonces.useValue map0.handle account == UInt256.zero
#guard Nonces.useChecked map0.handle account UInt256.zero == true

end Tests.EvmNoncesSpec
