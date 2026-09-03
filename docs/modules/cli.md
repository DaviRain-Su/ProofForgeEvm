# ProofForge.Cli

## Purpose

`pf`：把源模块抽出后编成 EVM 制品。`Evm.Registry` 只登记源码模块名并钉 target IR
digest，不能替代源模块 IR，也不依赖旧 mixed Golden。

## Surface

```
pf build [--out DIR] [--backend solc|yulc] [--module MOD] [Name ...]
pf init <name>
pf --version
```

- `evm`（唯一 target；`--target evm` 可显式给出，省略时默认）：`.bin` + `.yul` + `.abi.json`，
  默认 solc 后端，`--backend yulc` 或 `PROOFFORGE_EVM_BACKEND=yulc` 切换
- 裸名字映射到仓内 `Examples` fixture（`Counter` → `Examples.Counter`，其余多数在
  `Examples.Evm.*`）；`--module` 接受点分 Lean 模块（可重复）
- 用户工程应使用 `--module` 或 `pf.toml` 的 `[[program]]` 条目；不写名字 = 全部登记源模块
- 每次运行重新抽取 IR；`Examples` fixture 的 digest 必须与 `Evm.Registry` 钉值一致，
  否则 fail-closed（`ir/mismatch`）
- `pf init <name>` 复制 `templates/evm-counter`，并把 path-`require` 改写为指向本仓

## Tests

`Tests/CliSpec.lean` 钉参数解析与 usage;`Tests/BuildSpec.lean` /
`Tests/EvmBuildSpec.lean` 用 `#pf_evm_build` 对全部登记 fixture 做 digest 门禁。
