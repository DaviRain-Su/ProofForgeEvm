namespace ProofForge.Evm.WideWord

/-- Typed unsigned packed-word relation. The legacy `ge256` query remains for artifact stability;
new source APIs use this enum instead of numeric operation tags. -/
inductive Comparison where
  | eq
  | lt
  | le
  | gt
  | ge
  deriving BEq, Repr, Inhabited

inductive Bitwise where
  | and
  | or
  | xor
  deriving BEq, Repr, Inhabited

inductive Shift where
  | left
  | right
  deriving BEq, Repr, Inhabited

inductive Division where
  | quotient
  | remainder
  deriving BEq, Repr, Inhabited

/-- Packed 256-bit compare, checked arithmetic/division, bitwise operations, and logical shifts.
These are value queries: they do not touch storage, logs, or CALL. Dynamic operands stay in
`Val.ext`. -/
inductive Query where
  /-- `a ≥ b` on packed 256-bit words. Eight operands: a0..a3, b0..b3. -/
  | ge256
  /-- Typed unsigned comparison on packed 256-bit words. Eight operands: a0..a3, b0..b3. -/
  | compare256 (comparison : Comparison)
  /-- Packed address equality. Six operands: a0..a2, b0..b2. -/
  | eq20
  /-- Canonical ABI `bytes4` equality. Two left-aligned EVM-word operands. -/
  | eqBytes4
  /-- Packed binary bitwise operation; `limb` is 0..3. Eight operands. -/
  | bitwise256 (operation : Bitwise) (limb : Nat)
  /-- Packed bitwise complement; `limb` is 0..3. Four operands. -/
  | not256 (limb : Nat)
  /-- Packed logical shift by one UInt64 amount; `limb` is 0..3. Five operands. -/
  | shift256 (direction : Shift) (limb : Nat)
  /-- Checked unsigned division or modulo; zero divisor reverts. Eight operands. -/
  | checkedDivMod256 (operation : Division) (limb : Nat)
  /-- Checked 256-bit `add`/`sub`/`mul`; `limb` is 0..3 (w0 lowest).
  `op` is 0 add, 1 sub, 2 mul. Eight operands: a0..a3, b0..b3. -/
  | arith256 (op : Nat) (limb : Nat)
  /-- Sorted commutative `keccak256` of two `bytes32` values; `limb` is 0..3 (w0 lowest). -/
  | keccak256Pair32 (limb : Nat)
  /-- Fold a length plus leaf and eight siblings, then compare with a root; 41 operands. -/
  | merkleVerify256
  /-- Exact equality of two `bytes32` values; eight operands: a0..a3, b0..b3. -/
  | eqBytes32
  deriving BEq, Repr, Inhabited

def Query.arity : Query → Nat
  | .ge256 | .compare256 _ | .bitwise256 _ _ | .checkedDivMod256 _ _ | .arith256 _ _
  | .keccak256Pair32 _ | .eqBytes32 => 8
  | .merkleVerify256 => 41
  | .not256 _ => 4
  | .shift256 _ _ => 5
  | .eq20 => 6
  | .eqBytes4 => 2

def Query.wellFormed : Query → Bool
  | .ge256 | .compare256 _ | .eq20 | .eqBytes4 => true
  | .bitwise256 _ limb | .not256 limb | .shift256 _ limb |
      .checkedDivMod256 _ limb => limb ≤ 3
  | .arith256 op limb => op ≤ 2 && limb ≤ 3
  | .keccak256Pair32 limb => limb ≤ 3
  | .merkleVerify256 | .eqBytes32 => true

private def renderOperands (renderValue : V → String) (operands : Array V) : String :=
  String.intercalate "," (operands.map renderValue).toList

/-- Preserve the closed-union digest spelling (`ext.{repr kind}(...)`). -/
def Query.canonical (renderValue : V → String) (operands : Array V) : Query → String
  | .ge256 =>
      s!"ext.ProofForge.Evm.Ops.ValKind.ge256({renderOperands renderValue operands})"
  | .compare256 comparison =>
      s!"ext.ProofForge.Evm.Ops.ValKind.compare256.{repr comparison}" ++
        s!"({renderOperands renderValue operands})"
  | .eq20 =>
      s!"ext.ProofForge.Evm.Ops.ValKind.eq20({renderOperands renderValue operands})"
  | .eqBytes4 =>
      s!"ext.ProofForge.Evm.Ops.ValKind.eqBytes4({renderOperands renderValue operands})"
  | .bitwise256 operation limb =>
      s!"ext.ProofForge.Evm.Ops.ValKind.bitwise256.{repr operation} {limb}" ++
        s!"({renderOperands renderValue operands})"
  | .not256 limb =>
      s!"ext.ProofForge.Evm.Ops.ValKind.not256 {limb}" ++
        s!"({renderOperands renderValue operands})"
  | .shift256 direction limb =>
      s!"ext.ProofForge.Evm.Ops.ValKind.shift256.{repr direction} {limb}" ++
        s!"({renderOperands renderValue operands})"
  | .checkedDivMod256 operation limb =>
      s!"ext.ProofForge.Evm.Ops.ValKind.checkedDivMod256.{repr operation} {limb}" ++
        s!"({renderOperands renderValue operands})"
  | .arith256 op limb =>
      s!"ext.ProofForge.Evm.Ops.ValKind.arith256 {op} {limb}" ++
        s!"({renderOperands renderValue operands})"
  | .keccak256Pair32 limb =>
      s!"ext.ProofForge.Evm.Ops.ValKind.keccak256Pair32 {limb}" ++
        s!"({renderOperands renderValue operands})"
  | .merkleVerify256 =>
      s!"ext.ProofForge.Evm.Ops.ValKind.merkleVerify256({renderOperands renderValue operands})"
  | .eqBytes32 =>
      s!"ext.ProofForge.Evm.Ops.ValKind.eqBytes32({renderOperands renderValue operands})"

end ProofForge.Evm.WideWord
