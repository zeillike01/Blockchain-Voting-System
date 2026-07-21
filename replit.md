# SoulboundVoting

A Philippine national election dApp on SKALE Base Sepolia — voters cast soulbound ballot NFTs across two independent rounds (National/Local and Barangay) with a full Province → District → City → Barangay geographic hierarchy.

## Run & Operate

- `pnpm --filter @workspace/api-server run dev` — run the API server (port 5000)
- `pnpm run typecheck` — full typecheck across all packages
- `pnpm run build` — typecheck + build all packages
- `pnpm --filter @workspace/api-spec run codegen` — regenerate API hooks and Zod schemas from the OpenAPI spec
- `pnpm --filter @workspace/db run push` — push DB schema changes (dev only)
- Required env: `DATABASE_URL` — Postgres connection string

## Stack

- pnpm workspaces, Node.js 24, TypeScript 5.9
- API: Express 5
- DB: PostgreSQL + Drizzle ORM
- Validation: Zod (`zod/v4`), `drizzle-zod`
- API codegen: Orval (from OpenAPI spec)
- Build: esbuild (CJS bundle)

## Where things live

- `artifacts/soulbound-voting/src/config/chain.ts` — SKALE Base Sepolia network config (single source of truth for RPC, chainId, faucet URL)
- `artifacts/soulbound-voting/src/context/WalletContext.tsx` — wallet connection context (`useWallet()`)
- `artifacts/soulbound-voting/src/index.css` — Philippine flag color theme tokens
- Contract ABI + address: **NOT YET** — will live in `src/config/contract.ts` once deployed address is provided

## Architecture decisions

- **No traditional backend** — all data is on-chain; frontend calls the contract directly via ethers.js v6 + MetaMask `BrowserProvider`.
- **Single source of truth for contract** — ABI and address will live exclusively in `src/config/contract.ts` (does not exist yet); no other file should define them.
- **SKALE quirk: no ENS** — every `ethers.Contract` instance must have `resolveName = async () => null` set; this is handled in `WalletContext.tsx` and must be repeated for any contract instance created outside that context.
- **OpenZeppelin pinned to 5.0.2** — 5.1+ uses MCOPY opcode (Cancun), which SKALE doesn't support. Do not upgrade.
- **Compiler: solc 0.8.24, optimizer 200 runs, viaIR: false** — viaIR previously miscompiled dynamic array returns on SKALE. Do not change these settings.
- **chainId must be lowercased** when passed to `wallet_switchEthereumChain`/`wallet_addEthereumChain` (MetaMask requirement).

## Product

- **Voter**: Connect MetaMask → switch to SKALE Base Sepolia → cast National/Local ballot (Province→District→City, partial votes allowed) → cast Barangay ballot (separate round) → receive soulbound NFT receipt with ballot number.
- **Admin**: Add geography hierarchy in bulk (≤100 per batch tx), add candidates per level/position, open/close each round independently.
- **Public**: View live tally per candidate/position, ballot counts per round.

**Status**: Frontend scaffold complete. Awaiting deployed contract address to wire up ethers calls.

## User preferences

_Populate as you build — explicit user instructions worth remembering across sessions._

## Gotchas

- **Never call `getCities()` / `getBarangays()` (flat)** once real nationwide data is loaded — use scoped/paginated variants (`getCitiesOfDistrict`, `getBarangaysOfCityPaginated`) instead. Flat calls will time out with ~42k barangays.
- **Batch geography uploads in chunks of ≤100** — `BatchTooLarge` revert above that; show progress ("batch 3 of 12") in the UI.
- **Always decode the actual revert reason** — never overwrite it with a generic string. Surface `err.reason` / `err.shortMessage` / custom error name directly.
- **Verify the contract before building contract-call code** — run the raw `eth_call` for `getDistricts()` (selector `0xa92563ed`) and confirm non-empty data before wiring any reads.
- **Get ABI from compiled artifact, never hand-typed** — regenerate from Remix's Compiler tab every time the contract is redeployed.

## Pointers

- See the `pnpm-workspace` skill for workspace structure, TypeScript setup, and package details
