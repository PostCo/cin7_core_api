# frozen_string_literal: true

RSpec.describe "CIN7 Core native correction resource contracts" do
  it "posts a sale header without selecting accounting or fulfillment policy" do
    payload = {"CustomerID" => "customer-id", "Type" => "Advanced Sale", "SkipQuote" => true, "CurrencyRate" => "1.4253"}
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/ExternalApi/v2/sale") do |env|
        expect(JSON.parse(env.body)).to eq(payload)
        json_response({"ID" => "new-sale-id", "Type" => "Advanced Sale"})
      end
    end
    expect(build_client(stubs).sales.create(payload: payload).body.fetch("ID")).to eq("new-sale-id")
    stubs.verify_stubbed_calls
  end

  it "creates or rebuilds a credit note with explicit sale and credit-note task IDs" do
    payload = {
      "SaleID" => "parent-sale-id", "TaskID" => "credit-note-task-id", "CombineAdditionalCharges" => false,
      "CreditNoteInvoiceNumber" => "INV-TEST", "Status" => "AUTHORISED", "CreditNoteDate" => "2026-10-02",
      "CreditNoteConversionRate" => "1.43131", "Lines" => [],
      "AdditionalCharges" => [{"Description" => "Shipping refund", "Price" => "2.50", "Tax" => "0.23", "Total" => "2.73"}],
      "Restock" => [{"ProductID" => "product-id", "Quantity" => 1, "RestockLocationID" => "location-id"}]
    }
    original = Marshal.load(Marshal.dump(payload))
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/ExternalApi/v2/sale/creditnote") do |env|
        expect(JSON.parse(env.body)).to eq(original)
        json_response({"SaleID" => "parent-sale-id", "CreditNotes" => [payload]})
      end
    end
    response = build_client(stubs).credit_notes.create(payload: payload)
    expect(response.body.fetch("CreditNotes").first.fetch("TaskID")).to eq("credit-note-task-id")
    expect(payload).to eq(original)
    stubs.verify_stubbed_calls
  end

  %i[credit_notes fulfilments].each do |resource|
    it "undoes #{resource} by its explicit task ID without voiding" do
      path = (resource == :credit_notes) ? "creditnote" : "fulfilment"
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.delete("/ExternalApi/v2/sale/#{path}?TaskID=document-task-id&Void=false") { json_response({"SaleID" => "parent-sale-id"}) }
      end
      build_client(stubs).public_send(resource).undo(task_id: "document-task-id")
      stubs.verify_stubbed_calls
    end
  end

  it "reads and creates fulfilment tasks by parent sale ID" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/sale/fulfilment?SaleID=parent-sale-id&IncludeProductInfo=false") do
        json_response({"SaleID" => "parent-sale-id", "Fulfilments" => [{"TaskID" => "fulfilment-task-id"}]})
      end
      stub.post("/ExternalApi/v2/sale/fulfilment") do |env|
        expect(JSON.parse(env.body)).to eq({"SaleID" => "parent-sale-id"})
        json_response({"SaleID" => "parent-sale-id", "Fulfilments" => [{"TaskID" => "new-task-id"}]})
      end
    end
    resource = build_client(stubs).fulfilments
    expect(resource.for_sale(sale_id: "parent-sale-id", include_product_info: false).body.fetch("Fulfilments").first.fetch("TaskID")).to eq("fulfilment-task-id")
    expect(resource.create(payload: {"SaleID" => "parent-sale-id"}).body.fetch("Fulfilments").first.fetch("TaskID")).to eq("new-task-id")
    stubs.verify_stubbed_calls
  end

  {picks: "pick", packs: "pack", shipments: "ship"}.each do |resource, endpoint|
    it "reads #{resource} by fulfilment task and preserves the response shape" do
      options = (resource == :shipments) ? {} : {include_product_info: false}
      query = (resource == :shipments) ? "TaskID=fulfilment-task-id" : "TaskID=fulfilment-task-id&IncludeProductInfo=false"
      body = {"TaskID" => "fulfilment-task-id", "Status" => "AUTHORISED", "Lines" => [{"Quantity" => "1.25"}]}
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/ExternalApi/v2/sale/fulfilment/#{endpoint}?#{query}") { json_response(body) }
      end
      expect(build_client(stubs).public_send(resource).for_task(task_id: "fulfilment-task-id", **options).body).to eq(body)
      stubs.verify_stubbed_calls
    end

    {create: :post, update: :put}.each do |operation, verb|
      it "uses #{verb} for #{resource}.#{operation} without appending or restoring implicitly" do
        payload = {
          "TaskID" => "fulfilment-task-id", "Status" => "AUTHORISED",
          "Lines" => [{"ProductID" => "product-id", "LocationID" => "location-id", "Quantity" => "1.25", "Box" => "Box 1", "BatchSN" => "batch-1"}]
        }
        original = Marshal.load(Marshal.dump(payload))
        stubs = Faraday::Adapter::Test::Stubs.new do |stub|
          stub.public_send(verb, "/ExternalApi/v2/sale/fulfilment/#{endpoint}") do |env|
            expect(JSON.parse(env.body)).to eq(original)
            json_response(payload)
          end
        end
        expect(build_client(stubs).public_send(resource).public_send(operation, payload: payload).body).to eq(payload)
        expect(payload).to eq(original)
        stubs.verify_stubbed_calls
      end
    end
  end

  it "maps all product discovery filters and retains false options" do
    filters = {
      id: "product-id", page: 2, limit: 10, name: "Test", sku: "TEST-SKU", modified_since: "2026-10-02",
      include_deprecated: false, include_bom: false, include_suppliers: false, include_movements: false,
      include_attachments: false, include_reorder_levels: false, include_custom_prices: false
    }
    query = "ID=product-id&Page=2&Limit=10&Name=Test&Sku=TEST-SKU&ModifiedSince=2026-10-02&IncludeDeprecated=false&IncludeBOM=false&IncludeSuppliers=false&IncludeMovements=false&IncludeAttachments=false&IncludeReorderLevels=false&IncludeCustomPrices=false"
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/product?#{query}") { json_response({"Total" => 1, "Products" => [{"ID" => "product-id"}]}) }
    end
    expect(build_client(stubs).products.list(**filters).body.fetch("Products").first.fetch("ID")).to eq("product-id")
    stubs.verify_stubbed_calls
  end

  it "maps product availability filters and preserves stock quantities" do
    filters = {page: 1, limit: 10, id: "product-id", name: "Test", sku: "TEST-SKU", location: "Warehouse", batch: "batch-1", category: "Test"}
    body = {"Total" => 1, "ProductAvailabilityList" => [{"OnHand" => "3.50", "Allocated" => "1.25", "Available" => "2.25"}]}
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/ref/productavailability?Page=1&Limit=10&ID=product-id&Name=Test&Sku=TEST-SKU&Location=Warehouse&Batch=batch-1&Category=Test") { json_response(body) }
    end
    expect(build_client(stubs).product_availability.list(**filters).body).to eq(body)
    stubs.verify_stubbed_calls
  end

  it "maps carrier lookup filters" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/ref/carrier?Page=1&Limit=10&CarrierID=carrier-id&Description=Test") { json_response({"CarrierList" => [{"CarrierID" => "carrier-id"}]}) }
    end
    expect(build_client(stubs).carriers.list(page: 1, limit: 10, carrier_id: "carrier-id", description: "Test").body.fetch("CarrierList").first.fetch("CarrierID")).to eq("carrier-id")
    stubs.verify_stubbed_calls
  end

  it "rejects missing identifiers and invalid payload keys before dispatch" do
    client = build_client(Faraday::Adapter::Test::Stubs.new)
    %i[credit_notes fulfilments picks packs shipments].each do |resource|
      expect { client.public_send(resource).create(payload: {}) }.to raise_error(ArgumentError)
      expect { client.public_send(resource).create(payload: {TaskID: "task-id", SaleID: "sale-id"}) }.to raise_error(ArgumentError)
    end
    expect { client.credit_notes.create(payload: {"SaleID" => "sale-id", "TaskID" => " "}) }.to raise_error(ArgumentError)
    %i[picks packs shipments].each do |resource|
      expect { client.public_send(resource).for_task(task_id: " ") }.to raise_error(ArgumentError)
      expect { client.public_send(resource).update(payload: {}) }.to raise_error(ArgumentError)
    end
    expect { client.fulfilments.for_sale(sale_id: nil) }.to raise_error(ArgumentError)
    expect { client.fulfilments.undo(task_id: nil) }.to raise_error(ArgumentError)
    expect { client.credit_notes.undo(task_id: nil) }.to raise_error(ArgumentError)
    expect { client.sales.create(payload: []) }.to raise_error(ArgumentError)
  end

  it "rejects unsupported read filters before dispatch" do
    client = build_client(Faraday::Adapter::Test::Stubs.new)
    %i[products product_availability carriers].each do |resource|
      expect { client.public_send(resource).list(unsupported: true) }.to raise_error(ArgumentError, /Unknown parameters/)
    end
    expect { client.fulfilments.for_sale(sale_id: "sale-id", unsupported: true) }.to raise_error(ArgumentError, /Unknown parameters/)
    expect { client.picks.for_task(task_id: "task-id", unsupported: true) }.to raise_error(ArgumentError, /Unknown parameters/)
    expect { client.packs.for_task(task_id: "task-id", unsupported: true) }.to raise_error(ArgumentError, /Unknown parameters/)
  end
end
