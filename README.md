# Blockchain Voting System

A nationwide election simulation dApp built on SKALE, modeling the full Philippine local-government hierarchy — Province → District → City/Municipality → Barangay — with soulbound (non-transferable) NFT vote receipts and two independent voting rounds.

> **⚠️ Disclaimer:** This is an educational / portfolio project built and deployed on a public **testnet**. It is **not affiliated with, endorsed by, or connected to COMELEC** or any government body, and is not intended for use in real elections. Voter eligibility is currently self-declared and unverified — see [Known Limitations](#known-limitations) below.

## Features

- **Full geographic hierarchy**: Province → District → City/Municipality → Barangay, each level requiring its parent to exist first.
- **Two independent voting rounds**: `NATIONAL_LOCAL` (President through City Councilor) and `BARANGAY` (Captain + Kagawad), matching how Philippine elections actually separate barangay elections from national/local ones. A voter can complete either round independently, in any order.
- **Partial voting supported**: voters aren't required to vote for every position — e.g. voting for President only and submitting is valid.
- **Soulbound vote receipts**: each cast ballot mints a non-transferable ERC721 token carrying a public, per-round sequential ballot number, letting anyone cross-check that the sum of a race's candidate tallies is consistent with the total ballots cast in that round — without revealing who anyone voted for.
- **Bulk data tools**: batch-add functions for geography and candidates (chunked, capped per call) to support loading real nationwide-scale data without one transaction per entry.
- **MetaMask wallet integration** with automatic SKALE Base Sepolia network detection/switching.
- **Faucet shortcut** to the official SKALE Base Sepolia CREDIT faucet.

## Tech Stack

- **Smart contract**: Solidity ^0.8.20, OpenZeppelin Contracts (pinned to 5.0.2 — see [Deployment Notes](#deployment-notes)), deployed on [SKALE Base Sepolia](https://base-sepolia-testnet-explorer.skalenodes.com/)
- **Frontend**: React + TypeScript (Vite), ethers.js v6, shadcn/ui, lucide-react
- **Wallet**: MetaMask (`window.ethereum` + ethers `BrowserProvider`)

## Getting Started

```bash
npm install
cp .env.example .env   # fill in your values
npm run dev
```

### Environment variables

| Variable | Description |
|---|---|
| `VITE_CONTRACT_ADDRESS` | Deployed contract address on SKALE Base Sepolia |

## Deployment Notes

If you're redeploying the contract yourself, two settings matter more than they look:

1. **Compiler**: Solidity 0.8.24, optimizer enabled with `runs: 200`, `viaIR: false`, default EVM version. Aggressive size optimization (`runs: 1` + `viaIR: true`) previously caused silent, hard-to-diagnose failures in functions returning dynamic arrays of structs.
2. **OpenZeppelin version pin**: imports are pinned to `@openzeppelin/contracts@5.0.2`. Later 5.x versions rely on the `MCOPY` opcode (Cancun hardfork), which SKALE's EVM doesn't fully support — this silently breaks any function that copies a `string` into memory.

Always verify a fresh deployment with a raw `eth_call` before wiring up the frontend against it (see project history / commit notes for the exact verification snippet used during development).

## Known Limitations

- **No real voter-eligibility verification.** Anyone with a wallet can currently vote; there's no connection to any real voter registry. A Merkle-proof-based verification design (voter list hashed off-chain, only the root published on-chain) was scoped but not implemented in this version.
- **Single-owner admin key**, no timelock or multisig — the owner wallet has full control over geography, candidates, and round open/close state.
- **No cross-country search.** Navigation is cascading-selection only (pick your province, then district, then city, then barangay); there's no full-text search across all ~42,000 barangays, since that would require an off-chain search index.
- **Duplicate-position protection, not duplicate-registration protection.** The contract stops one ballot from voting twice in the same race, but can't verify a wallet belongs to a unique real person.

## License

MIT — see [LICENSE](./LICENSE).
