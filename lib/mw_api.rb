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
          @info = (error.to_s rescue error)
        end
        @text ||= @info
      rescue Exception => e
        error = e
        retry
      end
    end

    def to_s
      "#@code - #{@info ? @info : "(no #info given, try #text)"}"
    end

  end

  def self.wikipedia lang = :en
    @wp ||= {}
    @wp[lang.to_sym] ||= self.new "http://#{lang}.wikipedia.org/w/api.php"
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
    post      = options.delete :post
    uri.query = params.to_param
    result    = http_request uri, post
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

  def siteinfo
    @site_info ||= api(:action => :query, :meta => :siteinfo)["query"]["general"]
  end

  def method_missing name, *options, &block
    begin
      params = options.extract_options!.symbolize_keys.merge :action => name
      api options, params
    rescue ApiError => e
      case e.code
      when "mustbeposted";   api :post, options, params
      when "unknown_action"; super(name, *options, &block)
      else raise e
      end
    end
  end

  def inspect # :nodoc:
    "#<#{siteinfo["sitename"]} (#{siteinfo["lang"]}), #{@uri.inspect}>"
  end

  def colorized_inspect # :nodoc:
    ANSICode.white + "#<" + ANSICode.yellow + siteinfo["sitename"] +
    " (#{siteinfo["lang"]})" + ANSICode.white + ", #{@uri.colorized_inspect}>"
  end

  alias_method :api, :api_request
  alias_method :get, :page_content

end
