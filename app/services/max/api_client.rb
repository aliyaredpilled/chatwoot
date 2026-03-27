require 'net/http'
require 'uri'
require 'json'

module Max
  class ApiClient
    class Error < StandardError; end

    DEFAULT_BASE_URL = 'https://platform-api.max.ru'.freeze

    def initialize(bot_token:, base_url: DEFAULT_BASE_URL)
      @bot_token = bot_token
      @base_url = base_url
    end

    def get_me
      request(:get, '/me')
    end

    def get_updates(marker: nil, limit: 100, timeout: 20, types: nil)
      query = {
        marker: marker,
        limit: limit,
        timeout: timeout,
        types: Array(types).presence&.join(',')
      }.compact

      request(:get, '/updates', query: query)
    end

    def send_message(chat_id: nil, user_id: nil, text: nil, attachments: nil, link: nil, format: 'markdown')
      request(
        :post,
        '/messages',
        query: {
          chat_id: chat_id,
          user_id: user_id
        }.compact,
        body: {
          text: text,
          attachments: attachments,
          link: link,
          format: format
        }.compact
      )
    end

    private

    attr_reader :bot_token, :base_url

    def request(method, path, query: nil, body: nil)
      uri = URI.join(base_url, path)
      uri.query = URI.encode_www_form(query) if query.present?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = 60

      request = build_request(method, uri, body)
      request['Authorization'] = bot_token
      request['Content-Type'] = 'application/json' if body.present?

      response = http.request(request)
      parsed_body = parse_response_body(response.body)
      return parsed_body if response.is_a?(Net::HTTPSuccess)

      raise Error, "status=#{response.code} body=#{parsed_body}"
    end

    def build_request(method, uri, body)
      request_klass =
        case method
        when :get then Net::HTTP::Get
        when :post then Net::HTTP::Post
        when :put then Net::HTTP::Put
        when :delete then Net::HTTP::Delete
        else
          raise ArgumentError, "Unsupported method #{method}"
        end

      request = request_klass.new(uri)
      request.body = JSON.dump(body) if body.present?
      request
    end

    def parse_response_body(body)
      return {} if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError
      body
    end
  end
end
