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

    # Send message to a lead.
    # custom_id: opaque string stored by Umnico for deduplication / matching (e.g. "chatwoot:42")
    # reply_id:  numeric Umnico message ID to quote/reply to
    def send_message(lead_id:, text: nil, attachment: nil, source: nil, user_id: nil, custom_id: nil, reply_id: nil)
      body = { message: {} }
      body[:message][:text] = text if text.present?
      body[:message][:attachment] = attachment if attachment.present?
      body[:source] = source if source.present?
      body[:userId] = user_id if user_id.present?
      body[:customId] = custom_id if custom_id.present?
      body[:replyId] = reply_id if reply_id.present?

      request(:post, "/messaging/#{lead_id}/send", body: body)
    end

    # Upload file for attachment.
    # source: realId of the channel (source.realId from conversation attrs)
    # file_path: local path to the downloaded file
    # content_type: MIME type of the file
    # Returns the full upload response, e.g. { 'media' => {...}, 'type' => 'photo' }
    def upload_file(source:, file_path:, content_type: 'application/octet-stream')
      uri = URI("#{@base_url}/messaging/upload")

      http = build_http(uri)
      req = Net::HTTP::Post.new(uri)
      req['Authorization'] = "bearer #{@api_token}"

      form_data = [
        ['source', source],
        ['media', File.open(file_path), { content_type: content_type }]
      ]
      req.set_form(form_data, 'multipart/form-data')

      response = http.request(req)
      parsed = parse_response_body(response.body)
      return parsed if response.is_a?(Net::HTTPSuccess)

      raise Error, build_error_message(response.code, parsed)
    end

    # Get customer info
    def get_customer(customer_id)
      request(:get, "/customers/#{customer_id}/")
    end

    # Get managers (employees) list
    def get_managers
      request(:get, '/managers')
    end

    # List all integrations for the account
    def list_integrations
      request(:get, '/integrations')
    end

    # Write first to a new contact (POST /v1.3/messaging/post)
    # sa_id:       integration ID (integer)
    # destination: phone number, Telegram login, or email
    # text:        message text
    # custom_id:   optional opaque string for deduplication
    def send_outbound_message(sa_id:, destination:, text:, custom_id: nil)
      body = {
        message: { text: text },
        saId: sa_id,
        destination: destination
      }
      body[:customId] = custom_id if custom_id.present?

      request(:post, '/messaging/post', body: body)
    end

    # Check whether a WhatsApp/WABA number exists
    # sa_id:   integration ID
    # chat_id: phone number to check
    def check_contact(sa_id:, chat_id:)
      request(:post, '/messaging/check-contact', body: { saId: sa_id, chatId: chat_id })
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

      raise Error, build_error_message(response.code, parsed)
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

    def build_error_message(status_code, parsed)
      details = extract_error_details(parsed)
      return details if details.present?

      "Umnico API request failed with status #{status_code}"
    end

    def extract_error_details(parsed)
      case parsed
      when Hash
        parsed['message'].presence ||
          parsed['error'].presence ||
          extract_nested_errors(parsed['errors'])
      when Array
        extract_nested_errors(parsed)
      else
        parsed.to_s.presence
      end
    end

    def extract_nested_errors(errors)
      return if errors.blank?

      Array(errors).filter_map do |entry|
        case entry
        when String
          extract_message_from_string(entry)
        when Hash
          entry['message'].presence || extract_nested_errors(entry['errors'])
        else
          entry.to_s.presence
        end
      end.first
    end

    def extract_message_from_string(value)
      return value if value.exclude?('{') && value.exclude?('[')

      parsed = JSON.parse(value)
      extract_error_details(parsed) || value
    rescue JSON::ParserError
      value
    end
  end
end
