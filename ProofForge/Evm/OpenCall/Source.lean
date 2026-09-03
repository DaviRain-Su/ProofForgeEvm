import ProofForge.Attr
import ProofForge.Evm.Runtime

namespace ProofForge.Evm.OpenCall.Source

open ProofForge.Evm.Runtime

/--
Source-facing typed external CALL. `@[pf_inline]` erases these helpers into the Runtime stubs
the extractor recognizes as `Evm.OpenCall` plans. The payload is an inductive constructor whose
name is the ABI function name and whose fields are the ABI arguments. No raw calldata, selector
string, return-buffer length, or opcode is accepted.
-/

@[pf_inline] def call {α : Type} (target : Addr20) (payload : α) : UInt64 :=
  evmOpenCall target payload

@[pf_inline] def callSuccess {α : Type} (target : Addr20) (payload : α) : UInt64 :=
  evmOpenCallSuccess target payload

@[pf_inline] def callValue {α : Type} (target : Addr20) (value : UInt256) (payload : α) : UInt64 :=
  evmOpenCallValue target value payload

@[pf_inline] def staticWord {α : Type} (target : Addr20) (payload : α) : UInt256 :=
  evmOpenStaticWord target payload

/-- Exact two-word STATICCALL. The source carrier is the first `UInt256`; both words are still
size-gated by `CallResult.Policy.exactWords 2`. -/
@[pf_inline] def staticWords2 {α : Type} (target : Addr20) (payload : α) : UInt256 :=
  evmOpenStaticWords2 target payload

end ProofForge.Evm.OpenCall.Source
