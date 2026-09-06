---
schema_version: 1
type: feature
id: FEAT-014
title: Manage Account and Session
status: proposed
created: 2026-09-03
relationships:
  specs:
    - "[[product-delivery-roadmap|Product Delivery Roadmap]]"
    - "[[product-feature-inventory]]"
    - "[[model-entity-catalogue]]"
    - "[[api-catalogue]]"
    - "[[technical-architecture|Technical Architecture]]"
    - "[[ui-ux-system|UI/UX System]]"
  decisions: []
  plans: []
  reports:
    - "[[REP-013-backlog-lane-documentation-survey|REP-013]]"
  rules: []
  features:
    - "[[FEAT-013-saved-poses-albums-account-backed|FEAT-013]]"
  source_paths:
    - docs/harness/specs/data-contract.md
    - docs/harness/specs/api-contract.md
    - docs/harness/features/FEAT-013-saved-poses-albums-account-backed.md
---

# FEAT-014: Manage Account and Session

## Introduction

**Mục tiêu:** Cung cấp Account surface hẹp nhưng đầy đủ cho lifecycle quan sát được:
vào Account, xem identity/provider và session status, đi đến Saved, và sign-out an
toàn. Feature này là policy proposed; không claim Account UI, auth runtime hay
sign-out đã shipped/verified.

**Phạm vi v1:** Account screen chỉ read-only identity/provider/session status, route
đến Saved của [FEAT-013](FEAT-013-saved-poses-albums-account-backed.md), và
sign-out. FEAT-014 sở hữu signed-in/signed-out state, expiry/invalid-session
recovery, gating và account isolation. FEAT-013 tiêu thụ Account/session hợp lệ
nhưng sở hữu Saved collection semantics.

**Ngoài phạm vi:** profile editing, provider linking, account deletion, data export,
avatar persistence, multi-account relinking policy, Albums, và mọi SDK/endpoint/
config/token/callback contract mới. Provider authority tham chiếu Google-on-Supabase
contract đã ghi trong FEAT-013; chi tiết runtime vẫn cần evidence.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Signed-in Account | User | Xem account state và quản lý phiên | Mở Account, xem identity/provider, đi đến Saved, sign-out |
| Signed-out visitor/Guest | User | Hiểu trạng thái truy cập | Thấy signed-out context và sign-in-required gating |
| Auth/session authority | External system | Cung cấp identity và session validity | Xác thực hoặc báo session expired/invalid theo contract hiện hữu |
| FEAT-013 Saved Poses | Related feature | Bảo vệ Saved theo Account | Nhận valid Account/session; sở hữu Saved/Unsave/list/Try Pose |

### User needs

- Biết identity/provider hiện tại và session còn hợp lệ hay không.
- Có Account entry và lối tắt đến Saved mà không biến Account thành owner của Saved.
- Sign-out rõ ràng, idempotent, không để lại protected account state trong signed-out context.
- Recovery an toàn khi session expired/invalid, không chuyển nhầm sang collection của account khác.

### Preconditions

- [`Account`](../../spec/data/entities/account.md) là canonical identity model;
  session/credential semantics nằm ngoài entity catalogue.
- Provider/session contract phải được chấp thuận và runtime path có evidence trước
  approval/delivery; FEAT-014 không tự đóng gap đó.
- Saved route do FEAT-013 định nghĩa; FEAT-014 chỉ điều hướng sau khi xác định session state.

### Trigger

Người dùng chọn Account entry, Saved từ Account screen, sign-out, hoặc app nhận
expiry/invalid-session signal/401 từ protected request.

### Main flow

1. **Actor:** Signed-in Account mở Account. **System:** hiển thị identity/provider
   và session status read-only, cùng action đến Saved và sign-out.
2. **Actor:** Account chọn Saved. **System:** chuyển đến Saved của FEAT-013 với cùng
   Account/session, không tạo collection hay contract mới.
3. **Actor:** Account chọn sign-out. **System:** kết thúc local authenticated context,
   clear account-scoped local cache/state theo boundary hiện hữu, rồi đưa user về
   signed-out/browse hoặc sign-in-required context.

### Alternative flows

- **A1 — Signed-out Account entry.** Source step: 1. Condition: không có valid
  session. Behavior: hiển thị signed-out state và sign-in-required guidance, không
  hiển thị identity account cũ hay Saved collection. Ends with: signed-out context.
- **A2 — Session refresh succeeds.** Source step: 1–2. Condition: session hết hạn
  nhưng auth flow hiện hữu refresh thành công. Behavior: cập nhật status và tiếp tục
  action ban đầu khi an toàn, không claim refresh mechanics cụ thể. Ends with: action
  resumed under the refreshed valid session.
- **A3 — Repeated sign-out.** Source step: 3. Condition: user đã signed-out hoặc
  sign-out được gửi lại. Behavior: sign-out idempotent, giữ signed-out state và không
  ảnh hưởng dữ liệu account khác. Ends with: signed-out context.

### Exception flows

- **E1 — Expired/invalid session.** Source step: 1–2; Failure: auth authority hoặc
  protected API trả expiry/401. Handling: thử recovery theo auth boundary nếu hỗ trợ;
  nếu không, clear session, discard protected view và yêu cầu sign-in. Prohibited:
  fallback sang account khác hoặc render Saved cũ như hiện tại.
- **E2 — Sign-out cleanup incomplete.** Source step: 3; Failure: local
  account-scoped state không clear được hoàn toàn. Handling: block protected
  Account/Saved views và báo signed-out/retryable state. Prohibited: truy cập cache
  còn sót hoặc suy diễn remote revocation details khi chưa có evidence.
- **E3 — Identity/provider unavailable.** Source step: 1; Failure: session hợp lệ
  nhưng metadata presentation không lấy được. Handling: hiển thị unavailable và giữ
  protected data gated. Prohibited: invent identity fields/provider values.

### Postconditions

- **Success:** User thấy đúng Account context và có thể route đến Saved cùng Account hoặc sign-out.
- **Sign-out:** Không còn authenticated UI/context hoặc account-scoped local state có thể truy cập; user ở signed-out/browse hoặc sign-in-required context.
- **Failure:** Session invalid không làm lộ dữ liệu và không gán user sang account khác.

## Requirements

- **FR-001:** Account screen shall present read-only current identity, provider, và
  session status khi valid session; không profile editing trong v1.
- **FR-002:** Account screen shall route đến Saved do FEAT-013 sở hữu, giữ cùng
  Account/session và không redefine Saved/Unsave/Saved list/Try Pose.
- **FR-003:** Sign-out là action first-class, explicit, idempotent; clear local
  authenticated context và đưa user về signed-out/browse hoặc sign-in-required.
- **FR-004:** Expired/invalid session shall được refresh qua existing auth boundary
  nếu hỗ trợ, nếu không thì clear; protected Account/Saved views bị gated.
- **FR-005:** Recovery/sign-out shall ngăn cross-account leakage: stale identity,
  Saved collection, cached protected response, và account-scoped local state không
  được accessible sau context change/sign-out.
- **FR-006:** 401/invalid-session không được coi là empty collection hay success;
  phải đi qua FEAT-014 recovery/gating path, không invent token/revocation details.
- **FR-007:** Provider display và identity mapping dùng frozen contract FEAT-013;
  không định nghĩa provider, SDK, endpoint, config key, token format, callback URL mới.

### Non-goals

Profile editing; provider linking; account deletion; export; avatar persistence;
multi-account relinking; Albums; remote token revocation guarantees without evidence;
implementation-specific auth contracts.

## Acceptance

- [ ] Valid signed-in session mở Account và thấy read-only identity/provider/session
  status, Saved action, sign-out action.
- [ ] Account → Saved vào Saved của FEAT-013 bằng cùng Account/session; không redefine Saved.
- [ ] Sign-out explicit/idempotent, clear hoặc block account-scoped local state, rồi
  về signed-out/browse hoặc sign-in-required context.
- [ ] Signed-out user không access identity, protected Account state, hoặc Saved data;
  account actions bị gated.
- [ ] Expired/invalid session chỉ refresh qua existing boundary nếu available, nếu
  không thì clear an toàn và yêu cầu sign-in.
- [ ] Không path nào leak Account A identity/Saved/cache/local state cho Account B hoặc Guest.
- [ ] Editing, linking, deletion, export, avatar, relinking và remote revocation
  behavior vẫn out of scope nếu chưa có feature/decision riêng.

**Scenario: Account screen**

Given a valid signed-in Account
When the user opens Account
Then system shows read-only identity/provider/session status, Saved route, and sign-out.

**Scenario: sign-out**

Given a signed-in Account with account-scoped local state
When the user chooses sign-out
Then sign-out completes idempotently, protected local state is cleared or blocked, and
the user returns to signed-out/browse or sign-in-required context.

**Scenario: expired session**

Given client has Account A protected view and session expires
When a protected request returns 401
Then client refreshes only through existing auth boundary or clears session, never
shows Account A Saved data as valid, and never shows Account B data.

## Relationships

- [FEAT-013](FEAT-013-saved-poses-albums-account-backed.md) consumes FEAT-014’s valid
  Account/session and owns Saved/Unsave/Saved list/Try Pose semantics and Albums boundary.
- Shared entity: [`Account`](../../spec/data/entities/account.md) remains canonical;
  this Feature does not duplicate fields/schema.
- Shared auth/API boundary: [API Conventions](../../spec/api/conventions.md) and
  Google-on-Supabase policy in FEAT-013; no new API contract here.
- Roadmap: [Product Delivery Roadmap](../specs/product-delivery-roadmap.md), post-v1
  Account/session dependency.

### Current evidence and traceability

- **Documented policy:** FEAT-013 records Google-on-Supabase as the only enabled
  provider proposed for v1, plus 401 refresh/clear and no cross-account leakage.
- **Shared model:** `Account` defines identity fields and leaves session/credential
  mechanics outside the entity catalogue.
- **Runtime status:** Account UI, auth runtime, session lifecycle, sign-out cleanup,
  and invalid-session recovery are **Unresolved**; this Feature claims ownership,
  not implementation evidence.
- **Traceability:** Inventory, roadmap, and Harness README list FEAT-014; FEAT-013’s
  plan remains Saved delivery and consumes this boundary.
