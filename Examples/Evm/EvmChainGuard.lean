import ProofForge.Evm.Sdk

/-!
S5 example: bake an expected `chainId` as a constructor immutable and refuse entries whose
`Context.chainId` does not match. Artifact build is network-independent; Anvil can impersonate
Base Sepolia (`84532`) or VibeNet (`84538453`) via `--chain-id`.
-/

namespace Examples.Evm.EvmChainGuard
open ProofForge.Evm.Sdk

structure State where
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  | wrongChain (expected actual : UInt64)
  deriving Repr, DecidableEq, Inhabited, BEq

/-- Constructor `expectedChainId` is baked as `Immutable.u64`; dummy storage starts at 0. -/
@[pf_entry]
def init (_expectedChainId : UInt64) : State :=
  { dummy := 0 }

/-- Succeeds only when `CHAINID` equals the constructor immutable. -/
@[pf_entry]
def ping (s : State) : Except Error (State × UInt64) :=
  if Context.chainId == Immutable.u64 then
    if (0 : UInt64) ≠ 1 then
      .ok ({ s with dummy := Context.chainId }, Context.chainId)
    else
      .error .overflow
  else
    .error (.wrongChain Immutable.u64 Context.chainId)

@[pf_entry]
def expectedChainId (_s : State) : UInt64 :=
  Immutable.u64

@[pf_entry]
def chainId (_s : State) : UInt64 :=
  Context.chainId

@[pf_entry]
def get (s : State) : UInt64 :=
  s.dummy

end Examples.Evm.EvmChainGuard
