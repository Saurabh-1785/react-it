# Zero-Float Wallet

> Autonomous cross-chain reactive wallet for the **Reactive Omni Buildathon** (*Every Second Counts* track).

Zero-Float Wallet keeps user balances accruing continuous yield in an ERC-4626 savings vault on **Unichain Sepolia**, while maintaining a zero-float spending account on **Base Sepolia**. When a merchant requests payment within a short deadline, a reactive smart contract on **Reactive Omni** autonomously coordinates liquidity fronting on Base and settlement from Unichain.

---

## Architecture Flow

1. **Origin:** Merchant calls `requestPayment` on `PaymentRequestHub` (Base Sepolia), emitting `PaymentRequested`.
2. **Reaction:** `ZeroFloatReactive` (Reactive Omni) detects the event and emits two parallel callbacks.
3. **Execution (Hop 1):** `FloatCallbackReceiver` triggers `FloatPool.front` to pay the merchant immediately on Base Sepolia.
4. **Execution (Hop 2):** `VaultGateway` withdraws funds from `SavingsVault` on Unichain Sepolia and emits `SettlementReady`.
5. **Settlement (Hop 3):** `ZeroFloatReactive` catches `SettlementReady` and triggers `FloatPool.settle` on Base Sepolia to clear debt.

---

## Project Structure

```
react-it/
├── contracts/               # Foundry smart contracts (Solidity 0.8.25)
│   ├── src/
│   │   └── PaymentRequestHub.sol
│   ├── test/
│   │   └── PaymentRequestHub.t.sol
│   ├── script/
│   │   └── DeployHub.s.sol
│   └── foundry.toml
├── apps/web/                # Next.js web application
├── services/tracker/        # Latency tracking service
├── docs/                    # Architecture, Devlog, Security specs
├── DEPLOYMENTS.md           # On-chain addresses and transaction evidence
└── LICENSE                  # MIT License
```

---

## Quickstart

### Prerequisites
- [Foundry](https://book.getfoundry.sh/) (`forge`, `cast`)
- Node.js >= 18

### Building & Testing Contracts
```bash
cd contracts
forge build
forge test -vvv
```

---

## Deployment (Base Sepolia)
```bash
cd contracts
source .env
forge script script/DeployHub.s.sol:DeployHub \
  --rpc-url https://sepolia.base.org \
  --broadcast
```

---

## License
MIT
