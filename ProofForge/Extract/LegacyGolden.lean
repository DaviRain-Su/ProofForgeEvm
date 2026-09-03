import ProofForge.Extract.LegacyIR
import ProofForge.Extract.LegacyOps

/-! Hand-authored fixtures for the legacy mixed extraction IR. -/
namespace ProofForge.Golden

open ProofForge.Extract.Legacy
open ProofForge.Ops

def extractedCounter : Program :=
  { name := "Counter"
    slots := #[{ name := "value" }]
    methods := #[
      { kind := .init, name := "Examples.Counter.init", ixName := "initialize", paramCount := 1
        ops := #[.returnState (.arg 0)] },
      { kind := .increment, name := "Examples.Counter.increment", ixName := "increment", paramCount := 1
        ops := #[
          .checkedAddU64 (.field (.arg 1) "value") (.arg 0),
          .okState (.field (.arg 1) "value"),
          .errorOverflow
        ] },
      { kind := .increment, name := "Examples.Counter.decrement", ixName := "decrement", paramCount := 1
        ops := #[
          .checkedSubU64 (.field (.arg 1) "value") (.arg 0),
          .okState (.field (.arg 1) "value"),
          .errorOverflow
        ] },
      { kind := .get, name := "Examples.Counter.get", ixName := "get", paramCount := 0
        ops := #[.returnU64 (.field (.arg 0) "value")] },
      { kind := .increment, name := "Examples.Counter.scale", ixName := "scale", paramCount := 1
        ops := #[
          .ite .eq (.arg 0) (.lit 0)
            #[.okState (.lit 0)]
            #[.checkedMulU64 (.field (.arg 1) "value") (.arg 0), .okState (.field (.arg 1) "value"), .errorOverflow]
        ] },
      { kind := .increment, name := "Examples.Counter.divide", ixName := "divide", paramCount := 1
        ops := #[.checkedDivU64 (.field (.arg 1) "value") (.arg 0), .okState (.arg 0), .errorOverflow] },
      { kind := .increment, name := "Examples.Counter.modulo", ixName := "modulo", paramCount := 1
        ops := #[.checkedModU64 (.field (.arg 1) "value") (.arg 0), .okState (.arg 0), .errorOverflow] },
      { kind := .get, name := "Examples.Counter.nonzero", ixName := "nonzero", paramCount := 0
        ops := #[
          .ite .eq (.field (.arg 0) "value") (.lit 0)
            #[.returnU64 (.lit 1)]
            #[.returnU64 (.lit 0)]
        ] }
    ] }

def extractedPair : Program :=
  { name := "Pair"
    slots := #[{ name := "left" }, { name := "right" }]
    methods := #[
      { kind := .init, name := "Examples.Pair.init", ixName := "initialize", paramCount := 1
        ops := #[.returnState (.arg 0)] },
      { kind := .init, name := "Examples.Pair.initBoth", ixName := "initBoth", paramCount := 2
        ops := #[.returnState (.arg 0), .returnState (.arg 1)] },
      { kind := .increment, name := "Examples.Pair.creditLeft", ixName := "creditLeft", paramCount := 1
        ops := #[
          .checkedAddU64 (.field (.arg 1) "left") (.arg 0),
          .okState (.field (.arg 1) "left"),
          .errorOverflow
        ] },
      { kind := .get, name := "Examples.Pair.getLeft", ixName := "getLeft", paramCount := 0
        ops := #[.returnU64 (.field (.arg 0) "left")] },
      { kind := .get, name := "Examples.Pair.getRight", ixName := "getRight", paramCount := 0
        ops := #[.returnU64 (.field (.arg 0) "right")] }
    ] }

def extractedFlag : Program :=
  { name := "Flag"
    slots := #[{ name := "flag", width := 1, abi := "u8-le" }, { name := "count" }]
    methods := #[
      { kind := .init, name := "Examples.Flag.init", ixName := "initialize", paramCount := 1
        ops := #[.returnState (.lit 0), .returnState (.arg 0)] },
      { kind := .increment, name := "Examples.Flag.setFlag", ixName := "setFlag", paramCount := 1
        ops := #[
          .ite .le (.arg 0) (.lit 255)
            #[.okState (.field (.arg 1) "count")]
            #[.errorOverflow]
        ] },
      { kind := .get, name := "Examples.Flag.getFlag", ixName := "getFlag", paramCount := 0
        ops := #[.returnU64 (.field (.arg 0) "flag")] }
    ] }

def extractedPhase : Program :=
  { name := "Phase"
    slots := #[{ name := "mode" }]
    methods := #[
      { kind := .init, name := "Examples.Phase.init", ixName := "initialize", paramCount := 1
        ops := #[.returnState (.lit 0)] },
      { kind := .increment, name := "Examples.Phase.setIdle", ixName := "setIdle", paramCount := 0
        ops := #[
          .ite .ne (.lit 0) (.lit 1)
            #[.okState (.lit 0)]
            #[.errorOverflow]
        ] },
      { kind := .increment, name := "Examples.Phase.setLive", ixName := "setLive", paramCount := 1
        ops := #[
          .ite .le (.arg 0) (.lit (~~~(0 : UInt64)))
            #[.okState (.lit 1)]
            #[.errorOverflow]
        ] },
      { kind := .get, name := "Examples.Phase.isLive", ixName := "isLive", paramCount := 0
        ops := #[
          .ite .eq (.field (.arg 0) "mode") (.lit 1)
            #[.returnU64 (.lit 1)]
            #[.returnU64 (.lit 0)]
        ] }
    ] }

def extractedWindow : Program :=
  { name := "Window"
    slots := #[{ name := "cells_0" }, { name := "cells_1" }]
    methods := #[
      { kind := .init, name := "Examples.Window.init", ixName := "initialize", paramCount := 1
        ops := #[.returnState (.arg 0), .returnState (.lit 0)] },
      { kind := .increment, name := "Examples.Window.setTail", ixName := "setTail", paramCount := 1
        ops := #[
          .ite .le (.arg 0) (.lit (~~~(0 : UInt64)))
            #[.storeField "cells_1" (.arg 0), .okState (.arg 0)]
            #[.errorOverflow]
        ] },
      { kind := .get, name := "Examples.Window.getHead", ixName := "getHead", paramCount := 0
        ops := #[.returnU64 (.field (.arg 0) "cells_0")] }
    ] }

def extractedMaybe : Program :=
  { name := "Maybe"
    slots := #[{ name := "slot_tag" }, { name := "slot_p0" }]
    methods := #[
      { kind := .init, name := "Examples.Maybe.init", ixName := "initialize", paramCount := 1
        ops := #[.returnState (.lit 0), .returnState (.lit 0)] },
      { kind := .increment, name := "Examples.Maybe.setNone", ixName := "setNone", paramCount := 0
        ops := #[
          .ite .ne (.lit 0) (.lit 1)
            #[.storeField "slot_tag" (.lit 0), .storeField "slot_p0" (.lit 0),
              .okState (.lit 0)]
            #[.errorOverflow]
        ] },
      { kind := .increment, name := "Examples.Maybe.setSome", ixName := "setSome", paramCount := 1
        ops := #[
          .ite .le (.arg 0) (.lit (~~~(0 : UInt64)))
            #[.storeField "slot_tag" (.lit 1), .storeField "slot_p0" (.arg 0),
              .okState (.arg 0)]
            #[.errorOverflow]
        ] },
      { kind := .get, name := "Examples.Maybe.isSome", ixName := "isSome", paramCount := 0
        ops := #[
          .ite .eq (.field (.arg 0) "slot_tag") (.lit 1)
            #[.returnU64 (.lit 1)]
            #[.returnU64 (.lit 0)]
        ] },
      { kind := .get, name := "Examples.Maybe.getValue", ixName := "getValue", paramCount := 0
        ops := #[
          .ite .eq (.field (.arg 0) "slot_tag") (.lit 0)
            #[.returnU64 (.lit 0)]
            #[.returnU64 (.field (.arg 0) "slot_p0")]
        ] }
    ] }

def extractedEvmCtx : Program :=
  { name := "EvmCtx"
    slots := #[{ name := "dummy" }]
    methods := #[
      { kind := .init, name := "Examples.Evm.EvmCtx.init", ixName := "initialize", paramCount := 1
        ops := #[.returnState (.lit 0)] },
      { kind := .increment, name := "Examples.Evm.EvmCtx.stamp", ixName := "stamp", paramCount := 0
        ops := #[
          .ite .ne (.lit 0) (.lit 1)
            #[.okState .evmBlockNumber]
            #[.errorOverflow]
        ] },
      { kind := .get, name := "Examples.Evm.EvmCtx.caller", ixName := "caller", paramCount := 0
        ops := #[.returnU64 .evmCaller] },
      { kind := .get, name := "Examples.Evm.EvmCtx.height", ixName := "height", paramCount := 0
        ops := #[.returnU64 .evmBlockNumber] },
      { kind := .get, name := "Examples.Evm.EvmCtx.get", ixName := "get", paramCount := 0
        ops := #[.returnU64 (.field (.arg 0) "dummy")] }
    ] }

def extractedLang : Program :=
  { name := "Lang"
    slots := #[
      { name := "cells_0" }, { name := "cells_1" },
      { name := "cells_2" }, { name := "cells_3" }
    ]
    methods := #[
      { kind := .init, name := "Examples.Lang.init", ixName := "initialize", paramCount := 1
        ops := #[.returnState (.arg 0)] },
      { kind := .increment, name := "Examples.Lang.setAt", ixName := "setAt", paramCount := 2
        ops := #[
          .ite .lt (.arg 0) (.lit 4)
            #[.indexSet "cells" (.arg 0) (.arg 1) 4, .okState (.arg 1)]
            #[.errorNamed "oob"]
        ] },
      { kind := .get, name := "Examples.Lang.band", ixName := "band", paramCount := 2
        ops := #[.returnU64 (.bitAnd (.arg 0) (.arg 1))] },
      { kind := .get, name := "Examples.Lang.bor", ixName := "bor", paramCount := 2
        ops := #[.returnU64 (.bitOr (.arg 0) (.arg 1))] },
      { kind := .get, name := "Examples.Lang.both", ixName := "both", paramCount := 0
        retCount := 2
        ops := #[
          .returnU64 (.field (.arg 0) "cells_0"),
          .returnU64 (.field (.arg 0) "cells_1")
        ] },
      { kind := .get, name := "Examples.Lang.bnot", ixName := "bnot", paramCount := 1
        ops := #[.returnU64 (.bitNot (.arg 0))] },
      { kind := .get, name := "Examples.Lang.bxor", ixName := "bxor", paramCount := 2
        ops := #[.returnU64 (.bitXor (.arg 0) (.arg 1))] },
      { kind := .get, name := "Examples.Lang.get", ixName := "get", paramCount := 0
        ops := #[.returnU64 (.field (.arg 0) "cells_0")] },
      { kind := .get, name := "Examples.Lang.getAt", ixName := "getAt", paramCount := 1
        ops := #[
          .ite .lt (.arg 0) (.lit 4)
            #[.returnU64 (.indexGet (.arg 1) "cells" (.arg 0) 0)]
            #[.returnU64 (.lit 0)]
        ] },
      { kind := .get, name := "Examples.Lang.mask8", ixName := "mask8", paramCount := 1
        paramWidths := #[1]
        ops := #[.returnU64 (.arg 0)] },
      { kind := .get, name := "Examples.Lang.shl", ixName := "shl", paramCount := 2
        ops := #[.returnU64 (.shiftL (.arg 0) (.arg 1))] },
      { kind := .get, name := "Examples.Lang.shr", ixName := "shr", paramCount := 2
        ops := #[.returnU64 (.shiftR (.arg 0) (.arg 1))] },
      { kind := .get, name := "Examples.Lang.sum4", ixName := "sum4", paramCount := 0
        ops := #[
          .forAccum 4 (.indexGet (.arg 0) "cells" .loopIx 0) 0,
          .returnU64 (.local 0)
        ] }
    ] }

def programs : Array Program := #[
  extractedCounter, extractedPair, extractedFlag, extractedPhase, extractedWindow,
  extractedMaybe, extractedEvmCtx, extractedLang
]

/--
`#pf_build` 抽出的 digest 必须钉住。Phoenix 的 bounded-fold IR 和 Tree 的动态
allocator / insertion IR 直接钉 canonical digest；对应手写 fixture 继续作为布局/发射 smoke。
-/
def digestOf (name : String) : Option String :=
  if name == "Phoenix" then some "3a4652b6083de283"
  else if name == "Tree" then some "7ebaf60f7fcfb337"
  else (programs.find? (·.name == name)).map digestHex

end ProofForge.Golden
