# ProofForge.Evm.Runtime

## Purpose

普通 Lean 名，抽出后变成 EVM opcode / LOG / hashed Map / 封闭 CALL。不是新 DSL。

合约 `open ProofForge.Evm.Runtime`。抽出器只识别具名 Runtime stub（SDK 名字经
`@[pf_inline]` 消去）。根层不再提供混合 façade。

封闭能力经 `Evm.Component.Query/Call` 进入普通 CFG；generic Ops、IR 与主 Emit 只认识
一个 `.component` case。新增配方只扩 component-owned vocabulary/backend。

## Surface

宿主 stub `@[irreducible]`，值是 0（或把金额原样回传），不要 unfold。

- `structure Addr20` — 20 字节地址，三叶 `w0`/`w1`/`w2`（w2 仅低 4 字节），小端装
  字节 0..19。ABI 是一个 `address`，storage 仍三槽。
- `abbrev UInt256` / `Bytes32` — Core `UInt256` 与 `FixedBytes 32` 的兼容名。
- `evmCaller` / `evmSelf` — `CALLER` / `ADDRESS` 低 8 字节，不是完整 address，也不是
  `tx.origin`。
- `evmBlockNumber` / `evmTimestamp` / `evmChainId` / `evmCallValue` / `evmSelfBalance`
  — `NUMBER` / `TIMESTAMP` / `CHAINID` / `CALLVALUE` / `SELFBALANCE`；超 `UInt64`
  revert。默认算术仍是 `UInt64`。
- `evmCaller20` / `evmSelf20` / `evmCoinbase20` / `evmOrigin20` — 完整 20B，抽出认三叶。
- `evmImmU64` / `evmImmU64b` / `evmImm20` / `evmImm20b` — 构造期 `loadimmutable`。
- `evmCallValue256` / `evmSelfBalance256` / `evmGasLeft256` / `evmBaseFee256` /
  `evmPrevRandao256` / `evmGasLimit256` / `evmGasPrice256` / `evmBlobBaseFee256` —
  完整 256-bit 环境叶。`PREVRANDAO` 不得按 Paris 前 `DIFFICULTY` 解释；汇编钉 Cancun。
- `evmBlobHash32` / `evmSelector4` / `evmCalldataSize` / `evmBlockHash256` /
  `evmCodeSize20` / `evmCodeHash32` / `evmBalance256`。
- `evmDeposit amt` — `eq(callvalue(), amt)`，入口变 payable。
- `evmDeposit256` — 同上，金额是 packed wei。
- `evmSendEth dst amt` / `evmSendEth256` — `dst : Addr20`，组装 20B 后 value `CALL`，
  失败 revert。重入不进参考语义。
- `evmLogTipped` / `evmLogIncremented` / `evmLogTransfer` / `evmLogApproval` — LOG1。
- `evmLogTransfer256` / `evmLogApproval256` — LOG3，indexed address + `uint256` data。
- `evmLogTyped` — typed event constructor; extractor keeps name / types / `Indexed` flags.
- `evmRevertInsufficient` / `evmRevertUnauthorized` / `evmRevertZeroAddress` /
  `evmRevertPaused` / `evmRevertCapExceeded` — 命名错误。
- `evmReceive` — 无 calldata 的 payable `receive()`。
- `evmStoreStaticU64 field value` — 按 schema 解析静态 UInt64 叶，空/动态/未知/非
  UInt64 fail closed。
- `evmMapGetU64` / `evmMapSetU64` — hashed `Map UInt64 UInt64`：`keccak256(key || base)`。
- `evmMapGetAddr` / `evmMapSetAddr` — hashed `Map Addr20 UInt64`。
- `evmMapGetPair` / `evmMapSetPair` — pair-key `keccak256(owner||spender||base)`。
- `evmMapGetAddr256` / `evmMapSetAddr256` / `evmMapGetPair256` / `evmMapSetPair256` —
  256-bit payload。
- `evmTokenTransfer` / `evmTokenApprove` / `evmTokenTransferFrom` /
  `evmTokenBalanceOfSelf` / `evmTokenAllowanceOf` — 封闭 ERC-20；失败 / 假返回 revert。
- `evmWethDeposit` / `evmWethWithdraw` — 封闭 WETH。
- `evmAdd256` / `evmSub256` / `evmMul256` / `evmDiv256` / `evmMod256` — checked
  packed 算术，溢出或除零 revert。
- `evmGe256` / `evmEq256` / `evmLt256` / `evmLe256` / `evmGt256` / `evmEq20`。
- `evmAnd256` / `evmOr256` / `evmXor256` / `evmNot256` / `evmShl256` / `evmShr256`。
- `evmSwapExact2` / `evmSwapExact3` — 封闭 Uniswap V2 `swapExactTokensForTokens`。
- `evmPermit` / `evmTokenPermit` / `evmDomainSeparator` — 封闭 EIP-2612 / EIP-712。

ABI 上 `Addr20` 是一个 `address`，`UInt256` 是一个 `uint256`。不把非 EVM 名译成 opcode。

## Tests

`Tests/EvmCtxSpec.lean` + `runtime-tests/evm/anvil_ctx.sh`：`evmCaller` 低 8 字节、
`block.number`。
`Tests/EvmEnvironmentSpec.lean`：环境叶与 Cancun opcode。
`Tests/TipJarSpec.lean` + `anvil_tipjar.sh`：chainid、timestamp、Addr20、deposit /
sendEth / Tipped / `receive()`。
`Tests/VaultSpec.lean` + `anvil_vault.sh`：hashed Map 与封闭 ERC-20。
`Tests/TokenSpec.lean` / `OwnableSpec.lean` / `CappedSpec.lean` + 对应 anvil：
mint / allowance / pause / cap。
`Tests/WideSpec.lean` + `anvil_wide.sh`：UInt256 算术与比较。
`Tests/LangSpec.lean` + `anvil_lang.sh`：位运算、移位、tuple、下标、有界 for。
`Tests/EvmPayableSpec.lean` / `EvmLogErrorSpec.lean` / `EvmPrecompileSpec.lean` /
`EvmCallResultSpec.lean`：payable 守卫、命名错误、预编译与封闭 CALL 结果。
