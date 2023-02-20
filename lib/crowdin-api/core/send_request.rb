# frozen_string_literal: true

module Crowdin
  module Web
    class SendRequest
      attr_reader :request
      attr_reader :retry_opts

      def initialize(request, file_destination = nil)
        @request          = request
        @retry_opts = request.retry_opts
        @file_destination = file_destination
        @errors           = []
      end

      def perform
        if retry_opts
          retry_request
        else
          parse_response(process_request)
        end
      end

      private

        def retry_request
          retry_request_delay = retry_opts[:request_delay]
          retries_count = retry_opts[:retries_count]
          retry_error_messages = retry_opts[:error_messages]

          response = ''

          loop do
            response = parse_response(process_request)
            if response.is_a?(String) && response.match('Something went wrong')
              if retries_count.positive?
                retry_error_messages.each do |message|
                  break if response.match(message)
                end
    
                retries_count -= 1
                sleep retry_request_delay
              else
                return response
              end
            else
              return response
            end
          end
        end

        def process_request
          request.send(request.method)
        rescue StandardError => e
          @errors << "Something went wrong while request processing. Details - #{e.message}"
        end

        def parse_response(response)
          return @errors.join('; ') if @errors.any?

          begin
            if response
              if response.body.empty?
                response.code
              else
                parsed_body = JSON.parse(response.body)
                parsed_response = fetch_response_data(parsed_body)

                @errors.any? ? @errors.join('; ') : parsed_response
              end
            end
          rescue StandardError => e
            @errors << "Something went wrong while response processing. Details - #{e.message}"
            @errors.join('; ')
          end
        end

        def fetch_response_data(doc)
          if doc['data'].is_a?(Hash) && doc['data']['url'] && doc['data']['url'].include?('response-content-disposition')
            download_file(doc['data']['url'])
          else
            doc
          end
        end

        def download_file(url)
          download    = URI.parse(url).open
          destination = @file_destination || download.meta['content-disposition']
                                                     .match(/filename=("?)(.+)\1/)[2]

          IO.copy_stream(download, destination)

          destination
        rescue StandardError => e
          @errors << "Something went wrong while downloading file. Details - #{e.message}"
        end
    end
  end
end
