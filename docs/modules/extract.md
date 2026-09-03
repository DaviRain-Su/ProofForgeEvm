# ProofForge.Extract

## Purpose

从 elaborated `Expr` 抽出 `Extract.IR.Program`（`Core.IR.Program` 配上抽出器方言）。前端先从 `init` 的结果类型建立 typed state schema，再抽方法 Ops；物理槽表只是 schema 的兼容视图。

## State schema

`ProofForge.Core.Schema` 是状态布局的 source of truth：

- `Place` / `PathStep` 保存稳定的源位置身份。structure 字段由 owner type + 声明序号标识，
  字段名不参与身份判定，只用于诊断和兼容叶名；Vector 元素用 index；Option 的 tag /
  payload 是显式路径步骤。
- `Leaf` 保存 source scalar type；`VectorLayout` 保存长度、每元素字节数和每元素叶子数，
  不含 storage slot。
- `IR.Program.slots` 由 `IR.slotsOfSchema` 生成，继续保留 `nodes_0_value`、`slot_tag`
  这类显示名。抽出的程序必须满足 `IR.schemaMatchesSlots`。

`Evm.IR.fromExtracted` 只调用 typed layout 查询，不扫描 `_0_left`、`_tag`、`_p0` 猜
Vector / Option 布局。旧的手写 `Golden` fixture 没有 schema，字符串兼容解析只留在 IR
兼容层，不能再进入 emitter。

## Core evaluation and writeback

`ProofForge.Core.Eval` 在 schema 和规范化 Ops 都可用后，为每个抽出方法建立
`IR.Method.evaluation`：

- checked add/sub/mul/div/mod 变成显式 `ValueRef.checked kind lhs rhs`，状态写入不再依赖
  emitter 的“最近一次计算结果”寄存器。
- 静态状态写入使用 typed `Place`；Option 成功结果明确列出 tag 和 payload 两次写入；
  多叶 record diff 的每个 `storeField` 也有对应 typed write event。
- lexical scalar let、branch / bounded loop 保留为结构化 state-effect tree，不依赖 emitter
  的遍历游标。
- 运行时 Vector 下标写入使用 `DynamicPlace(vector Place, index, elementPath)`；其 commit
  明确没有虚构的静态首槽写入。
- `Evaluation.explicit = false` 只用于没有 schema 的旧手写 fixture。

当前 `Ops` 仍是前端 compatibility lowering，但 emitter 不再直接消费抽出方言：
`Core.Target.projectProgram` 按 `Evm.IR.extractRegistration` 递归投影公共 Core，并把
extension conversion 留在 `Evm` 模块；`Evm.IR` 再降到 EVM-only `Op`，把 typed `Place`
物化成 storage slot。`Core.Evaluation` 随 method 保留。这里刻意不让旧写回规则进入
Core：把任一物理布局特判塞回 Core 都会污染 source 语义。

## Source-form normalization

抽出器承诺对已测试的 syntax-only 写法保持同一 Core：直接 record constructor 与等价的
外层 pure `let` + record update 会抽成相同 schema、slots、方法 Ops 和 evaluation。规范化刻意很窄：
窄整数 alias 和包住 `if` 的 pure head `let` 做 zeta-reduction；`UInt64` pure let 保留成
`letLocal`，纯值 `if` 保留成 `Val.select`，避免把同一 mutation continuation 复制到两个
分支。动态 `Vector.set` 会保留 `.ok (newState, ret)` 的显式 `ret`，不会误用最后写入的
element value。普通复合 Boolean guard 即使 error 在 else 分支，也统一降成
bit/select value + structured `ite`；checked arithmetic guard 仍优先走专用 lowering。
EVM effect 和循环仍交给专用 decoder。这里不做全局 `whnf`，新增 Lean
表面形式应先加等价性 characterization test，再扩规范化或 decoder。连续的
`State → … → State` inline helper 先按顺序发 transition，再处理 continuation，避免把逐层
record expression 重复替换进后续每个 projection；helper 是否为 transition 由第一个用户
structure 输入类型与结果类型是否相同判定。`State → … → Node` 这类纯结构 reader 则展开
后再投影，不能因名称或恰好同处 Tree 模块而重定位到可变 State。

方法完成规范化后会递归检查所有 Val、branch 和 loop 的 `.arg`。init 只允许
`arg < paramCount`；mutate/view 另允许 `arg == paramCount` 表示隐式 state。任何 proof / let /
callback binder 泄漏都会在 lowering 之前 fail closed，不能再被 emitter 误认成 calldata。

## Boundary

递归下降 `Expr`。`x ≤ u64Max - y` → `checkedAddU64`；`y ≤ x` → `checkedSubU64`；
`y = 0 ∨ x ≤ u64Max / y` → `checkedMulU64`；`y ≠ 0` 后 `/` `%` →
`checkedDivU64` / `checkedModU64`。比较认 `=` `≠` `<` `≤` `>` `≥`。假支不必是
overflow。`match opt with | none => a | some n => b` 抽成 `ite (eq tag 0)`。
`ProofForge.Evm.Runtime` 的具名 stub 抽成 EVM 叶子或 `Evm.Component` 效应
（`opOfRuntimeApp` / `queryOfRuntimeApp`，不按 recipe 名枚举 walker）。位运算 /
有界 `forIn [:N]` / 运行时 `Vector` 下标 / 命名 `Error` 构造子 /
`UInt64 × UInt64` view 也抽。可变方法无 checked 算术 / ite / EVM 效应 /
语言叶 / `storeField` / 有界循环则 fail closed。

嵌套用户 structure 摊成 `parent_child` 槽；`Vector Nested n` 每个元素再摊，例如
`nodes_0_value`。固定布局、多构造子且 payload 全是 `UInt64` 的 inductive 摊成 tag + 最大
payload，短构造子补零；其 match 绑定 lexical locals。`extends` 仍关。mutate 的
`State.mk` / `Vector.set` / 嵌套 `with` 按叶 diff：改了几个槽就发几条 `storeField`，
不按合约猜 dest。root `@[pf_inline]` State helper 会先展开并保留其 transition；
UInt64/Bool scalar helper 与 `({ s with x := v }).x` 也在 typed value 边界归一化。
单叶仍压成 `okState`。`for i in [:n]` 改状态抽出 `forBody`，循环下标是 `loopIx`，
payload 仍是外层参数。运行时下标读写嵌套记录或 variant 走 `indexGet` / `indexSet`。
非固定 N 与 `extends` 仍关。

schema 默认从 `init` 返回类型收：必须是已注册 `structure`、无 `extends`。叶子接受
`UInt8/16/32/64`、`Bool`（1 字节 u8-le）、`Option UInt64`（展开双叶）、固定长度
`Vector T n`（其中 `T` 也必须是受支持的固定布局）、无 payload 用户枚举（一叶 tag）、
两构造子 option-like inductive，以及至少三个构造子且所有字段都是 `UInt64` 的 variant。
variant 使用一叶 tag + 最宽构造子的 payload，短构造子规范补零。嵌套用户 structure
递归摊平。不定长 `Array`、递归或带参数/索引的 inductive、非 `UInt64` variant payload
fail closed。可选 `fields?` 覆盖槽名时必须与 schema 导出的表一致。
ops 里出现的字段名必须在表内。

用户合约不绑仓库目录名。`extractModuleIR` / `#pf_evm_build` 收任意名字空间下的
`@[pf_entry]`。字段投影认已注册 structure，排除 `ProofForge` / `Lean` / `Std` /
`Init`；`Examples.` 本身不是准入条件。

`@[pf_entry]` 只是标记。种类从返回类型推断：structure → init；`Except` → mutate；
标量 / `Prod` / 有界容器 / `@[pf_boundary]` 类型 → view。Lean `init` 的链上名是
`initialize`。允许多个 init / mutate / view；槽表从名为 `init` 的那个收。重复链上名
fail closed。`init` 的 `paramCount` 按 λ 个数算。抽出按类型展开槽名（`name_tag` /
`name_i`），不按合约字段名写死。

## API

- `inferSchema env initName : Except String Core.Schema`
- `inferSlots env initName : Except String (Array Core.IR.Slot)`（schema 的兼容视图）
- `inferFields env initName : Except String (Array String)`
- `extractProgramIR env init increment get (name?) (fields?)`（抽出器方言）
- `extractModuleIR env ns (fields?)`（收 `@[pf_entry]`）
- `extractProgram` / `extractModule`（兼容适配器，产出 `Extract.Legacy.Program`）
- `#pf_evm_build Namespace`（`Evm.Commands`：抽出 + `Evm.IR.fromExtracted` + Yul）

## Tests

`Tests/BuildSpec.lean`：`#pf_evm_build` 收入口；无标记 fail closed；Legacy digest 随 ops 变。
`Tests/LayoutSpec.lean`：Flag / Maybe Legacy digest 稳定且互异。
`Tests/LangSpec.lean`：`extractProgramIR` 抽出窄 Vector 与 saturating `Nat.sub`，再经
`Evm.IR.fromExtracted` 发射。
`Tests/TargetOpsSpec.lean`：抽出方言 well-formed、Core-only 合成 backend 覆盖无
`Extract.IR` 修改的注册路径及 foreign-extension 拒绝；Legacy round-trip。
`Tests/CounterSpec.lean` / `PairSpec.lean` / `FlagSpec.lean` / `WindowSpec.lean` /
`PhaseSpec.lean`：对应 fixture 的源语义与抽出形状。
