# 🔱 AutoStakeHub 🥩

**Autonomous Decentralized Staking Protocol on Stacks**

---

## 💡 Overview

`AutoStakeHub` is a fully autonomous and decentralized smart contract built on the Stacks blockchain, designed to manage community staking of the native STX token. It implements a robust, time-locked staking mechanism that rewards users based on their staked amount and chosen lock-up duration, offering different Annual Percentage Yield (APY) tiers to incentivize long-term commitment.

The protocol features automated reward calculations, a transparent claim mechanism, a mandatory lock-in period, and a mechanism for **early withdrawal with a defined penalty**. Furthermore, it introduces an innovative `compound-stake-with-tier-upgrade` function, allowing stakers to reinvest their rewards and potentially upgrade their APY tier by extending their lock-up period, thereby maximizing capital efficiency and compounding returns.

### Key Features

* **Time-Locked Tiers:** Flexible lock periods (30, 90, 180, 365 days) corresponding to escalating APY rates.
* **Decentralized Rewards:** Rewards are calculated continuously based on block height, stake amount, and APY tier.
* **Early Withdrawal Penalty:** A $\mathbf{20\%}$ penalty is applied to the principal for any withdrawal before the lock period expires, reinforcing commitment. The penalty is directed to the contract's reward pool.
* **Compounding & Tier Upgrade:** Users can compound their pending rewards back into their stake, simultaneously selecting a new, longer lock-up period to benefit from a higher APY tier.
* **Emergency Controls:** Owner-only functions for funding the reward pool and toggling an `emergency-pause` mechanism for security.
* **Transparent Accounting:** Read-only functions provide full visibility into individual stake details and protocol-wide statistics.

---

## ⚙️ Contract Constants & Configuration

The protocol's economics and operational parameters are defined by the following constants:

| Constant | Value | Description |
| :--- | :--- | :--- |
| `tier-30-days` | `u30` | Minimum lock period (in days). |
| `tier-365-days` | `u365` | Maximum lock period (in days). |
| `apy-30-days` | `u500` | $5.00\%$ APY (500 basis points). |
| `apy-365-days` | `u2000` | $20.00\%$ APY (2000 basis points). |
| `basis-points` | `u10000` | Used for percentage calculations ($100\%$). |
| `blocks-per-day` | `u144` | Approximate average number of Stacks blocks per day. |
| `early-withdrawal-penalty` | `u2000` | $20\%$ penalty on principal for early unstaking (2000 basis points). |

### Error Codes

| Code | Constant | Description |
| :--- | :--- | :--- |
| `u200` | `err-owner-only` | Function restricted to the contract owner. |
| `u201` | `err-not-found` | Staking entry for the principal was not found. |
| `u202` | `err-already-staked` | Sender already has an active stake. (Protocol only allows one active stake per user). |
| `u204` | `err-lock-period-active` | Lock period is either active (for `unstake`) or expired (for `emergency-unstake`). |
| `u205` | `err-no-rewards` | No pending rewards to claim or compound. |
| `u207` | `err-invalid-tier` | Lock-up period does not match a valid tier or is invalid for compounding. |
| `u209` | `err-calculation-error` | An internal calculation resulted in an unexpected error (e.g., overflow). |

---

## 🔒 Private Functions (Internal Logic)

Private functions are **internal helpers** that cannot be called directly by external accounts or contracts. They encapsulate core business logic, validation, and calculation routines, making the public interface cleaner and more secure.

### `get-tier-apy`

**(private view: `(get-tier-apy (lock-days uint))` )**

Determines the corresponding Annual Percentage Yield (APY) in basis points for a given lock-up duration, based on the defined tier constants.

* **Parameters:** `lock-days` (`uint`) - The proposed lock-up period (e.g., `u90`).
* **Returns:** `uint` - The APY value (e.g., `u1000` for 10% APY). Returns `u0` if the days don't match a tier.

### `is-valid-tier`

**(private view: `(is-valid-tier (lock-days uint))` )**

Performs validation to check if the provided lock duration matches one of the protocol's configured staking tiers.

* **Parameters:** `lock-days` (`uint`) - The lock-up period to check.
* **Returns:** `bool` - `true` if it's a valid tier (30, 90, 180, or 365 days), `false` otherwise.

### `calculate-rewards-internal`

**(private view: `(calculate-rewards-internal (staker principal))` )**

The core calculation logic. It determines the pending rewards for a specific staker since their `last-claim-block` based on their staked amount, APY tier, and the number of blocks passed.

* **Parameters:** `staker` (`principal`) - The address of the staker.
* **Returns:** `(ok uint)` - The calculated reward amount. Returns `(ok u0)` if no stake is found.

### `is-lock-expired`

**(private view: `(is-lock-expired (staker principal))` )**

Checks the current block height against the stake's `start-block` and `lock-period-days` to determine if the mandatory lock-up period has completed.

* **Parameters:** `staker` (`principal`) - The address of the staker.
* **Returns:** `bool` - `true` if the lock period has expired, `false` otherwise.

---

## 📚 Public Functions (Interface)

### `stake`

**(public fn: `(stake (amount uint) (lock-days uint))` )**

Initiates a new staking deposit.

* **Returns:** `(ok true)` on success.

### `claim-rewards`

**(public fn: `(claim-rewards)` )**

Calculates and distributes all pending rewards to the staker, updating the `last-claim-block`.

* **Returns:** `(ok uint)` the amount of rewards claimed.

### `unstake`

**(public fn: `(unstake)` )**

Withdraws principal and rewards **after** the lock period has expired.

* **Returns:** `(ok uint)` the total amount returned (principal + rewards).

### `emergency-unstake`

**(public fn: `(emergency-unstake)` )**

Withdraws principal **before** lock expiry with a $\mathbf{20\%}$ penalty, which is added to the `reward-pool`. Rewards are forfeited.

* **Returns:** `(ok uint)` the penalty-adjusted principal returned.

### `compound-stake-with-tier-upgrade` 🚀

**(public fn: `(compound-stake-with-tier-upgrade (additional-lock-days uint))` )**

Reinvests pending rewards, calculates a new principal, resets the lock timer, and potentially upgrades the APY tier.

* **Returns:** `(ok { ... })` a tuple summarizing the compounding action.

---

## 🛠️ Administrative Functions

These functions are strictly restricted to the `contract-owner`.

### `fund-reward-pool`

**(public fn: `(fund-reward-pool (amount uint))` )**

Allows the contract owner to manually add STX to the protocol's reward pool.

### `toggle-emergency-pause`

**(public fn: `(toggle-emergency-pause)` )**

Toggles the `emergency-pause` flag, blocking state-mutating functions for security.

---

## 🔍 Read-Only Functions (Auditing & Interface)

These functions provide essential data retrieval and calculation utilities for external applications.

### `get-stake-info`

**(read-only fn: `(get-stake-info (staker principal))` )**

Retrieves the full stake data recorded for a given principal.

### `calculate-pending-rewards`

**(read-only fn: `(calculate-pending-rewards (staker principal))` )**

Calculates the estimated reward amount accrued since the last claim block.

### `get-protocol-stats`

**(read-only fn: `(get-protocol-stats)` )**

Returns a comprehensive set of global protocol statistics.

### `check-lock-status`

**(read-only fn: `(check-lock-status (staker principal))` )**

Provides a quick check to see if the staker's lock period has expired.

---

## 📐 Reward Calculation Logic

The protocol calculates rewards based on a continuous Annual Percentage Yield (APY) model, distributed per block.

The core reward formula is:

$$\text{Reward} = \frac{\text{Stake Amount} \times \text{APY} \times \text{Blocks Passed}}{\text{Basis Points} \times \text{Total Lock Blocks}}$$

---

## 🤝 Contribution

We welcome community involvement! Please use the GitHub Issues tracker to report any bugs or suggest new features.

### Development Setup

The contract is written in **Clarity**. You will need the [Clarinet CLI](https://docs.stacks.co/clarity/tools/clarinet) to run tests and deploy.

---

## 📜 MIT License

Copyright (c) 2025 AutoStakeHub Protocol Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

**THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.**

---

## ⚠️ Disclaimer

**This contract is for educational and developmental purposes. Use at your own risk.**

The deployment of this contract to a live blockchain network should only occur after a thorough, professional, third-party security audit. The users of this protocol acknowledge the inherent risks associated with smart contracts, including but not limited to, potential bugs, economic exploits, and loss of funds. The contract owner and developers are not liable for any financial losses incurred through the use of this protocol.
