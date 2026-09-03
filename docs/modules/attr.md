# ProofForge.Attr

## Purpose

标记可编译根。不是新语法。种类不写在属性里，从 `def` 的返回类型推断。

## Boundary

只记录声明名。不检查闭包（那是 Profile）、不抽出（那是 Extract）。只能标 `def`。
`@[pf_inline]` 允许抽出器在控制流边界展开已检查的有界 helper。`@[pf_boundary]`
只给 `ProofForge.` 名下的编译器自有 structure / inductive 走通用 boundary codec。

## API

- `@[pf_entry]`
- `@[pf_inline]`
- `@[pf_boundary]`
- `isEntry` / `isInline` / `isBoundary`

## Tests

`Tests/BuildSpec.lean`：有标记则 `#pf_evm_build` 成功；无标记 fail closed。
