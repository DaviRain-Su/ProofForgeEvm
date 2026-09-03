# ProofForge.Evm.Emit

## Purpose

把 `Evm.IR.Program` 编成 Yul 文本和 `abi.json`。公开入口先假定程序已经过
`Evm.IR.fromExtracted`；每个 method 再经 `Core.CFG` 降成显式 basic block。
Emitter 遍历 checked terminator 和 exit，不重新递归解释 source `ite` / `forBody`。

## Boundary

由于 Yul 没有 `goto`，runtime 用 `pf_pc` dispatcher：每个 `case` 对应一个 basic
block，branch / checked success / overflow 只改下一 block id。入口预声明 CFG
locals。`pf_last` 只显式承接原 ABI 的 checked/effect result；local 和 storage
value 直接按 CFG 中的显式引用读取，冲突 join fail closed。tuple return 由 CFG 的
`returnU64s` exit 一次编码为连续 ABI words。Constructor 从 `initialize` 的
`returnState` 取值。

`.field _ name` 的 storage slot、Vector base/stride 和 leaf width 已在 `Evm.IR`
物化，emitter 不扫描 frontend flattened names 猜布局。`indexGet` / `indexSet`
对定长向量做 `sload` / `sstore`，越界 `revert`。其余 Load 由 `Val` 决定：
`.arg i` → 入口参数；环境叶 → `caller()` / `number()` / `timestamp()` /
`chainid()` / `address()` / `callvalue()` / `selfbalance()`（超 `UInt64` 的
block number 等 revert）；Addr20 三叶按小端拆 `caller()` / `address()`；
immutable → `loadimmutable`。位运算和 mod-64 移位直接降成 Yul。
`Op.component` 交给 `Evm.Component.Emit`。

overflow 是 `revert(0, 0)`。命名错误走 4-byte selector `revert`。Yul 头含
`digest=`（`Evm.IR.digestHex`）。空 `entries` 失败。字面量用十六进制。

首选的 `init` / `initialize` → constructor；其它 `.init` 方法不会成为 runtime
entry。非 init 方法 → ABI entry；`kind.get` 标 `view`；含 `evmDeposit` /
`evmReceive` 的 mutate 标 `payable`。

## API

`emitYul` / `emitAbiChecked` / `emitAbi` / `emit`：输入 `Evm.IR.Program`。
`emit` 返回 `(yul, abi)`。`emitAbi` 在 codec 元数据损坏时回空串；汇编路径走
`emitAbiChecked`。

## Tests

`Tests/CFGSpec.lean`：显式 branch/join、非相邻 duplicate intern、fingerprint
collision 仍精确比较 payload、tuple exit、checked edge、component 操作数参与
substitution。
`Tests/EvmSpec.lean`：Counter Yul 含 object / selector / `sstore` / `revert(0, 0)` /
digest；ABI 含 constructor 与 view；Flag 窄槽 mask；Maybe 双叶清零；Pair 不暴露
runtime `initBoth`。
`Tests/LangSpec.lean`：位运算、移位、有界 for、下标、`uint8` ABI、tuple return。
`Tests/EmitSpec.lean` 只挂载模块。
