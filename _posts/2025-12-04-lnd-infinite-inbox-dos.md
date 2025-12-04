---
layout: post
title: "LND: Infinite Inbox DoS"
description: "Discussion of an LND DoS vulnerability from large incoming message queues."
modified: 2025-12-04
tags: [lightning, security, dos, lnd]
categories: [lightning]
image:
    feature: lnd_infinite_inbox_dos_header.png
---

LND 0.18.5 and below are vulnerable to a denial-of-service (DoS) attack that causes LND to run out of memory (OOM) and crash or hang.
Users should upgrade to at least [LND 0.19.0](https://github.com/lightningnetwork/lnd/releases/tag/v0.19.0-beta) to protect their nodes.

## The Infinite Inbox Vulnerability

When LND receives a message from one of its peers, a dedicated dispatcher thread queues the message for processing by the appropriate subsystem.
For two such subsystems (the gossiper and the channel link), up to 1,000 messages could be queued per peer.
Since Lightning protocol messages can be up to 64 KB in size, and since LND allowed as many peers as there were available file descriptors, memory could be exhausted quickly.

## The DoS Attack

A simple, free way to exploit the vulnerability was to open multiple connections to the victim and spam [`query_short_channel_ids`](https://github.com/lightning/bolts/blob/master/07-routing-gossip.md#the-query_short_channel_idsreply_short_channel_ids_end-messages) messages of size 64 KB, keeping the connections open until LND ran out of memory.

In my experiments against an LND node with 8 GB of RAM, I was able to cause an OOM in under 5 minutes.

## The Mitigation

The vulnerability was mitigated by reducing queue sizes and [introducing](https://github.com/lightningnetwork/lnd/pull/9458) a new "peer access manager" to limit peer connections.
Starting in [LND 0.19.0](https://github.com/lightningnetwork/lnd/releases/tag/v0.19.0-beta), queue sizes are reduced to 50 messages and no more than 100 connections are allowed from peers without open channels.

## Discovery

This vulnerability was discovered while examining how LND handles various peer messages.

### Timeline

- **2023-09-15:** Vulnerability reported to the LND security mailing list.
- **2025-03-12:** Mitigation [merged](https://github.com/lightningnetwork/lnd/pull/9458).
- **2025-05-22:** LND 0.19.0 released containing the fix.
- **2025-10-31:** Agreement on public disclosure after LND 0.20.0 is released.
- **2025-12-04:** Public disclosure.

## Takeaways

- More investment in Lightning security is needed.
- Users should keep their node software updated.
