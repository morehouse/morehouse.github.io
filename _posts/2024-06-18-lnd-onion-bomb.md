---
layout: post
title: "DoS: LND Onion Bomb"
description: "Discussion of an OOM bug in LND that can be exploited for DoS"
modified: 2024-06-18
tags: [lightning, security, dos, lnd]
categories: [lightning]
image:
    feature: lnd_onion_bomb_header.png
---

LND versions prior to 0.17.0 are vulnerable to a DoS attack where malicious onion packets cause the node to instantly run out of memory (OOM) and crash.
If you are running an LND release older than this, your funds are at risk!
Update to at least [0.17.0](https://github.com/lightningnetwork/lnd/releases/tag/v0.17.0-beta) to protect your node.

# Severity

It is critical that users update to at least LND 0.17.0 for several reasons.

- The attack is cheap and easy to carry out and will keep the victim offline for as long as it lasts.
- The source of the attack is concealed via onion routing.  The attacker does not need to connect directly to the victim.
- Prior to LND 0.17.0, all nodes are vulnerable.  The fix was not backported to the LND 0.16.x series or earlier.

# The Vulnerability

The Lightning Network uses [onion routing](https://en.wikipedia.org/wiki/Onion_routing) to provide senders and receivers of payments some degree of privacy.
Each node along a payment route receives an *onion packet* from the previous node, containing forwarding instructions for the next node on the route.
The onion packet is encrypted by the initiator of the payment, so that each node can only read its own forwarding instructions.

Once a node has "peeled off" its layer of encryption from the onion packet, it can extract its forwarding instructions according to the format [specified](https://github.com/lightning/bolts/blob/master/04-onion-routing.md#packet-structure) in the LN protocol:

| Field Name | Size | Description |
|:-----------|:-----|:------------|
| `length` | 1-9 bytes | The length of the `payload` field, encoded as [BigSize](https://github.com/lightning/bolts/blob/master/01-messaging.md#appendix-a-bigsize-test-vectors). |
| `payload` | `length` bytes | The forwarding instructions. |
| `hmac` | 32 bytes | The HMAC to use for the forwarded onion packet. |
| `next_onion` | remaining bytes | The onion packet to forward. | 
{: rules="groups"}

Prior to LND 0.17.0, the [code](https://github.com/lightningnetwork/lightning-onion/blob/ca23184850a16cd14d27619f3afdae543b3857a9/path.go#L231-L281) that extracts these instructions is essentially:

```go
// Decode unpacks an encoded HopPayload from the passed reader into the
// target HopPayload.
func (hp *HopPayload) Decode(r io.Reader) error {
    bufReader := bufio.NewReader(r)

    var b [8]byte
    varInt, err := ReadVarInt(bufReader, &b)
    if err != nil {
        return err
    }

    payloadSize := uint32(varInt)

    // Now that we know the payload size, we'll create a new buffer to
    // read it out in full.
    hp.Payload = make([]byte, payloadSize)
    if _, err := io.ReadFull(bufReader, hp.Payload[:]); err != nil {
        return err
    }
    if _, err := io.ReadFull(bufReader, hp.HMAC[:]); err != nil {
        return err
    }

    return nil
}
```

Note the absence of a bounds check on `payloadSize`!

Regardless of the actual payload size, **LND allocates memory for whatever `length` is encoded in the onion packet up to `UINT32_MAX` (4 GB).**

# The DoS Attack

It is trivial for an attacker to craft an onion packet that contains an encoded `length` of `UINT32_MAX` for the victim's forwarding instructions.
If the victim's node has less than 4 GB of memory available, it will OOM crash instantly upon receiving the attacker's packet.

However, if the victim's node has more than 4 GB of memory available, it is able to recover from the malicious packet.
The victim's node will temporarily allocate 4 GB, but the Go garbage collector will quickly reclaim that memory after decoding fails.

*So nodes with more than 4 GB of RAM are safe, right?*

Not quite.
The attacker can send many malicious packets simultaneously.
If the victim processes enough malicious packets before the garbage collector kicks in, an OOM will still occur.
And since LND decodes onion packets *in parallel*, it is not difficult for an attacker to beat the garbage collector.
In my experiments I was able to consistently crash nodes with up to 128 GB of RAM in just a few seconds.

# The Fix

A bounds check on the encoded `length` field was concealed in a large refactoring [commit](https://github.com/lightningnetwork/lightning-onion/commit/6afc43f3fc983ae37685812de027d0747e136b8f) and included in LND [0.17.0](https://github.com/lightningnetwork/lnd/releases/tag/v0.17.0-beta).
The fixed code is essentially:

```go
// Decode unpacks an encoded HopPayload from the passed reader into the
// target HopPayload.
func (hp *HopPayload) Decode(r io.Reader) error {
    bufReader := bufio.NewReader(r)

    payloadSize, err := tlvPayloadSize(bufReader)
    if err != nil {
        return err
    }

    // Now that we know the payload size, we'll create a new buffer to
    // read it out in full.
    hp.Payload = make([]byte, payloadSize)
    if _, err := io.ReadFull(bufReader, hp.Payload[:]); err != nil {
        return err
    }
    if _, err := io.ReadFull(bufReader, hp.HMAC[:]); err != nil {
        return err
    }

    return nil
}

// tlvPayloadSize uses the passed reader to extract the payload length
// encoded as a var-int.
func tlvPayloadSize(r io.Reader) (uint16, error) {
    var b [8]byte
    varInt, err := ReadVarInt(r, &b)
    if err != nil {
        return 0, err
    }

    if varInt > math.MaxUint16 {
        return 0, fmt.Errorf("payload size of %d is larger than the "+
            "maximum allowed size of %d", varInt, math.MaxUint16)
    }

    return uint16(varInt), nil
}
```

This new code reduces the maximum amount of memory LND will allocate when decoding an onion packet from 4 GB to 64 KB, which is enough to fully mitigate the DoS attack.

# Discovery

A simple [fuzz test](https://github.com/lightningnetwork/lnd/commit/9c51bea7906060bbf7b8dc23cab7d542a610eb10) for onion packet encoding and decoding revealed this vulnerability.

## Timeline

- **2023-06-20:** Vulnerability discovered and disclosed to Lightning Labs.
- **2023-08-23:** Fix [merged](https://github.com/lightningnetwork/lightning-onion/pull/57).
- **2023-10-03:** LND 0.17.0 released containing the fix.
- **2024-05-16:** Laolu gives the OK to disclose publicly once LND 0.18.0 is released and has some uptake.
- **2024-05-30:** LND 0.18.0 released.
- **2024-06-18:** Public disclosure.

# Prevention

This vulnerability was found in less than a minute of fuzz testing.
If basic fuzz tests had been written at the time the original onion decoding functions were introduced, the bug would have been caught before it was merged.

In general any function that processes untrusted inputs is a strong candidate for fuzz testing, and often these fuzz tests are *easier* to write than traditional unit tests.
A minimal fuzz test that detects this particular vulnerability is exceedingly simple:

```go
func FuzzHopPayload(f *testing.F) {
    f.Fuzz(func(t *testing.T, data []byte) {
        // Hop payloads larger than 1300 bytes violate the spec and never
        // reach the decoding step in practice.
        if len(data) > 1300 {
            return
        }

        var hopPayload sphinx.HopPayload
        hopPayload.Decode(bytes.NewReader(data))
    })
}
```

# Takeaways

- Write fuzz tests for all APIs that consume untrusted inputs.
- Update your LND nodes to at least 0.17.0.
