---
layout: post
title: "LND: Replacement Stalling Attack"
description: "Discussion of weaknesses in LND's sweeper system that can be exploited to steal funds."
modified: 2025-12-04
tags: [lightning, security, theft, lnd]
categories: [lightning]
image:
    feature: lnd_replacement_stalling_attack_header.png
---

A vulnerability in LND versions 0.18.5 and below allows attackers to steal node funds.
Users should immediately upgrade to [LND 0.19.0](https://github.com/lightningnetwork/lnd/releases/tag/v0.19.0-beta) or later to protect their funds.

## Background

LND has a [*sweeper* subsystem](/lightning/lnd-deadline-aware-budget-sweeper/) for managing transaction batching and fee bumping.
When a Lightning channel is force closed, the sweeper kicks into action, collecting HTLC inputs into batched claim transactions to save on mining fees.
The sweeper then periodically bumps the fees paid by those transactions until the transactions confirm.

It is critical that the sweeper gets certain HTLC transactions confirmed before the corresponding upstream HTLCs expire, or else the value of those HTLCs can be completely lost.
For this reason, a fairly aggressive default fee-bumping strategy is used, and as upstream HTLC deadlines approach, the sweeper is willing to spend up to half the value of those HTLCs in mining fees.

## Sweeper Weaknesses

LND's aggressive fee bumping could be thwarted, however, due to a couple weaknesses in the sweeper.

### Fee Resets on Reaggregation

If an input to a batched transaction was double-spent by someone else, the sweeper would regroup the remaining inputs into a new transaction and [*reset the fees paid*](https://github.com/lightningnetwork/lnd/issues/9422) by that transaction to the minimum value of the fee function.
If this happened many times, the sweeper would end up broadcasting transactions with much lower fees than intended, and upstream deadlines could be missed.

### Broadcast Delays

Additionally, the regrouping of inputs after a double spend would be delayed until the [*next* block confirmed](https://github.com/lightningnetwork/lnd/pull/8717#issuecomment-2099089198).
So if lots of double spends happened, the sweeper would miss out on 50% of the available opportunities to get its time-sensitive transactions confirmed.
Once again, this could cause upstream deadlines to be missed and funds to be lost.

## A Basic Replacement Stalling Attack

An attacker could take advantage of these sweeper weaknesses to steal funds.
The basic idea is to cause the sweeper to batch many HTLC inputs together, then repeatedly double spend those inputs, causing the sweeper to keep regrouping the remaining inputs into new transactions.
Each double spend prevents the sweeper's transaction from confirming for at least 2 blocks, while also resetting the fees paid by the next sweeper transaction to the minimum, so future double spends remain cheap.
After upstream HTLC timelocks expire, all remaining HTLCs could be stolen.

An attack would look like this:

1. The attacker opens a direct channel to the victim and routes ~40 HTLCs to themselves through the victim, using the minimum CLTV delta the victim allows (80 blocks by default).  The attacker intends to steal the last HTLC, so they make that one as large as possible.
2. The attacker holds the HTLCs until they expire and the victim force closes the channel to reclaim them.  At this point, the 80-block countdown to the upstream deadline starts, and the attacker needs to stall the victim for that long to steal funds.
3. Because all 40 of the attacker's HTLCs have the same upstream deadline, the victim's sweeper batches all 40 HTLC-Timeouts into a single transaction and broadcasts it.
4. The attacker sees the batched transaction in their mempool and immediately replaces the transaction with a preimage spend for one of the 40 HTLCs.
5. The double-spend confirms, and the victim is able to extract the HTLC preimage and settle the corresponding upstream HTLC, but the remaining 39 HTLC-Timeouts are not reaggregated until *another* block confirms (see the section "Broadcast Delays" above).
6. Another block confirms, and the victim broadcasts a new transaction containing the remaining HTLC-Timeouts.  The fees for this transaction are reset to the minimum value of the fee function.  The attacker repeats the process from Step 4, double-spending a new HTLC each time until the upstream deadline has passed.
7. The attacker steals the remaining HTLC(s) by claiming the preimage path downstream and the timeout path upstream.

### Attack Cost

In the worst case for the attacker, they must do ~40 replacements, each spending more total fees than the replaced batched transaction.
We can calculate the fees of each batched HTLC-Timeout transaction as `size * feerate`, where `size` and `feerate` are estimated as follows:

- `size`: `num_htlcs * 166.5 vB`
- `feerate`: minimum value of LND's fee function.  By default, this is the value returned by bitcoind's `estimatesmartfee` RPC. 

Today, `estimatesmartfee` returns feerates between 0.7 sat/vB and 2.1 sat/vB depending on the confirmation target.
To simplify calculations, we assume an average feerate of 1.4 sat/vB over the course of the attack.
We also assume on average there are 20 HTLCs present on the batched transaction, since it starts with 40 HTLCs and decreases by 1 every 2 blocks until a single HTLC remains.
With these simplifying assumptions, we get a rough cost as follows:

- average cost per replacement:  `20 HTLCs * 166.5 vB/HTLC * 1.4 sat/vB = 4,662 sat`
- total attack cost: `40 replacements * 4,662 sat/replacement = 186,480 sat`

**So for less than 200k sats, the attacker can steal essentially the entire channel capacity.**

### Optimizations

In practice, the cost of the attack is even less, since the attacker's double spends may not confirm in the first available block, which means fewer than 40 double spends actually need to confirm.
The attacker can also intentionally reduce the probability of confirmation by inflating the size of their double-spend transactions to the maximum possible while still replacing the victim's transactions.

Additionally, a smart attacker, knowing they need fewer double spends to confirm, can reduce the number of HTLCs they route at the start of the attack.
As a result, the victim's batched transactions become smaller and the attacker can save on replacement fees. 

For example, suppose the attacker can stall for 80 blocks with only 30 double spends.
Then the cost of the attack is reduced by over 40%:

- average cost per replacement: `15 HTLCs * 166.5 vB/HTLC * 1.4 sat/vB = 3,497 sat`
- total attack cost: `30 replacements * 3,497 sat/replacement = 104,910 sat`

## Mitigation

[Changes](https://github.com/lightningnetwork/lnd/pull/9447) were made in [LND 0.19.0](https://github.com/lightningnetwork/lnd/releases/tag/v0.19.0-beta) that eliminated the reaggregation delay and the fee function reset.

These changes, combined with the sweeper's aggressive default fee function, ensure that any replacement stalling attack costs many times more than the amount that can be stolen.

## Discovery

This attack vector was discovered during code review of LND's sweeper rewrite in May 2024.

### Timeline

- **2024-05-09:** Attack vector reported to the LND security mailing list.
- **2025-01-16:** No progress on a mitigation.  Reported the fee reset weakness [publicly](https://github.com/lightningnetwork/lnd/issues/9422) and followed up on the security mailing list. 
- **2025-02-21:** Mitigation [merged](https://github.com/lightningnetwork/lnd/pull/9447).
- **2025-05-22:** LND 0.19.0 released containing the fix.
- **2025-10-31:** Agreement to disclose publicly after LND 0.20.0 was released.
- **2025-12-04:** Public disclosure.

## Prevention

This vulnerability was introduced during LND's sweeper rewrite in May 2024, and I reported it before LND 0.18.0 was released containing the vulnerability.
In my report, I suggested that the new sweeper be released in 0.18.0 and this vulnerability be fixed in 0.18.1, since a mitigation would require some work and the new sweeper already fixed several [other vulnerabilities](/lightning/lnd-deadline-aware-budget-sweeper/).
Unfortunately that didn't happen, and this vulnerability went unaddressed until I followed up again in 2025.

In hindsight, I should have done a better job at keeping the LND team accountable.
I could have reported the vulnerability publicly, thereby forcing the issue to be addressed before the 0.18.0 release.
The downside is that this would have delayed other important security fixes to the sweeper subsystem.

Alternatively, I could have reported the vulnerability privately (as I did) but given the LND team a deadline (say, 6 months) after which I would disclose the vulnerability publicly regardless of whether they mitigated it.
This may have applied enough pressure to get the issue fixed in 0.18.1 as I originally intended.

## Takeaways

- Set disclosure deadlines to improve security outcomes.
- Users should keep their node software updated.
