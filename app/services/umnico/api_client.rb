require 'net/http'
require 'uri'
require 'json'

module Umnico
  class ApiClient
    class Error < StandardError; end

    BASE_URL = 'https://api.umnico.com/v1.3'.freeze

    def initialize(api_token:, base_url: BASE_URL)
      @api_token = api_token
      @base_url = base_url
    end

    # Verify token / get account + user info
    def get_account
      request(:get, '/account/me')
    end

    # List webhooks
    def list_webhooks
      request(:get, '/webhooks/')
    end

    # Create webhook
    def create_webhook(url:, name: 'chatwoot')
      request(:post, '/webhooks/', body: { url: url, name: name })
    end

    # Delete webhook
    def delete_webhook(webhook_id)
      request(:delete, "/webhooks/#{webhook_id}")
    end

    # Get lead details
    def get_lead(lead_id)
      request(:get, "/leads/#{lead_id}")
    end

    # Get message sources (channels) for a lead
    def get_lead_sources(lead_id)
      request(:get, "/messaging/#{lead_id}/sources")
    end

    # Get message history for a lead+source
    def get_message_history(lead_id, source_real_id, cursor: nil)
      body = cursor.present? ? { cursor: cursor } : {}
      request(:post, "/messaging/#{lead_id}/history/#{source_real_id}", body: body.presence)
    end

    # Send message to a lead
    def send_message(lead_id:, text: nil, attachment: nil, source: nil, user_id: nil)
      body = { message: {} }
      body[:message][:text] = text if text.present?
      body[:message][:attachment] = attachment if attachment.present?
      body[:source] = source if source.present?
      body[:userId] = user_id if user_id.present?

      request(:post, "/messaging/#{lead_id}/send", body: body)
    end

    # Upload file for attachment
    def upload_file(file_path:, content_type: 'application/octet-stream')
      uri = URI("#{@base_url}/messaging/upload")

      http = build_http(uri)
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "bearer #{@api_token}"

      form_data = [['file', File.open(file_path), { content_type: content_type }]]
      request.set_form(form_data, 'multipart/form-data')

      response = http.request(request)
      parsed = parse_response_body(response.body)
      return parsed if response.is_a?(Net::HTTPSuccess)

      raise Error, "status=#{response.code} body=#{parsed}"
    end

    # Get customer info
    def get_customer(customer_id)
      request(:get, "/customers/#{customer_id}/")
    end

    private

    attr_reader :api_token, :base_url

    def request(method, path, query: nil, body: nil)
      uri = URI("#{base_url}#{path}")
      uri.query = URI.encode_www_form(query) if query.present?

      http = build_http(uri)

      req = build_request(method, uri, body)
      req['Authorization'] = "bearer #{api_token}"
      req['Content-Type'] = 'application/json' if body.present?

      response = http.request(req)
      parsed = parse_response_body(response.body)
      return parsed if response.is_a?(Net::HTTPSuccess)

      raise Error, "status=#{response.code} body=#{parsed}"
    end

    def build_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = 30
      http.open_timeout = 10
      http
    end

    def build_request(method, uri, body)
      klass = case method
              when :get    then Net::HTTP::Get
              when :post   then Net::HTTP::Post
              when :put    then Net::HTTP::Put
              when :delete then Net::HTTP::Delete
              else raise ArgumentError, "Unsupported method #{method}"
              end

      req = klass.new(uri)
      req.body = JSON.dump(body) if body.present?
      req
    end

    def parse_response_body(body)
      return {} if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError
      body
    end
  end
end
