# frozen_string_literal: true

RSpec.describe "CIN7 Core credential redaction" do
  let(:blueprint_webhook) do
    {
      "ID" => "0bd90aa9-72f9-4f9c-bb0d-9f7cc406b07a",
      "Type" => "Sale/OrderAuthorised",
      "Name" => "Sale order has been authorised",
      "IsActive" => false,
      "ExternalURL" => "https://hookb.in/Zn8950P7",
      "ExternalAuthorizationType" => "basicauth",
      "ExternalUserName" => "Hello",
      "ExternalPassword" => "123",
      "ExternalBearerToken" => "",
      "ExternalHeaders" => [{"Key" => "Key", "Value" => "123"}, {"Key" => "6", "Value" => "0"}]
    }
  end

  it "preserves callback identity for the complete Blueprint webhook and other subscriptions" do
    other_hook = blueprint_webhook.merge(
      "ID" => "1cf8cb83-bf39-494b-87f9-1252b684d6d5", "Type" => "Sale/Created", "IsActive" => true,
      "ExternalURL" => "https://PostCo.example:443/webhook/cin7_core/10123?shop=HelloShop&version=10&format=%30a#section0",
      "ExternalAuthorizationType" => "bearerauth", "ExternalUserName" => "Sale", "ExternalPassword" => nil,
      "ExternalBearerToken" => "callback-private-token", "ExternalHeaders" => []
    )
    payload = {"Webhooks" => [blueprint_webhook, other_hook]}
    original = Marshal.load(Marshal.dump(payload))
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/webhooks") { json_response(payload) }
      stub.post("/ExternalApi/v2/webhooks") do |env|
        expect(JSON.parse(env.body)).to eq(original.fetch("Webhooks").first)
        json_response({"Webhooks" => [blueprint_webhook]})
      end
    end

    client = build_client(stubs)
    created = client.webhooks.create(payload: blueprint_webhook).body.fetch("Webhooks").first
    expect(created.fetch("ExternalURL")).to eq(blueprint_webhook.fetch("ExternalURL"))
    hooks = client.webhooks.list.body.fetch("Webhooks")
    hooks.zip(payload.fetch("Webhooks")).each do |actual, expected|
      %w[ID Type IsActive ExternalURL ExternalAuthorizationType].each do |key|
        expect(actual.fetch(key)).to eq(expected.fetch(key))
      end
      %w[ExternalUserName ExternalPassword ExternalBearerToken ExternalHeaders].each do |key|
        expect(actual.fetch(key)).to eq("[FILTERED]")
      end
    end
    expect(payload).to eq(original)
    stubs.verify_stubbed_calls
  end

  it "sanitizes URL credentials and their earlier free-text echoes without re-encoding callback identity" do
    url = "https://url-user:uri%2Dpassword@PostCo.example:443/hooks/10123?shop=10&access%5Ftoken=url%2Dtoken" \
      "&API_AUTH_ACCOUNTID=url-account&password=query%20password&authorization=Bearer%20signed-token&opaque=test-application-key&next=HelloShop#secret=fragment-secret"
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/webhooks") do
        json_response({"Message" => "url-user uri-password uri%2Dpassword url-token url%2Dtoken url-account query password signed-token fragment-secret",
                       "Webhooks" => [blueprint_webhook.merge("ExternalURL" => url)]})
      end
    end
    response = build_client(stubs).webhooks.list
    hook = response.body.fetch("Webhooks").first
    expect(hook.fetch("ExternalURL")).to eq(
      "https://[FILTERED]@PostCo.example:443/hooks/10123?shop=10&access%5Ftoken=[FILTERED]" \
      "&API_AUTH_ACCOUNTID=[FILTERED]&password=[FILTERED]&authorization=[FILTERED]&opaque=[FILTERED]&next=HelloShop#secret=[FILTERED]"
    )
    %w[url-user uri-password uri%2Dpassword url-token url%2Dtoken url-account signed-token fragment-secret test-application-key].each do |secret|
      expect(JSON.generate(response.body)).not_to include(secret)
    end
    expect(response.body.fetch("Message")).not_to include("query password")
  end

  it "filters complete credential components in callbacks while retaining incidental substrings" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/webhooks") do
        json_response({"Webhooks" => [blueprint_webhook.merge(
          "ExternalURL" => "https://private-token.callback0.example/hooks/private%2Dtoken?opaque=private-token&reference=prefix0suffix",
          "ExternalBearerToken" => "private-token"
        )]})
      end
    end
    url = build_client(stubs).webhooks.list.body.fetch("Webhooks").first.fetch("ExternalURL")
    expect(url).to eq("https://[FILTERED].callback0.example/hooks/[FILTERED]?opaque=[FILTERED]&reference=prefix0suffix")
  end

  it "filters outbound callback credentials echoed in a non-JSON error without changing the submitted URL" do
    payload = {"ExternalURL" => "https://callback-user:callback-password@example.test/hook?api_key=query%2Dcredential"}
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/ExternalApi/v2/webhooks") do |env|
        expect(JSON.parse(env.body)).to eq(payload)
        [503, {}, "callback-user callback-password query-credential query%2Dcredential"]
      end
    end
    expect { build_client(stubs).webhooks.create(payload: payload) }.to raise_error(Cin7CoreAPI::ServerError) { |error|
      expect(error.body).to eq("[FILTERED] [FILTERED] [FILTERED] [FILTERED]")
      expect(error).to be_ambiguous
      expect(error.cause).to be_nil
    }
  end

  it "filters username-only URL authentication and rejects malformed credential-bearing callbacks safely" do
    %w[https://private-user@example.test/hook https://user:password@example.test/invalid%query?token=%ZZ].each do |url|
      filtered = Cin7CoreAPI::Redactor.new.with_sensitive_values({"ExternalURL" => url}).filter({"ExternalURL" => url})
      expect(filtered.fetch("ExternalURL")).not_to include("private-user", "password", "%ZZ")
    end
  end

  it "preserves business account GUIDs and nulls across bank/account reads without learning them as credentials" do
    bank_id = "d5b0294d-e931-47d4-a58c-5c9e2d7d3090"
    bank = {"AccountID" => bank_id, "Bank" => "Unknown Bank", "AccountName" => "EFT bank account",
            "AccountNumber" => "No Number", "AccountCode" => "713", "Currency" => "AUD",
            "StatementBalance" => 0, "BalanceInDear" => 0, "InitialBalance" => 0}
    banks = {"Total" => 1, "Page" => 1, "BankAccountsList" => [bank]}
    accounts = {"Total" => 2, "Page" => 1, "AccountsList" => [
      {"Code" => "713", "BankAccountId" => bank_id, "Description" => "Linked bank #{bank_id}"},
      {"Code" => "800", "BankAccountId" => nil, "AccountID" => nil}
    ]}
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/ref/account/bank") { json_response(banks) }
      stub.get("/ExternalApi/v2/ref/account") { json_response(accounts) }
    end
    client = build_client(stubs)
    expect(client.bank_accounts.list.body).to eq(banks)
    expect(client.accounts.list.body).to eq(accounts)
    stubs.verify_stubbed_calls
  end

  it "still filters API account-ID headers and exact client credential echoes in business identifier fields" do
    credential = "11111111-1111-1111-1111-111111111111"
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/ref/account/bank") do
        json_response({"BankAccountsList" => [{"AccountID" => credential, "BankAccountId" => credential}],
                       "ExternalURL" => credential, "Message" => "echo: #{credential} unknown-account-credential"},
          headers: {"API_AUTH_ACCOUNTID" => "unknown-account-credential", "X-Echo" => credential})
      end
    end
    client = Cin7CoreAPI::Client.new(account_id: credential, application_key: "test-application-key",
      base_url: ClientHelpers::TEST_BASE_URL, adapter: [:test, stubs])
    response = client.bank_accounts.list
    expect(response.body.fetch("BankAccountsList").first).to eq("AccountID" => "[FILTERED]", "BankAccountId" => "[FILTERED]")
    expect(response.body.fetch("ExternalURL")).to eq("[FILTERED]")
    expect(response.headers.fetch("api_auth_accountid")).to eq("[FILTERED]")
    expect(JSON.generate([response.body, response.headers])).not_to include(credential, "unknown-account-credential")
  end

  it "sanitizes webhook responses and headers without changing outbound credentials or input" do
    payload = {"Type" => "Sale/Created", "ExternalAuthorizationType" => "bearerauth",
               "ExternalBearerToken" => "private-hook-token", "ExternalPassword" => "private-password",
               "ExternalUserName" => "private-user", "IsActive" => false,
               "ExternalHeaders" => [{"Key" => "X-Custom", "Value" => "custom-secret"}]}
    original = Marshal.load(Marshal.dump(payload))
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/ExternalApi/v2/webhooks") do |env|
        expect(JSON.parse(env.body)).to eq(original)
        expect(env.request_headers["api-auth-applicationkey"]).to eq("test-application-key")
        response = {"Webhooks" => [payload.merge("ID" => "hook-id", "Note" => "private-hook-token private-password custom-secret")]}
        json_response(response, headers: {"Authorization" => "Bearer private-hook-token", "Set-Cookie" => "session=secret",
                                          "api-auth-accountid" => "test-account-id", "X-API-Key" => "unknown-response-key", "Retry-After" => "20"})
      end
    end
    response = build_client(stubs).webhooks.create(payload: payload)
    serialized = JSON.generate([response.body, response.headers])
    %w[private-hook-token private-password private-user custom-secret session=secret test-account-id unknown-response-key].each do |secret|
      expect(serialized).not_to include(secret)
    end
    hook = response.body.fetch("Webhooks").first
    expect(hook.fetch("ID")).to eq("hook-id")
    expect(hook.fetch("ExternalAuthorizationType")).to eq("bearerauth")
    expect(hook.fetch("IsActive")).to be(false)
    expect(response.headers.fetch("retry-after")).to eq("20")
    expect(payload).to eq(original)
  end

  it "filters newly discovered response secrets even when repeated in earlier error text" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/webhooks") do
        json_response({"Message" => "unexpected-token unknown-header-secret", "Webhooks" => [{"ExternalBearerToken" => "unexpected-token"}]},
          status: 400, headers: {"X-API-Key" => "unknown-header-secret"})
      end
    end
    expect { build_client(stubs).webhooks.list }.to raise_error(Cin7CoreAPI::BadRequestError) { |error|
      expect([error.message, error.inspect, error.full_message, error.body, error.headers].inspect).not_to include("unexpected-token", "unknown-header-secret")
      expect(error.body.fetch("Message")).to include("[FILTERED]")
    }
  end

  it "keeps webhook identifiers usable when a custom header contains zero" do
    hook_id = "0bd90aa9-72f9-4f9c-bb0d-9f7cc406b07a"
    hook = {"ID" => hook_id, "Type" => "Sale/Created", "IsActive" => true,
            "ExternalHeaders" => [{"Key" => "X-Option", "Value" => "0"}],
            "Note" => "echo: prefix0suffix"}
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/webhooks") { json_response({"Webhooks" => [hook]}) }
      stub.put("/ExternalApi/v2/webhooks") do |env|
        expect(JSON.parse(env.body)).to eq("ID" => hook_id, "IsActive" => false)
        json_response({"Webhooks" => [hook.merge("IsActive" => false)]})
      end
      stub.delete("/ExternalApi/v2/webhooks?ID=#{hook_id}") { json_response({"Webhooks" => []}) }
    end
    client = build_client(stubs)
    listed = client.webhooks.list.body.fetch("Webhooks").first
    expect(listed.fetch("ID")).to eq(hook_id)
    expect(listed.fetch("ExternalHeaders")).to eq("[FILTERED]")
    expect(listed.fetch("Note")).to eq("echo: prefix[FILTERED]suffix")
    updated = client.webhooks.update(payload: {"ID" => listed.fetch("ID"), "IsActive" => false})
    client.webhooks.delete(id: updated.body.fetch("Webhooks").first.fetch("ID"))
    stubs.verify_stubbed_calls
  end

  %w[body headers ID Webhooks ExternalBearerToken].each do |credential|
    it "preserves envelope and schema keys when a credential equals #{credential}" do
      payload = {"ExternalBearerToken" => credential}
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("/ExternalApi/v2/webhooks") do |env|
          expect(JSON.parse(env.body)).to eq(payload)
          json_response({"Webhooks" => [payload.merge("ID" => "hook-id", "Note" => "echo: #{credential}")]},
            headers: {"X-Message" => "echo: #{credential}"})
        end
      end
      response = build_client(stubs).webhooks.create(payload: payload)
      hook = response.body.fetch("Webhooks").first
      expect(hook.keys).to contain_exactly("ExternalBearerToken", "ID", "Note")
      expect(hook.fetch("ID")).to eq("hook-id")
      expect(hook.fetch("ExternalBearerToken")).to eq("[FILTERED]")
      expect(hook.fetch("Note")).to eq("echo: [FILTERED]")
      expect(response.headers.fetch("x-message")).to eq("echo: [FILTERED]")
      expect(response.inspect).to eq("#<Cin7CoreAPI::Response status=200>")
      expect(payload).to eq("ExternalBearerToken" => credential)
      stubs.verify_stubbed_calls
    end
  end

  it "preserves GUID identifiers without exempting exact credential matches or free text" do
    identifier = "00000000-0000-0000-0000-000000000000"
    secret = "11111111-1111-1111-1111-111111111111"
    value = {"SaleID" => identifier, "TaskID" => identifier, "CreditID" => nil, "ID" => secret,
             "Message" => "echo: #{identifier} #{secret}", "Note" => identifier}
    filtered = Cin7CoreAPI::Redactor.new(["0", secret]).filter(value)
    expect(filtered.fetch("SaleID")).to eq(identifier)
    expect(filtered.fetch("TaskID")).to eq(identifier)
    expect(filtered.fetch("CreditID")).to be_nil
    expect(filtered.fetch("ID")).to eq("[FILTERED]")
    expect(filtered.fetch("Message")).not_to include("0", secret)
    expect(filtered.fetch("Note")).not_to include("0")
  end

  it "retains ambiguous write errors and redacts echoes when a credential equals body" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/ExternalApi/v2/webhooks") do
        json_response({"Message" => "echo: body"}, status: 503, headers: {"X-Message" => "echo: body"})
      end
    end
    expect do
      build_client(stubs).webhooks.create(payload: {"ExternalBearerToken" => "body"})
    end.to raise_error(Cin7CoreAPI::ServerError) { |error|
      expect(error).to be_ambiguous
      expect(error.status).to eq(503)
      expect(error.body.fetch("Message")).to eq("echo: [FILTERED]")
      expect(error.headers.fetch("x-message")).to eq("echo: [FILTERED]")
      expect(error.full_message).not_to include("echo: body")
      expect(error.cause).to be_nil
    }
    stubs.verify_stubbed_calls
  end

  it "redacts known secrets and labeled secrets from non-JSON bodies" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/ExternalApi/v2/webhooks") do
        [503, {}, 'test-application-key test-account-id password="unknown-password" ExternalBearerToken: unknown-token Bearer unknown-bearer private-hook-token']
      end
    end
    expect do
      build_client(stubs).webhooks.create(payload: {"ExternalBearerToken" => "private-hook-token"})
    end.to raise_error(Cin7CoreAPI::ServerError) { |error|
      %w[test-application-key test-account-id unknown-password unknown-token unknown-bearer private-hook-token].each do |secret|
        expect([error.body, error.message, error.full_message].inspect).not_to include(secret)
      end
    }
  end

  it "does not retain the unsafe transport exception as a cause" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/ExternalApi/v2/webhooks") do
        raise Faraday::ConnectionFailed, "test-application-key and arbitrary-request-secret"
      end
    end
    expect { build_client(stubs).webhooks.create(payload: {}) }.to raise_error(Cin7CoreAPI::TransportError) { |error|
      expect(error.cause).to be_nil
      expect(error.full_message).not_to include("test-application-key", "arbitrary-request-secret")
      expect(error).to be_ambiguous
    }
  end

  it "does not expose credentials or response contents through inspect" do
    client = build_client(Faraday::Adapter::Test::Stubs.new)
    objects = [client, client.connection, client.webhooks, Cin7CoreAPI::Redactor.new(["inspect-secret"]),
      Cin7CoreAPI::Response.new(status: 200, headers: {}, body: {"Note" => "private response"})]
    expect(objects.map(&:inspect).join).not_to include("test-account-id", "test-application-key", "inspect-secret", "private response")
  end

  it "does not leak secrets across clients" do
    first = Cin7CoreAPI::Redactor.new(["tenant-one-secret"])
    second = Cin7CoreAPI::Redactor.new(["tenant-two-secret"])
    expect(first.filter("tenant-one-secret tenant-two-secret")).to eq("[FILTERED] tenant-two-secret")
    expect(second.filter("tenant-one-secret tenant-two-secret")).to eq("tenant-one-secret [FILTERED]")
  end

  it "recognizes sensitive keys regardless of case or separators" do
    value = {"external_headers" => [{"Key" => "X-Secret", "Value" => "custom-value"}],
             "API_AUTH_APPLICATIONKEY" => "application-value", "external_bearer_token" => "bearer-value",
             "Description" => "custom-value application-value bearer-value"}
    filtered = Cin7CoreAPI::Redactor.new.with_sensitive_values(value).filter(value)
    expect(filtered.fetch("external_headers")).to eq("[FILTERED]")
    expect(filtered.fetch("Description")).not_to include("custom-value", "application-value", "bearer-value")
  end

  it "does not treat custom header names as secrets or corrupt webhook field names" do
    value = {"ID" => "hook-id", "ExternalAuthorizationType" => "basicauth",
             "ExternalHeaders" => [{"Key" => "ID", "Value" => "private-value"}, {"Key" => "Authorization", "Value" => "custom-auth"}]}
    filtered = Cin7CoreAPI::Redactor.new.with_sensitive_values(value).filter(value)
    expect(filtered.fetch("ID")).to eq("hook-id")
    expect(filtered.fetch("ExternalAuthorizationType")).to eq("basicauth")
    expect(filtered.fetch("ExternalHeaders")).to eq("[FILTERED]")
  end

  it "redacts URL credentials and an authorization token echoed without its scheme" do
    value = {"Authorization" => "Bearer unusual-bearer-value", "Message" => "unusual-bearer-value",
             "ExternalURL" => "https://name:uri-password@example.test/hook"}
    filtered = Cin7CoreAPI::Redactor.new.with_sensitive_values(value).filter(value)
    expect(filtered.fetch("Message")).to eq("[FILTERED]")
    expect(filtered.fetch("ExternalURL")).to eq("https://[FILTERED]@example.test/hook")
  end
end
