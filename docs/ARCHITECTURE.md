# Zero-Float Wallet: Architecture & Cross-Chain Flow

## Overview
Zero-Float Wallet enables users to earn continuous yield on their liquid balances in an ERC-4626 vault on Unichain Sepolia, while maintaining an instant-spending zero-balance smart account on Base Sepolia.

## Core Components

```
 [ Base Sepolia ]                [ Reactive Omni ]              [ Unichain Sepolia ]
+----------------------+        +--------------------+        +---------------------+
|  PaymentRequestHub   |        | ZeroFloatReactive  |        |    SavingsVault     |
| (PaymentRequested)   | -----> |   (Event Listener) |        |     (ERC-4626)      |
+----------------------+        +---------+----------+        +----------+----------+
           ^                              |                              |
           |                              v                              v
+----------------------+        +--------------------+        +---------------------+
| FloatCallbackReceiver|<-------| Callback 1: Front  |        |    VaultGateway     |
| (FloatPool.front &   |        | Callback 2: Redeem |------->| (withdrawForSettlement|
|  hub.complete)       |        +--------------------+        |  -> SettlementReady) |
+----------------------+                                      +----------+----------+
           ^                                                             |
           |                    +--------------------+                   |
           +--------------------| Callback 3: Settle |<------------------+
                                +--------------------+
```

### 1. Base Sepolia (Spending Side)
- `PaymentRequestHub`: Merchant entry point. Emits `PaymentRequested(requestId, account, merchant, token, amount, deadline)`.
- `ZeroFloatAccount` & `ZeroFloatFactory`: CREATE2 deterministic user smart wallets.
- `FloatPool`: Liquidity pool that advances credit instantly upon reactive callback.
- `FloatCallbackReceiver`: Authorized receiver for Reactive Omni callbacks.
- `PolicyRegistry`: EIP-712 spend policy validations.

### 2. Unichain Sepolia (Yield Side)
- `SavingsVault`: ERC-4626 vault compounding user deposits via mock yield strategy.
- `VaultGateway`: Callback receiver processing authorized redemptions for settlement.

### 3. Reactive Omni (Coordination Engine)
- `ZeroFloatReactive`: Subscribes to events across Base and Unichain, orchestrating autonomous multi-step callbacks without centralized keepers or cron jobs.
