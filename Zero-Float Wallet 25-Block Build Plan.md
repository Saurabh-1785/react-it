# Zero-Float Wallet: 25-Block Build Plan

Reactive Omni Buildathon, track: **Every Second Counts** (time-sensitive DeFi on Unichain Sepolia and Base Sepolia). Prepared for Saurabh on 17 Nov 2026.

## 0. Read this first: calendar reality

- Submissions close **2026/12/06 01:30 (UTC+5.5)**. From today (17 Nov) that is **19 calendar days**, not 25.
- This plan has **25 day-sized blocks**. Six calendar days carry two lighter blocks (see section 6). Every block ends with something you can verify on-chain or in a test run.
- Do **not** backdate commits or claim 25 days of work. The rules say everything must be built during the event, the repo must be public, and git history is visible to judges. Honest dated commits plus a tx hash per block is the strongest evidence of effort you can give.
- Blocks marked **(stretch)** can be cut without breaking the core loop. The cut list is at the end.
- Daily close-out (15 minutes, inside every block): com


mit with the block tag, append new addresses and tx hashes to `DEPLOYMENTS.md`, write 5 lines in `docs/devlog.md`. This builds the Craft score as you go instead of in the last 24 hours.

## 1. Pitch

Money in a spending wallet earns nothing, and money in a savings vault cannot be spent instantly. Zero-Float Wallet fixes this. The spending wallet on **Base Sepolia** holds almost nothing. The balance sits in an **ERC-4626 yield vault on Unichain Sepolia**. When a merchant or subscription contract emits a payment request with a deadline of a few seconds, a **reactive contract on Reactive Omni** sees the event and triggers callbacks that (1) front the exact amount from a liquidity pool on Base so the payment completes inside the window, and (2) withdraw the matching amount from the user's vault on Unichain, which then settles the pool. You earn yield on everything until the second you spend it.

Who could ship it: any wallet, neobank or payment processor. The user-facing promise is one line: *your checking balance earns yield.*

## 2. Why it needs Omni (your Integration argument)

- The payment window is seconds long. On the previous version of Reactive (about 7 second blocks) the reaction alone could outlast the window. Omni runs on CometBFT consensus with about 1 second blocks and instant finality, so react, callback and payment fit inside the window.
- The reactive contract is the **only** actor allowed to trigger fronting, withdrawal, settlement and circuit-breaking. There is no keeper bot, no cron and no manual call. State this explicitly in the README and demo.
- The flow spans three networks: events on Base Sepolia and Unichain Sepolia, execution on Reactive Omni, callbacks back to both.

## 3. Architecture

**Base Sepolia (spending side)**

- `PaymentRequestHub`: merchants call `requestPayment(account, merchant, token, amount, deadline)`. Emits `PaymentRequested`. Completes the payment when the account is funded.
- `ZeroFloatAccount` and `ZeroFloatFactory`: per-user wallet with deterministic (CREATE2) addresses.
- `FloatPool`: LP-funded liquidity that fronts credit and tracks per-account debt and per-request status.
- `PolicyRegistry`: EIP-712 signed spending rules.
- `FloatCallbackReceiver`: the single authorised entry point for callbacks. Idempotent per request.
- `CircuitBreaker`: halts fronting for a token when a risk signal fires.

**Unichain Sepolia (savings side)**

- `SavingsVault`: OpenZeppelin ERC-4626, with a clearly labelled `MockYieldStrategy` (testnets have no real yield).
- `VaultGateway`: callback receiver that withdraws for settlement and emits `SettlementReady`.
- `PegWatchHook` (stretch): Uniswap v4 hook that emits an event when a stable pool leaves its price band.

**Reactive Omni**

- `ZeroFloatReactive`: subscribes to Base `PaymentRequested`, Unichain `SettlementReady`, the Chainlink `AnswerUpdated` event (stretch) and the hook's deviation event (stretch).

**Event flow (the full loop you will show in the submission)**

1. Merchant tx on Base: `PaymentRequested` (origin event).
2. Reactive tx on Omni: `react()` runs, emits two callbacks.
3. Callback A on Base: policy check, `FloatPool.front`, account topped up, payment completed.
4. Callback B on Unichain: `VaultGateway.withdrawForSettlement`, emits `SettlementReady`.
5. Reactive tx on Omni: reacts to `SettlementReady`.
6. Callback C on Base: `FloatPool.settle`, debt cleared.

**Design decision, stated honestly:** moving tokens between chains in seconds needs a bridge. The pool fronts liquidity on Base immediately and is repaid by the Unichain withdrawal. On testnet the repayment uses a `MockBridgeReserve`. Say so in the docs and name what production would use (a canonical bridge or a solver network). Judges reward clear scope more than hidden shortcuts.

## 4. Tech stack

- **Reactive Omni**: reactive contracts, event subscriptions, callbacks. Docs: https://dev.reactive.network/ . Confirm exact base contract names, subscription calls, callback event signature, callback authorisation and how callback gas is funded in the docs, because Omni is new and details may differ from the previous version.
- **Chains**: Base Sepolia and Unichain Sepolia. Confirm chain ids, RPCs and supported origins/destinations at https://dev.reactive.network/origins-and-destinations#testnet-chains (mainnet list for reference: https://dev.reactive.network/origins-and-destinations#mainnet-chains).
- **Solidity 0.8.x + Foundry**: unit, fuzz, invariant, fork tests, gas snapshots, coverage.
- **OpenZeppelin**: ERC4626, EIP712, ECDSA, ERC-1271 support, ReentrancyGuard, Ownable2Step.
- **Permit2** for signature-based deposits.
- **EIP-712** typed spending policies.
- **Uniswap v4 hook** (stretch) on Unichain Sepolia.
- **Chainlink data feed** event (stretch) on Base Sepolia.
- **TypeScript, viem, wagmi, Next.js, SQLite** for the tracker service and the dashboard.
- **LLM policy assistant** (stretch): strict JSON schema, human signs, never holds keys.
- **Slither + GitHub Actions** for static analysis and CI.
- **Timestamps, not block counts**, for every timer, cooldown and deadline. Base Sepolia now produces blocks every 200 ms (official ground rule).

## 5. Scoring map (four criteria, scored 1 to 5 each)

| Criterion | What proves it | Blocks |
| --- | --- | --- |
| Execution | Reactive transactions and callbacks visible on-chain; hash chains in the README. Entries without them are not scored further. | 2, 3, 6, 12, 13, 24 |
| Integration | Reactive contract is the only trigger; three-hop flow; multi-chain subscriptions; why 7 second blocks could not do this | 6, 9, 11, 12, 13, 15, 16 |
| Usefulness | Real merchant and subscription scenarios; yield earned while waiting; dashboard | 19, 21, 22, 24 |
| Craft | CI, tests, Slither, NatSpec, docs someone else can follow, demo under 3 minutes | 1, 17, 18, 20, 25 |

## 6. Calendar

| Date | Blocks | Gate |
| --- | --- | --- |
| Tue 17 Nov | 1 |  |
| Wed 18 Nov | 2 |  |
| Thu 19 Nov | 3 | First origin to reactive to callback loop |
| Fri 20 Nov | 4 + 5 |  |
| Sat 21 Nov | 6 | **Core loop alive on Base** |
| Sun 22 Nov | 7 + 8 |  |
| Mon 23 Nov | 9 |  |
| Tue 24 Nov | 10 + 11 |  |
| Wed 25 Nov | 12 |  |
| Thu 26 Nov | 13 | **Full three-hop loop** |
| Fri 27 Nov | 14 |  |
| Sat 28 Nov | 15 (stretch) |  |
| Sun 29 Nov | 16 (stretch) |  |
| Mon 30 Nov | 17 |  |
| Tue 1 Dec | 18 | **Code freeze for contracts** |
| Wed 2 Dec | 19 + 20 |  |
| Thu 3 Dec | 21 + 22 |  |
| Fri 4 Dec | 23 (stretch) + 24 |  |
| Sat 5 Dec | 25 | **Submit by 20:00 IST**, leaving about 5.5 hours of buffer before the deadline |

## 7. The 25 blocks

### Block 1: Repo, CI and the origin contract live on Base Sepolia (Tue 17 Nov)

**Build:** Public GitHub repo with MIT licence. Foundry project in `contracts/`, plus `apps/web` and `services/tracker`. GitHub Actions: `forge build`, `forge test`, `forge fmt --check`, Slither. Deploy `PaymentRequestHub` with `requestPayment(account, merchant, token, amount, deadline)` emitting `PaymentRequested(requestId, account, merchant, token, amount, deadline)`. Choose indexed fields so the reactive contract can filter by topic. **Tech:** Foundry, Solidity 0.8.x, Base Sepolia. **Done when:** CI is green, the contract is verified on the explorer, and a `cast send` shows the event in the logs. **Evidence:** deploy tx hash and address in `DEPLOYMENTS.md`. Scores: Execution, Craft.

### Block 2: First reactive contract reacts to a Base Sepolia event (Wed 18 Nov)

**Build:** Deploy `ZeroFloatReactive` on Reactive Omni. Subscribe to the `PaymentRequested` topic on Base Sepolia. In `react()`, decode the log and emit a plain `Observed(requestId, originTimestamp)` event. Fund it with REACT as the docs describe. Write a deploy script. **Tech:** Reactive Omni (CometBFT, about 1 second blocks, instant finality). **Done when:** a request on Base produces a reactive transaction on Omni within a few seconds. **Evidence:** origin tx hash and reactive tx hash pair. Scores: Execution, Integration.

### Block 3: First callback closes the loop (Thu 19 Nov)

**Build:** `FloatCallbackReceiver` on Base Sepolia that accepts calls only from the authorised Reactive callback sender (per the docs) and checks the reactive contract identity. The reactive contract emits a callback calling `ack(requestId)`; the receiver emits `Acked`. Fund the callback budget as the docs describe. **Tech:** Reactive callbacks, access control. Check whether the first payload argument is overwritten with the reactive contract identity on Omni, as it was on the previous version, and validate it. **Done when:** you have an origin, reactive and callback transaction triple, and a random EOA calling `ack` reverts in a test. **Evidence:** three hashes. This hello-loop is the foundation for everything else. Scores: Execution, Integration.

### Block 4: ZeroFloatAccount and factory (Fri 20 Nov, with Block 5)

**Build:** `ZeroFloatAccount` per user: owner, small float of mock stablecoin `mUSD` (6 decimals), `topUp` callable only by `FloatPool`, `payMerchant` callable only by the hub, owner `withdraw`. `ZeroFloatFactory` with CREATE2 so addresses are predictable before deployment. NatSpec on every external function. **Done when:** access-control and accounting tests pass; the factory deploys; the address matches the prediction. **Evidence:** forge test output, deploy tx. Scores: Craft.

### Block 5: FloatPool with a per-account debt ledger (Fri 20 Nov)

**Build:** `FloatPool`: LP deposits and shares, `front(account, amount, requestId)` callable only by the callback receiver, `debt[account]`, `outstanding`, per-request status (None, Fronted, Settled, Expired), `settle(requestId, amount)`, per-account credit limit, utilisation cap. **Done when:** a fuzz test passes and an invariant test holds: pool assets plus outstanding equals deposits plus fees, over thousands of runs. **Evidence:** invariant test output, deploy tx. Scores: Execution, Craft.

### Block 6: First real loop on Base (Sat 21 Nov)

**Build:** In `react()`, decode `PaymentRequested` and emit a callback to the receiver's `front(...)`. The receiver calls `FloatPool.front`, which tops up the account; the same transaction calls `hub.complete(requestId)` to pay the merchant and emit `PaymentCompleted`. **Done when:** a request against an account with **zero** balance ends in `PaymentCompleted`. Measure seconds from request to completion and record them in `LATENCY.md`. **Evidence:** origin, reactive and callback hashes plus the latency number. Scores: Execution, Integration, Usefulness.

### Block 7: Timestamp windows, cooldowns and expiry (Sun 22 Nov, with Block 8)

**Build:** Remove every block-count assumption. Use `block.timestamp` for `deadline`, a `minWindow` of at least 5 seconds, a per-account cooldown between fronts, and `expire(requestId)` callable by anyone after the deadline (status becomes Expired; no funds move). Document that at 200 ms blocks many blocks share one timestamp, so windows are seconds and tests use `vm.warp`. **Done when:** on-time passes, one-second-late is rejected, the cooldown is enforced, and one on-chain example shows a late request ending in Expired. **Evidence:** test output, Expired tx hash. Scores: Execution, Craft.

### Block 8: EIP-712 spending policies (Sun 22 Nov)

**Build:** `PolicyRegistry` with typed data `SpendPolicy(owner, merchant, token, perTxLimit, dailyLimit, validUntil, nonce)`. `setPolicy(policy, signature)` using OpenZeppelin EIP712 and ECDSA, with ERC-1271 support. `checkAndConsume(account, merchant, token, amount)` with a daily bucket by timestamp. Nonce revocation. **Done when:** tests cover wrong signer, replay, expired policy and over-limit; a viem script signs with `signTypedData` and the on-chain recovery matches. **Evidence:** test output, `setPolicy` tx. Scores: Usefulness, Craft.

### Block 9: Enforce policy inside the callback, plus idempotency (Mon 23 Nov)

**Build:** The receiver checks `PolicyRegistry` before fronting. On a violation it emits `Denied(requestId, reason)` and returns without reverting, so the denial is itself a visible on-chain callback. Add `processed[requestId]` so a duplicate reaction cannot front twice. **Done when:** three live payments behave correctly: allowed, over-limit (Denied), duplicate (ignored). **Evidence:** three hash chains. Scores: Execution, Integration, Usefulness.

### Block 10: ERC-4626 SavingsVault on Unichain Sepolia (Tue 24 Nov, with Block 11)

**Build:** OpenZeppelin `ERC4626` vault over `mUSD` on Unichain, with `MockYieldStrategy` accruing a fixed rate by timestamp (label it as mock in code and docs), a virtual-share offset against inflation attacks, and `withdrawForSettlement` restricted to the gateway. **Done when:** tests show share price is monotonic and rounding is safe; deposit and withdraw txs succeed on Unichain Sepolia; share price visibly grows after an hour. **Evidence:** deploy tx, deposit tx, two share-price readings. Scores: Execution, Craft.

### Block 11: Multi-chain subscriptions (Tue 24 Nov)

**Build:** Extend `ZeroFloatReactive` to also subscribe to Unichain Sepolia events. Tag each reaction with the origin chain id, add admin subscribe/unsubscribe, and ignore unknown logs safely. **Tech:** multi-origin subscriptions per the docs and the testnet chains page. **Done when:** a test event on Unichain triggers a reactive tx, and the Base path still works. **Evidence:** one hash pair per origin chain. Scores: Integration.

### Block 12: Hop 2, vault withdrawal triggered from a Base event (Wed 25 Nov)

**Build:** `VaultGateway` on Unichain Sepolia as a callback receiver with `withdrawForSettlement(owner, amount, requestId)`. The owner pre-authorises the gateway with a bounded allowance. It redeems shares, moves the amount to a settlement escrow and emits `SettlementReady(requestId, amount, owner)`. The same `PaymentRequested` reaction now emits **two callbacks**: Base front and Unichain withdraw. **Done when:** one request produces two callbacks from the same reactive transaction. **Evidence:** origin, reactive, Base callback and Unichain callback hashes. Scores: Execution, Integration.

### Block 13: Hop 3, settlement closes the loop (Thu 26 Nov)

**Build:** The reactive contract reacts to `SettlementReady` on Unichain and emits a Base callback `FloatPool.settle(requestId, amount)`. A testnet `MockBridgeReserve` replenishes the pool (document it as a stand-in for a real bridge or solver network). Status moves to Settled and the debt is cleared. **Done when:** one request runs the full loop: PaymentRequested, front plus withdraw, SettlementReady, settle. The pool is solvent and the account debt is zero. **Evidence:** the six-hash chain, saved as the headline example in the README. Scores: Execution, Integration.

### Block 14: Permit2 gasless funding (Fri 27 Nov)

**Build:** Use canonical Permit2 (check that it is deployed on Base Sepolia and Unichain Sepolia; deploy from the Uniswap repo if it is missing). Add `PermitDepositRouter` so LP deposits into `FloatPool` and vault deposits use `permitTransferFrom` signatures with no separate approve tx. Add a combined flow: one signature for the deposit, one EIP-712 signature for the policy. **Done when:** a deposit succeeds from a signature alone; tests reject a reused nonce and an expired deadline. **Evidence:** deposit tx hash, test output. Scores: Usefulness, Craft.

### Block 15 (stretch): CircuitBreaker and a Uniswap v4 hook as a risk signal (Sat 28 Nov)

**Build:** `CircuitBreaker` on Base with `halt(token)` and `resume(token)` callable by the callback receiver. `PegWatchHook` (afterSwap) on Unichain Sepolia emits `PegDeviation(pool, tick, timestamp)` when a stable pool leaves its configured band; mine the hook address salt so the permission flags match. The reactive contract subscribes and calls `halt`. While halted, new fronts are Denied with reason HALTED. **Tech:** Uniswap v4 hooks and PoolManager (https://docs.uniswap.org/contracts/v4/overview). **Done when:** a large test swap pushes the pool out of band, fronting halts within seconds, and a payment during the halt is Denied. **Evidence:** swap tx, reactive tx, halt callback tx, Denied tx. Scores: Integration.

### Block 16 (stretch): Chainlink feed as a second risk source (Sun 29 Nov)

**Build:** The reactive contract subscribes to the Chainlink aggregator `AnswerUpdated` event on Base Sepolia. Check that a feed exists for your pair; otherwise deploy a `MockAggregator` that emits the same event and label it. A deviation beyond the threshold calls `halt`; recovery happens after a timestamp-based cooldown. **Tech:** Chainlink data feeds (https://docs.chain.link/data-feeds). **Done when:** an answer update triggers a halt, then an automatic resume after the cooldown. **Evidence:** hash chain for halt and resume. Scores: Integration.

### Block 17: Security hardening (Mon 30 Nov)

**Build:** `ReentrancyGuard` on front, settle and withdraw; checks-effects-interactions; role separation (owner, guardian with pause-only rights, callback sender); `Ownable2Step`; per-request and utilisation caps; emergency withdraw behind a timelock; complete events. Run Slither and either fix or document every finding in `SECURITY.md`. Write a threat model covering: forged callback, replay, duplicate reaction, pool drain, oracle or pool manipulation, and spam `PaymentRequested` griefing (mitigate with a registered-merchant list or a small bond). **Done when:** Slither is clean or every finding is justified; each threat has a test. **Evidence:** `SECURITY.md`, CI badge. Scores: Craft.

### Block 18: Test depth (Tue 1 Dec) - contract code freeze

**Build:** Foundry fuzz tests (amounts, deadlines, ordering), invariant tests (pool solvency, no double-front, debt equals fronted minus settled), fork tests against Base Sepolia and Unichain Sepolia state, `forge snapshot` gas report, `forge coverage`. Publish coverage in CI. **Done when:** core contracts reach about 90 percent line coverage; invariants pass with 256 runs at depth 500. **Evidence:** CI run link, coverage summary, gas snapshot. Scores: Craft.

### Block 19: Realistic scenarios (Wed 2 Dec, with Block 20)

**Build:** `DemoMerchant` (coffee checkout with a 10 second window) and `SubscriptionCharger` (a monthly pull charge). Script `demo/run-scenarios.ts` runs four scenarios: normal checkout, subscription charge, over-limit denial, depeg halt (if Blocks 15 or 16 are done). Each prints its full hash chain as JSON. **Done when:** one command runs all scenarios end to end. **Evidence:** `demo/output.json`. Scores: Usefulness, Execution.

### Block 20: Latency tracker service (Wed 2 Dec)

**Build:** `services/tracker` in TypeScript with viem. For each `requestId` it links the origin tx, the reactive tx and every callback tx, computes per-hop and total latency from timestamps, stores rows in SQLite, and serves `/api/payments` and `/api/stats` (p50 and p95). **Done when:** 20 payments are tracked with every stage linked and the stats endpoint returns percentiles. **Evidence:** sample API output saved in `docs/`. Scores: Execution, Craft.

### Block 21: Frontend 1, wallet, vault and policy (Thu 3 Dec, with Block 22)

**Build:** Next.js with wagmi and viem. Connect on Base Sepolia, show float balance and vault balance (Unichain), deposit with a Permit2 signature, set spending rules with a plain-language preview of the EIP-712 typed data before signing. Handle chain switching. **Done when:** from the browser you can deposit, set a policy and see both balances update. **Evidence:** screen recording, commit. Scores: Usefulness, Craft.

### Block 22: Frontend 2, live payment timeline (Thu 3 Dec)

**Build:** A timeline per payment: origin event, reactive tx, Base callback, Unichain callback, settlement. Each step shows elapsed seconds, a status chip and an explorer link. Add a counter for yield earned while the payment waited. Add a comparison bar between your measured total and the same flow on about 7 second blocks; label the second figure as an estimate from the previous version's block time. Data comes from the tracker API. **Done when:** during a demo scenario, each hop appears within about 2 seconds of landing on-chain. **Evidence:** recording of a live run. Scores: Usefulness, Integration.

### Block 23 (stretch): AI policy assistant (Fri 4 Dec, with Block 24)

**Build:** An endpoint that sends plain English (for example: coffee shops up to 20 a day) to an LLM, which must return JSON that validates against a strict schema and hard bounds. The UI shows the resulting EIP-712 preview; the user signs. The model holds no keys and cannot submit transactions. Optional: a small buffer recommender (moving average over payment history) that only suggests a credit limit. **Done when:** 20 test phrases give valid policies and 10 adversarial phrases (for example, ones telling the model to raise limits or skip confirmation) are rejected or clamped. **Evidence:** test table in `docs/ai-assistant.md`. Scores: Craft, Usefulness.

### Block 24: Benchmark and evidence run (Fri 4 Dec)

**Build:** Run 50 payments across the scenarios on the live testnets. Write `LATENCY.md` with p50 and p95 per hop, failures and retries, reported honestly including outliers. Collect every contract address and at least 5 complete hash chains into `DEPLOYMENTS.md`. Verify every contract on the explorers. Tag `v0.1.0`. **Done when:** the evidence table is complete and every link works from a clean browser. **Evidence:** `LATENCY.md`, `DEPLOYMENTS.md`, release tag. Scores: Execution, Craft.

### Block 25: Documentation, video and submission (Sat 5 Dec)

**Build:** README (problem, solution, architecture, quick start that works on a fresh machine in about 10 minutes), `ARCHITECTURE.md` with the event flow, `SECURITY.md`, `DEPLOYMENTS.md`, `LICENSE`. Record and upload the demo video. Submit on the buildathon page. **Done when:** a friend who has never seen the project can run it from the README; the submission is in by 20:00 IST. **Scores:** Craft, Usefulness.

## 8. Submission checklist (everything the brief asks for)

- Link to the **public repository**, open-source by the time you submit.
- **Deployed contract addresses** on Base Sepolia, Unichain Sepolia and Reactive Omni.
- **Transaction hashes showing the full loop**, from origin event to callback: at least 5 complete chains.
- **Demo video under three minutes.**
- Everything built during the event. Prior work may be used only as a dependency (for example OpenZeppelin, Permit2, Uniswap), never as the submission itself.
- Timestamps, not block counts, for timers, cooldowns and deadlines on Base Sepolia.
- Read the final page once more for any guest-judge announcements.

## 9. Demo video script (target 2:40)

- 0:00 to 0:20: the problem. Idle spending money earns nothing; savings cannot pay in seconds.
- 0:20 to 0:50: architecture in one diagram. Base, Unichain, Reactive Omni; say that the reactive contract is the only trigger.
- 0:50 to 2:10: live run in the timeline view. Zero-balance wallet, merchant request with a 10 second window, each hop appears, merchant is paid, vault share count drops, settlement clears. Then show one Denied payment (over limit) and one halt if built.
- 2:10 to 2:40: measured numbers from `LATENCY.md`, why about 1 second blocks and instant finality make this possible, and how a wallet or payment provider would ship it.

## 10. Cut list (if you fall behind)

Cut in this order, none of which breaks the core loop: Block 23 (AI assistant), Block 16 (Chainlink), Block 15 (v4 hook), the daily-limit part of Block 8, the yield counter in Block 22. Never cut Blocks 2, 3, 6, 12, 13, 24 or 25: they carry the Execution score, and entries without reactive transactions and callbacks on-chain are not scored further.

## 11. Risks and fallbacks

- **Omni API differences:** Omni is new. If a base contract or callback pattern from the previous version fails, read the current docs and copy the minimal working example before changing your design.
- **Chain support:** if an origin or destination you need is not listed on the testnet chains page, move that piece to a supported chain and say so in the docs.
- **Permit2 or Chainlink missing on a testnet:** deploy canonical Permit2, or use `MockAggregator`. Label mocks clearly.
- **Callback latency worse than the window:** widen the demo window and report the real numbers. A truthful 6 second result beats an invented 1 second one.
- **Duplicate or reordered reactions:** the `processed[requestId]` guard and per-request status enum exist for this.
- **Funding:** keep spare REACT and callback budget topped up before every demo run.

## 12. Reference links

- Reactive Network docs: https://dev.reactive.network/
- Mainnet chains: https://dev.reactive.network/origins-and-destinations#mainnet-chains
- Testnet chains: https://dev.reactive.network/origins-and-destinations#testnet-chains
- Foundry book: https://book.getfoundry.sh/
- OpenZeppelin Contracts: https://docs.openzeppelin.com/contracts/
- EIP-712: https://eips.ethereum.org/EIPS/eip-712
- ERC-4626: https://eips.ethereum.org/EIPS/eip-4626
- Permit2: https://github.com/Uniswap/permit2
- Uniswap v4: https://docs.uniswap.org/contracts/v4/overview
- Chainlink data feeds: https://docs.chain.link/data-feeds
