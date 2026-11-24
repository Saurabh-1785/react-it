# Development Log

## [Block 1] - 2026-11-17: Foundation, Monorepo Setup & Origin Contract
- Initialized project monorepo structure with `contracts/`, `apps/web/`, and `services/tracker/`.
- Configured Foundry toolchain with OpenZeppelin v5 contracts and custom compiler profiles.
- Implemented `PaymentRequestHub.sol` on Base Sepolia with time-bounded requests and topic-indexed events.
- Added comprehensive unit and fuzz test suites verifying deadline validation, nonces, and event emission.
- Configured GitHub Actions CI pipeline covering format validation, compilation, and automated tests.

## [Block 2] - 2026-11-18: Reactive Omni Contract & Event Subscription
- Integrated Reactive Network library (`reactive-lib`) with `AbstractReactive` base.
- Implemented `ZeroFloatReactive.sol` targeting Reactive Omni.
- Configured dynamic subscription to `PaymentRequested` event logs emitted on Base Sepolia (`chainId: 84532`).
- Implemented `react()` event processor decoding log topics/data and emitting `Observed` events.
- Added comprehensive unit and fuzz tests simulating ReactVM execution and log filtering.
- Created `contracts/script/DeployReactive.s.sol` for deployment to Reactive Omni.

## [Block 3] - 2026-11-19: First Reactive Callback & Provenance Verification
- Implemented `FloatCallbackReceiver.sol` on Base Sepolia inheriting `AbstractCallback` and `Ownable2Step`.
- Enforced strict two-layer callback provenance: only authorized callback proxy can invoke callbacks, and caller identity must match authorized reactive contract (`rvm_id`).
- Implemented `ack(address sender, bytes32 requestId)` endpoint with idempotency checks.
- Enhanced `ZeroFloatReactive.sol` to emit `Callback` events back to Base Sepolia upon observing `PaymentRequested`.
- Added unit tests for authorized callbacks, caller reversion, RVM ID spoofing protection, and duplicate rejection.

## [Block 4] - 2026-11-20: ZeroFloatAccount & CREATE2 Factory
- Implemented `ZeroFloatAccount.sol` per-user spending smart wallet with strict role separation (`topUp` for FloatPool, `payMerchant` for Hub, `withdraw` for Owner).
- Implemented `ZeroFloatFactory.sol` with deterministic CREATE2 address calculation (`getAccountAddress`).
- Created `MockUSD.sol` (6 decimals) stablecoin for testing payment flows.
- Added test suite confirming exact CREATE2 address prediction, balance accounting, and access control.
- Created `DeployBlock3And4.s.sol` deployment script for Base Sepolia.
