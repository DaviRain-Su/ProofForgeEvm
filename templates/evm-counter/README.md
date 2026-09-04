# EVM Counter 模板

> 模板里的 `proofforge` require 是发布形态：`from git … @ "v0.1.0"`。
> 在本仓 checkout 里跑 `pf init` 会把它改写成 path require（指向当前 checkout），所以 tag 还不存在时本地和 CI 也能 `lake build`。
> 一旦 GitHub Release / tag `v0.1.0` 存在，用户工程可以直接用该 git require。`proofforge-common` 仍是 `@ "main"`。
> 没有独立安装包，也没有 `curl | sh`。`pf init` 复制模板仍需要 checkout。

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

init 之后的 lakefile 是 path require，指向这次 checkout。不要把未改写的 git-tag require 留给本地 CI。

## 发布形态（tag `v0.1.0` 存在之后）

```lean
require «proofforge» from git
  "https://github.com/DaviRain-Su/ProofForgeEvm.git" @ "v0.1.0"
require «proofforge-common» from git
  "https://github.com/DaviRain-Su/ProofForgeCommon.git" @ "main"
```

GitHub Release 二进制名为 `pf-linux-x86_64` / `pf-macos-aarch64`。`pf init` 仍然需要 checkout 来复制本目录。

参考仓内例子：`Examples/Evm/TipJar.lean`（`import ProofForge.Evm.Sdk`）。

产品边界见 `docs/product/support-matrix.md` 与 `docs/product/writing-contracts.md`。
