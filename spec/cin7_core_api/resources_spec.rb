# frozen_string_literal: true

RSpec.describe "CIN7 Core resources" do
  def expect_get(path, expected_params, response_body = {})
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get(path) do |env|
        expect(env.params).to eq(expected_params)
        json_response(response_body)
      end
    end

    client = build_client(stubs)
    yield client
    stubs.verify_stubbed_calls
  end

  it "maps sale list filters to CIN7 parameter names" do
    expect_get(
      "/ExternalApi/v2/saleList",
      {"Page" => "2", "Limit" => "50", "ExternalID" => "shopify-123", "ReadyForShipping" => "false"}
    ) do |client|
      client.sales.list(page: 2, limit: 50, external_id: "shopify-123", ready_for_shipping: false)
    end
  end

  it "retrieves a sale by ID with options" do
    expect_get(
      "/ExternalApi/v2/sale",
      {"ID" => "sale-id", "IncludeTransactions" => "true"}
    ) do |client|
      client.sales.retrieve(id: "sale-id", include_transactions: true)
    end
  end

  it "lists sale credit notes" do
    expect_get(
      "/ExternalApi/v2/saleCreditNoteList",
      {"Page" => "1", "UpdatedSince" => "2026-08-01T00:00:00.000"}
    ) do |client|
      client.credit_notes.list(page: 1, updated_since: "2026-08-01T00:00:00.000")
    end
  end

  it "retrieves credit notes for a sale" do
    expect_get(
      "/ExternalApi/v2/sale/creditnote",
      {"SaleID" => "sale-id", "IncludePaymentInfo" => "true"}
    ) do |client|
      client.credit_notes.for_sale(sale_id: "sale-id", include_payment_info: true)
    end
  end

  it "retrieves payments for a sale" do
    expect_get("/ExternalApi/v2/sale/payment", {"SaleID" => "sale-id"}) do |client|
      client.payments.for_sale(sale_id: "sale-id")
    end
  end

  it "lists locations" do
    expect_get("/ExternalApi/v2/ref/location", {"Name" => "Sydney", "Deprecated" => "false"}) do |client|
      client.locations.list(name: "Sydney", deprecated: false)
    end
  end

  it "lists chart-of-account records" do
    expect_get("/ExternalApi/v2/ref/account", {"Type" => "BANK", "Status" => "ACTIVE"}) do |client|
      client.accounts.list(type: "BANK", status: "ACTIVE")
    end
  end

  it "lists bank accounts" do
    expect_get("/ExternalApi/v2/ref/account/bank", {"Bank" => "Commonwealth"}) do |client|
      client.bank_accounts.list(bank: "Commonwealth")
    end
  end

  it "lists customers" do
    expect_get(
      "/ExternalApi/v2/customer",
      {"Name" => "PostCo", "IncludeDeprecated" => "false", "IncludeProductPrices" => "true"}
    ) do |client|
      client.customers.list(name: "PostCo", include_deprecated: false, include_product_prices: true)
    end
  end

  it "lists customer credits" do
    expect_get(
      "/ExternalApi/v2/ref/customer/credits",
      {"CustomerID" => "customer-id", "ShowUsedCredits" => "false"}
    ) do |client|
      client.customer_credits.list(customer_id: "customer-id", show_used_credits: false)
    end
  end

  it "rejects unknown parameters" do
    stubs = Faraday::Adapter::Test::Stubs.new
    client = build_client(stubs)

    expect do
      client.sales.list(externalid: "typo")
    end.to raise_error(ArgumentError, "Unknown parameters: externalid")
  end

  it "requires a sale ID" do
    stubs = Faraday::Adapter::Test::Stubs.new
    client = build_client(stubs)

    expect do
      client.sales.retrieve(id: "")
    end.to raise_error(ArgumentError, "id is required")

    expect do
      client.credit_notes.for_sale(sale_id: nil)
    end.to raise_error(ArgumentError, "sale_id is required")
  end
end
