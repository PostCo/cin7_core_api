# frozen_string_literal: true

module Cin7CoreAPI
  class Client
    DEFAULT_BASE_URL = "https://inventory.dearsystems.com/ExternalApi/v2/"
    DEFAULT_OPEN_TIMEOUT = 5
    DEFAULT_TIMEOUT = 30

    attr_reader :connection

    def initialize(
      account_id:,
      application_key:,
      base_url: DEFAULT_BASE_URL,
      open_timeout: DEFAULT_OPEN_TIMEOUT,
      timeout: DEFAULT_TIMEOUT,
      adapter: Faraday.default_adapter
    )
      validate_credential!(:account_id, account_id)
      validate_credential!(:application_key, application_key)

      @connection = Connection.new(
        account_id: account_id,
        application_key: application_key,
        base_url: base_url,
        open_timeout: open_timeout,
        timeout: timeout,
        adapter: adapter
      )
    end

    def me
      @me ||= Resources::Me.new(connection)
    end

    def sales
      @sales ||= Resources::Sales.new(connection)
    end

    def credit_notes
      @credit_notes ||= Resources::CreditNotes.new(connection)
    end

    def payments
      @payments ||= Resources::Payments.new(connection)
    end

    def locations
      @locations ||= Resources::Locations.new(connection)
    end

    def accounts
      @accounts ||= Resources::Accounts.new(connection)
    end

    def bank_accounts
      @bank_accounts ||= Resources::BankAccounts.new(connection)
    end

    def customers
      @customers ||= Resources::Customers.new(connection)
    end

    def customer_credits
      @customer_credits ||= Resources::CustomerCredits.new(connection)
    end

    def orders
      @orders ||= Resources::Orders.new(connection)
    end

    def invoices
      @invoices ||= Resources::Invoices.new(connection)
    end

    def manual_journals
      @manual_journals ||= Resources::ManualJournals.new(connection)
    end

    def journals
      @journals ||= Resources::Journals.new(connection)
    end

    def tax_rules
      @tax_rules ||= Resources::TaxRules.new(connection)
    end

    def webhooks
      @webhooks ||= Resources::Webhooks.new(connection)
    end

    def fulfilments
      @fulfilments ||= Resources::Fulfilments.new(connection)
    end

    def picks
      @picks ||= Resources::Picks.new(connection)
    end

    def packs
      @packs ||= Resources::Packs.new(connection)
    end

    def shipments
      @shipments ||= Resources::Shipments.new(connection)
    end

    def products
      @products ||= Resources::Products.new(connection)
    end

    def product_availability
      @product_availability ||= Resources::ProductAvailability.new(connection)
    end

    def carriers
      @carriers ||= Resources::Carriers.new(connection)
    end

    def inspect
      "#<#{self.class}>"
    end

    private

    def validate_credential!(name, value)
      return if value.is_a?(String) && !value.strip.empty?

      raise ArgumentError, "#{name} must be a non-empty String"
    end
  end
end
