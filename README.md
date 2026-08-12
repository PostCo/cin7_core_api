# CIN7 Core API

`cin7_core_api` is a small Ruby client for the [CIN7 Core API v2](https://dearinventory.docs.apiary.io/).

The initial `0.1.x` interface is intentionally read-only. CIN7 Core and Shopify may already synchronize orders, refunds, credit notes, and restocks; write operations will be added only after their ownership and expected payloads have been validated against a sandbox account.

## Installation

Add the gem to your Gemfile:

```ruby
gem "cin7_core_api", github: "PostCo/cin7_core_api"
```

Then run:

```console
bundle install
```

Ruby 3.3 or newer is required.

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

## Errors and retries

Non-success responses raise an error with the response status, headers, and parsed body attached:

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

## Development

```console
bundle install
bundle exec rake
bundle exec rake build
```

The default Rake task runs the RSpec suite and Standard Ruby.

## CIN7 references

- [CIN7 Core API v2 reference](https://dearinventory.docs.apiary.io/)
- [Connecting to the CIN7 Core API](https://help.core.cin7.com/hc/en-us/articles/9982480315407-Connecting-to-the-Cin7-Core-API)
- [CIN7 Core Shopify integration](https://help.core.cin7.com/hc/en-us/articles/11797034961039-Shopify-settings)
