# frozen_string_literal: true

RSpec.describe "CIN7 Core write failures" do
  %i[post put delete].each do |method|
    {
      timeout: [nil, nil, Cin7CoreAPI::TransportError],
      server: [503, {"Error" => "upstream failed"}, Cin7CoreAPI::ServerError],
      invalid_json: [200, "invalid-json", Cin7CoreAPI::ParseError],
      empty_success: [200, "", Cin7CoreAPI::ParseError]
    }.each do |failure, (status, body, error_class)|
      it "marks #{method} #{failure} ambiguous without retrying" do
        calls = 0
        stubs = Faraday::Adapter::Test::Stubs.new do |stub|
          stub.public_send(method, "/ExternalApi/v2/sale/payment") do
            calls += 1
            raise Faraday::TimeoutError, "secret request dump" if failure == :timeout

            [status, {"Retry-After" => "12"}, body.is_a?(Hash) ? JSON.generate(body) : body]
          end
        end
        connection = build_client(stubs).connection
        options = (method == :delete) ? {params: {"ID" => "payment-id"}} : {payload: {"TaskID" => "task-id"}}

        expect do
          connection.public_send(method, "sale/payment", **options)
        end.to raise_error(error_class) { |error|
          expect(error).to be_ambiguous
          expect(error.request_method).to eq(method)
          expect(error.request_path).to eq("sale/payment")
          expect(error.message).not_to include("secret request dump")
          expect(error.cause).to be_nil
          expect(error.retry_after).to eq("12") unless failure == :timeout
        }
        expect(calls).to eq(1)
        stubs.verify_stubbed_calls
      end
    end
  end

  [400, 401, 403, 404, 405, 429].each do |status|
    it "reports HTTP #{status} as a rejection and never retries" do
      calls = 0
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("/ExternalApi/v2/sale/payment") do
          calls += 1
          json_response({"ErrorCode" => status}, status: status, headers: {"Retry-After" => "30"})
        end
      end
      expect do
        build_client(stubs).payments.create(payload: {"TaskID" => "task-id"})
      end.to raise_error(Cin7CoreAPI::Error) { |error|
        expect(error).not_to be_ambiguous
        expect(error.status).to eq(status)
        expect(error.retry_after).to eq("30")
      }
      expect(calls).to eq(1)
    end
  end

  it "does not classify a read 5xx as an ambiguous mutation" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/me") { json_response({}, status: 500) }
    end
    expect { build_client(stubs).me.retrieve }.to raise_error(Cin7CoreAPI::ServerError) { |error| expect(error).not_to be_ambiguous }
  end

  it "accepts 204 for a successful deletion" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.delete("/ExternalApi/v2/sale/payment?ID=payment-id") { [204, {}, ""] }
    end
    result = build_client(stubs).payments.delete(id: "payment-id")
    expect(result.status).to eq(204)
    expect(result).to be_no_content
  end

  it "rejects invalid JSON input before dispatch" do
    client = build_client(Faraday::Adapter::Test::Stubs.new)
    expect { client.payments.create(payload: {"TaskID" => "task-id", "Amount" => Float::NAN}) }.to raise_error(JSON::GeneratorError)
  end

  it "distinguishes a valid JSON string from a parse failure" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/me") { json_response("valid string") }
    end
    expect(build_client(stubs).me.retrieve.body).to eq("valid string")
  end
end
