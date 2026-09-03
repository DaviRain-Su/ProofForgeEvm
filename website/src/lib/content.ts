import type { Lang } from "@/lib/i18n";

export const REPO = "https://github.com/DaviRain-Su/ProofForgeEvm";
export const MCP = "https://proof-forge-mcp.davirain-yin.workers.dev/mcp";

export const NAV = [
  { href: "/", zh: "概览", en: "Overview" },
  { href: "/docs", zh: "文档", en: "Docs" },
  { href: "/examples", zh: "示例", en: "Examples" },
  { href: "/cli", zh: "CLI", en: "CLI" },
] as const;

export const HERO = {
  kicker: { zh: "Lean 4 编译剖面", en: "Lean 4 compiler profile" },
  title: { zh: "普通 Lean。链上字节。", en: "Ordinary Lean. On-chain bytes." },
  lead: {
    zh: "不是一门新合约语言。普通 def 写合约，普通 theorem 证合约。同一主语抽出到 EVM Yul，由 solc 或 yulc 汇编。",
    en: "Not a new contract language. Write contracts as defs, prove them as theorems. One subject lowers to EVM Yul, assembled by solc or yulc.",
  },
};

export const PIPELINE = [
  {
    id: "lean",
    zh: "普通 Lean",
    en: "Ordinary Lean",
    detail: {
      zh: "def / theorem / structure。入口用 @[pf_entry] 标记。没有 program … where。",
      en: "def / theorem / structure. Mark entries with @[pf_entry]. No program … where.",
    },
  },
  {
    id: "profile",
    zh: "Profile",
    en: "Profile",
    detail: {
      zh: "传递闭包准入。拒绝 IO、partial、sorry、@[extern]、无界递归。Fail-closed。",
      en: "Transitive-closure admission. Rejects IO, partial, sorry, @[extern], unbounded recursion. Fail-closed.",
    },
  },
  {
    id: "extract",
    zh: "Extract",
    en: "Extract",
    detail: {
      zh: "Expr → typed Core + target-neutral Ops。证明主语与编译主语共享 IR digest。",
      en: "Expr → typed Core + target-neutral Ops. Proof subject and compile subject share the IR digest.",
    },
  },
  {
    id: "split",
    zh: "EVM IR",
    en: "EVM IR",
    detail: {
      zh: "Core 降到 EVM IR。物化 storage slot / selector / ABI。Registry 钉 47 个示例 digest。",
      en: "Core lowers to EVM IR. Owns storage slots / selector / ABI. The registry pins 47 example digests.",
    },
  },
  {
    id: "emit",
    zh: "Yul → .bin",
    en: "Yul → .bin",
    detail: {
      zh: "Emit 出 Yul。solc 或 powdr yulc 汇编 .bin / .yul / .abi.json。工程门：Anvil。",
      en: "Emit writes Yul. solc or powdr yulc assembles .bin / .yul / .abi.json. Engineering gate: Anvil.",
    },
  },
];

export const PILLARS = [
  {
    title: { zh: "同一主语", en: "One subject" },
    body: {
      zh: "定理钉在用户 def 上，编译走同一抽出 IR。禁止「证的是 A，编的是 B」。",
      en: "Theorems pin the user def; compile walks the same extracted IR. No proving A while emitting B.",
    },
  },
  {
    title: { zh: "Fail-closed 子集", en: "Fail-closed subset" },
    body: {
      zh: "能降到链上的才过 Profile。过不了的不是警告，是拒绝。",
      en: "Only what can lower on-chain passes Profile. Failures are refusals, not warnings.",
    },
  },
  {
    title: { zh: "一条 Core，两条后端", en: "One Core, two backends" },
    body: {
      zh: "Lean / Profile / Extract / CFG / EVM IR 共享一条链。solc 与 yulc 汇编同一份 Yul。",
      en: "Lean / Profile / Extract / CFG / EVM IR share one chain. solc and yulc assemble the same Yul.",
    },
  },
  {
    title: { zh: "诚实的信任边界", en: "Honest trust boundary" },
    body: {
      zh: "Kernel 接受的是关于 def / IR 的定理。不声称 .bin、EVM 或公网部署正确。",
      en: "The kernel accepts theorems about the def / IR. That is not a claim about .bin, the EVM, or mainnet.",
    },
  },
];

export const TARGETS = [
  {
    id: "solc" as const,
    name: "solc",
    kicker: { zh: "默认后端", en: "default backend" },
    artifacts: [".bin", ".yul", ".abi.json"],
    points: {
      zh: [
        "Lean → Extract IR → EVM IR → Yul → 钉死的 solc 0.8.34",
        "pf build 默认写出 Name.bin / Name.yul / Name.abi.json",
        "Registry 钉 47 个示例 digest；抽出不匹配即拒绝",
        "Anvil 工程门；v0 拒绝公网 broadcast",
      ],
      en: [
        "Lean → Extract IR → EVM IR → Yul → pinned solc 0.8.34",
        "pf build writes Name.bin / Name.yul / Name.abi.json by default",
        "The registry pins 47 example digests; a mismatch is a refusal",
        "Anvil engineering gate; v0 refuses public broadcast",
      ],
    },
  },
  {
    id: "yulc" as const,
    name: "yulc",
    kicker: { zh: "powdr 后端", en: "powdr backend" },
    artifacts: [".bin", ".yul", ".abi.json"],
    points: {
      zh: [
        "同一份 Yul，--backend yulc 或 PROOFFORGE_EVM_BACKEND=yulc",
        "Evm.Sdk：storage、ERC-721 / ERC-1155、roles、pausable",
        "用户项目只 import ProofForge.Attr + ProofForge.Evm.Sdk",
        "CLI：pf build / pf init / pf --version",
      ],
      en: [
        "The same Yul, via --backend yulc or PROOFFORGE_EVM_BACKEND=yulc",
        "Evm.Sdk: storage, ERC-721 / ERC-1155, roles, pausable",
        "User projects import only ProofForge.Attr + ProofForge.Evm.Sdk",
        "CLI: pf build / pf init / pf --version",
      ],
    },
  },
];

export const TRUST = {
  title: { zh: "信任边界", en: "Trust boundary" },
  weak: {
    zh: "弱声明：kernel 接受了关于用户 def / 抽出 IR 的定理。TCB = Lean kernel + 主语绑定。",
    en: "Weak claim: the kernel accepted theorems about the user def / extracted IR. TCB = Lean kernel + subject binding.",
  },
  eng: {
    zh: "工程声明：同一 IR 经发射器 + 钉死的 solc 或 yulc，在 Anvil 上与夹具一致。",
    en: "Engineering claim: the same IR, through the emitter and pinned solc or yulc, matches fixtures on Anvil.",
  },
  not: {
    zh: "不做的声明：.bin / EVM 语义精化 / 定理 ⇒ 已部署合约。",
    en: "Not claimed: .bin / full EVM refinement / theorem ⇒ deployed contract.",
  },
};

export const TOOLCHAIN = [
  { name: "Lean 4", value: "v4.31.0" },
  { name: "solc", value: "0.8.34" },
  { name: "Foundry", value: "1.7.1" },
  { name: "CLI", value: "pf" },
];

export const COMMANDS = [
  {
    title: { zh: "构建编译器", en: "Build the compiler" },
    cmd: "lake build",
  },
  {
    title: { zh: "solc 后端", en: "solc backend" },
    cmd: "lake exe pf -- build --out build/evm Counter",
    note: { zh: "写出 Counter.bin / Counter.yul / Counter.abi.json", en: "Writes Counter.bin / Counter.yul / Counter.abi.json" },
  },
  {
    title: { zh: "yulc 后端", en: "yulc backend" },
    cmd: "lake exe pf -- build --backend yulc --out build/evm Counter",
    note: { zh: "同一份 Yul，由 powdr yulc 汇编", en: "The same Yul, assembled by powdr yulc" },
  },
  {
    title: { zh: "Anvil 工程门", en: "Anvil engineering gate" },
    cmd: "runtime-tests/evm/anvil.sh",
  },
  {
    title: { zh: "用户项目", en: "User project" },
    cmd: "pf init demo && cd demo && lake build && lake env pf build",
    note: { zh: "模板在 templates/evm-counter。只 import Attr 与 Evm.Sdk。", en: "Template is templates/evm-counter. Import only Attr and Evm.Sdk." },
  },
];

export const DOC_SECTIONS = [
  { id: "start", zh: "开始", en: "Start" },
  { id: "surface", zh: "语言表面", en: "Surface" },
  { id: "pipeline", zh: "编译链", en: "Pipeline" },
  { id: "sdk", zh: "SDK", en: "SDK" },
  { id: "evm", zh: "EVM", en: "EVM" },
  { id: "proofs", zh: "证明", en: "Proofs" },
  { id: "trust", zh: "信任", en: "Trust" },
  { id: "mcp", zh: "MCP", en: "MCP" },
] as const;

export type DocId = (typeof DOC_SECTIONS)[number]["id"];

export const DOCS: Record<DocId, { zh: { title: string; blocks: string[] }; en: { title: string; blocks: string[] } }> = {
  start: {
    zh: {
      title: "开始",
      blocks: [
        "ProofForge EVM 是 Lean 4 的编译剖面，不是 DSL。克隆仓库，用 Lake 构建，用 pf 编合约。",
        "Toolchain 钉死：leanprover/lean4:v4.31.0、solc 0.8.34、Foundry 1.7.1。不要用 PATH 里随便一个汇编器顶替锁版本。",
        "第一份合约建议从 Examples.Counter 读起：UInt64、checked add。同一文件里有 Proofs 节。",
      ],
    },
    en: {
      title: "Start",
      blocks: [
        "ProofForge EVM is a Lean 4 compiler profile, not a DSL. Clone the repo, build with Lake, compile with pf.",
        "Toolchain is pinned: leanprover/lean4:v4.31.0, solc 0.8.34, Foundry 1.7.1. Do not substitute a PATH assembler for the lock.",
        "Read Examples.Counter first: UInt64, checked add. The Proofs section lives in the same file.",
      ],
    },
  },
  surface: {
    zh: {
      title: "语言表面",
      blocks: [
        "用户写的是普通 Lean。没有 program … where。入口用 @[pf_entry]；内联用 @[pf_inline]。",
        "Profile 检查传递闭包：IO、partial、sorry、@[extern]、@[implemented_by]、无界递归一律拒绝。",
        "抽出权威是 elaborated Expr 闭包，不是 Lean.Compiler.IR。业务类型检查仍由 Lean 完成。",
      ],
    },
    en: {
      title: "Surface",
      blocks: [
        "Users write ordinary Lean. There is no program … where. Mark entries @[pf_entry]; inline with @[pf_inline].",
        "Profile checks the transitive closure: IO, partial, sorry, @[extern], @[implemented_by], unbounded recursion are refused.",
        "Extract authority is the elaborated Expr closure, not Lean.Compiler.IR. Lean still owns business typing.",
      ],
    },
  },
  pipeline: {
    zh: {
      title: "编译链",
      blocks: [
        "Profile → Extract.IR / Core → Evm.IR → Yul Emit → Assemble（solc 或 yulc）。Core 拥有 schema、control、checked arithmetic。",
        "Core.Target 做公共 Val/Op/Program 投影。具体 opcode 留在 EVM 模块。",
        "CLI 构建必须重新从用户模块抽 IR，不能组装 legacy Golden fixture。Registry 只列可构建模块并钉 47 个 digest。",
      ],
    },
    en: {
      title: "Pipeline",
      blocks: [
        "Profile → Extract.IR / Core → Evm.IR → Yul Emit → Assemble (solc or yulc). Core owns schema, control, checked arithmetic.",
        "Core.Target projects Val/Op/Program. Concrete opcodes stay in EVM-owned modules.",
        "CLI build re-extracts IR from the user module. It does not assemble a legacy Golden fixture. The registry lists modules and pins 47 digests.",
      ],
    },
  },
  sdk: {
    zh: {
      title: "SDK",
      blocks: [
        "ProofForge.Evm.Sdk 是合同源表面：storage、ERC-721 / ERC-1155、roles、pausable、reentrancy、payments。",
        "用户项目只 import ProofForge.Attr 与 ProofForge.Evm.Sdk，不碰 ProofForge 伞模块。SDK 传递闭包不得到达 Emit / Assemble / Registry。",
        "Storage.Layout 是编译期 cursor；descriptor 抽取期消去。SDK 不包装 .ok / .error，不改变 Lean 控制流。",
      ],
    },
    en: {
      title: "SDK",
      blocks: [
        "ProofForge.Evm.Sdk is the contract-facing surface: storage, ERC-721 / ERC-1155, roles, pausable, reentrancy, payments.",
        "User projects import only ProofForge.Attr and ProofForge.Evm.Sdk — never the ProofForge umbrella. The SDK closure must not reach Emit / Assemble / Registry.",
        "Storage.Layout is a compile-time cursor; descriptors erase at extract. The SDK does not wrap .ok / .error and does not change Lean control flow.",
      ],
    },
  },
  evm: {
    zh: {
      title: "EVM",
      blocks: [
        "EVM 是本仓库的唯一目标。普通 Lean、Profile、Extract 和 Core CFG 降到 EVM IR，再发射 Yul。",
        "双后端：默认 solc 0.8.34；powdr yulc 由 --backend yulc 选用。产物都是 .bin / .yul / .abi.json。",
        "runtime-tests/evm 在 Anvil 上跑链上工程门。Examples.Token / Capped / TipJar 已坐在 SDK 表面上。",
      ],
    },
    en: {
      title: "EVM",
      blocks: [
        "EVM is the only target in this repository. Ordinary Lean, Profile, Extract, and Core CFG lower to EVM IR, then emit Yul.",
        "Dual backends: solc 0.8.34 by default; powdr yulc via --backend yulc. Artifacts are .bin / .yul / .abi.json.",
        "runtime-tests/evm runs on-chain engineering gates on Anvil. Examples.Token / Capped / TipJar already sit on the SDK surface.",
      ],
    },
  },
  proofs: {
    zh: {
      title: "证明",
      blocks: [
        "第一批 kernel-checked 性质落在合约文件的 Proofs 节：成功路径后置条件、单调性、Token supply 效应、Capped cap 不变量。",
        "只依赖标准公理 propext / Quot.sound。CI 由 scripts/check_no_sorry.py 保证证明批次不含占位符。",
        "证明主语和编译主语必须共享同一个 IR digest。",
      ],
    },
    en: {
      title: "Proofs",
      blocks: [
        "The first kernel-checked properties live in each contract file's Proofs section: success postconditions, monotonicity, Token supply effect, Capped cap invariant.",
        "They depend only on the standard axioms propext / Quot.sound. CI (scripts/check_no_sorry.py) refuses placeholders in the proof batch.",
        "Proof subject and compile subject must share the same IR digest.",
      ],
    },
  },
  trust: {
    zh: {
      title: "信任",
      blocks: [
        "弱声明（对外 v0）：kernel 接受了关于用户 def / 抽出 IR 的定理。TCB = Lean kernel + 主语绑定。",
        "工程声明：同一 IR 经 PF 发射器 + pinned solc 或 yulc 得到的 .bin，在 pinned Anvil 上行为与夹具一致。",
        "不做的声明：.bin / 全 EVM refinement；定理不蕴含公网部署正确。",
      ],
    },
    en: {
      title: "Trust",
      blocks: [
        "Weak claim (v0 public): the kernel accepted theorems about the user def / extracted IR. TCB = Lean kernel + subject binding.",
        "Engineering claim: the .bin from that IR through the PF emitter + pinned solc or yulc matches fixtures on pinned Anvil.",
        "Not claimed: .bin / full EVM refinement. A theorem does not imply a correct public deployment.",
      ],
    },
  },
  mcp: {
    zh: {
      title: "MCP",
      blocks: [
        "远程 MCP 只提供文档、目录与脚手架指导，不 spawn Lean，不持有密钥，不广播。",
        "本机 stdio MCP 才封装 pf doctor / install / build / artifacts / local。local 仅 EVM。",
        "Agent 接线：codex mcp add proof-forge-mcp --url https://proof-forge-mcp.davirain-yin.workers.dev/mcp",
      ],
    },
    en: {
      title: "MCP",
      blocks: [
        "The remote MCP serves docs, catalogs, and scaffold guidance. It does not spawn Lean, hold keys, or broadcast.",
        "The local stdio MCP wraps pf doctor / install / build / artifacts / local. local is EVM only.",
        "Agent wiring: codex mcp add proof-forge-mcp --url https://proof-forge-mcp.davirain-yin.workers.dev/mcp",
      ],
    },
  },
};

export function copy(lang: Lang, rec: { zh: string; en: string }): string {
  return rec[lang];
}
