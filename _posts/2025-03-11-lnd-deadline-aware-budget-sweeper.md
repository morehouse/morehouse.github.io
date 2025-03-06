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

Strategies used by each implementation, including previous LND strategy.

## Problems

# The Deadline and Budget Aware RBF Strategy

Description of LND's new sweeper strategy, overview of architecture.

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
