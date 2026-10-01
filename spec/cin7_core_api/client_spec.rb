# frozen_string_literal: true

RSpec.describe Cin7CoreAPI::Client do
  describe "credentials" do
    it "requires a non-empty account ID" do
      expect do
        described_class.new(account_id: " ", application_key: "key")
      end.to raise_error(ArgumentError, "account_id must be a non-empty String")
    end

    it "requires a non-empty application key" do
      expect do
        described_class.new(account_id: "account", application_key: nil)
      end.to raise_error(ArgumentError, "application_key must be a non-empty String")
    end
  end

  it "memoizes each resource client" do
    stubs = Faraday::Adapter::Test::Stubs.new
    client = build_client(stubs)

    expect(client.sales).to equal(client.sales)
    expect(client.credit_notes).to equal(client.credit_notes)
    expect(client.payments).to equal(client.payments)
    %i[orders invoices manual_journals journals tax_rules webhooks fulfilments picks packs shipments products product_availability carriers].each do |resource|
      expect(client.public_send(resource)).to equal(client.public_send(resource))
    end
  end
end
