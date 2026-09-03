# ProofForge.Evm.Assemble

## Purpose

把 `Evm.IR.Program` 先编成 Yul / ABI，再调用本机汇编器写出 `.bin`。

## Boundary

子进程，不是 FFI。默认后端是锁定的 `solc 0.8.34`，`--evm-version cancun`
（opcode `0x44` 是 `PREVRANDAO`，不是 Paris 前的 `DIFFICULTY`）。`yulc` 由
`PROOFFORGE_EVM_BACKEND=yulc` 或 `assembleProgramWithBackend … .yulc` 选择；
二进制来自 `PROOFFORGE_YULC` 或仓内 `powdr-probe` 构建产物。PATH 上随便一个
solc 不算。写出 `{name}.yul` / `{name}.abi.json` / `{name}.bin`。

## API

- `Backend`：`.solc` | `.yulc`；`parseBackend` / `backendFromEnv`
- `requiredSolcVersion` / `requiredEvmVersion`
- `assembleProgramWithBackend outDir program backend : IO Result`
- `assembleProgram`（读环境选后端）
- `Result`：`yulPath` / `abiPath` / `binPath` / `binHex` / `backend`
- `lake exe pfEvmAssemble -- build/evm` 遍历 `Evm.Golden.programs`

## Tests

`Tests/EvmBuildSpec.lean` / `Tests/BuildSpec.lean`：`#pf_evm_build` 钉登记 fixture
的 digest 与 Yul 对象。solc 门在 `pfEvmAssemble`。
`runtime-tests/evm/anvil.sh`：Anvil 工程门（见 `evm.md`）。
