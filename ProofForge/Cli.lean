import Lean
import ProofForge.Extract
import ProofForge.Core.IR
import ProofForge.Evm.Assemble
import ProofForge.Evm.IR
import ProofForge.Evm.Registry

namespace ProofForge.Cli

inductive Command where
  | build
  | init
  deriving BEq, Repr, Inhabited

structure Options where
  command : Command := .build
  outDir : System.FilePath := "build/out"
  names : Array String := #[]
  evmBackend : Option ProofForge.Evm.Assemble.Backend := none
  /-- Fully-qualified Lean modules (`MyContract.Counter`). Overrides in-tree fixture mapping when set. -/
  modules : Array String := #[]
  /-- Project directory name for `pf init`. -/
  initName : String := ""
  help : Bool := false
  version : Bool := false

private def usage : String :=
  "pf — ProofForge EVM compiler\n" ++
    "\n" ++
    "Usage:\n" ++
    "  pf build [--out DIR] [--backend solc|yulc] [--module MOD] [Contract ...]\n" ++
    "  pf init <name>\n" ++
    "  pf --version\n" ++
    "\n" ++
    "build writes Name.bin / Name.yul / Name.abi.json (default backend solc; --backend yulc or PROOFFORGE_EVM_BACKEND=yulc)\n" ++
    "--module takes a dotted Lean module (repeatable). Bare Contract names map to in-tree Examples fixtures.\n" ++
    "User projects should pass --module or list [[program]] entries in pf.toml.\n" ++
    "No contract names on build means every registered source module.\n"

def parseArgs (args : List String) : Except String Options :=
  let rec go (rest : List String) (o : Options) : Except String Options :=
    match rest with
    | [] => .ok o
    | "-h" :: _ | "--help" :: _ => .ok { o with help := true }
    | "--version" :: _ | "-V" :: _ => .ok { o with version := true }
    | "--target" :: t :: rest =>
      if t == "evm" then go rest o
      else .error s!"unknown target {t} (this build of pf supports EVM only)"
    | "--out" :: d :: rest => go rest { o with outDir := d }
    | "--module" :: m :: rest => go rest { o with modules := o.modules.push m }
    | "--backend" :: b :: rest =>
      match ProofForge.Evm.Assemble.parseBackend b with
      | some backend => go rest { o with evmBackend := some backend }
      | none => .error s!"unknown evm backend {b} (want solc or yulc)"
    | flag :: rest =>
      if flag.startsWith "--backend=" then
        let b := (flag.replace "--backend=" "").trimAscii.toString
        match ProofForge.Evm.Assemble.parseBackend b with
        | some backend => go rest { o with evmBackend := some backend }
        | none => .error s!"unknown evm backend {b} (want solc or yulc)"
      else if flag.startsWith "-" then .error s!"unknown flag {flag}"
      else if o.command == .init && o.initName.isEmpty then
        go rest { o with initName := flag }
      else
        go rest { o with names := o.names.push flag }
  let args := args.dropWhile (· == "--")
  let (_cmd, rest) :=
    match args with
    | "build" :: rest => (Command.build, rest)
    | "init" :: rest => (Command.init, rest)
    | rest => (Command.build, rest)
  go rest { command := _cmd }

private def evmProgramNames : Array String :=
  Evm.Registry.names

private def selectEvmNames (names : Array String) : Except String (Array String) :=
  if names.isEmpty then .ok evmProgramNames
  else
    names.mapM fun n =>
      match evmProgramNames.find? (· == n) with
      | some _ => .ok n
      | none => .error s!"unknown evm program {n}"

/-- Dual-target fixtures stay at `Examples.<Name>`; EVM-only fixtures live under
`Examples.Evm.<Name>`. Program registry names are the last component. -/
private def sharedFixtureNames : Array String :=
  #["Counter", "Flag", "Lang", "Maybe", "Pair", "Phase", "TokenShape", "Window"]

/-- Ergonomics fixtures not yet moved under `Examples.Evm.`. -/
private def rootFixtureNames : Array String :=
  #["EvmExceptErgonomics", "EvmTokenErgonomics"]

def fixtureModule (name : String) : Lean.Name :=
  if sharedFixtureNames.contains name || rootFixtureNames.contains name then
    Lean.Name.str `Examples name
  else
    Lean.Name.str `Examples.Evm name

structure BuildUnit where
  name : String
  module : Lean.Name
  deriving Repr

private def dottedToName (mod : String) : Lean.Name :=
  (mod.splitOn ".").foldl (fun n p => if p.isEmpty then n else Lean.Name.str n p) .anonymous

private def basenameOfModule (mod : String) : String :=
  match (mod.splitOn ".").getLast? with
  | some n => n
  | none => mod

private def trimStr (s : String) : String :=
  s.trimAscii.toString

private def dropStr (s : String) (n : Nat) : String :=
  (s.drop n).toString

private def dropEndStr (s : String) (n : Nat) : String :=
  (s.dropEnd n).toString

private def unquoteToml (v0 : String) : String :=
  let v := trimStr v0
  if v.startsWith "\"" && v.endsWith "\"" && v.length ≥ 2 then
    dropEndStr (dropStr v 1) 1
  else if v.startsWith "'" && v.endsWith "'" && v.length ≥ 2 then
    dropEndStr (dropStr v 1) 1
  else v

/-- Value after the first `=` on a TOML assignment line. -/
private def tomlValue (line : String) : Option String :=
  match line.splitOn "=" with
  | _ :: rest =>
    if rest.isEmpty then none
    else some (unquoteToml (String.intercalate "=" rest))
  | _ => none

/-- Minimal `pf.toml` reader: collect `[[program]]` tables with `name` / `module`. -/
private def parsePfTomlPrograms (text : String) : Array BuildUnit := Id.run do
  let mut units : Array BuildUnit := #[]
  let mut inProgram := false
  let mut curName : Option String := none
  let mut curModule : Option String := none
  let flush (units : Array BuildUnit) (curName : Option String) (curModule : Option String) :=
    match curModule with
    | some m =>
      let n := curName.getD (basenameOfModule m)
      units.push { name := n, module := dottedToName m }
    | none => units
  for line0 in text.splitOn "\n" do
    let line := trimStr line0
    if line.isEmpty || line.startsWith "#" then
      pure ()
    else if line == "[[program]]" then
      if inProgram then
        units := flush units curName curModule
      inProgram := true
      curName := none
      curModule := none
    else if inProgram then
      if line.startsWith "name" then
        match tomlValue line with
        | some v => curName := some v
        | none => pure ()
      else if line.startsWith "module" then
        match tomlValue line with
        | some v => curModule := some v
        | none => pure ()
      else if line.startsWith "[" then
        units := flush units curName curModule
        inProgram := false
        curName := none
        curModule := none
  if inProgram then
    units := flush units curName curModule
  units

private def loadPfTomlUnits : IO (Array BuildUnit) := do
  let path : System.FilePath := "pf.toml"
  if !(← path.pathExists) then
    return #[]
  let text ← IO.FS.readFile path
  return parsePfTomlPrograms text

private def resolveUnits (opts : Options)
    (selectNames : Array String → Except String (Array String))
    (tomlUnits : Array BuildUnit) :
    Except String (Array BuildUnit) := do
  if !opts.modules.isEmpty then
    pure <| opts.modules.map fun m =>
      { name := basenameOfModule m, module := dottedToName m }
  else if !opts.names.isEmpty then
    let names ← selectNames opts.names
    pure <| names.map fun n => { name := n, module := fixtureModule n }
  else if !tomlUnits.isEmpty then
    pure tomlUnits
  else
    let names ← selectNames #[]
    pure <| names.map fun n => { name := n, module := fixtureModule n }

private def isExamplesModule : Lean.Name → Bool
  | .str .anonymous "Examples" => true
  | .str pref _ => isExamplesModule pref
  | _ => false

/--
CLI builds must re-extract IR from user modules; never assemble legacy Golden smoke fixtures.
The registry only lists buildable modules and pins canonical digests for Examples fixtures.
-/
private unsafe def extractEvmPrograms (units : Array BuildUnit) :
    IO (Except String (Array ProofForge.Evm.IR.Program)) :=
  try
    Lean.initSearchPath (← Lean.findSysroot)
    -- `lake env pf build` exports LEAN_PATH with every workspace package's
    -- build dir. Lean's import lookup short-circuits on the first entry whose
    -- module-root *directory* exists (`SearchPath.findWithExt`), so a package
    -- dir that owns sibling modules shadows a later entry that owns the
    -- exact module (e.g. `ProofForge/Attr.olean` only in proofforge-common).
    -- Resolve the transitive import closure ourselves, file-existence first,
    -- and reduce the search path to the dirs that actually supply modules.
    let envDirs : Array System.FilePath ← do
      let mut acc : Array System.FilePath := #[]
      if let some sp := ← IO.getEnv "LEAN_PATH" then
        for p in sp.splitOn ":" do
          if p.isEmpty then continue
          try acc := acc.push (← IO.FS.realPath p) catch _ => pure ()
      pure acc
    let allDirs : List System.FilePath :=
      (← Lean.searchPathRef.get) ++ envDirs.toList
    let mut visited : Std.HashSet Lean.Name := {}
    let mut queue : Array Lean.Name := units.map (·.module)
    let mut missing : Array Lean.Name := #[]
    -- Resolved artifacts: module -> (olean, ilean) real paths.
    let mut artifacts : Array (Lean.Name × System.FilePath × System.FilePath) := #[]
    repeat
      if queue.isEmpty then break
      let mod := queue[0]!
      queue := queue.drop 1
      if visited.contains mod then continue
      visited := visited.insert mod
      let mut found : Option System.FilePath := none
      for dir in allDirs do
        let olean := Lean.modToFilePath dir mod "olean"
        if ← olean.pathExists then
          found := some olean
          break
      match found with
      | none => missing := missing.push mod
      | some olean =>
        artifacts := artifacts.push (mod, olean, olean.withExtension "ilean")
        -- Walk the closure via the ilean's `directImports` (present for every
        let ilean := olean.withExtension "ilean"
        try
          let contents ← IO.FS.readFile ilean
          match Lean.Json.parse contents with
          | .error _ => pure ()
          | .ok json =>
            match json.getObjVal? "directImports" with
            | .error _ => pure ()
            | .ok imports =>
              let entries : Array Lean.Json :=
                match imports.getArr? with
                | .ok arr => arr
                | .error _ => #[]
              for entry in entries do
                let first? : Option Lean.Json :=
                  match entry.getArr? with
                  | .ok arr => arr[0]?
                  | .error _ => none
                match first? with
                | some (Lean.Json.str name) =>
                    queue := queue.push (name.toName)
                | _ => pure ()
        catch _ => pure ()
    if missing.isEmpty then
      -- Lean's import lookup (`SearchPath.findWithExt`) short-circuits on the
      -- first entry whose module-root *directory* exists, so a package dir
      -- that owns sibling modules shadows a later entry owning the exact
      -- module (e.g. `ProofForge/Evm/Emit.olean` only in this repo while
      -- `ProofForge/` exists in proofforge-common's build dir).
      -- Materialize a merged view in a private temp dir, but ONLY for the
      -- shadowed gaps: a module needs a copy iff the first search dir owning
      -- its root segment (`ProofForge/`, `Examples/`, …) lacks its olean.
      -- Copying the full closure (incl. the toolchain's Init/Std tree) filled
      -- CI runners' tmpfs with GBs of duplicates (error 28).
      let mergeDir : System.FilePath :=
        ((← IO.getEnv "XDG_RUNTIME_DIR") |>.getD ((← IO.getEnv "TMPDIR") |>.getD "/tmp"))
          / "pf-lean-path"
      -- A root segment (e.g. `ProofForge`) is "split" when the closure contains
      -- modules of that root that the FIRST search dir owning the root does not
      -- supply. For every split root, copy ALL closure modules of the root into
      -- the merged view (mergeDir/R itself shadows the owner dirs, so a partial
      -- copy would fail the remaining lookups). Unsplit roots (Init/Std, and
      -- `Examples` whose modules all live in this repo) resolve unaided.
      let mut splitRoots : Std.HashSet String := {}
      for (mod, _, _) in artifacts do
        let rootDirName := mod.getRoot.toString
        let mut naiveDir? : Option System.FilePath := none
        for dir in allDirs do
          if ← (dir / rootDirName).pathExists then
            naiveDir? := some dir
            break
        match naiveDir? with
        | none => pure ()
        | some naiveDir =>
            let naiveOlean := Lean.modToFilePath naiveDir mod "olean"
            if !(← naiveOlean.pathExists) then
              splitRoots := splitRoots.insert rootDirName
      let gaps := artifacts.filter fun (mod, _, _) =>
        splitRoots.contains mod.getRoot.toString
      -- Stale artifacts from earlier runs (possibly built against a different
      -- dependency revision) must not mix with the current closure.
      try IO.FS.removeDirAll mergeDir catch _ => pure ()
      for (mod, olean, ilean) in gaps do
        let dst := Lean.modToFilePath mergeDir mod "olean"
        if !(← dst.parent.get!.pathExists) then
          IO.FS.createDirAll dst.parent.get!
        IO.FS.writeBinFile dst (← IO.FS.readBinFile olean)
        let ileanDst := System.FilePath.withExtension dst "ilean"
        IO.FS.writeBinFile ileanDst (← IO.FS.readBinFile ilean)
        -- Opportunistic olean parts (server / private level data) and IR data
        -- must come along or finalizeImport fails with `missing ... data file`.
        for part in ["olean.private", "olean.server", "ir"] do
          let srcPart := System.FilePath.withExtension olean part
          if ← srcPart.pathExists then
            IO.FS.writeBinFile (System.FilePath.withExtension dst part)
              (← IO.FS.readBinFile srcPart)
      Lean.searchPathRef.set (mergeDir :: allDirs)
    else
      -- Closure incomplete: keep the plain LEAN_PATH order and let Lean
      -- report the original resolution error.
      Lean.searchPathRef.set allDirs
    let modules := units.map fun u => ({ module := u.module } : Lean.Import)
    Lean.enableInitializersExecution
    let env ← Lean.importModules modules {} (loadExts := true)
    let mut errors : Array String := #[]
    let mut programs : Array ProofForge.Evm.IR.Program := #[]
    for u in units do
      match Extract.extractModuleIR env u.module none >>= Evm.IR.fromExtracted with
      | .error reason =>
        errors := errors.push s!"{u.name}: {reason}"
      | .ok program =>
        if !isExamplesModule u.module then
          programs := programs.push program
        else
          let digest := Evm.IR.digestHex program
          match Evm.Registry.digestOf u.name with
          | some expected =>
            if digest == expected then
              programs := programs.push program
            else
              errors := errors.push
                s!"{u.name}: ir/mismatch: extracted evm digest {digest} != fixture {expected}"
          | none =>
            programs := programs.push program
    if errors.isEmpty then
      return .ok programs
    else
      return .error (String.intercalate "\n" errors.toList)
  catch e =>
    return .error s!"source import failed: {e}"

private def pfVersion : String := "0.1.0"

private def runInit (opts : Options) : IO UInt32 := do
  if opts.initName.isEmpty then
    IO.eprintln "pf: init wants a project name"
    return 1
  let dst : System.FilePath := opts.initName
  if ← dst.pathExists then
    IO.eprintln s!"pf: refusing to overwrite {dst}"
    return 1
  let src : System.FilePath := "templates/evm-counter"
  if !(← src.pathExists) then
    IO.eprintln s!"pf: template missing at {src} (run from the ProofForge EVM checkout)"
    return 1
  let proc ← IO.Process.output { cmd := "cp", args := #["-R", toString src, toString dst] }
  if proc.exitCode != 0 then
    IO.eprintln s!"pf: cp failed\n{proc.stderr}"
    return 1
  -- Sibling of the checkout → `from ".."`. Otherwise the absolute path to this
  -- checkout so `pf init /tmp/demo` still resolves the SDK. The published
  -- template require is a git tag. Rewrite it to a path so CI can init before
  -- the tag exists.
  let lakefile := dst / "lakefile.lean"
  if ← lakefile.pathExists then
    let repoRoot ← IO.currentDir
    let dstAbs ←
      try
        IO.FS.realPath dst
      catch _ =>
        pure (repoRoot / dst)
    let parentAbs ←
      match dstAbs.parent with
      | some p =>
        try IO.FS.realPath p catch _ => pure p
      | none => pure dstAbs
    let requireFrom :=
      if parentAbs == repoRoot then ".."
      else repoRoot.toString
    let old ← IO.FS.readFile lakefile
    let pathRequire := s!"require «proofforge» from \"{requireFrom}\""
    let rewritten :=
      old.replace
        "require «proofforge» from git\n  \"https://github.com/DaviRain-Su/ProofForgeEvm.git\" @ \"v0.1.0\""
        pathRequire
        |>.replace "require «proofforge» from \"..\" / \"..\"" pathRequire
        |>.replace "require «proofforge» from \"../..\"" pathRequire
    IO.FS.writeFile lakefile rewritten
  IO.println s!"initialized {dst} (target=evm)"
  IO.println s!"next: cd {dst} && lake build && lake env pf build"
  IO.println s!"  (run `lake build pf` from the ProofForge EVM checkout; put `.lake/build/bin` on PATH)"
  return 0

private def toolLine (cmd : String) (args : Array String) (fallback : String) : IO String := do
  try
    let proc ← IO.Process.output { cmd := cmd, args := args }
    if proc.exitCode == 0 then
      let line := (trimStr proc.stdout).splitOn "\n" |>.headD (trimStr proc.stdout)
      return if line.isEmpty then fallback else line
    else
      return fallback
  catch _ =>
    return fallback

private def printVersion : IO Unit := do
  IO.println s!"pf {pfVersion} (ProofForge EVM)"
  IO.println s!"lean {Lean.versionString}"
  IO.println s!"solc {(← toolLine "solc" #["--version"] "0.8.34+commit.80d5c536 (pin; binary not on PATH)")}"
  IO.println "pins: lean v4.31.0; solc 0.8.34; foundry 1.7.1"

unsafe def run (args : List String) : IO UInt32 := do
  match parseArgs args with
  | .error reason =>
    IO.eprintln s!"pf: {reason}"
    IO.eprintln usage
    return 1
  | .ok opts =>
    if opts.help then
      IO.println usage
      return 0
    if opts.version then
      printVersion
      return 0
    match opts.command with
    | .init => return ← runInit opts
    | .build =>
    let tomlUnits ← loadPfTomlUnits
    match resolveUnits opts selectEvmNames tomlUnits with
    | .error reason =>
      IO.eprintln s!"pf: {reason}"
      return 1
    | .ok units =>
      match ← extractEvmPrograms units with
      | .error reason =>
        IO.eprintln s!"pf: {reason}"
        return 1
      | .ok programs =>
        IO.FS.createDirAll opts.outDir
        let backend ← match opts.evmBackend with
          | some b => pure b
          | none => ProofForge.Evm.Assemble.backendFromEnv
        for program in programs do
          let r ← ProofForge.Evm.Assemble.assembleProgramWithBackend opts.outDir program backend
          let backendName :=
            match r.backend with
            | .solc => "solc"
            | .yulc => "yulc"
          IO.println s!"wrote {r.binPath} {r.abiPath} ({r.binHex.length / 2} bytes, {backendName})"
        return 0

end ProofForge.Cli

unsafe def main (args : List String) : IO UInt32 :=
  ProofForge.Cli.run args
