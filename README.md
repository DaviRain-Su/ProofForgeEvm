# ProofForge EVM

Lean 4 编写的 EVM 合约编译器：从带 `@[pf_entry]` 标记的 Lean 源码抽取 IR，
经 Yul 生成 EVM 字节码与 ABI。本仓库是 ProofForge 的 EVM 单链分支 —— 只维护
EVM target（SVM / NEAR / XRPL / Wasm 实现已移除，留在上游多链仓库）。

## 布局

- `ProofForge/Core/` — 目标无关的值/效果 IR、CFG、codec、schema
- `ProofForge/Extract/` — Lean 表达式 → IR 抽取器（EVM-only）
- `ProofForge/Evm/` — EVM Ops / IR / Yul Emit / Assemble（solc、yulc 后端）/ Registry
- `ProofForge/Evm/Sdk/` — 合约侧 SDK（storage、ERC-721/1155、roles、pausable…）
- `ProofForge/Cli.lean` — `pf` 命令行（`pf build` / `pf init`）
- `Examples/` — EVM 合约示例（digest 钉在 `ProofForge/Evm/Registry.lean`）
- `Tests/` — elaboration 期规格（`#guard` / `example`）
- `templates/evm-counter/` — `pf init` 的用户工程模板
- `runtime-tests/evm/` — Anvil 链上集成门禁
- `powdr-probe/` — powdr EVM/Yul 语义探针（独立 Lake 工程）

## 构建与测试

```text
./.agents/setup        # 安装固定工具链：elan/Lake v4.31.0、solc 0.8.34、foundry 1.7.1
lake build             # 编译器库
lake build Tests       # 测试套件（elaboration 期断言）
lake build Examples    # 示例合约
```

本地 CI 镜像：`scripts/ci_local.sh`（`--fast` 只跑 Python 守卫）。

## CLI

```text
pf build [--out DIR] [--backend solc|yulc] [--module MOD] [Contract ...]
pf init <name>
pf --version
```

`pf build` 对每个程序写出 `Name.bin` / `Name.yul` / `Name.abi.json`。
裸合约名映射到 `Examples` fixture；用户工程用 `--module` 或 `pf.toml`
的 `[[program]]` 条目。

## 链上门禁

```text
runtime-tests/evm/anvil.sh     # 全部 Anvil 门禁（缺 Foundry 时跳过）
```

## 用户工程

```text
pf init demo && cd demo && lake build && lake env pf build
```

合约只 `import ProofForge.Attr` + `ProofForge.Evm.Sdk`，不要 import 伞模块
`ProofForge`。SDK 传递闭包不得触及 Emit/Assemble/Registry
（`scripts/check_sdk_import_closure.py` 在 CI 强制）。
