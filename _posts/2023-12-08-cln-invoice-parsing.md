---
layout: post
title: "Invoice Parsing Bugs in CLN"
description: "Discussion of several invoice parsing bugs discovered in CLN"
modified: 2023-12-08
tags: [lightning, security, cln]
categories: [lightning]
image:
    feature: cln_invoice_parsing.png
---

Several invoice parsing bugs were fixed in [CLN 23.11](https://github.com/ElementsProject/lightning/releases/tag/v23.11), including bugs that caused crashes, undefined behavior, and use of uninitialized memory.
These bugs could be reliably triggered by specially crafted invoices, enabling a
malicious counterparty to crash the victim's node upon invoice payment.

The parsing bugs were discovered by a new fuzz test written by [Niklas Gögge](https://github.com/dergoegge) and enhanced by me.

# Bugs fixed in v23.11

| # | | Type | Root Cause | Fix |
|:--|-|:-----|:-----------|:----|
| **1** || undefined behavior | unchecked return value | [eeec529](https://github.com/ElementsProject/lightning/commit/eeec5290316fa78974c4ef5e8cfb7bdf7a08c09c) |
| **2** || use of uninitialized memory | missing check for 0-length TLV | [ee501b0](https://github.com/ElementsProject/lightning/commit/ee501b035b2e8340476984d0063fda3f954d7f51) |
| **3** || crash | unnecessary assertion | [ee8cf69](https://github.com/ElementsProject/lightning/commit/ee8cf69f281c78d47b838200c690378b0b3918a4) |
| **4** || crash | missing recovery ID validation | [c1f2068](https://github.com/ElementsProject/lightning/commit/c1f20687a6babbd2ded354553936889ebda8f142) |
| **5** || crash | missing pubkey validation | [87f4907](https://github.com/ElementsProject/lightning/commit/87f4907bb40a38e06254ef9b9a3600f58f3a3f5b) |
{: rules="groups"}

# The fuzz target

The fuzz target that uncovered these bugs was [initially written](https://github.com/ElementsProject/lightning/pull/6750) by Niklas Gögge in December 2022, though it wasn't made public until October 2023.
The target simply provides fuzzer-generated inputs to CLN's invoice decoding function, similar to fuzz targets written for other implementations [[1](https://github.com/lightningdevkit/rust-lightning/blob/c2bbfffb1eb249c2c422cf2e9ccac97a34275f7a/fuzz/src/invoice_deser.rs), [2](https://github.com/lightningnetwork/lnd/blob/27319315bb21130f9618877da5d9acda6d6ab453/zpay32/fuzz_test.go#L44-L49)].

To improve the fuzzer's efficiency, Niklas also wrote a custom mutator for the target.
Invoices are encoded in [bech32](https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki) which requires a valid checksum at the end of the encoding, making it quite difficult for fuzzers to generate valid bech32 consistently.
As a result, bech32-naive fuzzers will generally get stuck at the bech32 decoding stage and have a hard time exploring deeper into the invoice parsing logic.
Niklas' custom mutator teaches the fuzzer how to generate valid bech32 so that it can focus its fuzzing on invoice parsing.

## Initial fuzzing in 2022

After writing the fuzz target in December 2022, Niklas privately reported several bugs to CLN including a stack buffer overflow, an assertion failure, and undefined behavior due to a 0-length array.
Many of the bugs were fixed in [PR 5891](https://github.com/ElementsProject/lightning/pull/5891) and released in [CLN 23.02](https://github.com/ElementsProject/lightning/releases/tag/v23.02).

## Merging the fuzz target in 2023

In October 2023, Niklas submitted his fuzz target for review in [PR 6750](https://github.com/ElementsProject/lightning/pull/6750).
The initial corpus in that PR actually triggered bugs 1 and 2, but Niklas didn't notice because he had been fuzzing with some UBSan options misconfigured.
CLN's CI didn't detect the bugs either, since [UBSan](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html) had previously been [accidentally disabled](https://github.com/ElementsProject/lightning/commit/364de0094713ed388daa0fc0de7f18c41d1759f0) in CI.

Niklas also discovered bug 3 during initial fuzzing, but he initially thought it was a false report and hard-coded an exception for it in the fuzz target.

## Enhancements

The initial fuzz target only fuzzed the invoice decoding logic, skipping signature checks.
I [modified](https://github.com/ElementsProject/lightning/commit/4b29502098535f0aa00a46fe5692a2d49bb5ebce) the target to also run the signature-checking logic, which enabled the fuzzer to quickly find bug 4.

While bug 5 should have also been discoverable by the fuzzer after this change, it remained undetected even after many weeks of CPU time.
It wasn't until I added a [custom cross-over mutator](https://github.com/ElementsProject/lightning/pull/6805) for the fuzz target that bug 5 was discovered.
The cross-over mutator is based on Niklas' custom mutator and simply combines pieces from multiple bech32-decoded invoices before re-encoding the result in bech32.
Within a few CPU hours of fuzzing with this extra mutator, the fuzzer found bug 5.

# Impact

The severity of these bugs seems relatively low since they can only be triggered when paying an invoice.
If a malicious invoice causes your node to crash, as long as you can restart your node in a timely manner and avoid paying any more invoices from the malicious counterparty, no further harm can be done.

Since bug 2 involves uninitialized memory it could potentially be more serious, as a sophisticated attacker *may* be able to extract sensitive data from the invoice-decoding process.
Such an attack would be quite complex, and it is unclear whether it would even be possible in practice.
It's also unclear exactly what sensitive data could be extracted, since CLN handles private keys in a separate dedicated process (the `hsmd` daemon).

# Takeaways

- Fuzz testing is an essential component of writing robust and secure software.  Any API that consumes untrusted inputs should be fuzz tested.
- Custom mutators can be very powerful for fuzzing deeper logic in the codebase.
- Fuzz testing of C or C++ code should use both ASan *and* UBSan.  MSan and valgrind can also be useful.
