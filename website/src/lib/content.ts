import type { Lang } from "@/lib/i18n";

export const REPO = "https://github.com/DaviRain-Su/ProofForgeEvm";

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
    zh: "不是一门新合约语言。普通 def 写合约，普通 theorem 证合约。同一主语抽出到 EVM Yul；默认由钉死的 solc 汇编，yulc 仍是实验后端。",
    en: "Not a new contract language. Write contracts as defs, prove them as theorems. One subject lowers to EVM Yul; pinned solc is the supported assembler, yulc stays experimental.",
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
      zh: "Expr → typed Core + target-neutral Ops。示例 digest 由 Registry 钉住；用户模块每次重新抽出。",
      en: "Expr → typed Core + target-neutral Ops. Example digests are pinned by the registry; user modules re-extract every build.",
    },
  },
  {
    id: "split",
    zh: "EVM IR",
    en: "EVM IR",
    detail: {
      zh: "Core 降到 EVM IR。物化 storage slot / selector / ABI。Registry 钉 52 个示例 digest。",
      en: "Core lowers to EVM IR. Owns storage slots / selector / ABI. The registry pins 52 example digests.",
    },
  },
  {
    id: "emit",
    zh: "Yul → .bin",
    en: "Yul → .bin",
    detail: {
      zh: "Emit 出 Yul。默认 solc 汇编 .bin / .yul / .abi.json。工程门：Anvil。yulc 为实验车道。",
      en: "Emit writes Yul. Default solc assembles .bin / .yul / .abi.json. Engineering gate: Anvil. yulc is an experimental lane.",
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
    title: { zh: "一条 Core，一个产品后端", en: "One Core, one product backend" },
    body: {
      zh: "Lean / Profile / Extract / CFG / EVM IR 共享一条链。产品承诺钉在 solc；yulc 是可选实验汇编。",
      en: "Lean / Profile / Extract / CFG / EVM IR share one chain. The product promise is pinned to solc; yulc is optional and experimental.",
    },
  },
  {
    title: { zh: "诚实的信任边界", en: "Honest trust boundary" },
    body: {
      zh: "Kernel 接受的是关于 def 的定理。不声称 extracted IR / .bin / EVM / 公网部署已被证明。",
      en: "The kernel accepts theorems about the def. That is not a claim that extracted IR / .bin / EVM / mainnet deployment are proved.",
    },
  },
];

export const TARGETS = [
  {
    id: "solc" as const,
    name: "solc",
    kicker: { zh: "支持的默认后端", en: "supported default" },
    artifacts: [".bin", ".yul", ".abi.json"],
    points: {
      zh: [
        "Lean → Extract IR → EVM IR → Yul → 钉死的 solc 0.8.34",
        "pf build 默认写出 Name.bin / Name.yul / Name.abi.json",
        "Registry 钉 52 个示例 digest；抽出不匹配即拒绝",
        "Anvil 工程门；v0 拒绝公网 broadcast",
      ],
      en: [
        "Lean → Extract IR → EVM IR → Yul → pinned solc 0.8.34",
        "pf build writes Name.bin / Name.yul / Name.abi.json by default",
        "The registry pins 52 example digests; a mismatch is a refusal",
        "Anvil engineering gate; v0 refuses public broadcast",
      ],
    },
  },
  {
    id: "yulc" as const,
    name: "yulc",
    kicker: { zh: "实验后端（非 merge 门禁）", en: "experimental (not a merge gate)" },
    artifacts: [".bin", ".yul", ".abi.json"],
    points: {
      zh: [
        "同一份 Yul，--backend yulc 或 PROOFFORGE_EVM_BACKEND=yulc",
        "CI 为周跑 / 手动；不作 PR merge gate",
        "Anvil 双后端门目前覆盖 Counter / Capped / Const / Flag / Phase / Wide / TipJar",
        "含外部 CALL / gas() 的合约可能被 yulc 拒绝",
      ],
      en: [
        "The same Yul, via --backend yulc or PROOFFORGE_EVM_BACKEND=yulc",
        "CI is weekly / manual; it is not a PR merge gate",
        "Dual-backend Anvil gates currently cover Counter / Capped / Const / Flag / Phase / Wide / TipJar",
        "Contracts with external CALL / gas() may be refused by yulc",
      ],
    },
  },
];

export const TRUST = {
  title: { zh: "信任边界", en: "Trust boundary" },
  weak: {
    zh: "弱声明：kernel 接受了关于用户 def 的定理。TCB = Lean kernel + 主语绑定。这不等于 IR / Yul / bytecode 精化。",
    en: "Weak claim: the kernel accepted theorems about the user def. TCB = Lean kernel + subject binding. That is not IR / Yul / bytecode refinement.",
  },
  eng: {
    zh: "工程声明：同一 IR 经发射器 + 钉死的 solc，在 Anvil 上与夹具一致。yulc 仅在已标注的实验子集上有对照门。",
    en: "Engineering claim: the same IR, through the emitter and pinned solc, matches fixtures on Anvil. yulc has dual-backend gates only on the labeled experimental subset.",
  },
  not: {
    zh: "不做的声明：.bin / 全 EVM 语义精化 / 定理 ⇒ 已部署合约；也不声称 ERC-721/1155 为完整标准实现。",
    en: "Not claimed: .bin / full EVM refinement / theorem ⇒ deployed contract; ERC-721/1155 are not claimed as full standard implementations.",
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
    title: { zh: "构建编译器与 CLI", en: "Build compiler + CLI" },
    cmd: "lake build && lake build pf",
  },
  {
    title: { zh: "solc 后端（支持）", en: "solc backend (supported)" },
    cmd: "lake exe pf -- build --out build/evm Counter",
    note: {
      zh: "写出 Counter.bin / Counter.yul / Counter.abi.json",
      en: "Writes Counter.bin / Counter.yul / Counter.abi.json",
    },
  },
  {
    title: { zh: "yulc 后端（实验）", en: "yulc backend (experimental)" },
    cmd: "lake exe pf -- build --backend yulc --out build/evm Counter",
    note: {
      zh: "需本机 yulc；周跑 CI，非 merge 门禁",
      en: "Requires a local yulc; weekly CI, not a merge gate",
    },
  },
  {
    title: { zh: "Anvil 工程门", en: "Anvil engineering gate" },
    cmd: "runtime-tests/evm/anvil.sh",
  },
  {
    title: { zh: "用户项目（checkout 内）", en: "User project (from checkout)" },
    cmd: "export PATH=\"$PWD/.lake/build/bin:$PATH\" && lake exe pf -- init demo && cd demo && lake build && lake env pf build",
    note: {
      zh: "模板在 templates/evm-counter。当前 init 依赖仓库 checkout；尚无独立安装包。",
      en: "Template is templates/evm-counter. init currently requires a repo checkout; there is no standalone installer yet.",
    },
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
  { id: "limits", zh: "边界", en: "Limits" },
] as const;

export type DocId = (typeof DOC_SECTIONS)[number]["id"];

export const DOCS: Record<
  DocId,
  { zh: { title: string; blocks: string[] }; en: { title: string; blocks: string[] } }
> = {
  start: {
    zh: {
      title: "开始",
      blocks: [
        "ProofForge EVM 是 Lean 4 的编译剖面，不是 DSL。克隆仓库，用 Lake 构建，用 pf 编合约。",
        "Toolchain 钉死：leanprover/lean4:v4.31.0、solc 0.8.34、Foundry 1.7.1。不要用 PATH 里随便一个汇编器顶替锁版本。",
        "可复制路径（在仓库根）：lake build pf && export PATH=\"$PWD/.lake/build/bin:$PATH\" && lake exe pf -- init demo && cd demo && lake build && lake env pf build。",
        "产品能力矩阵与写合约指南见 docs/product/。模块内部说明见 docs/modules/。",
      ],
    },
    en: {
      title: "Start",
      blocks: [
        "ProofForge EVM is a Lean 4 compiler profile, not a DSL. Clone the repo, build with Lake, compile with pf.",
        "Toolchain is pinned: leanprover/lean4:v4.31.0, solc 0.8.34, Foundry 1.7.1. Do not substitute a PATH assembler for the lock.",
        "Reproducible path (repo root): lake build pf && export PATH=\"$PWD/.lake/build/bin:$PATH\" && lake exe pf -- init demo && cd demo && lake build && lake env pf build.",
        "See docs/product/ for the support matrix and writing guide. See docs/modules/ for internal module notes.",
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
        "当前效应仍常编码成 UInt64 载体；示例里可见 dummy / hold / 假守卫。这是已知产品债，不是推荐写法的终点。",
      ],
    },
    en: {
      title: "Surface",
      blocks: [
        "Users write ordinary Lean. There is no program … where. Mark entries @[pf_entry]; inline with @[pf_inline].",
        "Profile checks the transitive closure: IO, partial, sorry, @[extern], @[implemented_by], unbounded recursion are refused.",
        "Extract authority is the elaborated Expr closure, not Lean.Compiler.IR. Lean still owns business typing.",
        "Effects are still often encoded as UInt64 carriers; examples show dummy / hold / fake guards. That is known product debt, not the end state.",
      ],
    },
  },
  pipeline: {
    zh: {
      title: "编译链",
      blocks: [
        "Profile → Extract.IR / Core → Evm.IR → Yul Emit → Assemble（默认 solc；可选 yulc）。Core 拥有 schema、control、checked arithmetic。",
        "CLI 构建必须重新从用户模块抽 IR，不能组装 legacy Golden fixture。Registry 只钉仓内 Examples 的 52 个 digest。",
        "详细边界见 docs/product/support-matrix.md。",
      ],
    },
    en: {
      title: "Pipeline",
      blocks: [
        "Profile → Extract.IR / Core → Evm.IR → Yul Emit → Assemble (solc by default; optional yulc). Core owns schema, control, checked arithmetic.",
        "CLI build re-extracts IR from the user module. It does not assemble a legacy Golden fixture. The registry pins 52 in-tree Examples digests only.",
        "See docs/product/support-matrix.md for the detailed boundary.",
      ],
    },
  },
  sdk: {
    zh: {
      title: "SDK",
      blocks: [
        "ProofForge.Evm.Sdk 是合同源表面：storage、fungible ledger、roles、pausable、reentrancy、payments，以及 ERC-721/1155 的 bounded core。",
        "用户项目只 import ProofForge.Attr 与 ProofForge.Evm.Sdk，不碰 ProofForge 伞模块。SDK 传递闭包不得到达 Emit / Assemble / Registry。",
        "ERC-721/1155 当前是账本/授权 core，不是完整标准实现（已覆盖所列 canonical events；仍缺 safe 回调、完整 metadata ABI）。对外请称 core / bounded policy。",
      ],
    },
    en: {
      title: "SDK",
      blocks: [
        "ProofForge.Evm.Sdk is the contract-facing surface: storage, fungible ledger, roles, pausable, reentrancy, payments, and bounded ERC-721/1155 cores.",
        "User projects import only ProofForge.Attr and ProofForge.Evm.Sdk — never the ProofForge umbrella. The SDK closure must not reach Emit / Assemble / Registry.",
        "ERC-721/1155 are ledger/approval cores today, not full standard implementations (the listed canonical events are covered; safe callbacks and complete metadata ABI are absent). Call them core / bounded policy.",
      ],
    },
  },
  evm: {
    zh: {
      title: "EVM",
      blocks: [
        "EVM 是本仓库的唯一目标。普通 Lean、Profile、Extract 和 Core CFG 降到 EVM IR，再发射 Yul。",
        "产品后端：默认 solc 0.8.34。powdr yulc 是实验选项，周跑/手动 CI，覆盖子集见 support matrix。",
        "runtime-tests/evm 在 Anvil 上跑链上工程门。Examples.Token / Capped / TipJar 已坐在 SDK 表面上。",
      ],
    },
    en: {
      title: "EVM",
      blocks: [
        "EVM is the only target in this repository. Ordinary Lean, Profile, Extract, and Core CFG lower to EVM IR, then emit Yul.",
        "Product backend: solc 0.8.34 by default. powdr yulc is experimental, weekly/manual CI; see the support matrix for the covered subset.",
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
        "当前定理钉的是用户 def / 静态字段，不是 hashed-map 余额世界，也不是 .bin 精化。",
      ],
    },
    en: {
      title: "Proofs",
      blocks: [
        "The first kernel-checked properties live in each contract file's Proofs section: success postconditions, monotonicity, Token supply effect, Capped cap invariant.",
        "They depend only on the standard axioms propext / Quot.sound. CI (scripts/check_no_sorry.py) refuses placeholders in the proof batch.",
        "Today's theorems pin the user def / static fields — not a hashed-map balance world, and not .bin refinement.",
      ],
    },
  },
  trust: {
    zh: {
      title: "信任",
      blocks: [
        "弱声明（对外 v0）：kernel 接受了关于用户 def 的定理。TCB = Lean kernel + 主语绑定。",
        "工程声明：同一 IR 经 PF 发射器 + pinned solc 得到的 .bin，在 pinned Anvil 上行为与夹具一致。",
        "不做的声明：.bin / 全 EVM refinement；定理不蕴含公网部署正确；也不把 yulc 说成已支持的对等后端。",
      ],
    },
    en: {
      title: "Trust",
      blocks: [
        "Weak claim (v0 public): the kernel accepted theorems about the user def. TCB = Lean kernel + subject binding.",
        "Engineering claim: the .bin from that IR through the PF emitter + pinned solc matches fixtures on pinned Anvil.",
        "Not claimed: .bin / full EVM refinement. A theorem does not imply a correct public deployment. yulc is not a supported peer backend.",
      ],
    },
  },
  limits: {
    zh: {
      title: "边界",
      blocks: [
        "CLI 表面只有 pf build / pf init / pf --version。没有 doctor / install / artifacts / local，也没有本仓 MCP server。",
        "pf init 目前必须在仓库 checkout 根附近运行，并改写 path-require；离开 checkout 的独立安装包尚未发布。",
        "明确不做：动态 callee、delegatecall、create2、proxy、无界循环、主网部署声明、bytecode refinement。",
        "官网 Forge 面板里的 Yul/ABI 摘录是示意形状，不是每次构建的实时产物。",
      ],
    },
    en: {
      title: "Limits",
      blocks: [
        "The CLI surface is pf build / pf init / pf --version only. There is no doctor / install / artifacts / local, and no in-repo MCP server.",
        "pf init currently must run from a repo checkout and rewrites a path-require; a standalone installer outside the checkout is not published yet.",
        "Explicitly out of scope: dynamic callee, delegatecall, create2, proxy, unbounded loops, mainnet deployment claims, bytecode refinement.",
        "Yul/ABI excerpts in the website Forge panel are illustrative shapes, not live build artifacts.",
      ],
    },
  },
};

export function copy(lang: Lang, rec: { zh: string; en: string }): string {
  return rec[lang];
}
