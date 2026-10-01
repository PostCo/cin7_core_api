# frozen_string_literal: true

RSpec.describe "CIN7 Core pilot resource contracts" do
  let(:sale_id) { "11111111-1111-4111-8111-111111111111" }
  let(:task_id) { "22222222-2222-4222-8222-222222222222" }

  def expect_request(method, path, params: {}, payload: nil, response: {})
    calls = 0
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.public_send(method, "/ExternalApi/v2/#{path}") do |env|
        calls += 1
        expect(env.params).to eq(params)
        if payload
          expect(env.request_headers["Content-Type"]).to eq("application/json")
          expect(env.body).to be_a(String)
          expect(JSON.parse(env.body)).to eq(payload)
        else
          expect(env.body).to be_nil
        end
        json_response(response)
      end
    end

    result = yield build_client(stubs)
    expect(result.body).to eq(response)
    expect(calls).to eq(1)
    stubs.verify_stubbed_calls
  end

  it "reads orders and invoices by parent sale, preserving false options" do
    {orders: "sale/order", invoices: "sale/invoice"}.each do |resource, path|
      expect_request(:get, path,
        params: {"SaleID" => sale_id, "CombineAdditionalCharges" => "false", "IncludeProductInfo" => "true"}) do |client|
        client.public_send(resource).for_sale(sale_id: sale_id, combine_additional_charges: false, include_product_info: true)
      end
    end
  end

  it "posts the complete order including shipping, discounts, taxes and no auto-fulfilment" do
    payload = {"SaleID" => sale_id, "Status" => "AUTHORISED", "Memo" => "preserved memo",
               "AutoPickPackShipMode" => "NOPICK",
               "Lines" => [{"ProductID" => "product-id", "SKU" => "shirt", "Quantity" => 2,
                            "Price" => 20.0, "Discount" => 10, "Tax" => 3.6, "TaxRule" => "GST", "Total" => 36}],
               "AdditionalCharges" => [{"Description" => "Shipping", "Price" => 5, "Tax" => 0.5}]}
    expect_request(:post, "sale/order", payload: payload) { |client| client.orders.create(payload: payload) }
  end

  it "writes invoices with distinct sale/task IDs and preserves omitted versus empty collections" do
    payload = {"SaleID" => sale_id, "TaskID" => task_id, "Status" => "AUTHORISED",
               "InvoiceDate" => "2026-09-29T00:00:00", "InvoiceDueDate" => "2026-10-29T00:00:00",
               "CurrencyConversionRate" => 1.42541, "CombineAdditionalCharges" => false,
               "LinkedFulfillmentNumber" => "2", "Lines" => [], "AdditionalCharges" => []}
    expect_request(:post, "sale/invoice", payload: payload) { |client| client.invoices.create(payload: payload) }

    partial = {"SaleID" => sale_id, "TaskID" => task_id, "Memo" => "a partial update"}
    expect_request(:put, "sale/invoice", payload: partial) { |client| client.invoices.update(payload: partial) }
  end

  it "leaves explicit new-invoice task IDs to the caller" do
    payload = {"SaleID" => sale_id, "TaskID" => "00000000-0000-0000-0000-000000000000"}
    expect_request(:post, "sale/invoice", payload: payload) { |client| client.invoices.create(payload: payload) }
  end

  it "undoes only the explicitly addressed sale or invoice, with Void=false" do
    expect_request(:delete, "sale", params: {"ID" => sale_id, "Void" => "false"}) { |client| client.sales.undo(id: sale_id) }
    expect_request(:delete, "sale/invoice", params: {"TaskID" => task_id, "Void" => "false"}) do |client|
      client.invoices.undo(task_id: task_id)
    end
  end

  it "updates the sale header without rewriting its documents" do
    payload = {"ID" => sale_id, "Note" => "Existing note\nPostCo journal JR-00001"}
    expect_request(:put, "sale", payload: payload) { |client| client.sales.update(payload: payload) }
  end

  it "posts payment and refund legs to the explicit task with no financial transformation" do
    %w[PAYMENT REFUND].each do |type|
      payload = {"TaskID" => task_id, "Type" => type, "Reference" => "postco-operation-1",
                 "Amount" => 42.35, "DatePaid" => "2026-09-29T00:00:00", "Account" => "merchant-liability",
                 "CurrencyRate" => 1.42541}
      expect_request(:post, "sale/payment", payload: payload, response: payload.merge("ID" => "payment-id")) do |client|
        client.payments.create(payload: payload)
      end
    end
  end

  it "updates and deletes by payment ID, not sale or task ID" do
    payload = {"ID" => "payment-id", "Account" => "merchant-liability", "Reference" => "original-reference",
               "Amount" => 42.35, "DatePaid" => "2026-09-29T00:00:00", "CurrencyRate" => 1.42541}
    expect_request(:put, "sale/payment", payload: payload) { |client| client.payments.update(payload: payload) }
    expect_request(:delete, "sale/payment", params: {"ID" => "payment-id"}, response: {"Success" => true}) do |client|
      client.payments.delete(id: "payment-id")
    end
  end

  it "reads and replaces sale manual-journal lines without appending or rounding implicitly" do
    expect_request(:get, "sale/manualJournal", params: {"SaleID" => sale_id}) do |client|
      client.manual_journals.for_sale(sale_id: sale_id)
    end
    payload = {"SaleID" => sale_id, "Status" => "AUTHORISED", "Lines" => [
      {"Reference" => "existing", "Amount" => 1, "Date" => "2026-09-28T00:00:00", "Debit" => "expense", "Credit" => "liability"},
      {"Reference" => "new-bonus", "Amount" => 84.50, "Date" => "2026-09-29T00:00:00", "Debit" => "expense", "Credit" => "liability"}
    ]}
    expect_request(:post, "sale/manualJournal", payload: payload) { |client| client.manual_journals.create(payload: payload) }
  end

  it "searches and retrieves journals with the documented response envelope" do
    response = {"Total" => 1, "Page" => 1, "Journals" => [{"TaskID" => task_id}]}
    expect_request(:get, "journal", params: {"Page" => "2", "Limit" => "50", "Search" => "postco-1", "Status" => "COMPLETED"}, response: response) do |client|
      client.journals.list(page: 2, limit: 50, search: "postco-1", status: "COMPLETED")
    end
    expect_request(:get, "journal", params: {"TaskID" => task_id}, response: response) { |client| client.journals.retrieve(task_id: task_id) }
  end

  it "creates and completes standalone journals retaining both currency amounts" do
    payload = {"Status" => "DRAFT", "Currency" => "USD", "CurrencyConversionRate" => 1.40834,
               "EffectiveDate" => "2026-09-29T00:00:00", "Narration" => "postco-1", "Notes" => "sale and return references",
               "Lines" => [{"Debit" => "expense", "Credit" => "liability", "Reference" => "postco-1", "Amount" => 60, "BaseAmount" => 84.5004}]}
    expect_request(:post, "journal", payload: payload) { |client| client.journals.create(payload: payload) }
    updated = payload.merge("TaskID" => task_id, "Status" => "COMPLETED")
    expect_request(:put, "journal", payload: updated) { |client| client.journals.update(payload: updated) }
  end

  it "maps every tax filter, retaining boolean false" do
    expect_request(:get, "ref/tax", params: {"Page" => "1", "Limit" => "100", "ID" => "tax-id", "Name" => "GST",
                                             "IsActive" => "true", "IsTaxForSale" => "true", "IsTaxForPurchase" => "false", "Account" => "tax-account"},
      response: {"TaxRuleList" => []}) do |client|
      client.tax_rules.list(page: 1, limit: 100, id: "tax-id", name: "GST", is_active: true,
        is_tax_for_sale: true, is_tax_for_purchase: false, account: "tax-account")
    end
  end

  it "lists, creates, updates and deletes webhooks using subscription IDs" do
    expect_request(:get, "webhooks", response: {"Webhooks" => []}) { |client| client.webhooks.list }
    payload = {"Type" => "Sale/CreditNoteAuthorised", "IsActive" => true,
               "ExternalURL" => "https://example.test/cin7", "ExternalAuthorizationType" => "bearerauth",
               "ExternalBearerToken" => "hook-secret"}
    expect_request(:post, "webhooks", payload: payload) { |client| client.webhooks.create(payload: payload) }
    updated = payload.merge("ID" => "hook-id", "IsActive" => false)
    expect_request(:put, "webhooks", payload: updated) { |client| client.webhooks.update(payload: updated) }
    expect_request(:delete, "webhooks", params: {"ID" => "hook-id"}, response: {"Webhooks" => []}) do |client|
      client.webhooks.delete(id: "hook-id")
    end
  end

  it "rejects missing or blank explicit identifiers before dispatch" do
    client = build_client(Faraday::Adapter::Test::Stubs.new)
    {
      sales: {update: ["ID"]}, payments: {create: ["TaskID"], update: ["ID"]},
      orders: {create: ["SaleID"]}, invoices: {create: %w[SaleID TaskID], update: %w[SaleID TaskID]},
      manual_journals: {create: ["SaleID"]}, journals: {update: ["TaskID"]}, webhooks: {update: ["ID"]}
    }.each do |resource, methods|
      methods.each do |method, identifiers|
        identifiers.each do |missing|
          [nil, "", " \t"].each do |blank|
            payload = identifiers.to_h { |key| [key, "an-id"] }.merge(missing => blank)
            expect { client.public_send(resource).public_send(method, payload: payload) }.to raise_error(ArgumentError, "#{missing} is required")
          end
        end
      end
    end

    [-> { client.sales.undo(id: " ") }, -> { client.invoices.undo(task_id: nil) },
      -> { client.payments.delete(id: "") }, -> { client.webhooks.delete(id: nil) },
      -> { client.journals.retrieve(task_id: nil) }, -> { client.orders.for_sale(sale_id: nil) },
      -> { client.invoices.for_sale(sale_id: nil) }, -> { client.manual_journals.for_sale(sale_id: nil) }].each do |call|
      expect(&call).to raise_error(ArgumentError)
    end
  end

  it "rejects non-object payloads and ambiguous key casing without making requests" do
    client = build_client(Faraday::Adapter::Test::Stubs.new)
    [nil, [], "{}", {TaskID: "task-id"}].each do |payload|
      expect { client.payments.create(payload: payload) }.to raise_error(ArgumentError, /String keys/)
    end
  end

  it "rejects unknown read filters" do
    client = build_client(Faraday::Adapter::Test::Stubs.new)
    expect { client.tax_rules.list(active: true) }.to raise_error(ArgumentError, /Unknown parameters/)
    expect { client.orders.for_sale(sale_id: sale_id, id: "typo") }.to raise_error(ArgumentError, /Unknown parameters/)
    expect { client.invoices.for_sale(sale_id: sale_id, task_id: task_id) }.to raise_error(ArgumentError, /Unknown parameters/)
    expect { client.journals.list(id: task_id) }.to raise_error(ArgumentError, /Unknown parameters/)
  end
end
