---
layout: post
title: "DoS: Fake Lightning Channels"
description: "Technical analysis of the fake channel DoS vector in the Lightning Network"
modified: 2023-08-23
tags: [lightning, security, dos]
categories: [lightning]
image:
    feature: fake_channel_dos.png
---

Lightning nodes released prior to the following versions are susceptible to a
DoS attack involving the creation of large numbers of fake channels:

- [LND 0.16.0](https://github.com/lightningnetwork/lnd/releases/tag/v0.16.0-beta)
- [CLN 23.02](https://github.com/ElementsProject/lightning/releases/tag/v23.02)
- [eclair 0.9.0](https://github.com/ACINQ/eclair/releases/tag/v0.9.0)
- [LDK 0.0.114](https://github.com/lightningdevkit/rust-lightning/releases/tag/v0.0.114)

If you are running node software older than this, your funds may be at risk!
Update to at least the above versions to help protect your node.

# The vulnerability

When one lightning node (the funder) wishes to open a channel to another node
(the fundee), the following sequence of events takes place:

![channel funding diagram](/images/channel_funding.png)

1. The funder sends an `open_channel` message with the desired parameters for
   the channel.
2. The fundee checks that the channel parameters are reasonable and then sends
   an `accept_channel` message.
3. The funder creates the funding transaction and sends a `funding_created`
   message containing the funding outpoint and their signature for the
   commitment transaction.
4. The fundee verifies the funder's commitment signature and sends
   `funding_signed` with their own signature for the commitment.  The fundee
   begins watching the chain for the funding transaction.
5. The funder verifies the fundee's commitment signature, broadcasts the funding
   transaction, and then watches for it to show up onchain.
6. Both nodes send `channel_ready` once the funding transaction has enough
   confirmations. Payments can now be sent across the channel.

*But what happens if the funder doesn't broadcast the funding transaction in
step 5?*

![channel funding DoS diagram](/images/channel_funding_dos.png)

The fundee, eager for inbound liquidity, is willing to wait for the
funding transaction to confirm for a period of time. But eventually the fundee
needs to give up on the pending channel and reclaim the resources allocated to
it. BOLT 2 recommends waiting for [2016 blocks](
https://github.com/lightning/bolts/blob/7d3ef5a6b20eb84982ea2bfc029497082adf20d8/02-peer-protocol.md#the-channel_ready-message)
(2 weeks) before abandoning the pending channel.

**Thus for 2 weeks the fundee devotes some amount of database storage, RAM,
and CPU time to watching for the pending channel to confirm.**

# The fake channel DoS attack

An attacker can thus force a victim node to consume a small amount of resources
by opening a fake channel with the victim and never publishing it onchain.  If
the attacker can create lots of fake channels, they can lock up lots of the
victim's resources.

Fake channels are trivial to create.  Since there is no way for the victim
to verify the funding outpoint sent to them in the `funding_created` message,
the attacker doesn't even need to construct a real funding transaction.  They
can use a randomly-generated funding transaction ID and sign a commitment
transaction based on that fake ID.  The victim will successfully verify the
commitment signature against the provided (fake) funding outpoint and gladly
allocate resources for the fake pending channel.

Opening lots of these fake channels is also trivial against node software
older than the above releases. Some older node implementations do impose a
limit on the number of pending channels allowed per peer, but such limits are
easily bypassed by using a new attacker node ID for each fake channel.

# DoS effects

In my experiments, I was able to create hundreds of thousands of fake channels
against victim nodes (owned by me), with all kinds of adverse effects. In some
cases, funds were clearly at risk of being stolen due to the victim node's
inability to respond to cheating attempts.

Here's how the DoS attack affected each node implementation.

## LND

Over the course of a couple days, LND's performance degraded so drastically that
it stopped responding to requests from its peers or from the CLI. The
performance degradation continued on restart, even if the attacker was no longer
actively DoSing.

I didn't continue the DoS experiment for more than a couple days, but it's very
possible that with enough time the victim node would have become unresponsive
enough that funds could be stolen without consequence.

## CLN

After one day of the DoS attack, CLN's `connectd` daemon was completely blocked
and unable to respond to connection requests from other nodes. Most other
functionality of CLN continued to work, and funds were not at risk since the
separate `lightningd` daemon was not blocked by the DoS attack.

## eclair

One day into the DoS, eclair OOM crashed.  After that, every time eclair
restarted, it OOM crashed again within 30 minutes, even if the attacker was no
longer actively DoSing.  Funds were clearly at risk, since an offline node
cannot catch cheating attempts.

## LDK

Since LDK is a library and not a full node implementation, it was trickier to
experiment with.  LDK Node didn't exist at the time, but I found the
[ldk-sample]( https://github.com/lightningdevkit/ldk-sample) node and modified
it to run on mainnet for the experiment.

Within hours of the DoS attack, ldk-sample's performance degraded drastically,
causing it to unsync with the blockchain.  A few days later, ldk-sample's view
of the blockchain was pinned more than 144 blocks in the past, preventing it
from responding to cheating attempts before the attacker's CSV timelock
expired.

# DoS defenses

I reported the DoS vector to the 4 major lightning implementations around
the start of 2023. eclair and LDK were already aware of the potential DoS
vector but hadn't realized the severity of the vulnerability. Within days of
receiving my report, every lightning implementation began working on defenses,
some openly and others in secret.

All implementations have now shipped releases with defenses against the DoS.  If
you're interested in the technical details of the defenses, see the linked pull
requests and commits.

| Date Reported | Implementation | Defenses                     | Release | 
|:--------------|:---------------|:-----------------------------|:--------|
| 2022-12-12    | LND    | pending channel limit [[1](https://github.com/lightningnetwork/lnd/commit/3f6315242a7ceb160c12f6997f5c020362424877)] | 0.16.0  | 
| 2022-12-15    | CLN    | significant performance improvements [[1](https://github.com/ElementsProject/lightning/pull/5837), [2](https://github.com/ElementsProject/lightning/pull/5849)] | 23.02   | 
| 2022-12-28    | eclair | pending channel and peer limits [[1](https://github.com/ACINQ/eclair/pull/2552), [2](https://github.com/ACINQ/eclair/pull/2601)] | 0.9.0   | 
| 2023-01-17    | LDK    | pending channel and peer limits [[1](https://github.com/lightningdevkit/rust-lightning/pull/1988)]      | 0.0.114 | 
{: rules="groups"}

# Lessons

## Use watchtowers

When all else fails, watchtowers help to protect funds if your lightning node is
incapacitated by a DoS attack.  If you have significant funds at risk, it's
cheap insurance to run a private watchtower on a separate machine.

## Multiple processes

Prior to the above releases, CLN was the only lightning implementation that
clearly kept user funds safe while
under DoS, because CLN actually runs as multiple separate daemon processes. In
the case of this DoS attack, the `connectd` daemon responsible for handling
peer connections became locked up while the `lightningd` daemon watching the
blockchain was relatively unaffected.

Multiprocess architectures in general provide some defense against DoS, as
one process slowing down or crashing doesn't automatically bring down the other
processes.  For this reason, other implementations may want to consider
splitting their nodes into separate processes.  CLN could also improve
robustness further by attempting to restart DoS-able subdaemons like `connectd`
and `gossipd` if they crash, rather than shutting the whole node down.

## More security auditing needed

I discovered this DoS vector last year.  I had been reviewing the dual funding
protocol and found a [griefing
attack](https://github.com/lightning/bolts/pull/851#discussion_r997537630)
involving fake dual-funded channels. After discussing the attack with Bastien
Teinturier, I came to realize that a similar attack may also affect the
single-funded protocol.

But I convinced myself for a couple months that surely such a trivial attack
would have been defended against already.  It wasn't until I spent some time
studying implementations' funding code that I realized there were no defenses.

The fact that this DoS vector went unnoticed since the beginning of the
Lightning Network should make everyone a little scared. If a newcomer like me
could discover this vulnerability in a couple months, there are probably many
other vulnerabilities in the Lightning Network waiting to be found and
exploited.

For quite some time, it seems that security and robustness have not been the
top priority for node implementations, with some implementations not even
having security policies until 6-10 months ago 
[[1](https://github.com/lightningnetwork/lnd/commit/609cc8b883c7e6186e447e8d7e6349688d78d4fd),
[2](https://github.com/ElementsProject/lightning/commit/e29fd2a8e26d655a7fb0f8b1c18092c2cdd787da)].
Everyone wants new lightning
features: dual funded channels, Taproot channels, splicing, BOLT 12, etc.
And those things are important.  But every one of them introduces more
complexity and more potential attack surface.  If we're going to make lightning
even more complex, we also need to ramp up the engineering effort we put towards
making the network secure and robust.

Because in the end it doesn't matter how feature-rich and easy-to-use the
Lightning Network is if it can't keep user funds safe.
