# Cross-Chain Latency Benchmarks & Proofs

## Performance Model: "Every Second Counts"

In traditional cross-chain setups, asynchronous relayers and long block times (such as 7–12 second L1/L2 intervals) make sub-10-second checkout deadlines impossible. 

Zero-Float Wallet leverages:
1. **Base Sepolia:** 200 ms block times (fast local settlement and instant inclusion).
2. **Reactive Omni:** CometBFT consensus with ~1-second block times and instant finality.
3. **Autonomous Callbacks:** No off-chain keepers or relayers; execution is guaranteed natively by Reactive Network.

---

## Simulated Execution Latency (Block 6 Core Loop)

| Hop | From | To | Operation | Elapsed (s) | Cumulative (s) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Hop 0 (Origin)** | Merchant EOA | Base Sepolia | `requestPayment()` emitted | 0.20s | 0.20s |
| **Hop 1 (Observe)** | Base Sepolia | Reactive Omni | Reactive VM intercepts event | 1.00s | 1.20s |
| **Hop 2 (React)** | Reactive Omni | Reactive Omni | `react()` decodes and emits callback | 0.05s | 1.25s |
| **Hop 3 (Callback)** | Reactive Omni | Base Sepolia | Proxy invokes `frontCallback()` | 1.00s | 2.25s |
| **Hop 4 (Complete)** | Base Sepolia | Base Sepolia | Funds fronted & merchant paid | 0.20s | **2.45s** |

> **Result:** The full reactive loop completes in approximately **2.45 seconds**, fitting comfortably inside a 5–10 second merchant deadline window.

---

## Live On-Chain Latency Evidence (Pending Testnet Runs)

| Run ID | Request ID | Origin Tx (Base) | Reactive Tx (Omni) | Callback Tx (Base) | Measured Latency | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| #01 | Pending | Pending | Pending | Pending | ~2.5s | Target |
