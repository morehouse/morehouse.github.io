---
layout: post
title: "LND's Deadline-Aware Budget Sweeper"
description: "Discussion about the benefits of LND's new approach to fee bumping commitment and HTLC transactions."
additional_authors: and Yong Yu
modified: 2025-03-11
tags: [lightning, security, lnd]
categories: [lightning]
image:
    feature: lnd_deadline_aware_budget_sweeper_header.png
---

Starting with [v0.18.0](https://github.com/lightningnetwork/lnd/releases/tag/v0.18.0-beta), LND has a completely rewritten *sweeper* subsystem for managing transaction batching and fee bumping.
The new sweeper uses HTLC deadlines and fee budgets to compute a *fee rate curve* over which urgent transactions are fee bumped.
This new fee bumping strategy has some nice security benefits and is something other Lightning implementations should consider adopting.

# Background

When an unreliable (or malicious) Lightning node goes offline while HTLCs are in flight, the other node in the channel can no longer claim the HTLCs *off chain* and will eventually have to force close and claim the HTLCs *on chain*.
When this happens, it is critical that all HTLCs are claimed before certain deadlines:

- Incoming HTLCs need to be claimed before their timelocks expire and the channel counterparty can submit a competing timeout claim.
- Outgoing HTLCs need to be claimed before their corresponding upstream HTLCs expire and the upstream node can reclaim them on chain.

If HTLCs are not claimed before their deadlines, they can be entirely lost (or stolen).

Thus Lightning nodes need to pay enough transaction fees to ensure timely confirmation of their commitment and HTLC transactions.
At the same time, nodes don't want to *overpay* the fees, as these fees can become a major cost for node operators.

The solution implemented by all Lightning nodes is to start with a relatively low fee rate for these transactions and then use RBF to increase the fee rate as deadlines get closer.

# RBF Strategies

Each node implementation uses a slightly different algorithm for choosing RBF fee rates, but in general there's two main strategies:

- external fee rate estimators
- exponential bumping

## External Fee Rate Estimators

This strategy chooses fee rates based on Bitcoin Core's (or some other) fee rate estimator.
The estimator is queried with the HTLC deadline as the confirmation target, and the returned fee rate is used for commitment and HTLC transactions.
Typically the estimator is requeried every block to update fee rates and RBF any unconfirmed transactions.

[CLN](https://github.com/ElementsProject/lightning/blob/b5eef8af4db9f2a58f435bb5beb54299b2800e67/lightningd/chaintopology.c#L419-L440) and [LND](https://github.com/lightningnetwork/lnd/blob/f8211a2c3b3d2112159cd119bd7674743336c661/sweep/sweeper.go#L470-L493) prior to v0.18.0 use this strategy exclusively.
[eclair](https://github.com/ACINQ/eclair/blob/95bbf063c9283b525c2bf9f37184cfe12c860df1/eclair-core/src/main/scala/fr/acinq/eclair/channel/publish/ReplaceableTxPublisher.scala#L221-L248) uses this strategy until deadlines are within 6 blocks, after which it switches to exponential bumping.
[LDK](https://github.com/lightningdevkit/rust-lightning/blob/3a5f4282468e6148e592e324c2a72405bdb4b193/lightning/src/chain/package.rs#L1361-L1369) uses a combined strategy that sometimes uses the fee rate from the estimator and other times uses exponential bumping.

## Exponential Bumping

In this strategy, the fee rate estimator is used to determine the initial fee rate, after which a fixed multiplier is used to increase fee rates for each RBF transaction.

[eclair](https://github.com/ACINQ/eclair/blob/95bbf063c9283b525c2bf9f37184cfe12c860df1/eclair-core/src/main/scala/fr/acinq/eclair/channel/publish/ReplaceableTxPublisher.scala#L221-L248) uses this strategy when deadlines are within 6 blocks, increasing fee rates by 20% each block.
When [LDK](https://github.com/lightningdevkit/rust-lightning/blob/3a5f4282468e6148e592e324c2a72405bdb4b193/lightning/src/chain/package.rs#L1361-L1369) uses this strategy, it increases fee rates by 25% on each RBF.

## Problems

While external fee rate estimators can be helpful, they're not perfect.
And relying on them too much can lead to missed deadlines when unusual things are happening in the mempool or with miners (e.g., increasing mempool congestion, pinning, replacement cycling, miner censorship).
In such situations, higher-than-estimated fee rates may be needed to actually get transactions confirmed.
Exponential bumping strategies help here but can still be ineffective if the original fee rate was too low.

# The Deadline and Budget Aware RBF Strategy

LND's new sweeper subsystem, released in v0.18.0, takes a novel approach to RBFing commitment and HTLC transactions.
The system was designed around a key observation: for each HTLC on a commitment transaction, there are specific *deadline* and *budget* constraints for claiming that HTLC.
The **deadline** is the block height by which the node needs to confirm the claim transaction for the HTLC.
The **budget** is the maximum absolute fee the node operator is willing to pay to sweep the HTLC by the deadline.
In practice, the budget is likely to be a fixed proportion of the HTLC value (i.e. operators are willing to pay more fees for larger HTLCs), so LND's budget [configuration parameters](https://docs.lightning.engineering/lightning-network-tools/lnd/sweeper) are based on proportions.

The sweeper operates by aggregating HTLC claims with matching deadlines into a single batched transaction.
The budget for the batched transaction is calculated as the sum of the budgets for the individual HTLCs in the transaction.
Based on the transaction budget and deadline, a **fee function** is computed that determines how much of the budget is spent as the deadline approaches.
By default, a linear fee function is used which starts at a low fee (determined by the minimum relay fee rate or an external estimator) and ends with the total budget being allocated to fees when the deadline is one block away.
The initial batched transaction is published and a "fee bumper" is assigned to monitor confirmation status in the background.
For each block the transaction remains unconfirmed, the fee bumper broadcasts a new transaction with a higher fee rate determined by the fee function.

The sweeper architecture looks like this:

![channel funding diagram](/images/lnd_deadline_aware_budget_sweeper_header.png)

For more details about LND's new sweeper, see the [technical documentation](https://github.com/lightningnetwork/lnd/blob/master/sweep/README.md).
In this blog post, we'll focus mostly on the sweeper's deadline and budget aware RBF strategy.

## Benefits

### Replacement Cycling Defense

### Partial Pinning Defense

### Reduced Reliance on Feerate Estimators

### LND-Specific Bug and Vulnerability Fixes

#### Fee Bump Failures

#### Invalid Batching

## Risks

Discuss the riskiness of changing this security-critical code.
Point to the many bugs introduced and fixed during the process.

# Conclusion

Summary and call-to-action for other implementations to consider adopting an RBF strategy similar to LND's.
