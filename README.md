# CIN7 Core API

`cin7_core_api` is a small Ruby client for the [CIN7 Core API v2](https://dearinventory.docs.apiary.io/).

Version `0.2.0` adds explicit payment, order, invoice, journal, and webhook operations while preserving the `0.1.x` read methods. It performs one request per call, without automatic retries or accounting policy. The caller owns authorization, concurrency, document matching, financial calculations, and recovery after uncertain writes.

## Installation

Add the gem to your Gemfile:

```ruby
gem "cin7_core_api", github: "PostCo/cin7_core_api", ref: "<reviewed-full-commit-sha>"
```

Then run:

```console
bundle install
```

Ruby 3.3 or newer is required.

The `0.2.0` source is prepared for review; this README does not assert that it has been published. Pin a reviewed source commit until a release is available.

## Authentication

Create a client using the Account ID and API Application Key from CIN7 Core's API setup page:

```ruby
client = Cin7CoreAPI::Client.new(
  account_id: ENV.fetch("CIN7_CORE_ACCOUNT_ID"),
  application_key: ENV.fetch("CIN7_CORE_APPLICATION_KEY")
)
```

Credentials belong to one CIN7 Core company and should not be shared or logged. Configuration is held by the client instance, so an application can safely construct separate clients for different retailers.

For an approved sandbox or mock server, the URL and timeouts can be overridden:

```ruby
client = Cin7CoreAPI::Client.new(
  account_id: "account-id",
  application_key: "application-key",
  base_url: "https://example.test/ExternalApi/v2/",
  open_timeout: 2,
  timeout: 10
)
```

## Usage

The gem returns `Cin7CoreAPI::Response` objects. Response JSON retains CIN7's original key names:

```ruby
response = client.sales.list(page: 1, limit: 100, external_id: "shopify-order-id")

response.status       # => 200
response.success?     # => true
response.headers      # => {"content-type" => "application/json", ...}
response.body["SaleList"]
response.body["Total"]
```

Available read operations:

| Ruby operation | CIN7 Core endpoint |
| --- | --- |
| `client.me.retrieve` | `GET /me` |
| `client.sales.list` | `GET /saleList` |
| `client.sales.retrieve(id:)` | `GET /sale?ID=...` |
| `client.credit_notes.list` | `GET /saleCreditNoteList` |
| `client.credit_notes.for_sale(sale_id:)` | `GET /sale/creditnote?SaleID=...` |
| `client.payments.for_sale(sale_id:)` | `GET /sale/payment?SaleID=...` |
| `client.locations.list` | `GET /ref/location` |
| `client.accounts.list` | `GET /ref/account` |
| `client.bank_accounts.list` | `GET /ref/account/bank` |
| `client.customers.list` | `GET /customer` |
| `client.customer_credits.list` | `GET /ref/customer/credits` |

Ruby keyword arguments use `snake_case` and are explicitly translated to CIN7's parameter names:

```ruby
client.sales.list(
  page: 2,
  limit: 100,
  updated_since: "2026-08-01T00:00:00.000",
  order_status: "AUTHORISED"
)

client.sales.retrieve(
  id: "7d636591-9d84-4ff1-a4fb-b9ab6f8b7cd7",
  include_transactions: true
)

client.credit_notes.for_sale(
  sale_id: "7d636591-9d84-4ff1-a4fb-b9ab6f8b7cd7",
  include_payment_info: true
)

client.customer_credits.list(
  customer_id: "c786e00a-d745-4c4f-9f95-cf06149b4925",
  show_used_credits: false
)
```

Unknown keyword arguments raise `ArgumentError` rather than silently sending a misspelled CIN7 parameter.

`ExternalID` is an optional Cin7 field and may be null on native connector imports. It is not a guaranteed Shopify order identifier. Resolve and persist the parent sale ID and the specific invoice/credit-note task IDs using verified business references. Do not substitute a parent `SaleID` for an advanced sale's document `TaskID`.

## Pilot operations

Every operation returns the same `Cin7CoreAPI::Response` wrapper as the read methods. Payloads must be Hashes with Cin7 JSON field names as **String keys**. They are encoded as JSON, without case conversion, accounting calculations, FX rounding, or implicit document fields. Identifier presence is checked locally; Cin7 validates the remaining payload and state transitions.

| Ruby method | HTTP operation | Required payload identifiers / read filters |
| --- | --- | --- |
| `client.sales.update(payload:)` | `PUT /sale` | `ID` |
| `client.sales.undo(id:)` | `DELETE /sale?ID=...&Void=false` | Parent sale ID |
| `client.payments.create(payload:)` | `POST /sale/payment` | `TaskID` of the invoice or credit note |
| `client.payments.update(payload:)` | `PUT /sale/payment` | Payment `ID` |
| `client.payments.delete(id:)` | `DELETE /sale/payment?ID=...` | Payment ID |
| `client.orders.for_sale(sale_id:, **options)` | `GET /sale/order` | `sale_id`, `combine_additional_charges`, `include_product_info` |
| `client.orders.create(payload:)` | `POST /sale/order` | `SaleID` |
| `client.invoices.for_sale(sale_id:, **options)` | `GET /sale/invoice` | `sale_id`, `combine_additional_charges`, `include_product_info` |
| `client.invoices.create(payload:)` | `POST /sale/invoice` | `SaleID`, `TaskID` |
| `client.invoices.update(payload:)` | `PUT /sale/invoice` | `SaleID`, `TaskID` |
| `client.invoices.undo(task_id:)` | `DELETE /sale/invoice?TaskID=...&Void=false` | Invoice task ID |
| `client.manual_journals.for_sale(sale_id:)` | `GET /sale/manualJournal` | Parent sale ID |
| `client.manual_journals.create(payload:)` | `POST /sale/manualJournal` | `SaleID` |
| `client.journals.list(**filters)` | `GET /journal` | `page`, `limit`, `task_id`, `status`, `search` |
| `client.journals.retrieve(task_id:)` | `GET /journal?TaskID=...` | Journal task ID; retains the `Journals` response envelope |
| `client.journals.create(payload:)` | `POST /journal` | Server allocates the journal task ID |
| `client.journals.update(payload:)` | `PUT /journal` | `TaskID` |
| `client.tax_rules.list(**filters)` | `GET /ref/tax` | `page`, `limit`, `id`, `name`, `is_active`, `is_tax_for_sale`, `is_tax_for_purchase`, `account` |
| `client.webhooks.list` | `GET /webhooks` | No filters; returns the `Webhooks` envelope |
| `client.webhooks.create(payload:)` | `POST /webhooks` | Server allocates the subscription ID |
| `client.webhooks.update(payload:)` | `PUT /webhooks` | Subscription `ID` |
| `client.webhooks.delete(id:)` | `DELETE /webhooks?ID=...` | Subscription ID |

### Payments and document corrections

```ruby
response = client.payments.create(payload: {
  "TaskID" => matched_credit_note_task_id,
  "Type" => "REFUND",
  "Reference" => persisted_operation_reference,
  "Amount" => 60.00,
  "DatePaid" => "2026-09-29T00:00:00",
  "Account" => merchant_liability_account_code,
  "CurrencyRate" => 1.42541
})
payment_id = response.body.fetch("ID")
```

`PAYMENT` requires an authorized invoice; `REFUND` requires an authorized credit note. Amounts use customer-currency major units, not cents. `Account` is a chart-of-accounts code. Payments backed by `CreditID` cannot have their `Amount` or `Account` updated, and prepayments cannot be updated. The client preserves supplied FX precision, including five-place values such as `1.42541`; it does not truncate to the Blueprint's four-place annotation.

Order and invoice writes require the appropriate draft/not-available state. The method name `create` denotes POST: sale document POSTs can replace existing collections. Preserve all unrelated lines, charges, taxes and discounts. An invoice PUT can omit collections; supplying an empty collection deletes its contents. The all-zero `TaskID` explicitly requests a new invoice; the client never supplies it automatically.

Undo uses `Void=false` and can reverse downstream work and accounting. Snapshot documents/payments before removal or undo, and verify fulfilment, locks, export status, and the endpoint's eligibility first. The v2 Blueprint contains contradictory invoice-undo eligibility text; exposing the HTTP operation does not establish that it is safe for every simple or advanced sale. The client performs no automatic payment restoration, native credit-note creation, restocking, or fulfilment writes.

### Journals and setup

Sale manual-journal payloads contain `SaleID`, `Status` (`DRAFT`/`AUTHORISED`) and `Lines` of `Reference`, `Amount`, `Date`, `Debit`, `Credit`. Their amounts are in **company base currency**. Read and retain all existing lines when appending a bonus entry.

Standalone journals contain `Status` (`DRAFT`/`COMPLETED`), `Currency`, `CurrencyConversionRate`, `EffectiveDate`, `Narration`, `Notes` and `Lines` of `Debit`, `Credit`, `Reference`, `Amount`, `BaseAmount`. `Amount` uses the selected currency; `BaseAmount` uses company base currency. The caller owns conversions and rounding. `journals.list(search:)` searches `Narration`/`Notes` as well as journal number/status. Keep a durable unique business reference in searchable fields. An uncertain manual-journal result is not permission to create a standalone replacement.

Account and tax reads do not prove connector mappings. Validate active/payment-enabled liability accounts, merchant mappings, active sale tax rules, and `/me` lock/currency settings in the application. Journal availability can depend on the accounting integration; verify it before choosing a fallback.

### Webhooks

```ruby
client.webhooks.create(payload: {
  "Type" => "Sale/CreditNoteAuthorised",
  "IsActive" => true,
  "ExternalURL" => callback_url,
  "ExternalAuthorizationType" => "bearerauth",
  "ExternalBearerToken" => callback_token
})
```

The Blueprint supports bearer/basic authentication, not an HMAC signature contract. Webhooks require the Automation module and are limited to five subscriptions per event type. It documents six delivery attempts: first after one minute, then delays of 5, 10, 15, 20 and 25 minutes, followed by deactivation on repeated failure. Manage only subscriptions owned by your application. Use polling as recovery and fetch authoritative sale state after notifications; `SaleID`, `SaleTaskID`, and `TaskID` differ across event payloads.

## Errors and retries

Non-success responses raise an error with the response status, sanitized headers, and sanitized parsed body attached:

```ruby
begin
  client.sales.retrieve(id: sale_id)
rescue Cin7CoreAPI::RateLimitError => error
  error.status       # => 429
  error.retry_after  # value of the Retry-After response header, when present
  error.body         # CIN7's parsed error body
end
```

Errors include:

- `Cin7CoreAPI::BadRequestError`
- `Cin7CoreAPI::AuthenticationError`
- `Cin7CoreAPI::ForbiddenError`
- `Cin7CoreAPI::NotFoundError`
- `Cin7CoreAPI::MethodNotAllowedError`
- `Cin7CoreAPI::RateLimitError`
- `Cin7CoreAPI::ServerError`
- `Cin7CoreAPI::TransportError`
- `Cin7CoreAPI::ParseError`

All inherit from `Cin7CoreAPI::Error`.

The gem does not retry requests automatically. CIN7 Core limits an API application to 60 calls per minute, and the calling application is better placed to apply queueing, idempotency, backoff, and retry policies.

For POST, PUT and DELETE, `error.ambiguous?` is true after transport failures, HTTP 5xx responses, or invalid/empty successful JSON responses (except HTTP 204). A write may already have applied. `error.request_method` is a Symbol (`:post`, `:put`, `:delete`, or `:get`), and `error.request_path` identifies the endpoint without query parameters. Reads and HTTP 4xx rejections return `ambiguous? == false`; this flag describes uncertainty about a mutation, not general retryability. HTTP 429 retains `retry_after` when present.

```ruby
begin
  client.payments.create(payload: saved_payload)
rescue Cin7CoreAPI::Error => error
  if error.ambiguous?
    # Persist recovery state. Read payments for the parent sale and match the
    # saved reference, task, type, amount, account, date and FX before retrying.
    # A missing immediate readback does not prove the write failed.
  else
    # Handle the sanitized rejection according to application policy.
  end
end
```

Neither a payment reference nor a journal reference is a documented server-side idempotency key. The gem supplies no exactly-once guarantee. It does not switch journal strategies, undo a sale, or replay a write after failure.

### Sensitive data

The transport removes known API credentials and credential-bearing fields from response bodies/headers, including webhook tokens, passwords, usernames, authorization/cookie headers, and custom `ExternalHeaders`. It also filters known credential values echoed in other text. JSON field names stay intact; GUID identifiers are filtered only when the complete value matches a known credential. Outbound payloads are sent unchanged, and caller-owned Hashes are not mutated. Response and client/connection/resource inspection omit payloads and authentication state. Error messages omit response bodies; inspect `error.body` for sanitized details. Transport errors deliberately omit the upstream message and cause, which may contain the authenticated request.

Business `AccountID` and `BankAccountId` values remain GUIDs or null; they are distinct from the `api-auth-accountid` credential header. Callback `ExternalURL` values retain their spelling and escaping for subscription matching. URL userinfo and sensitive query/fragment parameters are filtered, as are complete credential values in URL components; incidental substrings from other subscriptions' credentials do not rewrite callback identity. URL credentials are also removed from free-text echoes. Malformed callback URLs are filtered entirely.

Keep webhook credentials in your own encrypted configuration: sanitized webhook responses are **not** suitable for round-tripping as update payloads. Redaction targets credentials; ordinary business data and customer information still require appropriate application logging controls.

## Development

```console
bundle install
bundle exec rake
bundle exec rake build
```

The default Rake task runs the RSpec suite and Standard Ruby.

For a checkout containing untracked research scripts, lint only the intended gem source, not research artifacts:

```console
mise exec -- bundle exec rspec
mise exec -- bundle exec standardrb --cache false $(git ls-files '*.rb' '*.gemspec' Gemfile Rakefile)
mise exec -- bundle exec rake build
```

Stage intended new source/spec files before using the tracked-file lint command. CI tests Ruby 3.3 and 3.4. Specs use Faraday's test adapter and do not verify live accounting behavior. Inspect the built gem's file list before release: the gemspec packages only `lib/**/*.rb`, README, changelog and license. Preserve untracked research files. Publication and push require a separate release decision; RubyGems MFA remains required.

## CIN7 references

- [CIN7 Core API v2 reference](https://dearinventory.docs.apiary.io/)
- [Connecting to the CIN7 Core API](https://help.core.cin7.com/hc/en-us/articles/9982480315407-Connecting-to-the-Cin7-Core-API)
- [CIN7 Core Shopify integration](https://help.core.cin7.com/hc/en-us/articles/11797034961039-Shopify-settings)
