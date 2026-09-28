# frozen_string_literal: true

RSpec.describe Cin7CoreAPI::Connection do
  it "sends CIN7 credentials and JSON headers" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/me") do |env|
        expect(env.request_headers["api-auth-accountid"]).to eq("test-account-id")
        expect(env.request_headers["api-auth-applicationkey"]).to eq("test-application-key")
        expect(env.request_headers["Accept"]).to eq("application/json")
        expect(env.request_headers["Content-Type"]).to eq("application/json")
        expect(env.request_headers["User-Agent"]).to eq("cin7_core_api/#{Cin7CoreAPI::VERSION}")

        json_response({"Company" => "PostCo Test"})
      end
    end

    response = build_client(stubs).me.retrieve

    expect(response.status).to eq(200)
    expect(response.body).to eq("Company" => "PostCo Test")
    expect(response).to be_success
    stubs.verify_stubbed_calls
  end

  it "normalizes response header names" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/me") do
        json_response({}, headers: {"Retry-After" => "15"})
      end
    end

    response = build_client(stubs).me.retrieve

    expect(response.headers["retry-after"]).to eq("15")
  end

  it "handles a successful response without content" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/me") { [204, {}, ""] }
    end

    response = build_client(stubs).me.retrieve

    expect(response.body).to be_nil
    expect(response).to be_no_content
  end

  it "raises a parse error while retaining a non-JSON successful response" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/me") { [200, {"Content-Type" => "text/html"}, "not-json"] }
    end

    expect do
      build_client(stubs).me.retrieve
    end.to raise_error(Cin7CoreAPI::ParseError) { |error|
      expect(error.status).to eq(200)
      expect(error.body).to eq("not-json")
    }
  end

  {
    400 => Cin7CoreAPI::BadRequestError,
    401 => Cin7CoreAPI::AuthenticationError,
    403 => Cin7CoreAPI::ForbiddenError,
    404 => Cin7CoreAPI::NotFoundError,
    405 => Cin7CoreAPI::MethodNotAllowedError,
    429 => Cin7CoreAPI::RateLimitError,
    500 => Cin7CoreAPI::ServerError,
    503 => Cin7CoreAPI::ServerError
  }.each do |status, error_class|
    it "maps HTTP #{status} to #{error_class}" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/ExternalApi/v2/me") do
          json_response({"ErrorCode" => status}, status: status, headers: {"Retry-After" => "30"})
        end
      end

      expect do
        build_client(stubs).me.retrieve
      end.to raise_error(error_class) { |error|
        expect(error.status).to eq(status)
        expect(error.body).to eq("ErrorCode" => status)
        expect(error.retry_after).to eq("30")
      }
    end
  end

  it "preserves a non-JSON error body" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/me") { [503, {"Content-Type" => "text/html"}, "Service unavailable"] }
    end

    expect do
      build_client(stubs).me.retrieve
    end.to raise_error(Cin7CoreAPI::ServerError) { |error|
      expect(error.body).to eq("Service unavailable")
    }
  end

  it "wraps Faraday transport failures" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/me") { raise Faraday::TimeoutError, "execution expired" }
    end

    expect do
      build_client(stubs).me.retrieve
    end.to raise_error(Cin7CoreAPI::TransportError, /Faraday::TimeoutError/) { |error|
      expect(error).not_to be_ambiguous
      expect(error.cause).to be_nil
    }
  end
end
