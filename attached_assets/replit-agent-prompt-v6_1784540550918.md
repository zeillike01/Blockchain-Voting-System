# Replit Agent Prompt — SoulboundVoting v6, Fresh Build

Paste this into Replit's Agent chat. Attach `SoulboundVotingv6.sol` as a file alongside this prompt.

---

Read this entire prompt before doing anything.

## Deployment — you do NOT deploy this contract

**I will deploy `SoulboundVotingv6.sol` myself, manually, through Remix, using my own wallet. You will not deploy it, you will not ask me for a private key, and you will not run Hardhat/Foundry deploy scripts against it.** I will give you the deployed contract address once it's live. Until then, your only jobs are: (1) confirm you understand the contract's interface by reading the attached source, and (2) prepare everything else (frontend scaffolding, styling, wallet connection code) that doesn't require a live address yet. **Do not write any contract-calling code with a placeholder/fake address and call it done** — wait for the real one.

## Stack
- React + TypeScript (Vite)
- ethers.js v6
- shadcn/ui components, lucide-react icons
- Target chain: SKALE Base Sepolia
  - chainId: `0x135A9D92`
  - RPC: `https://base-sepolia-testnet.skalenodes.com/v1/jubilant-horrible-ancha`
  - Explorer: `https://base-sepolia-testnet-explorer.skalenodes.com/`
  - Native currency: CREDIT
  - Official faucet (web UI only, no public API): `https://base-sepolia-faucet.skale.space/`

## Contract overview (SoulboundVotingv6.sol, attached)
ERC721 soulbound receipt NFT. Full geographic hierarchy: **Province → District → City/Municipality → Barangay**, each level requiring its parent to exist first (`addProvince(name)` → `addDistrict(name, provinceId)` → `addCity(name, districtId)` → `addBarangay(name, cityId)`).

Two fully independent voting rounds:
- `Round.NATIONAL_LOCAL` (0) — President through City Councilor. Voter self-declares `provinceId`, `districtId`, `cityId` when casting: `castNationalLocalBallot(provinceId, districtId, cityId, votes)`.
- `Round.BARANGAY` (1) — Barangay Captain + Kagawad. Voter self-declares `barangayId`: `castBarangayBallot(barangayId, votes)`.

Each round has independent `votingOpenFor[round]` and `hasVotedInRound[round][address]` — a voter can complete one round without affecting the other, in either order.

Candidates are added via level-specific functions, each only accepting positions valid for that level (contract reverts `PositionNotAllowedForLevel` otherwise): `addNationalCandidate`, `addProvincialCandidate(provinceId, ...)`, `addDistrictCandidate(districtId, ...)`, `addCityCandidate(cityId, ...)`, `addBarangayCandidate(barangayId, ...)`, and matching `remove*Candidate` functions.

Each cast ballot mints a soulbound NFT carrying a **per-round sequential ballot number** — `getBallotInfo(tokenId)` returns `(round, ballotNumber)`. `totalBallotsInRound(round)` gives the running total for public cross-checking against summed candidate tallies.

**Bulk data support (for real nationwide geography):** alongside the single `addProvince`/`addDistrict`/`addCity`/`addBarangay` functions, there are batch versions — `addProvincesBatch`, `addDistrictsBatch(names, provinceId)`, `addCitiesBatch(names, districtId)`, `addBarangaysBatch(names, cityId)` — each accepting up to 100 names per call (`BatchTooLarge` reverts above that). At real Philippine scale (~42,000 barangays), any bulk-upload admin feature must chunk its input into batches of ≤100 and make multiple sequential batch calls, not one call per entry and not one giant array.

**Reads at scale:** `getProvinces()`/`getDistricts()` are flat and safe to call directly (nationwide counts are small: ~82 provinces, ~250 districts). `getCities()`/`getBarangays()` (flat, unpaginated) exist but **must not be called once real nationwide data is loaded** — use the scoped/paginated versions instead: `getDistrictsOfProvince(provinceId)`, `getCitiesOfDistrict(districtId)` (both scoped, safe unpaginated), and `getBarangaysOfCityPaginated(cityId, offset, limit)` (scoped *and* paginated, since a single city can have 100+ barangays). `getCitiesPaginated`/`getBarangaysPaginated` (flat + paginated) exist as an admin fallback only, not for normal voter-facing use.

## CRITICAL — compiler settings (do not deviate, even if I'm not the one compiling)
```js
solidity: {
  version: "0.8.24",
  settings: {
    optimizer: { enabled: true, runs: 200 },
    viaIR: false
  }
}
```
EVM version: default. Do not use `runs: 1` — combined with `viaIR: true` this previously miscompiled every function returning a dynamic array of structs, causing silent empty-data reverts on reads while writes and simple scalar reads worked fine. SKALE's real contract size limit is 64KB (not Ethereum's 24KB), so aggressive size optimization is unnecessary.

## CRITICAL — OpenZeppelin pin (do not deviate)
The contract imports are pinned: `@openzeppelin/contracts@5.0.2`. Do not suggest upgrading these. OpenZeppelin 5.1+ uses the `MCOPY` opcode (Cancun hardfork), which SKALE's EVM doesn't fully support — this caused every string-returning function to silently revert with zero data in an earlier version of this project.

## Once I give you the deployed address

1. **Verify before building anything.** Run a raw JSON-RPC `eth_call` directly (no ethers/ABI) against `getDistricts()`, selector `0xa92563ed`:
   ```js
   fetch("https://base-sepolia-testnet.skalenodes.com/v1/jubilant-horrible-ancha",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({jsonrpc:"2.0",method:"eth_call",params:[{to:"ADDRESS_HERE",data:"0xa92563ed"},"latest"],id:1})}).then(r=>r.json()).then(d=>console.log(d));
   ```
   Real encoded data → proceed. `"result": "0x"` → stop and tell me immediately, do not attempt to fix it by redeploying anything yourself.

2. **Get the ABI from the compiled build artifact, never hand-typed.** I'll provide it directly from Remix's Compiler tab, or you can compile the attached `.sol` locally *only to extract the ABI JSON* — do not deploy that compilation anywhere. This rule applies every time, not just this first deployment — if the contract ever changes and gets redeployed later, regenerate the ABI fresh from that build rather than editing the old one by hand.

## Hard-won lessons — read this section carefully, do not repeat these

This project went through several redeploys before reaching v6, and each of the following cost real debugging time. Don't reintroduce any of them.

1. **Never show a generic error message that hides the real revert reason.** An earlier version of this app had a bug where the catch-all error handler replaced every failed transaction's actual error with a generic string like "Check that you are the owner and voting is closed" — regardless of what actually went wrong. This made real bugs (like a duplicate-name revert) look identical to unrelated problems and wasted hours. Always surface the actual decoded error — the custom error name (e.g. `DuplicateDistrictName`, `MismatchedHierarchy`) or `err.reason`/`err.shortMessage` — directly to the user or at minimum to the console, never overwrite it with a hardcoded guess.

2. **Test the full read+write flow directly in Remix before writing any frontend code**, not just a single read-only check. Once you have the deployed address: add a province, add a district under it, add a city, add a barangay, add one candidate, open a round, and cast one full test ballot — all directly through Remix's Deploy tab UI. If something is going to be broken, find out there, where it's easy to isolate, rather than discovering it three layers deep in a React component later.

3. **Watch for truncated copy-pastes**, especially with the ABI or long file contents. This project hit multiple bugs that looked like code problems but were actually partial pastes silently cutting off mid-file (a truncated ABI, a truncated config file) when copied on a mobile device. When transferring the ABI or any large file, prefer direct file upload/download over manual copy-paste where possible, and if something looks like it's missing entries or fails in a way that doesn't match the actual code, check for truncation before assuming it's a logic bug.

4. **Search the whole codebase for every place `CONTRACT_ADDRESS`/`CONTRACT_ABI` could be defined**, not just `config.ts`. This project once had a stale/duplicate address lingering somewhere that caused confusing "it's fixed but still broken" symptoms, because a previous, broken contract address was still being used in one path while another path had the correct one. Confirm there's exactly one source of truth for the contract address and ABI, and that every file importing it points to the same place.

5. **Don't trust an address from earlier context without re-confirming it.** This project has had at least three different deployed contract addresses across its history as bugs were found and fixed. If at any point you're unsure which address is actually current, ask rather than assume — using a stale address silently is worse than asking.

6. **This is a clean break from any earlier AdminPanel/Web3Context code that might exist in this Replit project.** The v6 contract's function signatures (geography hierarchy, two rounds, per-round candidate functions) are completely different from earlier versions. Don't try to patch or partially adapt old admin panel code — build fresh against v6's actual interface as described below.

### SKALE has no ENS
Every `ethers.Contract` instance (read-only and signer-connected) needs `resolveName = async () => null` set explicitly.

### Wallet connection — plain MetaMask, no third-party services
`window.ethereum` + ethers v6 `BrowserProvider`. Prompt a network switch to SKALE Base Sepolia on connect (`wallet_switchEthereumChain`, falling back to `wallet_addEthereumChain`). Link to `metamask.io/download` if no wallet is detected.

Two implementation details, easy to miss:
- MetaMask expects `chainId` as lowercase hex in these RPC calls. Call `.toLowerCase()` on `SKALE_BASE_SEPOLIA.chainId` specifically when passing it into `wallet_switchEthereumChain`/`wallet_addEthereumChain`, even though it's stored as mixed-case elsewhere in `config.ts`.
- If the user dismisses/rejects the switch or add-network prompt, don't just log it and stop silently. Show a visible "You're on the wrong network — click to switch" banner/button that re-triggers the same flow, so a user who closes the popup by accident isn't left with a dead app and no explanation.

### Faucet button
Opens `https://base-sepolia-faucet.skale.space/` in a new tab, copies the connected address to clipboard first. No public API exists for this faucet.

### Admin panel
Cascading creation flow (Province → District → City → Barangay, each disabled until its parent is selected/exists), candidate management per level, independent open/close toggles for both rounds, full loading/error/toast handling on every read and write.

**Bulk upload:** support pasting/uploading a list of names (e.g., one per line, or CSV) for districts/cities/barangays under a selected parent, then submitting via the batch functions in chunks of ≤100 per transaction — show progress across chunks (e.g., "uploading batch 3 of 12"), since a 42,000-barangay dataset means hundreds of sequential transactions, not one.

**Reads:** use `getProvinces()`/`getDistricts()` directly. For cities and barangays, always use the scoped getters (`getCitiesOfDistrict`, `getBarangaysOfCityPaginated`) filtered by whatever parent is currently selected in the admin UI — never call the flat `getCities()`/`getBarangays()` once real data is loaded.

### Voter ballot UI
- National/Local round: cascading Province → District → City dropdowns, using the scoped getters (`getDistrictsOfProvince(provinceId)`, `getCitiesOfDistrict(districtId)`) filtered by whatever parent was just selected — never fetch the full nationwide list and filter client-side. Then candidate selection per position. **Partial voting must work** — voting for only President and submitting is valid; don't require every position filled before enabling submit.
- Barangay round: separate flow — Province → District → City → Barangay, using `getBarangaysOfCityPaginated(cityId, offset, limit)` for the final step since a city can have 100+ barangays. Separate submit and separate "already voted" state from the national/local round.
- **No cross-country search.** Voters navigate purely by cascading selection (Province → District → City → Barangay) — there is no "type a barangay name and find it anywhere in the Philippines" search feature, since that would require an off-chain search index that doesn't exist in this build. Within a single already-loaded scoped list (e.g., barangays in the one city just selected), simple client-side substring filtering on the current page's results is fine and expected — that's different from a full nationwide search and doesn't need new infrastructure.
- After a successful vote, show the voter their ballot number (`getBallotInfo`) as their public proof of participation.

## UI Theme — Philippine flag colors

Use the official Philippine flag palette as the design system's core colors:
- **Blue**: `#0038A8` — primary/header, navigation, primary buttons
- **Red**: `#CE1126` — used for the barangay round or "closed/urgent" states, secondary accents, destructive actions can stay standard red-for-danger conceptually but visually align with this red
- **White**: `#FFFFFF` — backgrounds, cards, contrast against blue/red
- **Golden yellow**: `#FCD116` — highlights, active-state badges, the "sun" motif, ballot-number displays, success accents

Practical guidance, not just raw color swapping:
- Don't put white or light gold text directly on gold backgrounds — contrast fails. Use gold as an accent/border/badge color, not large body-text backgrounds.
- The three-star/sun motif in the actual flag is a nice source of subtle iconographic inspiration (e.g., a sun-ray icon for "voting open" status, three small stars for the three-tier navigation Province/City/Barangay) — optional, don't force it if it looks kitschy.
- Keep sufficient contrast for form inputs and error states — don't sacrifice usability for theme purity. Standard red/green for error/success is fine to keep even within this palette, since CE1126 red already doubles naturally as an error-adjacent color.

## What to do right now
Read the attached contract, confirm you understand its function signatures, and set up the project scaffolding (Vite config, folder structure, Tailwind theme tokens using the palette above) that doesn't require a live contract address. Then wait for me to provide the deployed address before writing any contract-calling code.
