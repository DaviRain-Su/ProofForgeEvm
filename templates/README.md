# Templates

ProofForge EVM 用户工程骨架。

| 目录 | Target | 用途 |
|---|---|---|
| [`evm-counter`](evm-counter/) | EVM Yul | `pf init` |

`pf init <name>` 会复制该目录。从 checkout 运行时，把发布形态的 git-tag
`require`（`@ "v0.1.0"`）改写成指向本仓的 path require（通常为 `..`）。

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
