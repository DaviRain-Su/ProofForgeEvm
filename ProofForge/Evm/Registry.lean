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
  { name := "EvmStaticRoster", digest := "13617c85ae8d2231" },
  { name := "EvmCrew", digest := "223f5a54a8d54ae4" },
  { name := "EvmQuota", digest := "e414f3a5e7b949f8" },
  { name := "EvmAggregateStorage", digest := "bdaa6220cc10b84f" },
  { name := "EvmOrderedStorage", digest := "c37f9c0a33352f4" },
  { name := "EvmVecLog", digest := "173b1bf58cda76b3" },
  { name := "EvmVecStack", digest := "8903e992dacdb808" },
  { name := "GuardedPayout", digest := "359f6025f96aa432" },
  { name := "ArtLink", digest := "8a9ae8e161265c03" },
  { name := "PackLink", digest := "58b4fe91408c541e" },
  { name := "DomainLink", digest := "52e88ad42d5a8789" },
  { name := "OwnerLink", digest := "9d2521b3536b3df6" },
  { name := "ClockLink", digest := "6aaaa4e3809c1df5" },
  { name := "RecoverLink", digest := "c3097c1dfd4fd261" },
  { name := "SignerLink", digest := "e3d539121ce1e0d8" },
  { name := "ReceiverLink", digest := "9457ca840a166ba3" },
  { name := "DroppedLetLink", digest := "59b5fa7e28c2695" },
  { name := "VestLink", digest := "4d4f50a585db704d" },
  { name := "Vest20Link", digest := "daab53b9a3e785ac" },
  { name := "ProofLink", digest := "c41e5e834c987462" },
  { name := "HeaderLink", digest := "8c4a049ef323d412" },
  { name := "AdminDelayLink", digest := "200dd10d949030a7" },
  { name := "MetaGateLink", digest := "b7a3eb3bad62bb7" },
  { name := "Auth3009Link", digest := "aa7369d7796f83fc" },
  { name := "AuditLink", digest := "ad40c48e855ad5ef" },
  { name := "Vault4626Link", digest := "7b6ba7c4df14c6f7" },
  { name := "NineLink", digest := "62828ef440d0ecdb" },
  { name := "Collectible", digest := "19250482fbd80a03" },
  { name := "Gallery", digest := "9fdfc61d00414718" },
  { name := "Badge", digest := "bdb4d1d1a4e9baa7" },
  { name := "TipJar", digest := "33bcabf27f5b9523" },
  { name := "Lang", digest := "2e4474516ac72500" },
  { name := "Vault", digest := "bb2f93cb28d7501" },
  { name := "Ownable", digest := "86d62e4974bfb6fd" },
  { name := "Token", digest := "e25dfb4e1eaa54c" },
  { name := "Erc20Meta", digest := "3dfa816778bd3ef6" },
  { name := "SafePay", digest := "3971d7ce6eb18141" },
  { name := "RoyaltyArt", digest := "89fe67825f5f9c28" },
  { name := "Capped", digest := "b0b0b7244ebb8aed" },
  { name := "MultiToken", digest := "41d2adc0aff313ef" },
  { name := "CraftToken", digest := "2ba8b59633a3bd11" },
  { name := "TwoStepCounter", digest := "af949b4ad7572721" },
  { name := "Credits", digest := "38e5e3c91cadf3e6" },
  { name := "Wide", digest := "a190f187d58d188e" },
  { name := "Const", digest := "81830f8855cd3dda" },
  { name := "EvmFeatureFlags", digest := "69f5dfec989af858" },
  { name := "EvmClaimBitmap", digest := "d91809979ad94cdc" },
  { name := "EvmRingMailbox", digest := "2f008a994093209a" },
  { name := "EvmRingHistory", digest := "51b492f52021f6ec" },
  { name := "EvmAllowlist", digest := "970ab4ce80ebee80" },
  { name := "EvmIdRegistry", digest := "92520ed7aaa372d0" },
  { name := "EvmConfigMap", digest := "1d79e81070ea266d" },
  { name := "EvmScoreMap", digest := "2f0fb0f0f9dd7663" },
  { name := "EvmCheckpointBook", digest := "86923ed0c8147e06" },
  { name := "EvmCheckpointTrace", digest := "904229061bdc4a3e" },
  { name := "EvmSafeCastAccumulator", digest := "f9eb0bacf4d40cfd" },
  { name := "EvmSafeCastConfig", digest := "f8b5f1fb8ddc7dce" },
  { name := "EvmPriceBand", digest := "a7015ac3e2e471ad" },
  { name := "EvmTypedErrors", digest := "499001a31fb4d9e7" },
  { name := "EvmTypedEvents", digest := "90bd573ddf9e2e49" },
  { name := "EvmChainGuard", digest := "ebef98a36a4b1cc5" },
  { name := "EvmOpenCall", digest := "65230e506893f7c0" }
]

def names : Array String := entries.map (·.name)

def digestOf (name : String) : Option String :=
  (entries.find? (·.name == name)).map (·.digest)

end ProofForge.Evm.Registry
