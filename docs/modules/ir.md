# Core IR and EVM ABI

## Purpose

`ProofForge.Core.IR` owns the stable, comparable source-program shape. Physical
layouts are deliberately outside Core.

## Boundary

Core 记录 source schema、flattened leaves 和方法；`ixName` 是可复用的入口名。
证明主语与发射主语共享抽出后的 source 程序；物理 digest 由 `Evm.IR.digestHex`
按 `canonical` 做 FNV-1a 64（构造器 + 按 `ixName` 排序的 entries，不含 Lean 全名）。

`Evm.IR.fromExtracted` 经 `Evm.IR.extractRegistration` 投影后物化 storage slot 和
selector。无根层 `ProofForge.IR` 兼容 façade。

`Program.schema` / `Method.evaluation` 是 identity 和 state 语义。
`Core.Target.Registration` 递归投影所有公共 Core values/ops，只把 extension
leaves/effects 交给拥有方 callback。它同时携带 value arity、op well-formedness 和
CFG dialect，所以投影在物理 lowering 之前先校验。抽出器方言只含 `.evm` 扩展；
`Extract.IR` 不再包含 backend conversion 函数。接受既有公共语言的 backend 不必给
`Extract.IR` 加 case。真正新的 source/runtime intrinsic 仍要扩前端方言。

## Types

Shared: `ProofForge/Core/IR.lean` (`MethodKind`, `Method`, `Program`) and
`ProofForge/Core/Target.lean` (`Registration`, generic value/op/program projection).

EVM ABI: `ProofForge/Evm/IR.lean`（`Slot` / `Vector` / `Method` / `Program`，
`canonical` / `digestHex`）。selector 由 `Crypto.Keccak.selector` 从 `ixName` 与 ABI
类型算出。

## Errors

投影对 foreign extension、extension arity、op well-formedness 或 CFG validation
失败时 fail closed。EVM 另拒绝空槽表、缺 constructor、缺 runtime entry、空 ops，
以及 method 上的 foreign annotations。

## Tests

`Tests/EvmSpec.lean`：Counter 三方法、digest 稳定且随 ops 变、Flag 窄宽、Maybe 双叶、
Pair 构造器只保留 `initialize`。
`Tests/TargetOpsSpec.lean`：Core-only 合成 backend 覆盖无 `Extract.IR` 修改的注册路径
及 foreign-extension 拒绝；`schemaMatchesSlots`。
`Tests/BuildSpec.lean` / `Tests/LayoutSpec.lean`：Legacy digest 稳定且随程序形状变。
