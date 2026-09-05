import ProofForge.Attr

namespace ProofForge.Evm.Sdk.OzAudit

/-!
# EVM SDK OZ completion-audit inventory

Compile-time counters and bounded static table for the coverage inventory in
`docs/product/oz-sdk-backlog.md` and the authority snapshot of OpenZeppelin `contracts/` tree paths.
This is an audit witness, not runtime interface discovery: unknown rows fail closed via
`isComplete`, `allRowsClassified`, and `treeMatchesAuthority`.

Authority snapshot (2026-09-03 re-inventory for W5 slice 1):
- tree SHA `641ba990cad2f7f70878e0d66be1bfbef95710e8`
- 452 `contracts/` tree paths, 367 Solidity sources
- 32 backlog coverage rows: 2 DONE, 21 PARTIAL, 9 ABSENT (all 9 blocked by non-goals; no
  implementable gap since row 12, `interfaces/IERC1271.sol`, shipped `checkSignature` and
  `checkNow` over the 65-byte signature bound, and `validSignature` / `validNow` over
  `OpenCall.staticTryMagic` (OZ `false` instead of revert). Rows 10 and 21 (`IERC1155` /
  `token/ERC1155`) stay PARTIAL because batches are bounded. `DuplicateId()` is that profile's
  fail-closed bound versus OZ in-order duplicate application, not a `temporaryGapCount` row.
  Rows 9 and 20 (`IERC721` / `token/ERC721`) stay PARTIAL after `Gallery` shipped bounded
  `totalSupply` / `tokenByIndex` / `tokenOfOwnerByIndex` over UInt64 ids with capacity 4, and
  after `Collectible.safeTransferFrom__id` shipped the three-argument overload. Row 5
  (`finance/VestingWallet`) stays PARTIAL after `VestLink` shipped stored-beneficiary
  `transferOwnership`, parameterless `release()`, a constructor-stored OZ cliff
  (`cliffDuration`, `cliff()`), CREATE of a zero beneficiary that reverts
  `OwnableInvalidOwner(address)`, constructor `OwnershipTransferred(address(0), owner)`,
  only-owner reverts `OwnableUnauthorizedAccount(address)` via `Access.ownerViolation`, and
  `Vest20Link` as the dual-asset wallet (`release()` native ETH plus `release(address)` ERC-20),
  and Ownable2Step `transferOwnership` / `acceptOwnership` / `pendingOwner`.
  Remaining named restriction on that row is VestLink is the ETH-only smaller profile (Vest20Link is dual-asset).
  Rows 8 and 19 (`IERC20*` / `token/ERC20`) stay PARTIAL after `Erc20Meta` shipped issuer
  `permit` / `DOMAIN_SEPARATOR` / `nonces` over the closed Token/1 EIP-2612 path.
  Remaining named restriction on those rows is extensions/permit-votes.
  Row 16 (`draft-IERC3009` and sibling drafts) stays PARTIAL after `Auth3009Link` shipped
  `cancelAuthorization` over a distinct `CancelAuthorization` typehash and
  `authorizationState` as a Bool view of the auth-used slot.
  Remaining named restriction on that row is the remaining draft interfaces.
  Row 1 (`access/Ownable`, `Ownable2Step`) stays PARTIAL after TwoStepCounter/Credits CREATE
  reverts `OwnableInvalidOwner(address)` and logs `OwnershipTransferred(address(0), owner)`.
  Remaining named gap on that row is nominate-zero still `ZeroAddress()`.
  `temporaryGapCount` stays 0.)

Each table row carries a stable path tag (top-level OZ path group), a DONE/PARTIAL/ABSENT status,
an independent permanent-blocker bit (`isBlocked`), and for blocked rows a permanent non-goal
category tag aligned with `oz-sdk-backlog.md` § Permanent non-goals.

`isAbsent` means no profile is shipped. `isBlocked` means the remaining gap is a documented
permanent non-goal. Temporary implementable gaps may be `isAbsent` without `isBlocked`; blocked
rows must always be absent (`isBlocked → isAbsent`), but absent rows are not automatically blocked.
-/

/-- Rows in the coverage table (`oz-sdk-backlog.md`). -/
def coverageRows : UInt64 := 32

/-- Rows marked DONE (bounded capability shipped). -/
def doneCount : UInt64 := 2

/-- Rows marked PARTIAL (named restricted profile). -/
def partialCount : UInt64 := 21

/-- Rows marked ABSENT (no profile shipped). -/
def absentCount : UInt64 := 9

/-- Rows whose remaining gap is blocked by a documented permanent non-goal. -/
def blockedCount : UInt64 := 9

/-- Rows marked ABSENT without a permanent non-goal blocker (implementable gap). -/
def temporaryGapCount : UInt64 := 0

/-- Authority snapshot: `contracts/` tree paths. -/
def authorityTreePaths : UInt64 := 452

/-- Authority snapshot: Solidity sources under `contracts/`. -/
def authoritySoliditySources : UInt64 := 367

/-- Unclassified / out-of-range row status. -/
def statusUnknown : UInt8 := 0

/-- Bounded capability shipped. -/
def statusDone : UInt8 := 1

/-- Named restricted profile exists. -/
def statusPartial : UInt8 := 2

/-- No corresponding profile shipped (blocked by non-goal). -/
def statusAbsent : UInt8 := 3

/-- No permanent non-goal tag (DONE/PARTIAL rows). -/
def nonGoalNone : UInt8 := 0

/-- Proxies, delegatecall, CREATE/CREATE2/CREATE3, storage-slot escape hatches. -/
def nonGoalProxyCreateSlot : UInt8 := 1

/-- Raw/arbitrary calldata, low-level calls, multicall, ERC-2771, and callback/receiver hooks
that are not a closed ABI. Bounded ERC-721/1155 receiving hooks (`onERC*Received`, `data` at most
32 bytes, batch at most 4) are in. An ERC-1271 wallet stays out. Calling a known hook with a
fixed ABI through `OpenCall.callMagic` is in. -/
def nonGoalArbitraryCall : UInt8 := 2

/-- Account abstraction, ERC-4337/7579 execution, paymasters. -/
def nonGoalAccountAbstraction : UInt8 := 3

/-- Governor/timelock/votes and unbounded proposal/voter/account relations. -/
def nonGoalUnboundedGovernance : UInt8 := 4

/-- Cross-chain bridge/executor protocols and global registries. -/
def nonGoalCrossChainRegistry : UInt8 := 5

/-- Upstream vendor/mocks — not runtime SDK surface. -/
def nonGoalNotRuntime : UInt8 := 6

/-- Path tag: `access/Ownable.sol`, `Ownable2Step.sol`. -/
def tagAccessOwnable : UInt8 := 1

/-- Path tag: `access/AccessControl.sol`, `IAccessControl.sol`. -/
def tagAccessControl : UInt8 := 2

/-- Path tag: `access/extensions/*`, `access/manager/*`. -/
def tagAccessExt : UInt8 := 3

/-- Path tag: `account/**`. -/
def tagAccount : UInt8 := 4

/-- Path tag: `crosschain/**`. -/
def tagCrosschain : UInt8 := 5

/-- Path tag: `finance/VestingWallet*.sol`. -/
def tagFinanceVesting : UInt8 := 6

/-- Path tag: `governance/**`. -/
def tagGovernance : UInt8 := 7

/-- Path tag: `interfaces/IERC165.sol`. -/
def tagIface165 : UInt8 := 8

/-- Path tag: `interfaces/IERC20*.sol`, `IERC2612.sol`. -/
def tagIface20 : UInt8 := 9

/-- Path tag: `interfaces/IERC721*.sol`, `IERC4906.sol`, `IERC2309.sol`. -/
def tagIface721 : UInt8 := 10

/-- Path tag: `interfaces/IERC1155*.sol`. -/
def tagIface1155 : UInt8 := 11

/-- Path tag: `interfaces/IERC2981.sol`. -/
def tagIface2981 : UInt8 := 12

/-- Path tag: `interfaces/IERC1271.sol`. -/
def tagIface1271 : UInt8 := 13

/-- Path tag: `interfaces/IERC3156*.sol`, `IERC4626.sol`, `IERC6909.sol`, `IERC777*.sol`, `IERC1363*.sol`. -/
def tagIfaceFinance : UInt8 := 14

/-- Path tag: `interfaces/IERC1820*.sol`, `IERC1967.sol`, `IERC1822.sol`. -/
def tagIfaceProxy : UInt8 := 15

/-- Path tag: `interfaces/IERC5267.sol`, `IERC5313.sol`, `IERC6372.sol`, `IERC5805.sol`. -/
def tagIfaceVotes : UInt8 := 16

/-- Path tag: `interfaces/draft-IERC3009.sol`, `IERC7674.sol`, `IERC7751.sol`, `IERC7786.sol`, `IERC7802.sol`, `IERC7821.sol`. -/
def tagIfaceDraft : UInt8 := 17

/-- Path tag: `metatx/ERC2771*.sol`. -/
def tagMetatx : UInt8 := 18

/-- Path tag: `proxy/**`, `interfaces/IERC1967.sol`. -/
def tagProxy : UInt8 := 19

/-- Path tag: `token/ERC20/**`. -/
def tagToken20 : UInt8 := 20

/-- Path tag: `token/ERC721/**`. -/
def tagToken721 : UInt8 := 21

/-- Path tag: `token/ERC1155/**`. -/
def tagToken1155 : UInt8 := 22

/-- Path tag: `token/ERC6909/**`. -/
def tagToken6909 : UInt8 := 23

/-- Path tag: `token/common/ERC2981.sol`, `ERC1363Utils.sol`. -/
def tagTokenCommon : UInt8 := 24

/-- Path tag: `utils/Context.sol`, `Pausable.sol`, `ReentrancyGuard*.sol`. -/
def tagUtilsGuard : UInt8 := 25

/-- Path tag: `utils/Address.sol`, `LowLevelCall.sol`, `Multicall.sol`, `RelayedCall.sol`, `SimulateCall.sol`, `Calldata.sol`, `Memory.sol`. -/
def tagUtilsCall : UInt8 := 26

/-- Path tag: `utils/cryptography/**`. -/
def tagUtilsCrypto : UInt8 := 27

/-- Path tag: `utils/math/**`, `SafeCast.sol`, `Panic.sol`, `Errors.sol`, `Comparators.sol`. -/
def tagUtilsMath : UInt8 := 28

/-- Path tag: `utils/structs/**`, `Arrays.sol`, `Bytes.sol`, `Strings.sol`, `Base*`, `RLP.sol`, `Packing.sol`, `ShortStrings.sol`. -/
def tagUtilsStruct : UInt8 := 29

/-- Path tag: `utils/Create2.sol`, `Create3.sol`, `StorageSlot.sol`, `SlotDerivation.sol`, `TransientSlot.sol`, `draft-InteroperableAddress.sol`. -/
def tagUtilsSlot : UInt8 := 30

/-- Path tag: `utils/Blockhash.sol`, `BlockHeader.sol`, `ERC6372Utils.sol`, `Nonces*.sol`, `RateLimiter.sol`. -/
def tagUtilsBlock : UInt8 := 31

/-- Path tag: `vendor/**`, `mocks/**`. -/
def tagVendor : UInt8 := 32

/-- Sum of classified backlog rows. -/
@[pf_inline] def classifiedCount : UInt64 :=
  doneCount + partialCount + absentCount

/-- True when every backlog row is accounted for. -/
@[pf_inline] def isComplete : Bool :=
  classifiedCount == coverageRows

/-- True when `status` is one of DONE/PARTIAL/ABSENT. -/
def isKnownStatus (status : UInt8) : Bool :=
  status == statusDone || status == statusPartial || status == statusAbsent

/-- Stable path tag for backlog row `row` (`0..31`); `0` when out of range. -/
def pathTagOf (row : UInt64) : UInt8 :=
  if row == 0 then tagAccessOwnable
  else if row == 1 then tagAccessControl
  else if row == 2 then tagAccessExt
  else if row == 3 then tagAccount
  else if row == 4 then tagCrosschain
  else if row == 5 then tagFinanceVesting
  else if row == 6 then tagGovernance
  else if row == 7 then tagIface165
  else if row == 8 then tagIface20
  else if row == 9 then tagIface721
  else if row == 10 then tagIface1155
  else if row == 11 then tagIface2981
  else if row == 12 then tagIface1271
  else if row == 13 then tagIfaceFinance
  else if row == 14 then tagIfaceProxy
  else if row == 15 then tagIfaceVotes
  else if row == 16 then tagIfaceDraft
  else if row == 17 then tagMetatx
  else if row == 18 then tagProxy
  else if row == 19 then tagToken20
  else if row == 20 then tagToken721
  else if row == 21 then tagToken1155
  else if row == 22 then tagToken6909
  else if row == 23 then tagTokenCommon
  else if row == 24 then tagUtilsGuard
  else if row == 25 then tagUtilsCall
  else if row == 26 then tagUtilsCrypto
  else if row == 27 then tagUtilsMath
  else if row == 28 then tagUtilsStruct
  else if row == 29 then tagUtilsSlot
  else if row == 30 then tagUtilsBlock
  else if row == 31 then tagVendor
  else 0

/-- DONE/PARTIAL/ABSENT status for backlog row `row`; `statusUnknown` when out of range. -/
def statusOf (row : UInt64) : UInt8 :=
  if row == 0 then statusPartial
  else if row == 1 then statusPartial
  else if row == 2 then statusPartial
  else if row == 3 then statusAbsent
  else if row == 4 then statusAbsent
  else if row == 5 then statusPartial
  else if row == 6 then statusAbsent
  else if row == 7 then statusDone
  else if row == 8 then statusPartial
  else if row == 9 then statusPartial
  else if row == 10 then statusPartial
  else if row == 11 then statusDone
  else if row == 12 then statusPartial
  else if row == 13 then statusPartial
  else if row == 14 then statusAbsent
  else if row == 15 then statusPartial
  else if row == 16 then statusPartial
  else if row == 17 then statusAbsent
  else if row == 18 then statusAbsent
  else if row == 19 then statusPartial
  else if row == 20 then statusPartial
  else if row == 21 then statusPartial
  else if row == 22 then statusPartial
  else if row == 23 then statusPartial
  else if row == 24 then statusPartial
  else if row == 25 then statusAbsent
  else if row == 26 then statusPartial
  else if row == 27 then statusPartial
  else if row == 28 then statusPartial
  else if row == 29 then statusAbsent
  else if row == 30 then statusPartial
  else if row == 31 then statusAbsent
  else statusUnknown

/-- True when no corresponding profile is shipped for backlog row `row`. -/
def isAbsent (row : UInt64) : Bool :=
  statusOf row == statusAbsent

/-- Permanent non-goal blocker bit for backlog row `row` (independent of `isAbsent`). -/
def isBlocked (row : UInt64) : Bool :=
  if row == 3 then true
  else if row == 4 then true
  else if row == 6 then true
  else if row == 14 then true
  else if row == 17 then true
  else if row == 18 then true
  else if row == 25 then true
  else if row == 29 then true
  else if row == 31 then true
  else false

/-- True when the row is an implementable ABSENT gap (not permanently blocked). -/
def isTemporaryGap (row : UInt64) : Bool :=
  isAbsent row && !isBlocked row

/-- Blocked rows must be ABSENT; temporary gaps may be ABSENT without being blocked. -/
def blockedImpliesAbsent (row : UInt64) : Bool :=
  !isBlocked row || isAbsent row

/-- Permanent non-goal category for blocked row `row`; `nonGoalNone` when not blocked. -/
def nonGoalTagOf (row : UInt64) : UInt8 :=
  if row == 3 then nonGoalAccountAbstraction
  else if row == 4 then nonGoalCrossChainRegistry
  else if row == 6 then nonGoalUnboundedGovernance
  else if row == 14 then nonGoalCrossChainRegistry
  else if row == 17 then nonGoalArbitraryCall
  else if row == 18 then nonGoalProxyCreateSlot
  else if row == 25 then nonGoalArbitraryCall
  else if row == 29 then nonGoalProxyCreateSlot
  else if row == 31 then nonGoalNotRuntime
  else nonGoalNone

/-- True when `tag` is one of the documented permanent non-goal categories. -/
def isKnownNonGoalTag (tag : UInt8) : Bool :=
  tag == nonGoalProxyCreateSlot || tag == nonGoalArbitraryCall ||
    tag == nonGoalAccountAbstraction || tag == nonGoalUnboundedGovernance ||
    tag == nonGoalCrossChainRegistry || tag == nonGoalNotRuntime

/-- True when blocked rows carry a known tag and non-blocked rows carry `nonGoalNone`. -/
def blockedRowTagged (row : UInt64) : Bool :=
  if row >= coverageRows then false
  else if isBlocked row then
    nonGoalTagOf row != nonGoalNone && isKnownNonGoalTag (nonGoalTagOf row)
  else
    nonGoalTagOf row == nonGoalNone

/-- True when every in-range row has consistent non-goal evidence. -/
def allBlockedRowsTagged : Bool :=
  blockedRowTagged 0 && blockedRowTagged 1 && blockedRowTagged 2 && blockedRowTagged 3 &&
  blockedRowTagged 4 && blockedRowTagged 5 && blockedRowTagged 6 && blockedRowTagged 7 &&
  blockedRowTagged 8 && blockedRowTagged 9 && blockedRowTagged 10 && blockedRowTagged 11 &&
  blockedRowTagged 12 && blockedRowTagged 13 && blockedRowTagged 14 && blockedRowTagged 15 &&
  blockedRowTagged 16 && blockedRowTagged 17 && blockedRowTagged 18 && blockedRowTagged 19 &&
  blockedRowTagged 20 && blockedRowTagged 21 && blockedRowTagged 22 && blockedRowTagged 23 &&
  blockedRowTagged 24 && blockedRowTagged 25 && blockedRowTagged 26 && blockedRowTagged 27 &&
  blockedRowTagged 28 && blockedRowTagged 29 && blockedRowTagged 30 && blockedRowTagged 31 &&
  !blockedRowTagged 32

/-- True when `row` is in range and carries a known status. -/
def isClassified (row : UInt64) : Bool :=
  row < coverageRows && isKnownStatus (statusOf row)

private def classifyRow (row : UInt64) : Bool :=
  isClassified row && pathTagOf row != 0 && blockedImpliesAbsent row

/-- True when every in-range row is classified with a consistent blocker bit. -/
def allRowsClassified : Bool :=
  classifyRow 0 && classifyRow 1 && classifyRow 2 && classifyRow 3 &&
  classifyRow 4 && classifyRow 5 && classifyRow 6 && classifyRow 7 &&
  classifyRow 8 && classifyRow 9 && classifyRow 10 && classifyRow 11 &&
  classifyRow 12 && classifyRow 13 && classifyRow 14 && classifyRow 15 &&
  classifyRow 16 && classifyRow 17 && classifyRow 18 && classifyRow 19 &&
  classifyRow 20 && classifyRow 21 && classifyRow 22 && classifyRow 23 &&
  classifyRow 24 && classifyRow 25 && classifyRow 26 && classifyRow 27 &&
  classifyRow 28 && classifyRow 29 && classifyRow 30 && classifyRow 31 &&
  !isClassified 32

/-- True when caller-supplied tree counts match the pinned authority snapshot. -/
@[pf_inline] def treeMatchesAuthority (paths sources : UInt64) : Bool :=
  paths == authorityTreePaths && sources == authoritySoliditySources

/-- Fail-closed audit gate: inventory complete and authority counts match. -/
@[pf_inline] def auditOk (paths sources : UInt64) : Bool :=
  isComplete && treeMatchesAuthority paths sources

/-- Compile-time audit gate including per-row classification (not lowered to EVM). -/
def auditOkClassified (paths sources : UInt64) : Bool :=
  auditOk paths sources && allRowsClassified

/-- Compile-time audit gate including permanent non-goal evidence on blocked rows. -/
def auditOkEvidence (paths sources : UInt64) : Bool :=
  auditOkClassified paths sources && allBlockedRowsTagged

end ProofForge.Evm.Sdk.OzAudit
