import Lake
open Lake DSL

package «proofforge» where
  version := v!"0.0.1"

/-- Shared Attr + Core/Crypto surface used by the EVM SDK. -/
lean_lib ProofForgeCore where
  roots := #[
    `ProofForge.Attr,
    `ProofForge.Core.Codec,
    `ProofForge.Core.Collections,
    `ProofForge.Core.Math,
    `ProofForge.Core.Ops,
    `ProofForge.Core.SafeCast,
    `ProofForge.Core.Value
  ]

/-- Contract-facing EVM SDK (+ Runtime/Source needed for `pf_inline` erase). No Emit. -/
lean_lib ProofForgeEvmSdk where
  roots := #[
    `ProofForge.Evm.ClosedCall.Source,
    `ProofForge.Evm.HashedMap.Source,
    `ProofForge.Evm.NativeFx.Source,
    `ProofForge.Evm.OpenCall.Source,
    `ProofForge.Evm.Runtime,
    `ProofForge.Evm.Sdk,
    `ProofForge.Evm.Sdk.Access,
    `ProofForge.Evm.Sdk.Base,
    `ProofForge.Evm.Sdk.Erc165,
    `ProofForge.Evm.Sdk.Erc2981,
    `ProofForge.Evm.Sdk.Erc1155,
    `ProofForge.Evm.Sdk.Erc721,
    `ProofForge.Evm.Sdk.Fungible,
    `ProofForge.Evm.Sdk.Ownable,
    `ProofForge.Evm.Sdk.Pausable,
    `ProofForge.Evm.Sdk.Payments,
    `ProofForge.Evm.Sdk.Reentrancy,
    `ProofForge.Evm.Sdk.SafeErc20,
    `ProofForge.Evm.Sdk.Roles,
    `ProofForge.Evm.Sdk.Nonces,
    `ProofForge.Evm.Sdk.Storage,
    `ProofForge.Evm.Sdk.StorageBitmap,
    `ProofForge.Evm.Sdk.StorageCheckpoints,
    `ProofForge.Evm.Sdk.StorageEnumerableMap,
    `ProofForge.Evm.Sdk.StorageEnumerableSet,
    `ProofForge.Evm.Sdk.StorageRing,
    `ProofForge.Evm.Sdk.StorageVec,
    `ProofForge.Evm.StaticStorage.Source,
    `ProofForge.Evm.WideWord.Source
  ]

/-- Compiler: Extract, Evm IR/Emit/Assemble/Registry, and the `ProofForge` umbrella. -/
@[default_target]
lean_lib ProofForge where
  roots := #[
    `ProofForge,
    `ProofForge.Cli,
    `ProofForge.Core.CFG,
    `ProofForge.Core.Eval,
    `ProofForge.Core.FixedPoint,
    `ProofForge.Core.IR,
    `ProofForge.Core.Schema,
    `ProofForge.Core.Target,
    `ProofForge.Crypto.Keccak,
    `ProofForge.Crypto.Sha256,
    `ProofForge.Crypto.Sha256Compat,
    `ProofForge.Evm.Assemble,
    `ProofForge.Evm.AssembleMain,
    `ProofForge.Evm.CallResult,
    `ProofForge.Evm.CallResult.Emit,
    `ProofForge.Evm.ClosedCall,
    `ProofForge.Evm.ClosedCall.Emit,
    `ProofForge.Evm.Codec,
    `ProofForge.Evm.Codec.Emit,
    `ProofForge.Evm.Commands,
    `ProofForge.Evm.Component,
    `ProofForge.Evm.Component.Emit,
    `ProofForge.Evm.Emit,
    `ProofForge.Evm.Environment,
    `ProofForge.Evm.Environment.Emit,
    `ProofForge.Evm.Golden,
    `ProofForge.Evm.HashedMap,
    `ProofForge.Evm.HashedMap.Emit,
    `ProofForge.Evm.IR,
    `ProofForge.Evm.IRCompat,
    `ProofForge.Evm.Keccak,
    `ProofForge.Evm.LogError,
    `ProofForge.Evm.LogError.Emit,
    `ProofForge.Evm.NativeFx,
    `ProofForge.Evm.NativeFx.Emit,
    `ProofForge.Evm.OpenCall,
    `ProofForge.Evm.OpenCall.Emit,
    `ProofForge.Evm.Ops,
    `ProofForge.Evm.Payable,
    `ProofForge.Evm.Payable.Emit,
    `ProofForge.Evm.Precompile,
    `ProofForge.Evm.Precompile.Emit,
    `ProofForge.Evm.Registry,
    `ProofForge.Evm.StaticStorage,
    `ProofForge.Evm.StaticStorage.Emit,
    `ProofForge.Evm.WideWord,
    `ProofForge.Evm.WideWord.Emit,
    `ProofForge.Extract,
    `ProofForge.Extract.Compat,
    `ProofForge.Extract.Decode,
    `ProofForge.Extract.IR,
    `ProofForge.Extract.LegacyAdapter,
    `ProofForge.Extract.LegacyEval,
    `ProofForge.Extract.LegacyGolden,
    `ProofForge.Extract.LegacyIR,
    `ProofForge.Extract.LegacyOps,
    `ProofForge.Extract.Lexical,
    `ProofForge.Extract.Ops,
    `ProofForge.Profile
  ]

/-- Build every module under `Examples/` (EVM fixtures only). -/
lean_lib Examples where
  globs := #[.one `Examples, .submodules `Examples]

lean_lib Tests

lean_exe pfEvmAssemble where
  root := `ProofForge.Evm.AssembleMain

lean_exe pf where
  root := `ProofForge.Cli
  supportInterpreter := true
