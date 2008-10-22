%w[ rubygems uri thread curb ].each { |lib| require lib }

class MediaWiki

  VERSION = "0.0.1"

  class ApiError < StandardError

    attr_reader :raw, :code, :info, :text

    def initialize error
      @raw = error
      begin
        case error
        when Hash
          @code, @info, @text = error["error"].values_at "code", "info", "*"
        when /^(unknown_[^ ]*): (.*)$/m
          @code, @info = $1, $2
        when /^---\n *error: *\n *code: +help *\n *info: *\n *\*: *|( *\n)+(.*)$/m
          @code = "help"
          @text = $2
        else
          @code = "unknown"
          @info = error.to_s
        end
        @text ||= @info
      rescue Exception => error
        puts "Fehler"
        error = nil
        retry
      end
    end

    def to_s
      "#@code - #{@info ? @info : "(no #info given, try #text)"}"
    end

  end

  attr_reader :agent

  def initialize uri
    @uri   = uri
    @mutex = Mutex.new
    @agent = Curl::Easy.new do |curb|
      curb.enable_cookies        = true
      curb.follow_location       = true
      curb.multipart_form_post   = true
      curb.headers["User-Agent"] = "Mozilla/5.0 (compatible; MediaWiki Client " +
                                   "#{VERSION}; #{RUBY_PLATFORM})"
    end
  end

  def http_request url, post = false
     @mutex.synchronize do
      agent.url = url.to_s
      post ? agent.http_post : agent.http_get
      agent.body_str
    end
  end

  def api_request *options
    options.flatten!
    uri       = URI.parse @uri
    params    = options.extract_options!.symbolize_keys.merge :format => :yaml
    uri.query = params.to_param
    result    = http_request uri, options.include?(:post)
    begin
      raise ArgumentError unless result && result[0..3] == "---\n"
      result = YAML.load(result) || {}
      raise ApiError, result if result.include? "error"
    rescue ArgumentError
      raise ApiError, result
    end
    result
  end

  def page_content name
    result = api :action => :query, :prop   => :revisions,
                 :titles => name,   :rvprop => :content
    return "" if result["query"]["pages"].first["missing"]
    result["query"]["pages"].first["revisions"].first["*"]
  end

  def site_info
    @site_info ||= api(:action => :query, :meta => :siteinfo)["query"]["general"]
  end

  def method_missing name, *options, &block
    begin
      params = options.extract_options!.symbolize_keys.merge :action => name
      api options, params
    rescue ApiError => e
      if e.code == "unknown_action"
        super(name, *options, &block)
      else
        raise e
      end
    end
  end

  def inspect # :nodoc:
    "#<#{site_info["sitename"]} (#{site_info["lang"]}), #{@uri.inspect}>"
  end

  def colorized_inspect # :nodoc:
    ANSICode.white + "#<" + ANSICode.yellow + site_info["sitename"] +
    " (#{site_info["lang"]})" + ANSICode.white + ", #{@uri.colorized_inspect}>"
  end

  alias_method :api, :api_request
  alias_method :get, :page_content

end
