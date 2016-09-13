module Rawler
  class Base

    DEFAULT_LOGFILE = "rawler_log.txt"

    attr_accessor :responses

    def initialize(url, output, options={})
      @responses = {}

      Rawler.url      = URI.escape(url)
      output.sync     = true
      Rawler.output   = Logger.new(output)
      Rawler.username = options[:username]
      Rawler.password = options[:password]
      Rawler.wait     = options[:wait]
      Rawler.css      = options[:css]
      Rawler.ignore_fragments = options[:ignore_fragments]

      Rawler.local    = options[:local]

      Rawler.set_include_pattern(options[:include], false) unless options[:include].nil?
      Rawler.set_include_pattern(options[:iinclude], true) unless options[:iinclude].nil?

      Rawler.set_skip_pattern(options[:skip], false) unless options[:skip].nil?
      Rawler.set_skip_pattern(options[:iskip], true) unless options[:iskip].nil?

      # Using a custom logfile implies logging.
      Rawler.logfile  = options[:logfile] || DEFAULT_LOGFILE
      Rawler.log      = options[:log] || Rawler.logfile != DEFAULT_LOGFILE

      @logfile = File.new(Rawler.logfile, "w") if Rawler.log
    end

    def validate
      validate_links_in_page(Rawler.url)
      @logfile.close if Rawler.log
    end

    def errors
      @responses.reject{ |link, response|
        (100..399).include?(response[:status].to_i)
      }
    end

    private

    def validate_links_in_page(page)
      Rawler::Crawler.new(page).links.each do |page_url|
        validate_page(page_url, page)
        sleep(Rawler.wait)
      end
    end

    def validate_css_links_in_page(page)
      Rawler::Crawler.new(page).css_links.each do |page_url|
        validate_non_html(page_url, page)
        sleep(Rawler.wait)
      end
    end

    def validate_page(page_url, from_url)
      if not_yet_parsed?(page_url)
        add_status_code(page_url, from_url)
        validate_links_in_page(page_url) if same_domain?(page_url)
        validate_css_links_in_page(page_url) if same_domain?(page_url) and Rawler.css
      end
    end

    def validate_non_html(page_url, from_url)
      if not_yet_parsed?(page_url)
        add_status_code(page_url, from_url)
      end
    end

    def add_status_code(link, from_url)
      response = Rawler::Request.get(link)

      redirect_to = redirect(response, link)

      record_response(response.code, link, from_url, redirect_to)
      responses[link] = { :status => response.code.to_i }

      validate_page(redirect_to, from_url) if redirect_to

    rescue Errno::ECONNREFUSED
      record_response("Connection refused", link, from_url, redirect_to)
    rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, Errno::ETIMEDOUT,
      EOFError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError, SocketError
      record_response("Connection problems", link, from_url, redirect_to)
    rescue Exception => e
      error("Unknown error #{e} (#{e.class}) - #{link} - Called from: #{from_url}")
    end

    def redirect(response, from)
      return nil unless response['Location']
      return response['Location'] if URI.parse(response['Location']).absolute?

      URI.join(from, response['Location']).to_s
    end

    def same_domain?(link)
      URI.parse(Rawler.url).host == URI.parse(link).host
    end

    def not_yet_parsed?(link)
      responses[link].nil?
    end

    def error(message)
      Rawler.output.error(message)
    end

    def record_response(code, link, from_url, redirection=nil)
      message = "#{code} - #{link}"

      if code.to_i != 200
        message += " - Called from: #{from_url}"
      end

      message += " - Following redirection to: #{redirection}" if redirection

      code = code.to_i
      case code / 100
      when 1,2
        Rawler.output.info(message)
      when 3 then
        Rawler.output.warn(message)
      when 4,5 then
        Rawler.output.error(message)
      else
        Rawler.output.error("Unknown code #{message}")
      end
      @logfile.puts(message) if Rawler.log
    end
  end
end
