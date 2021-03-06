require 'bundler'
Bundler.require 
require 'google/apis/drive_v3'
require 'google/api_client/client_secrets'
require 'digest/md5'

REDIS = ENV['REDIS_URL'] ? Redis.new(url: ENV['REDIS_URL']) : Redis.new

if development?
  require 'sinatra/reloader'
end

use Rack::Session::Cookie, :secret => (ENV['COOKIE_SECRET'] || 'ohmysecret!!'), expire_after: 2592000

helpers do
  def query_builder q
    q.gsub("'", ' ').split(" ").map{|x|
      "(fullText contains '#{x}')"
    }.join(" and ")
  end

  def  embed link 
    link = link.web_view_link.sub("/view", "/preview")
  end

  def files query: "", page_token: ""
    page_token = page_token.to_s
    query = query.to_s
    client_opts = JSON.parse(session[:credentials])
    auth_client = Signet::OAuth2::Client.new(client_opts)
    drive = Google::Apis::DriveV3::DriveService.new
    opts = {options: { authorization: auth_client }}
    unless query == ''
      opts[:q] = query_builder(query)
    else
      opts[:q] = "(mimeType != 'application/pdf') and (mimeType != 'image/jpeg')"
    end
    opts[:order_by] = "modifiedTime desc"
    unless page_token == ''
      opts[:page_token] = page_token
    end
    opts[:fields] = 'nextPageToken, files(id, name, created_time, video_media_metadata, webViewLink)'
    files = drive.list_files(opts)
    return files.files.select{|x|
      x.video_media_metadata
    }, files.next_page_token
  end

  def next_page
    request.path + "?" + [request.query_string, "page_token=#{@next_page_token}"].join("&")
  end

  def pad i
    if i < 10
      "0#{i}"
    else
      i.to_s
    end
  end

  def duration i
    m = i.to_i/1000/60
    "#{pad(m/60)}:#{pad(m%60)}"
  end

  def media_info file
    if file.video_media_metadata
      "#{duration(file.video_media_metadata.duration_millis)} #{file.video_media_metadata.height}p"
    end
  end

  def mobile?
    !!(request.user_agent =~ /iPhone|Android|SmartTV|iPad/)
  end
end


get '/' do
  if session[:credentials] 
    redirect "/home"
  end
  haml :top
end

def redis_key str
  Digest::MD5.hexdigest(str)
end

get '/home' do
  auth
  @files, @next_page_token = files(query: params[:query], page_token: params[:page_token])
  haml :files
end

post '/api/status' do
  auth
  ary = JSON.parse(request.body.read)
  if ary.count  > 1
    keys = ary.map{|x| redis_key("#{x}/watched/#{session[:email]}") }
    r = REDIS.mget(*keys)
    result = []
    ary.each_with_index{|id,i|
      result << {id: id, watched: !!r[i]}
    }
    return result.to_json
  end
  return 'ng'
end

post '/api/watch' do
  auth
  key = request.body.read.chomp
  content_type :json
  REDIS.set(redis_key("#{key}/watched/#{session[:email]}"), "alloy")
  "true"
end

require './auth'
