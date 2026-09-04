namespace ProofForge.Evm.Registry

/-- Source program registered for EVM builds and its canonical target-IR digest. -/
structure Entry where
  name : String
  digest : String
  deriving BEq, Repr, Inhabited

def entries : Array Entry := #[
  { name := "Counter", digest := "254202356ee921d6" },
  { name := "TokenShape", digest := "2517523f63989d26" },
  { name := "Pair", digest := "8a6b6ee40b8ade46" },
  { name := "Window", digest := "966cbad710c7eff1" },
  { name := "Phase", digest := "bed1d2111e652ac1" },
  { name := "Flag", digest := "6056d4920876b4f7" },
  { name := "Maybe", digest := "6b602a44477483ee" },
  { name := "EvmCtx", digest := "b4a1d16740330566" },
  { name := "EvmBounded", digest := "51a043bef939cbd7" },
  { name := "EvmExceptErgonomics", digest := "8def48aa72cd2c19" },
  { name := "EvmTokenErgonomics", digest := "138c08a82e1ad205" },
  { name := "EvmSearch", digest := "1b6e78b520b5030d" },
  { name := "EvmFindIndex", digest := "18f1ba6730bc0351" },
  { name := "EvmStaticCounter", digest := "6225c3939859e297" },
  { name := "EvmStaticRoster", digest := "a87e8840e3904357" },
  { name := "EvmCrew", digest := "223f5a54a8d54ae4" },
  { name := "EvmQuota", digest := "e414f3a5e7b949f8" },
  { name := "EvmAggregateStorage", digest := "f66d438ad668929d" },
  { name := "EvmOrderedStorage", digest := "c37f9c0a33352f4" },
  { name := "EvmVecLog", digest := "bea39a52948599c0" },
  { name := "EvmVecStack", digest := "8903e992dacdb808" },
  { name := "GuardedPayout", digest := "359f6025f96aa432" },
  { name := "ArtLink", digest := "e95d5b45be20b193" },
  { name := "PackLink", digest := "58b4fe91408c541e" },
  { name := "DomainLink", digest := "52e88ad42d5a8789" },
  { name := "OwnerLink", digest := "9d2521b3536b3df6" },
  { name := "ClockLink", digest := "6aaaa4e3809c1df5" },
  { name := "RecoverLink", digest := "c3097c1dfd4fd261" },
  { name := "VestLink", digest := "b3e15e6ff33fddec" },
  { name := "ProofLink", digest := "c41e5e834c987462" },
  { name := "HeaderLink", digest := "8c4a049ef323d412" },
  { name := "AdminDelayLink", digest := "376071c5220a95b7" },
  { name := "MetaGateLink", digest := "b7a3eb3bad62bb7" },
  { name := "Auth3009Link", digest := "c0188e81405c51f5" },
  { name := "AuditLink", digest := "d5cb688dcc4d25ae" },
  { name := "Vault4626Link", digest := "bfdf7768e0161aad" },
  { name := "NineLink", digest := "b111fab5448214f" },
  { name := "Collectible", digest := "4bd851369a01366d" },
  { name := "Badge", digest := "78a916b0b209aa21" },
  { name := "TipJar", digest := "33bcabf27f5b9523" },
  { name := "Lang", digest := "d2a43e6bf208bff0" },
  { name := "Vault", digest := "bb2f93cb28d7501" },
  { name := "Ownable", digest := "2dc1afccaffe17c4" },
  { name := "Token", digest := "e25dfb4e1eaa54c" },
  { name := "Erc20Meta", digest := "9e1221ef24a9c091" },
  { name := "SafePay", digest := "3971d7ce6eb18141" },
  { name := "RoyaltyArt", digest := "89fe67825f5f9c28" },
  { name := "Capped", digest := "b0b0b7244ebb8aed" },
  { name := "MultiToken", digest := "ed7b0806a745732d" },
  { name := "CraftToken", digest := "498e28455f1c4cb7" },
  { name := "TwoStepCounter", digest := "9e20eb417583ce6e" },
  { name := "Credits", digest := "c2ceddddbf415d40" },
  { name := "Wide", digest := "a190f187d58d188e" },
  { name := "Const", digest := "81830f8855cd3dda" },
  { name := "EvmFeatureFlags", digest := "5cc9bb266f23487f" },
  { name := "EvmClaimBitmap", digest := "d91809979ad94cdc" },
  { name := "EvmRingMailbox", digest := "5f2a66d9732449cd" },
  { name := "EvmRingHistory", digest := "51b492f52021f6ec" },
  { name := "EvmAllowlist", digest := "5398786232c20c14" },
  { name := "EvmIdRegistry", digest := "92520ed7aaa372d0" },
  { name := "EvmConfigMap", digest := "6bcde246def26437" },
  { name := "EvmScoreMap", digest := "2f0fb0f0f9dd7663" },
  { name := "EvmCheckpointBook", digest := "ba538445e3647f45" },
  { name := "EvmCheckpointTrace", digest := "904229061bdc4a3e" },
  { name := "EvmSafeCastAccumulator", digest := "f9eb0bacf4d40cfd" },
  { name := "EvmSafeCastConfig", digest := "40d1569adcdc05a6" },
  { name := "EvmPriceBand", digest := "a7015ac3e2e471ad" },
  { name := "EvmTypedErrors", digest := "499001a31fb4d9e7" },
  { name := "EvmTypedEvents", digest := "90bd573ddf9e2e49" },
  { name := "EvmChainGuard", digest := "ebef98a36a4b1cc5" },
  { name := "EvmOpenCall", digest := "9fe4427d5b5d3114" }
]

def names : Array String := entries.map (·.name)

def digestOf (name : String) : Option String :=
  (entries.find? (·.name == name)).map (·.digest)

end ProofForge.Evm.Registry
