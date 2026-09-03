import ProofForge

#guard
  ProofForge.Extract.Legacy.digestHex ProofForge.Golden.extractedFlag ==
    ProofForge.Extract.Legacy.digestHex ProofForge.Golden.extractedFlag

#guard
  ProofForge.Extract.Legacy.digestHex ProofForge.Golden.extractedFlag !=
    ProofForge.Extract.Legacy.digestHex ProofForge.Golden.extractedMaybe
