# frozen_string_literal: true

require "socket"

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

  %i[get post put delete].each do |method|
    it "wraps #{method} decompression failures without leaking details or retrying" do
      calls = 0
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.public_send(method, "/ExternalApi/v2/sale/payment") do
          calls += 1
          raise Zlib::DataError, "test-application-key response dump"
        end
      end
      options = %i[get delete].include?(method) ? {params: {"ID" => "payment-id"}} : {payload: {"TaskID" => "task-id"}}

      expect do
        build_client(stubs).connection.public_send(method, "sale/payment", **options)
      end.to raise_error(Cin7CoreAPI::TransportError) { |error|
        expect(error.ambiguous?).to eq(method != :get)
        expect(error.request_method).to eq(method)
        expect(error.request_path).to eq("sale/payment")
        expect(error.message).not_to include("test-application-key", "response dump")
        expect(error.cause).to be_nil
      }
      expect(calls).to eq(1)
      stubs.verify_stubbed_calls
    end
  end

  it "wraps corrupt gzip responses through the default HTTP adapter" do
    server = TCPServer.new("127.0.0.1", 0)
    calls = 0
    worker = Thread.new do
      socket = server.accept
      calls += 1
      headers = []
      headers << socket.gets until headers.last == "\r\n"
      length = headers.grep(/\AContent-Length:/i).first.split(":", 2).last.to_i
      socket.read(length)
      socket.write("HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nContent-Length: 11\r\nConnection: close\r\n\r\ninvalidgzip")
    ensure
      socket&.close
    end
    client = Cin7CoreAPI::Client.new(
      account_id: "test-account-id", application_key: "test-application-key",
      base_url: "http://127.0.0.1:#{server.addr[1]}/ExternalApi/v2/", timeout: 2, open_timeout: 2
    )

    expect { client.payments.create(payload: {"TaskID" => "task-id"}) }.to raise_error(Cin7CoreAPI::TransportError) { |error|
      expect(error).to be_ambiguous
      expect(error.message).to include("Zlib::DataError")
      expect(error.request_path).to eq("sale/payment")
      expect(error.cause).to be_nil
    }
    worker.value
    expect(calls).to eq(1)
  ensure
    server&.close
    worker&.kill
    worker&.join
  end

  [Encoding::UTF_8, Encoding::BINARY].each do |encoding|
    [200, 400, 503].each do |status|
      it "safely classifies HTTP #{status} with malformed #{encoding} response bytes" do
        calls = 0
        stubs = Faraday::Adapter::Test::Stubs.new do |stub|
          stub.post("/ExternalApi/v2/sale/payment") do
            calls += 1
            [status, {}, "{\"Error\":\"test-application-key\xFF\"}".dup.force_encoding(encoding)]
          end
        end
        error_class = {200 => Cin7CoreAPI::ParseError, 400 => Cin7CoreAPI::BadRequestError, 503 => Cin7CoreAPI::ServerError}.fetch(status)

        expect do
          build_client(stubs).payments.create(payload: {"TaskID" => "task-id"})
        end.to raise_error(error_class) { |error|
          expect(error.ambiguous?).to eq(status != 400)
          expect(error.status).to eq(status)
          expect(error.request_path).to eq("sale/payment")
          expect(error.body).to be_valid_encoding
          expect(error.body).not_to include("test-application-key")
          expect(error.message).not_to include("test-application-key")
          expect(error.cause).to be_nil
        }
        expect(calls).to eq(1)
        stubs.verify_stubbed_calls
      end
    end
  end

  it "does not classify malformed read response bytes as an ambiguous mutation" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/me") { [200, {}, "bad\xFF"] }
    end
    expect { build_client(stubs).me.retrieve }.to raise_error(Cin7CoreAPI::ParseError) { |error| expect(error).not_to be_ambiguous }
  end

  it "preserves UTF-8 business data returned as binary bytes" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/ExternalApi/v2/me") { [200, {}, JSON.generate({"Name" => "Café"}).b] }
    end
    expect(build_client(stubs).me.retrieve.body).to eq({"Name" => "Café"})
  end
end
