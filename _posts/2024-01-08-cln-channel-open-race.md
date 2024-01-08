---
layout: post
title: "DoS: Channel Open Race in CLN"
description: "Discussion of a race condition in CLN that can be exploited for DoS"
modified: 2024-01-08
tags: [lightning, security, dos, cln]
categories: [lightning]
image:
    feature: cln_channel_open_race_header.png
---

CLN versions between [23.02](https://github.com/ElementsProject/lightning/releases/tag/v23.02) and [23.05.2](https://github.com/ElementsProject/lightning/releases/tag/v23.05.2) are susceptible to a DoS attack involving the exploitation of a race condition during channel opens.
If you are running any version in this range, your funds may be at risk!
Update to at least [23.08](https://github.com/ElementsProject/lightning/releases/tag/v23.08) to help protect your node.

# The Vulnerability

The vulnerability arises from a race condition between two different flows in CLN: the channel open flow and the peer connection flow.

## The Channel Open Flow

When a peer opens a channel with a CLN node, the following interactions occur on the CLN node.

![channel open diagram](/images/cln_channel_open_no_race1.png)

1. The `connectd` daemon notifies `lightningd` about the channel open request.
2. `lightningd` launches a new `openingd` daemon to handle the channel open negotiation.
3. `openingd` completes the channel open negotiation up to the point where the funding outpoint is known.
4. `openingd` sends the funding outpoint to `lightningd` and exits.
5. `lightningd` launches a `channeld` daemon to manage the new channel.

## The Peer Connection Flow

Once a peer has a channel with a CLN node, if the peer disconnects and reconnects the following occurs on the CLN node.

![channel exists diagram](/images/cln_channel_open_no_race2.png)

1. The `connectd` daemon notifies `lightningd` about the new peer connection.
2. `lightningd` calls a plugin hook notifying the `chanbackup` plugin about the new peer connection.
3. `chanbackup` notifies `lightningd` that it is done running the hook.
4. With the hook finished, `lightningd` recognizes that a previous channel exists with the peer and launches a `channeld` daemon to manage it.

## The Race Condition

Problems arise when the peer connection flow overlaps with the channel open flow, causing `lightningd` to attempt launching the same `channeld` daemon twice.
This can happen if the peer quickly opens a channel after connecting, and the `chanbackup` plugin is delayed in handling the peer connection hook, leading to the following interactions on the CLN node.

![channel open race diagram](/images/cln_channel_open_race.png)

1. The `connectd` daemon notifies `lightningd` about the new peer connection.
2. `lightningd` calls a plugin hook notifying the `chanbackup` plugin about the new peer connection.
3. The `connectd` daemon notifies `lightningd` about the channel open request.
4. `lightningd` launches a new `openingd` daemon to handle the channel open negotiation.
5. `openingd` completes the channel open negotiation up to the point where the funding outpoint is known.
6. `openingd` sends the funding outpoint to `lightningd` and exits.
7. `lightningd` launches a `channeld` daemon to manage the new channel.
8. `chanbackup` notifies `lightningd` that it is done running the hook.
9. With the hook finished, `lightningd` recognizes that a previous channel exists with the peer and attempts to launch a `channeld` daemon to manage it. **Since the daemon is already running, an assertion failure occurs and CLN crashes.**

# The DoS Attack

To reliably trigger the assertion failure, an attacker needs to somehow slow down the `chanbackup` plugin so that a channel can be opened before the plugin finishes running the peer connected hook.
One way to do this is to overload `chanbackup` with many peer connections and channel state changes.
As it turns out, the [fake channel DoS attack](/lightning/fake-channel-dos/) is a trivial and free method of generating these events and overloading `chanbackup`.

On a local network with low latency, I was able to generate enough load on `chanbackup` to consistently crash CLN nodes in under 5 seconds.
In the real world the attack would be carried out across the Internet with higher latencies, so more load on `chanbackup` would be required to trigger the race condition.
In my experiments, crashing CLN nodes across the Internet took around 30 seconds.

# The Defense

To prevent the assertion failure from triggering, a [small patch](https://github.com/ElementsProject/lightning/commit/af394244914e69a5b2f16e1f10ef412217f9714a) was added to [CLN 23.08](https://github.com/ElementsProject/lightning/releases/tag/v23.08) that checks if a `channeld` is already running when the peer connected hook returns.
If so, `lightningd` does not attempt to start the `channeld` again.

Note that this patch does not actually remove the race condition, though it does prevent crashing when the race occurs.

# Discovery

This vulnerability was discovered during follow-up testing prior to the [disclosure](https://lists.linuxfoundation.org/pipermail/lightning-dev/2023-August/004064.html) of the fake channel DoS vector.
At the time, Rusty and I agreed to move forward with the planned disclosure of the fake channel DoS vector, but to delay disclosure of this channel open race until a later date.

Since the channel open race can be triggered by the fake channel DoS attack, it is a valid question how the race went undiscovered during the implementation of defenses against that attack.
The answer is that the race was actually untriggerable until a few weeks *after* the fake channel DoS defenses were merged.

While the race condition was [introduced](https://github.com/ElementsProject/lightning/pull/5078) in March 2022, the race couldn't actually trigger because no plugins used the peer connected hook.
It wasn't until February 2023 that the race was exposed, when the [peer storage backup](https://github.com/ElementsProject/lightning/pull/5361) feature made `chanbackup` the first official plugin to use the hook.

## Timeline

- **2022-03-23:** Race condition [introduced](https://github.com/ElementsProject/lightning/pull/5078) to CLN 0.11.
- **2022-12-15:** Fake channel DoS vector disclosed to Blockstream.
- **2023-01-21:** Fake channel DoS defenses fully merged [[1](https://github.com/ElementsProject/lightning/pull/5837), [2](https://github.com/ElementsProject/lightning/pull/5849)].
- **2023-02-08:** Peer storage backup feature [introduced](https://github.com/ElementsProject/lightning/pull/5361), exposing the channel open race vulnerability.
- **2023-03-03:** CLN 23.02 released.
- **2023-07-28:** Rusty gives the OK to disclose the fake channel DoS vector.
- **2023-08-14:** Follow-up testing reveals the channel open race vulnerability. Disclosed to Blockstream.
- **2023-08-21:** Defense against the channel open race DoS [merged](https://github.com/ElementsProject/lightning/commit/af394244914e69a5b2f16e1f10ef412217f9714a).
- **2023-08-22:** Rusty gives the OK to continue with the fake channel DoS disclosure, but requests that the channel open race vulnerability be omitted from the disclosure.
- **2023-08-23:** [Public disclosure](https://lists.linuxfoundation.org/pipermail/lightning-dev/2023-August/004064.html) of the fake channel DoS.
- **2023-08-23:** CLN 23.08 released.
- **2023-12-04:** Rusty gives the OK to disclose the channel open race vulnerability.
- **2024-01-08:** Public disclosure.

# Prevention

This vulnerability could have been prevented by a couple software engineering best practices.

## Avoid Race Conditions

The [original purpose](https://github.com/ElementsProject/lightning/pull/2341) of the peer connected hook was to enable plugins to filter and reject incoming connections from certain peers.
Therefore the hook was designed to be *synchronous*, and all other events initiated by the peer were blocked until the hook returned.
Unfortunately, [PR 5078](https://github.com/ElementsProject/lightning/pull/5078) destroyed that property of the hook by introducing a *known* race condition to the code (search for "this is racy" in commit [2424b7d](https://github.com/ElementsProject/lightning/commit/2424b7dea899e11b33ee4da9f95836e058db4a0c)).
If PR 5078 hadn't done this, there would be no race condition to exploit and this vulnerability would never have existed.

Race conditions can be nasty and should be avoided whenever possible.
Knowingly adding race conditions where they didn't previously exist is generally a bad idea.

## Do Stress Testing

When I disclosed the fake channel DoS vector to Blockstream, I also provided a DoS program that demonstrated the attack.
That same DoS program revealed the channel open race vulnerability after it became triggerable in February 2023.
If a stress test based on the DoS program had been added to CLN's CI pipeline or release process, this vulnerability could have been caught much earlier, before it was included in any releases.

In general, there is some difficulty in releasing such a test publicly while the vulnerability it tests for is still secret.
In such situations the test can remain unreleased until the vulnerability has been publicly disclosed, and in the meantime the test can be run privately during the release process to ensure no regressions have been introduced.
In CLN's case, this may have been unnecessary -- a stress test could have plausibly been added to [PR 5849](https://github.com/ElementsProject/lightning/pull/5849) without raising suspicion.

# Takeaways

- Avoid race conditions.
- Use regression and stress testing.
- Update your CLN nodes to at least v23.08.
