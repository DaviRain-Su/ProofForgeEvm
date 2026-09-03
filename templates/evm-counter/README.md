# EVM Counter 模板

> `pf init` 复制本目录，并把 path-`require` 改写到当前 ProofForge EVM checkout。
> 独立发布路径（`require … from git @ "vX.Y.Z"`）尚未提供；在 tag/release 就绪前，请只使用 checkout 内的 path-require。

## 目标形状

- 只依赖 EVM SDK（+ Attr），不 import `ProofForge` 伞模块 / Emit / Registry。
- `pf.toml` 声明模块路径，CLI 不再假设 `Examples.*`。
- `lake build` 类型检查合约；`pf build` 产出 `.bin` / `.yul` / `.abi.json`。

## 用法（在仓库 checkout 根）

```bash
lake build pf
export PATH="$PWD/.lake/build/bin:$PATH"
lake exe pf -- init my-contract
cd my-contract
lake build
lake env pf build
```

参考仓内例子：`Examples/Evm/TipJar.lean`（`import ProofForge.Evm.Sdk`）。

产品边界见 `docs/product/support-matrix.md` 与 `docs/product/writing-contracts.md`。
