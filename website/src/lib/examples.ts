export type TargetId = "solc" | "yulc";

export type Example = {
  id: string;
  name: string;
  targets: TargetId[];
  tags: { zh: string; en: string }[];
  summary: { zh: string; en: string };
  lean: string;
  theorems: { name: string; claim: { zh: string; en: string } }[];
  evm?: { yul: string; abi: string };
};

export const EXAMPLES: Example[] = [
  {
    id: "Counter",
    name: "Counter",
    targets: ["solc", "yulc"],
    tags: [
      { zh: "竖切", en: "vertical slice" },
      { zh: "checked 算术", en: "checked arithmetic" },
    ],
    summary: {
      zh: "UInt64 计数器。init / get / increment / decrement。溢出 fail-closed，不回绕。",
      en: "UInt64 counter. init / get / increment / decrement. Overflow is fail-closed — no wrap.",
    },
    lean: `import ProofForge

namespace Examples.Counter

structure State where
  value : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

/-- 2^64 - 1。Lean 4.31 无 \`UInt64.max\`。 -/
def u64Max : UInt64 := ~~~(0 : UInt64)

/-- 不用 \`initialize\`：那是 Lean 的命令关键字。 -/
@[pf_entry]
def init (initial : UInt64) : State :=
  { value := initial }

@[pf_entry]
def get (s : State) : UInt64 :=
  s.value

/-- checked add：溢出则失败，不更新状态。 -/
@[pf_entry]
def increment (s : State) (delta : UInt64) : Except Error (State × UInt64) :=
  if s.value ≤ u64Max - delta then
    let next := s.value + delta
    .ok ({ value := next }, next)
  else
    .error .overflow
`,
    theorems: [
      {
        name: "increment_ok",
        claim: {
          zh: "成功路径：新值恰为 s.value + d，返回值等于新状态。",
          en: "On success, the new value is exactly s.value + d and the return matches.",
        },
      },
      {
        name: "increment_ok_bound",
        claim: {
          zh: "成功路径单调：guard 保证不回绕，值不减。",
          en: "Success is monotonic: the guard forbids wraparound.",
        },
      },
      {
        name: "increment_overflow_not_ok",
        claim: {
          zh: "溢出分支与成功分支互斥。",
          en: "The overflow branch is exclusive of success.",
        },
      },
    ],
    evm: {
      yul: `object "Counter" {
  code {
    datacopy(0, dataoffset("runtime"), datasize("runtime"))
    return(0, datasize("runtime"))
  }
  object "runtime" {
    code {
      switch shr(224, calldataload(0))
      case 0x1b77eea6 { /* init(uint64) */ }
      case 0xd09de08a { /* increment(uint64) */
        let s := sload(0)
        let d := calldataload(4)
        if gt(s, sub(not(0), d)) { revert(0, 0) }
        sstore(0, add(s, d))
      }
      case 0x20965255 { /* get() */
        mstore(0, sload(0))
        return(0, 32)
      }
    }
  }
}`,
      abi: `[
  { "type": "function", "name": "init", "inputs": [{ "name": "initial", "type": "uint64" }], "outputs": [] },
  { "type": "function", "name": "increment", "inputs": [{ "name": "delta", "type": "uint64" }], "outputs": [{ "type": "uint64" }] },
  { "type": "function", "name": "get", "inputs": [], "outputs": [{ "type": "uint64" }] }
]`,
    },
  },
  {
    id: "Capped",
    name: "Capped",
    targets: ["solc", "yulc"],
    tags: [{ zh: "供给上限", en: "supply cap" }, { zh: "pausable", en: "pausable" }],
    summary: {
      zh: "带 cap 的可铸造代币。mint 不得越过 cap；证明钉在同一 @[pf_entry] 主语上。",
      en: "Mintable token with a hard cap. Mint must not cross the cap; proofs share the @[pf_entry] subject.",
    },
    lean: `import ProofForge

namespace Examples.Evm.Capped
open ProofForge.Evm.Sdk

/-- paused 是 UInt8（0 运行，1 暂停）；cap / supply 是账户里的 UInt256。
    owner 是构造期 immutable。没有 hashed map。 -/
structure State where
  paused : UInt8
  cap : UInt256
  supply : UInt256
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_entry]
def init (_owner : Address) : State :=
  { paused := Pausable.running, cap := ⟨100, 0, 0, 0⟩, supply := UInt256.zero }

/-- 只有构造期 owner 能加 supply。
    非 owner → \`Unauthorized(caller)\`；paused → \`Paused()\`；
    \`supply + v\` 超过 cap → \`CapExceeded()\`。 -/
@[pf_entry]
def mint (s : State) (value : UInt256) : Except Error (State × UInt64) :=
  if Address.eqImmutable Context.caller then
    if s.paused != Pausable.running then
      .ok ({ paused := s.paused, cap := s.cap, supply := s.supply },
        Access.runningViolation)
    else if UInt256.atLeast s.cap (UInt256.add s.supply value) then
      if (0 : UInt64) ≠ 1 then
        .ok ({ paused := s.paused, cap := s.cap,
               supply := UInt256.add s.supply value },
          value.w0)
      else
        .error .overflow
    else
      .ok ({ paused := s.paused, cap := s.cap, supply := s.supply },
        Revert.capExceeded)
  else
    .ok ({ paused := s.paused, cap := s.cap, supply := s.supply },
      Revert.unauthorized Context.caller)
`,
    theorems: [
      {
        name: "mint_supply_within_cap",
        claim: {
          zh: "进入时 supply ≤ cap，则 mint 任何路径都保持 supply ≤ cap。",
          en: "If supply ≤ cap on entry, every mint path keeps supply ≤ cap.",
        },
      },
      {
        name: "mint_supply_effect",
        claim: {
          zh: "mint 要么不动 supply，要么恰好加上 v。",
          en: "mint either leaves supply unchanged or adds exactly v.",
        },
      },
    ],
    evm: {
      yul: `object "Capped" {
  code { /* ctor stores owner, cap */ }
  object "runtime" {
    code {
      // Storage.Layout cursor → hashed-map namespace
      // descriptor erased at extract; not on-chain
    }
  }
}`,
      abi: `[{ "type": "function", "name": "mint", "inputs": [
    { "name": "value", "type": "uint256" }
  ], "outputs": [] }]`,
    },
  },
  {
    id: "Token",
    name: "Token",
    targets: ["solc"],
    tags: [
      { zh: "Evm.Sdk", en: "Evm.Sdk" },
      { zh: "hashed map", en: "hashed map" },
    ],
    summary: {
      zh: "EVM SDK 表面：typed hashed maps、Address / UInt256、封闭 call facade。descriptor 抽取期消去。",
      en: "EVM SDK surface: typed hashed maps, Address / UInt256, closed-call facade. Descriptors erase at extract.",
    },
    lean: `import ProofForge

namespace Examples.Evm.Token
open ProofForge.Evm.Sdk

/-- \`paused\` is 0 while running and 1 while paused. The owner is a constructor immutable;
\`cap\` and \`supply\` use ordinary state slots, while balances, allowances, and nonces use maps. -/
structure State where
  dummy : UInt64
  paused : UInt8
  cap : UInt256
  supply : UInt256
  deriving Repr, DecidableEq, Inhabited

structure ContractStorage where
  balances : Fungible.Balances
  allowances : Fungible.Allowances
  nonces : Storage.AddressMap256

attribute [pf_inline]
  ContractStorage.balances ContractStorage.allowances ContractStorage.nonces

/-- The static cursor assigns disjoint map namespaces; no numeric slot escapes into contract code. -/
@[pf_inline] def storage : ContractStorage :=
  { balances := Storage.Layout.root.addressMap256 |>.handle
    allowances := Storage.Layout.root.addressMap256 |>.next |>.addressPairMap256 |>.handle
    nonces := Storage.Layout.root.addressMap256 |>.next |>.addressPairMap256 |>.next
      |>.addressMap256 |>.handle }

/-- Pause-gated transfer: sequential \`Effect.ensure\` soft-aborts (R5-012 Bool ABI). -/
@[pf_entry]
def transfer (s : State) (destination : Address) (amount : UInt256) :
    Except Error (State × Bool) :=
  Effect.ensure (Access.requireRunning s.paused) (hold s) Access.runningViolation fun _ =>
  Effect.ensure (!Address.isZero destination) (hold s) Revert.zeroAddress fun _ =>
  Effect.ensure (Fungible.Balances.canDebit storage.balances Context.caller amount) (hold s)
      (Fungible.Balances.insufficient storage.balances Context.caller amount) fun _ =>
  if Address.eq Context.caller destination ||
      Fungible.Balances.canCredit storage.balances destination amount then
    let movement :=
      Fungible.Balances.transfer storage.balances Context.caller destination amount
    .ok ({ dummy := movement, paused := s.paused, cap := s.cap, supply := s.supply },
      Effect.thenTrue (Event.transfer Context.caller destination amount))
  else
    .error .overflow
`,
    theorems: [
      {
        name: "transfer_preserves_supply",
        claim: {
          zh: "成功 transfer 不改变 total supply。",
          en: "A successful transfer does not change total supply.",
        },
      },
      {
        name: "mint_supply_effect",
        claim: {
          zh: "mint 要么不动 supply，要么恰好加上 v。",
          en: "mint either leaves supply unchanged or adds exactly v.",
        },
      },
    ],
    evm: {
      yul: `object "Token" {
  object "runtime" {
    code {
      // keccak(slot, key) hashed map
      let fromSlot := keccak256(from, 0x00)
      let bal := sload(fromSlot)
      if lt(bal, amt) { revert(0, 0) }
      sstore(fromSlot, sub(bal, amt))
    }
  }
}`,
      abi: `[{ "type": "function", "name": "transfer", "inputs": [
    { "name": "destination", "type": "address" },
    { "name": "amount", "type": "uint256" }
  ] }]`,
    },
  },
  {
    id: "Vault",
    name: "Vault",
    targets: ["solc"],
    tags: [{ zh: "托管", en: "custody" }, { zh: "ERC-20", en: "ERC-20" }],
    summary: {
      zh: "份额 hashed map + 封闭 ERC-20 / WETH call facade。storage cursor 分配 namespace。",
      en: "Share hashed map plus a closed ERC-20 / WETH call facade. A storage cursor assigns namespaces.",
    },
    lean: `import ProofForge.Evm.Sdk

namespace Examples.Evm.Vault
open ProofForge.Evm.Sdk

/-- \`shares\` 的 hashed Map 用 slot 0 当 base。 -/
structure State where
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

@[pf_inline] def keys : Storage.U64Map := { base := 0 }
@[pf_inline] def shares : Fungible.Balances := { base := 0 }

/-- Checked additive 256-bit share credit. -/
@[pf_entry]
def credit (_s : State) (who : Address) (v : UInt256) : Except Error (State × UInt64) :=
  if Fungible.Balances.canCredit shares who v then
    .ok ({ dummy := 0 }, Fungible.Balances.credit shares who v)
  else
    .error .overflow

/-- 封闭 ERC-20 \`transfer(address,uint256)\`。 -/
@[pf_entry]
def pull (_s : State) (token dest : Address) (amt : UInt256) :
    Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := 0 }, ERC20.transfer token dest amt)
  else
    .error .overflow
`,
    theorems: [],
    evm: {
      yul: `object "Vault" {
  object "runtime" {
    code {
      // hashed Map Address → UInt256 shares
      let slot := keccak256(who, 0x00)
      sstore(slot, add(sload(slot), v))
    }
  }
}`,
      abi: `[{ "type": "function", "name": "credit", "inputs": [
    { "name": "who", "type": "address" },
    { "name": "v", "type": "uint256" }
  ] }]`,
    },
  },
  {
    id: "Ownable",
    name: "Ownable",
    targets: ["solc"],
    tags: [{ zh: "所有权", en: "ownership" }, { zh: "roles", en: "roles" }],
    summary: {
      zh: "构造期 immutable owner。非 owner 走 Unauthorized(caller)；零地址走 ZeroAddress()。",
      en: "Constructor-immutable owner. Non-owner hits Unauthorized(caller); zero address hits ZeroAddress().",
    },
    lean: `import ProofForge.Evm.Sdk

namespace Examples.Evm.Ownable
open ProofForge.Evm.Sdk

/-- owner 是构造期 immutable；storage 只留计数。allowance 走 checked UInt256 pair ledger。 -/
structure State where
  value : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  | unauthorized
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_entry]
def init (_owner : Address) : State :=
  { value := 0 }

/-- 只有构造期 owner 能加。非 owner → \`Unauthorized(caller)\`。整值比较由 SDK Address 拥有。 -/
@[pf_entry]
def bump (s : State) (delta : UInt64) : Except Error (State × UInt64) :=
  if Address.eqImmutable Context.caller then
    if s.value ≤ u64Max - delta then
      let next := s.value + delta
      .ok ({ value := next }, next)
    else
      .error .overflow
  else
    .ok (s, Revert.unauthorized Context.caller)
`,
    theorems: [],
    evm: {
      yul: `object "Ownable" {
  object "runtime" {
    code {
      if iszero(eq(caller(), sload(ownerSlot))) { revert(0, 0) }
    }
  }
}`,
      abi: `[{ "type": "function", "name": "bump", "inputs": [{ "name": "delta", "type": "uint64" }] }]`,
    },
  },
  {
    id: "TipJar",
    name: "TipJar",
    targets: ["solc", "yulc"],
    tags: [
      { zh: "payments", en: "payments" },
      { zh: "context", en: "context" },
    ],
    summary: {
      zh: "payable deposit / value CALL payout / receive()。Context 读 chainId、timestamp、callValue。",
      en: "Payable deposit, value-CALL payout, and receive(). Context reads chainId, timestamp, callValue.",
    },
    lean: `import ProofForge.Evm.Sdk

namespace Examples.Evm.TipJar
open ProofForge.Evm.Sdk

/-- 无链上业务状态；init 只占入口形状。 -/
structure State where
  dummy : UInt64
  deriving Repr, DecidableEq, Inhabited

inductive Error where
  | overflow
  deriving Repr, DecidableEq, Inhabited, BEq

@[pf_entry]
def init (_seed : UInt64) : State :=
  { dummy := 0 }

/-- \`eq(callvalue(), packed uint256)\`。入口因此 payable。不是 \`systemTransfer\`。 -/
@[pf_entry]
def deposit (_s : State) (amt : UInt256) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := 0 }, Ether.accept amt)
  else
    .error .overflow

/-- value CALL 到 20B Address，金额是 packed wei。失败 revert。重入不进参考语义。 -/
@[pf_entry]
def payout (_s : State) (dst : Address) (amt : UInt256) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := 0 }, Ether.send dst amt)
  else
    .error .overflow

/-- 无 calldata 的 payable \`receive()\`。 -/
@[pf_entry]
def receive (_s : State) : Except Error (State × UInt64) :=
  if (0 : UInt64) ≠ 1 then
    .ok ({ dummy := 0 }, Ether.receive)
  else
    .error .overflow
`,
    theorems: [],
    evm: {
      yul: `object "TipJar" {
  object "runtime" {
    code {
      switch shr(224, calldataload(0))
      case 0x00 { /* receive() — empty calldata */ }
      default {
        if eq(callvalue(), amt) { /* deposit */ }
        let ok := call(gas(), dst, amt, 0, 0, 0, 0)
        if iszero(ok) { revert(0, 0) }
      }
    }
  }
}`,
      abi: `[
  { "type": "function", "name": "deposit", "stateMutability": "payable", "inputs": [{ "name": "amt", "type": "uint256" }] },
  { "type": "function", "name": "payout", "inputs": [
    { "name": "dst", "type": "address" },
    { "name": "amt", "type": "uint256" }
  ] },
  { "type": "receive", "stateMutability": "payable" }
]`,
    },
  },
];

export function exampleById(id: string): Example | undefined {
  return EXAMPLES.find((e) => e.id === id);
}
