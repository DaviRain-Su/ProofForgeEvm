# Fable SDK foundations design / SDK 基础设计

> Status: design proposal, reviewed against `origin/main` on 2026-09-03.
> Scope: a staged path from the current closed EVM components to typed events, typed external
> calls, honest OpenZeppelin-compatible examples, and Base-ready execution.

## Objective / 目标

Fable should extend ProofForge EVM without weakening its current fail-closed boundary:

- source values remain typed and bounded;
- the extractor retains semantic metadata instead of reducing it to raw bytes;
- EVM-owned plans define ABI and memory geometry;
- one interpreter emits each CALL/LOG/revert shape;
- ABI JSON and Yul are derived from the same typed descriptor;
- existing closed operations and their canonical digests remain stable unless a migration is
  explicitly approved.

The recommended first product slice is **S1a, target-local typed events**. It establishes the
metadata path needed by OpenZeppelin-style SDK work while avoiding extractor/API commitments and
digest churn.

## Current code boundary / 当前代码边界

The design starts from these existing facts, not from a replacement architecture:

- `Evm.ClosedCall` is a closed union for known ERC-20/WETH/Uniswap/permit calls. Each case owns its
  operand count, effects, and canonical spelling.
- `Evm.CallResult` is the sole typed returndata policy layer. Its established ClosedCall policies
  accept at most one word, while S2 adds separately bounded typed policies of up to four ABI
  words; `CallResult.Emit` is their sole interpreter.
- `Evm.LogError` validates only target-local LOG/revert geometry. It deliberately is not a source
  API for arbitrary event signatures or selectors.
- `Evm.NativeFx` owns the current closed ETH, log, and revert semantic names. Its generic
  `name(uint64)`, ERC-20 `Transfer`, and `Approval` events are lowered through `LogError.Emit`.
- Parameterized source errors already demonstrate the desired metadata flow:
  `Core.Ops.ErrorFrame` → Extract IR → EVM IR → selector/Yul/ABI generation. The first slice is
  intentionally narrow: one to four named `UInt64` fields.
- ABI event discovery is currently coupled to `Component.Call.logName`; `Transfer256` and
  `Approval256` receive special ABI declarations.

Typed events should mirror the successful **frame → IR → target encoding → ABI** shape of
`ErrorFrame`, but must not reuse `ErrorFrame` itself: event arguments need indexed metadata,
address/`uint256` types, and valid zero-data layouts that typed errors do not model.

## Stages / 阶段

| Stage | Deliverable | Exit evidence |
|---|---|---|
| S0 | Named init gate | CI check is visibly named `pf init demo` and builds the generated project |
| S1a | Target-local typed event frame and emitter path | plan/IR/golden tests; no existing digest change |
| S1b | Extractor, SDK facade, ABI, and Anvil receipts | one source event crosses the full path |
| S2 | Richer bounded returndata policies | multiword typed decode and malformed-return gates |
| S3 | `OpenCall`, a typed external CALL surface | dynamic target with static ABI contract; no raw calldata |
| S4 | OZ event adoption plus ERC-165/721/1155 coverage | standard topics/ABI with honest support claims |
| S5 | Base RPC and chain-id parameterization | same command path works for Anvil and configured Base RPC |
| S6 | OZ example waves | each wave has Lean, ABI, Yul, and chain-level evidence |

### S0 — init gate naming / 初始化门禁命名

S0 is an integration prerequisite, not an SDK architecture change. The required check name is
`pf init demo`; it must run the named-project flow (`pf init demo`, generated-project
`lake build`, then `pf build`) rather than an opaque “smoke” label.

At review time this work is present on PR #4, not assumed to be on `main`. S0 is complete only when
the branch carrying this design sees that named check as a required, green CI result. No S1 code
should duplicate the init-gate implementation.

### S1a — target-local typed events first / 先做目标端 typed events

Add a target-local typed event descriptor beside the existing EVM components. Final Lean names
are intentionally left to implementation, but the descriptor must retain:

- event name;
- declaration-order argument name and ABI type;
- whether each argument is indexed;
- typed source limbs/values required to materialize its ABI word.

The initial type vocabulary is a closed EVM list covering the already supported static ABI forms
needed by SDK events (not an arbitrary type string). The descriptor's well-formedness gate must
enforce:

- at most four topics including the signature topic;
- each initial argument encodes to exactly one ABI word;
- data-word count remains within the active `LogError.LogPlan` bound;
- indexed values use EVM topic encoding appropriate to their declared type;
- duplicate or malformed argument names and unsupported types fail before Yul emission.

The EVM layer computes the signature topic from the canonical
`Name(type1,type2,...)`, materializes indexed topics and non-indexed data in declaration order,
then delegates only the final geometry to `LogError.Emit.emitLog`. ABI JSON must be generated from
the same descriptor and deduplicated by canonical event identity; conflicting metadata for one
identity is an error.

“Target-local first” means S1a is proven with direct EVM plan/IR fixtures. It does not yet publish
a generic source syntax or SDK API. Existing `NativeFx.log`, `logTransfer256`, and
`logApproval256` cases remain unchanged.

Zero digest churn is a hard acceptance condition:

1. canonical spellings of all existing `ClosedCall`, `NativeFx`, `Component`, and EVM IR nodes are
   byte-identical;
2. current digest/golden fixtures remain unchanged;
3. the new canonical spelling appears only in programs that contain the new typed-event node;
4. current Yul and ABI goldens for `Transfer`/`Approval` remain byte-identical.

**Recommended next implementation:** S1a, because it is target-local, testable without source API
design, and unlocks the metadata model needed by S1b and S4.

### S1b — extractor + SDK + Anvil / 全链路接入

After S1a is stable, add the source-facing path:

1. the extractor recognizes the approved fixed event form and builds the target-local frame
   without converting names, types, or indexed flags to raw strings/bytes;
2. Extract IR projection and EVM IR preserve the frame through branches and bounded loops;
3. an SDK facade exposes only the approved typed constructors;
4. EVM ABI collection walks nested control flow exactly as typed-error collection already does;
5. Anvil tests verify receipt topics/data and ABI decoding.

Acceptance requires at least an address-indexed plus `uint256`-data event and a boolean-data event,
along with fail-closed tests for a fifth topic, unsupported type, malformed frame, and ABI identity
conflict. A test must also prove that an event in nested `ite`/bounded `forBody` is included once in
ABI metadata.

S1b may migrate closed event call sites only after equivalence tests prove their topic, data, ABI,
canonical digest, and effect summary are unchanged.

### S2 — richer returndata policies / 更丰富的返回数据策略

S2 extends `CallResult.Policy` without bypassing it in individual call emitters. It supports a
compile-time fixed, bounded list of static ABI words and typed decoding of those words. One
explicit maximum rejects larger plans.

Implemented behavior:

- CALL/STATICCALL success remains mandatory;
- exact-size policies compare `returndatasize()` with the full expected static frame;
- copied returndata is bounded by the plan before emission;
- decoded words are validated against their declared scalar/address/bool constraints;
- current ERC-20 compatibility and success-only policies retain their behavior;
- malformed size, non-canonical bool/address values, call failure, and code-less empty success
  fail closed.

`CallResult.Emit.emit` retains its `Option String` first-word compatibility carrier. S2 adds
`emitBound`, which returns a bounded typed result collection while preserving existing consumer
output and fresh-name order. Arbitrary or unbounded returndata is not introduced by the default
policies.

**Implementation note (S2):** `maxResultWords = 4` (128 bytes), matching `LogError.maxLogDataWords`.
New constructors are `exactWords n`, `strictBool`, `magicBytes4 selector`, and `words kinds`
(`uint256` / `boolean` / `address20` / `bytes4`). `Emit.emitBound` returns the bound Yul names;
`emit` still projects the first-word `Option String` so ClosedCall / Precompile output is
unchanged. `Request.fail` defaults to `revert0` (`revert(0, 0)`); `bubble` is opt-in and applies
only to the call-failure gate (policy tails stay `revert(0, 0)`). Bubble copies callee-controlled
`returndatasize()` and is not a bounded plan. yulc already rejects `gas()` on every CallResult
CALL/STATICCALL; bubble additionally needs dynamic `returndatacopy`. See the support-matrix yulc
row. OpenCall (S3) is not part of this slice.

### S3 — `OpenCall` typed external CALL / 类型化开放调用

`OpenCall` is an EVM component sibling to `ClosedCall`, not a raw opcode escape hatch. “Open”
means the target address may come from a typed source value; the call contract remains static and
compiler-checked:

- CALL or STATICCALL kind;
- compile-time selector and fixed ABI argument schema;
- typed argument values and optional typed CALL value;
- one S2 `CallResult.Policy` and fixed result schema;
- explicit `externalCall`/value effect summary.

Calldata is assembled by the EVM interpreter from the typed schema. The source API never accepts
an arbitrary bytes payload, selector string, return buffer length, or opcode. `delegatecall`,
CREATE/CREATE2, and proxy dispatch are not variants of `OpenCall`.

Acceptance includes a state-supplied and parameter-supplied target, one two-word return, CALL value
gating, EOA/code-less rejection where the policy requires contract code, malformed return
rejection, and effect-order tests around storage writes. Reentrancy is documented as an
application-visible risk; `OpenCall` does not silently add a guard.

`NativeFx.sendEth` currently emits its value CALL directly, while closed protocol calls use
`CallResult.Emit`. S3 must either keep native send as an explicitly separate zero-calldata
primitive or migrate it only with byte-equivalence tests; it must not create a third result-policy
interpreter.

**Implementation note (S3):** `Evm.OpenCall` is a `Component` sibling of `ClosedCall`. Source
helpers `Sdk.OpenCall.call` / `callSuccess` / `callValue` / `staticWord` / `staticWords2` erase to
Runtime stubs; the extractor rebuilds a `Plan` from the payload constructor (name + named closed
scalars, ≤8 words) plus a typed `Addr20` target and optional `UInt256` CALL value. Calldata is
assembled in `OpenCall.Emit`; every result gate is `CallResult.Emit.emitBound` (no third
interpreter). `NativeFx.sendEth` stays the zero-calldata primitive. Reentrancy is documented as
application-visible; OpenCall does not add a guard. `delegatecall`, CREATE2, proxy dispatch, raw
calldata, and unbounded argument lists remain refused.

Exit evidence on this slice: `Tests/EvmOpenCallSpec.lean` (plan/golden/extract/fail-closed + existing
Token/Vault/TipJar digest pins) and `runtime-tests/evm/anvil_opencall.sh` (parameter- and
state-supplied targets, two-word return, CALL value, EOA rejection, malformed returndata, CALL
before `sstore`).

### S4 — OZ adoption and coverage / OpenZeppelin 对齐

“OZ adoption” means compatible signatures, indexed flags, ABI metadata, and observable behavior
for the stated subset. It does not mean a drop-in or complete OpenZeppelin implementation.

| Surface | Current `main` | S4 target | Honest boundary after S4 |
|---|---|---|---|
| ERC-20 events | Closed `Transfer`/`Approval` logs and ABI | Re-express through typed events only if zero-churn equivalence holds | Existing ERC-20-style subset, not a blanket full-ERC claim |
| ERC-165 | No SDK implementation found | Bounded `supportsInterface(bytes4)` policy for explicitly implemented interface IDs; `0xffffffff` is false | Reports only interfaces whose required surface is actually present |
| ERC-721 | O(1) ownership/approval/balance core; events and receiver hooks are app-owned | Standard `Transfer`, `Approval`, and `ApprovalForAll` event descriptors and example adoption; ERC-165 ID only when the full advertised function set exists | No “full ERC-721” claim without safe-transfer/receiver and metadata decisions |
| ERC-1155 | Bounded single-id balance/operator core; no standard events, batch calls, receiver hooks, or metadata URI | Standard `TransferSingle` and `ApprovalForAll`; `TransferBatch` only with a separately approved bounded dynamic-event plan | Single-id bounded core with those two events; no “full ERC-1155” claim |

The `TransferBatch` payload contains dynamic arrays and does not fit S1a's one-word-per-argument or
the current four-data-word `LogPlan` contract. S4 must not fake it with a nonstandard fixed event.
It is either deferred or implemented as a distinct bounded dynamic-event plan with exact ABI
offset/length tests.

Acceptance compares topic 0, indexed topics, data bytes, and ABI JSON against the canonical
OpenZeppelin event declarations. ERC-165 tests include supported IDs, an unsupported ID, and the
invalid ID.

### S5 — Base RPC/chain-id parameterization / Base 网络参数化

The local Anvil helper already reads `PF_EVM_CHAIN_ID` (default `31338`) but constructs its own
loopback RPC URL. S5 turns network selection into an explicit execution contract:

- RPC URL and expected chain ID are separate required/derived parameters for remote execution;
- every deploy/send flow reads the observed chain ID and fails before signing if it differs;
- private keys remain environment/secret inputs and are never persisted in generated config;
- Anvil continues to provide safe local defaults;
- Base mainnet/Sepolia are named presets or documented configurations, not compiler special cases;
- artifact build is network-independent; only deployment and chain tests consume RPC settings.

Acceptance runs the same deployment entry point against local Anvil and a configured Base-style
RPC, proves the mismatch gate, and records chain ID, deployment address, transaction hash, and
artifact digest. CI must not require a public funded key; remote evidence can remain an explicit
protected/manual gate.

### S6 — OZ example waves / OZ 示例分波

Examples land in dependency order and each wave stays honest about its supported subset:

1. **Wave A — policy events:** Ownable/Pausable/Roles examples adopt typed events and ERC-165 where
   applicable. *(S4b landed `OwnershipTransferred` + `Paused`/`Unpaused` on TwoStepCounter,
   Credits, and Capped; not constructor logs, Ownable2Step `OwnershipTransferStarted`, Roles,
   or ERC-165.)*
2. **Wave B — ERC-721:** Collectible/Badge adopt `Transfer`, `Approval`, and `ApprovalForAll`;
   advertised interface IDs are limited to implemented functions. *(S4a landed the three
   canonical events; not ERC-165, safe callbacks, or metadata URI.)*
3. **Wave C — ERC-1155 single-id:** MultiToken/CraftToken adopt `TransferSingle` and
   `ApprovalForAll`. *(S4c landed LOG4 `TransferSingle` with two data words and LOG3
   `ApprovalForAll` on both examples; not `TransferBatch`, safe callbacks, metadata URI, or
   ERC-165.)*
4. **Wave D — bounded batch/cross-contract examples:** only after the required bounded dynamic
   event and `OpenCall` policies are independently accepted.

Every wave requires a source example, extractor/IR structural gate, ABI golden, Yul build, Anvil
behavior and receipt assertions, and support-matrix wording. An example is not evidence for a
standard claim unless its required interface and negative cases are covered.

## Non-goals / 非目标

These stages do not add:

- proxies or upgrade machinery;
- `delegatecall`;
- CREATE2 (or a general contract-creation API);
- arbitrary bytes calldata;
- unbounded structures.

In particular, `OpenCall` opens target selection only inside a statically typed, bounded ABI
contract. It is not a route around these non-goals.

## Review notes

**Verdict — approve with amendments.** The S0–S6 direction fits the current component boundaries,
and S1a is the safest first implementation.

**Risks amended in this design:**

- A direct reuse of `ErrorFrame` would be wrong: its current gate requires one to four named
  `UInt64` fields and carries no indexed metadata. S1a mirrors its path, not its data type.
- `LogError` currently permits at most four topics and four data words. Common ERC-721 and
  single-id ERC-1155 events fit; ERC-1155 `TransferBatch` does not.
- Before S2, `CallResult` was structurally single-word (`retBound ≤ 32`, `Option String` result).
  S2 retains that compatibility carrier and adds bounded `emitBound` names for up to four words.
- Event ABI is currently inferred from `NativeFx.logName` with special cases. S1 must derive ABI
  and emission from one frame before removing any special case.
- `NativeFx.sendEth` does not currently consume `CallResult`; S3 must preserve that deliberate
  boundary or migrate it with byte-level evidence.

**Missing acceptance criteria added:** existing digest/Yul/ABI zero-churn gates, nested-control-flow
ABI discovery, malformed typed-event failures, multiword returndata shape/canonicality failures,
`OpenCall` EOA/effect-order tests, canonical OZ topic/data comparisons, ERC-165 invalid-ID behavior,
and remote chain-ID mismatch refusal.
