# Templates

ProofForge EVM 用户工程骨架。

| 目录 | Target | 用途 |
|---|---|---|
| [`evm-counter`](evm-counter/) | EVM Yul | `pf init` |

`pf init <name>` 会复制该目录，并把 `require … from ".." / ".."`
改写成相对 monorepo 根的路径（通常为 `..`）。

约束：

- 合约只 `import ProofForge.Attr` + `ProofForge.Evm.Sdk`
- 不 `import ProofForge` 伞模块
- 不依赖 `Examples` / Emit / Registry

上手：

```text
pf init demo
cd demo && lake build
lake env pf build      # 读取 pf.toml 的 [[program]]
# 或：lake exe pf -- build
```
