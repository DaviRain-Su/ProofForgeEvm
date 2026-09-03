# ProofForge EVM

[![CI](https://github.com/DaviRain-Su/ProofForgeEvm/actions/workflows/ci.yml/badge.svg)](https://github.com/DaviRain-Su/ProofForgeEvm/actions/workflows/ci.yml)

[English](README.md)

Lean 4 → EVM 合约编译器：用 `@[pf_entry]` 标记普通 Lean 入口；ProofForge 抽出受检 IR，
发射 Yul，再由 **钉死的 solc** 汇编字节码与 ABI（powdr `yulc` 为**实验**后端）。
本仓库是 ProofForge 的 EVM 单目标分支。

产品契约：[`docs/product/support-matrix.md`](docs/product/support-matrix.md)。
写合约指南：[`docs/product/writing-contracts.md`](docs/product/writing-contracts.md)。
站点：[`website/`](website/)（GitHub Pages）。

## 布局

- `ProofForge/Core/` — 目标无关的值/效果 IR、CFG、codec、schema
- `ProofForge/Extract/` — Lean 表达式 → IR 抽取器（仅 EVM）
- `ProofForge/Evm/` — EVM Ops / IR / Yul Emit / Assemble（solc，实验性 yulc）/ Registry
- `ProofForge/Evm/Sdk/` — 合约侧 SDK（storage、fungible、有界 ERC-721/1155 core、roles、pausable…）
- `ProofForge/Cli.lean` — `pf` CLI（`pf build` / `pf init` / `pf --version`）
- `Examples/` — EVM 合约示例（digest 钉在 `ProofForge/Evm/Registry.lean`）
- `Tests/` — elaboration 期规格（`#guard` / `example`）
- `templates/evm-counter/` — `pf init` 用户工程模板
- `runtime-tests/evm/` — Anvil 链上集成门禁
- `powdr-probe/` — powdr EVM/Yul 语义探针（独立 Lake 包）
- `docs/product/` — 能力矩阵、写合约指南、路线图
- `docs/research/` — **历史**决策笔记（已归档）
- `website/` — 项目站点（Vite + React）

## 构建与测试

```text
./.agents/setup        # 钉死工具链：elan/Lake v4.31.0、solc 0.8.34、foundry 1.7.1
lake build             # 编译器库
lake build pf          # CLI 可执行文件
lake build Tests       # 测试套件
lake build Examples    # 示例合约
```

本地 CI 镜像：`scripts/ci_local.sh`（`--fast` 只跑 Python 守卫）。

## CLI

```text
pf build [--out DIR] [--backend solc|yulc] [--module MOD] [Contract ...]
pf init <name>
pf --version
```

`pf build` 写出 `Name.bin` / `Name.yul` / `Name.abi.json`。
默认后端是 **solc**。`--backend yulc` 为实验（周跑/手动 CI，不是 merge 门禁）。
裸名映射到仓内 `Examples`；用户工程传 `--module` 或在 `pf.toml` 写 `[[program]]`。

## 链上门禁

```text
runtime-tests/evm/anvil.sh     # 完整 Anvil 门禁（无 Foundry 时跳过）
```

## 用户工程（在本仓 checkout 内）

```text
lake build pf
export PATH="$PWD/.lake/build/bin:$PATH"
lake exe pf -- init demo
cd demo
lake build
lake env pf build
```

`pf init` 目前依赖仓库 checkout（复制 `templates/evm-counter` 并改写 path-`require`）。
尚无独立安装包。

合约只 import `ProofForge.Attr` + `ProofForge.Evm.Sdk`，不要 import `ProofForge` 伞模块。
SDK 传递闭包不得触及 Emit/Assemble/Registry（CI：`scripts/check_sdk_import_closure.py`）。

## 信任边界

- Kernel 定理钉的是用户 `def` / 静态字段，**不是** `.bin` 或 EVM 精化。
- Anvil 变绿是**工程**门，不是证明。
- ERC-721/1155 SDK 模块是**有界 core**，不是完整标准实现。

## 许可证

[MIT](LICENSE)
