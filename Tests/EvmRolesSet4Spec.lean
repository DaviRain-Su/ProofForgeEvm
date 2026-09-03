import ProofForge

/-!
W3 Set4 SDK focused suite: fixed-capacity shape and vacancy decisions for the four-slot role profile.

Host note: checked-runtime stubs keep `Address.eq`/`Address.isZero` host-`true`, so host evaluation
cannot test membership, grant-slot selection, or revoke-slot selection. Anvil gates on a Set4
consumer will own live semantics; this suite pins compile-time capacity and empty-set shape.
-/

namespace Tests.EvmRolesSet4Spec

open ProofForge.Evm.Sdk

def who : Address := ⟨1, 2, 3⟩

#guard Roles.capacity4 == 4
#guard Roles.Set4.empty == ⟨Address.zero, Address.zero, Address.zero, Address.zero⟩
#guard Roles.Set4.empty.slot0 == Address.zero && Roles.Set4.empty.slot1 == Address.zero &&
  Roles.Set4.empty.slot2 == Address.zero && Roles.Set4.empty.slot3 == Address.zero

#guard Roles.Set4.hasVacancy Roles.Set4.empty
#guard Roles.Set4.full Roles.Set4.empty == false
#guard Roles.Set4.member Roles.Set4.empty who == false

end Tests.EvmRolesSet4Spec
