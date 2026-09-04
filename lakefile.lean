import Lake
open Lake DSL

package «proofforge» where
  version := v!"0.1.0"

/-- Shared Attr + Core/Crypto surface, maintained in ProofForgeCommon.
    Tracks ProofForgeCommon main; Common CI gates every push, so a
    -- breakage surfaces in these repositories' CI immediately. -/
require «proofforge-common» from git
  "https://github.com/DaviRain-Su/ProofForgeCommon.git" @ "main"

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
    `ProofForge.Evm.Sdk.Erc4626,
    `ProofForge.Evm.Sdk.Erc6909,
    `ProofForge.Evm.Sdk.Erc721,
    `ProofForge.Evm.Sdk.Fungible,
    `ProofForge.Evm.Sdk.Erc20Meta,
    `ProofForge.Evm.Sdk.MetadataUri,
    `ProofForge.Evm.Sdk.Eip712Domain,
    `ProofForge.Evm.Sdk.Ierc5313,
    `ProofForge.Evm.Sdk.Ierc6372,
    `ProofForge.Evm.Sdk.Ecdsa,
    `ProofForge.Evm.Sdk.Ierc1271,
    `ProofForge.Evm.Sdk.Vesting,
    `ProofForge.Evm.Sdk.MerkleProof,
    `ProofForge.Evm.Sdk.BlockHeader,
    `ProofForge.Evm.Sdk.DefaultAdminDelay,
    `ProofForge.Evm.Sdk.Erc3009,
    `ProofForge.Evm.Sdk.OzAudit,
    `ProofForge.Evm.Sdk.Ownable,
    `ProofForge.Evm.Sdk.Pausable,
    `ProofForge.Evm.Sdk.Payments,
    `ProofForge.Evm.Sdk.Reentrancy,
    `ProofForge.Evm.Sdk.SafeErc20,
    `ProofForge.Evm.Sdk.Roles,
    `ProofForge.Evm.Sdk.Nonces,
    `ProofForge.Evm.Sdk.RateLimit,
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

/-- Compiler: Extract, Evm IR/Emit/Assemble/Registry, and the `ProofForge` umbrella.
    The lib is named `ProofForgeEvm` (not `ProofForge`): a lean_lib name claims its
    namespace for this package, and a `ProofForge` lib would shadow the
    `ProofForge.Core.*` / `ProofForge.Crypto.*` modules exported by the required
    `proofforge-common` package. -/
@[default_target]
lean_lib ProofForgeEvm where
  globs := #[
    .one `ProofForge,
    .one `ProofForge.Cli,
    .submodules `ProofForge.Evm,
    .one `ProofForge.Extract,
    .submodules `ProofForge.Extract
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

/-- Golden Yul emitter for `scripts/check_yul_fragment.py`. A compiled exe (not
`lake env lean --run`) so module resolution uses Lake's package ownership instead
of directory-prefix shadowing across proofforge-common. -/
lean_exe pfEmitGoldenYul where
  root := `scripts.emit_evm_golden_yul
