# ProofForge.Crypto

## Purpose

本机、kernel 可算的哈希。不是链上 opcode，也不属于某一条链。

## Boundary

| 模块 | 拥有 | 不拥有 |
|---|---|---|
| `Crypto.Sha256` | FIPS 180-4 SHA-256；`digestBytes` / `digestHex` / `first8Le` / `first8Be` | 链上 opcode |
| `Crypto.Keccak` | Ethereum Keccak-256（domain `0x01`）；ABI `selector` / `signature` | 链上 opcode |

`ProofForge.Crypto.Sha256Compat` 中的 `ProofForge.Sha256` 和
`ProofForge.Evm.Keccak` 只是旧名转发。新代码应
`import ProofForge.Crypto.Sha256` / `ProofForge.Crypto.Keccak`。

## Tests

`Tests/Sha256Spec.lean` 的空串 / `abc`；`Tests/EvmSpec.lean` 的空串 Keccak 与
`increment` / `get` selector 夹具。
