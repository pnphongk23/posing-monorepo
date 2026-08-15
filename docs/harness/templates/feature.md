---
schema_version: 1
type: feature
id: FEAT-000
title: Confirm an online order
status: draft
created: 2026-01-01
relationships:
  specs:
    - "[[api-overview]]"
  decisions: []
  plans: []
  reports: []
  rules: []
  features: []
  source_paths:
    - src/orders.ts
---

# FEAT-000: Confirm an online order

## Introduction

**Purpose:** Let a shopper confirm a valid basket and receive an order reference.

**In scope:** Confirmation of an in-stock basket with a supported delivery address.

**Out of scope:** Payment settlement and warehouse fulfilment.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Shopper | Business role | Place the intended order | Review and confirm basket details |
| Payment provider | External system | Authorize the purchase amount | Return an authorization outcome |

### User needs

- The shopper needs a stable order reference after one successful confirmation.

### Preconditions

- The basket contains at least one available item.
- The shopper has supplied a supported delivery address.

### Trigger

The shopper chooses to confirm the reviewed basket.

### Main flow

1. **Actor:** The shopper confirms the basket. **System:** The system validates price, stock, and address.
2. **Actor:** The payment provider authorizes the amount. **System:** The system creates one order.
3. **Actor:** The shopper views the result. **System:** The system presents the order reference.

### Alternative flows

- **A1 — Correct changed price.** Source step: 1. Condition: a price changed after review. Behavior: the system shows the new total and asks for confirmation. Resume at step: 1.
- **A2 — Save for later.** Source step: 1. Condition: the shopper declines the new total. Behavior: the system retains the basket without creating an order. Ends with: unchanged basket.

### Exception flows

- **E1 — Authorization unavailable.** Source step: 2. Failure: the provider cannot answer. Handling: show a retryable failure and retain the basket. Prohibited: creating an order or claiming authorization. Failure postcondition: no order exists.

### Postconditions

- **Success:** Exactly one order and reference exist for the confirmation.
- **Failure:** The basket remains recoverable and no success is reported.

## Requirements

- **FR-001:** When the shopper confirms an eligible basket, the system shall validate price, stock, and address before requesting authorization.
- **FR-002:** When authorization succeeds, the system shall create exactly one order and present its reference.
- **BR-001:** An order must not exist without a successful authorization outcome.
- **NFR-001:** Confirmation retries shall not create duplicate orders.

## Acceptance

- [ ] A valid confirmation returns one order reference.
- [ ] A changed price requires renewed confirmation.
- [ ] Provider failure creates no order.

**Scenario: valid confirmation**  
Given an eligible reviewed basket  
When the shopper confirms and authorization succeeds  
Then exactly one order reference is shown.

**Scenario: authorization failure**  
Given an eligible reviewed basket  
When the provider cannot authorize  
Then no order is created and the basket remains recoverable.

## Relationships

- Specs: [[api-overview]]
- Source: `src/orders.ts`
