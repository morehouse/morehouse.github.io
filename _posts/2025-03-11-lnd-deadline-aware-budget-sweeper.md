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

Synopsis

# Background

Rundown of why RBFing is important for getting commitments and HTLC claims confirmed.

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
